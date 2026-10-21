# Radiance (codeberg.org/StillDeadcode/radiance): tensor-parallel engine for the
# dual R9700s, from the upstream image pinned by digest in pins.json.
#
# One unit instance per model id: llama-swap's engine shim starts radiance@<id>
# with the model file's args (see engine-shim.sh). The image is FROM scratch and
# needs no host ROCm, only an amdgpu driver that supports ROCm 10.1.
#
# Weights: /var/lib/models/cache/radiance, mounted read-only at /models.
# `ai add --engine radiance --from REPO:FILE.rad` downloads there.
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  inf = config.mySystem.services.inference;
  cfg = inf.radiance;
  pins = (lib.importJSON ../../../../pins.json).radiance;
  podman = lib.getExe config.virtualisation.podman.package;
  weightsDir = "/var/lib/models/cache/radiance";
  run = "/run/radiance-%i";

  # Present already, or pull it now. Shared by the deploy-time prefetch and
  # each engine start (a pruned image, or a load before the prefetch finished).
  ensureImage = "${podman} image exists ${cfg.image} || ${podman} pull ${cfg.image}";

  # The env file is optional for the unit (its stop commands must run even if
  # the file is gone), so a start without it has to fail here instead.
  preStart = pkgs.writeShellScript "radiance-prestart" ''
    if [ -z "''${ENGINE_ARGS:-}" ]; then
      echo "no ENGINE_ARGS: start radiance@ through llama-swap (ai up), not by hand" >&2
      exit 1
    fi
    ${ensureImage}
  '';
in
{
  options.mySystem.services.inference.radiance = {
    enable = lib.mkEnableOption "Radiance engine units for llama-swap";

    image = lib.mkOption {
      type = lib.types.str;
      default = "${pins.image}@${pins.digest}";
      defaultText = lib.literalExpression ''"''${pins.radiance.image}@''${pins.radiance.digest}"'';
      description = "Image reference. Bump with `nix run .#update-pins radiance`.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = inf.enable && inf.acceleration == "rocm";
        message = "mySystem.services.inference.radiance needs inference enabled with acceleration = \"rocm\"";
      }
    ];

    mySystem.services.inference = {
      engines = [ "radiance" ];
      # --served-model-name: responses report the llama-swap id, like llama's --alias.
      macros.radiance = "${lib.getExe inf.engineShim} radiance \${MODEL_ID} --host 127.0.0.1 --port \${PORT} --served-model-name \${MODEL_ID}";
    };

    # Pull at deploy without blocking the switch (Type=exec returns once the
    # script runs). A failed pull pages; the next engine start retries it.
    systemd.services.radiance-image = {
      description = "Pull ${cfg.image}";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.OnFailure = [ "notify-radiance-image-fail.service" ];
      serviceConfig.Type = "exec";
      script = ensureImage;
    };

    systemd.services.notify-radiance-image-fail = mkFailureUnit {
      name = "radiance-image";
      title = "Radiance image pull failed";
      body = "podman pull ${cfg.image} failed. Check: journalctl -u radiance-image";
      tags = "warning";
    };

    # Run flags follow upstream docs/DOCKER.md and deploy/compose/common.yaml.
    # Container plumbing (cidfile, sdnotify, -d --replace) mirrors oci-containers.
    systemd.services."radiance@" = {
      description = "Radiance engine for model %i";
      # Never outlives the front door: llama-swap stopping or restarting (deploy,
      # ai train on) takes the engine and its VRAM down with it.
      bindsTo = [ "llama-swap.service" ];
      after = [ "llama-swap.service" ];
      # A deploy must not restart a changed instance by itself: it would start
      # outside llama-swap with no env file (prestart refuses; switch exits 4).
      # When the front door changes, BindsTo already takes the engine down.
      restartIfChanged = false;
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        Delegate = true;
        Environment = "PODMAN_SYSTEMD_UNIT=%n";
        # "-": systemd re-reads this for ExecStop/ExecStopPost; a missing file
        # must not fail the stop (that left the unit failed after ai train on).
        EnvironmentFile = "-/run/llama-swap/radiance-%i.env";
        RuntimeDirectory = "radiance-%i";
        ExecStartPre = preStart;
        ExecStart = lib.concatStringsSep " " [
          podman
          "run"
          "--name=radiance-%i"
          "--cidfile=${run}/ctr-id"
          "--cgroups=enabled"
          "--sdnotify=conmon"
          "-d"
          "--replace"
          "--rm"
          "--log-driver=journald"
          "--pull=never"
          "--init" # forwards SIGTERM: the engine finishes its step and releases the cards
          "--stop-timeout=60" # upstream stop_grace_period
          "--network=host" # binds 127.0.0.1:<llama-swap port> on the host
          "--ulimit=memlock=-1"
          "--security-opt=seccomp=unconfined" # io_uring and the ROCm NUMA calls
          "--device=/dev/kfd"
          "--device=/dev/dri"
          "--group-add=${toString config.ids.gids.render}"
          "--group-add=${toString config.ids.gids.video}"
          "--user=65534:65534" # upstream runs as a plain user too; /models is read-only
          "--tmpfs=/tmp"
          "--volume=${weightsDir}:/models:ro"
          cfg.image
          "$ENGINE_ARGS" # unbraced: systemd splits it into words, no shell
        ];
        ExecStop = "${podman} stop --ignore --cidfile=${run}/ctr-id";
        ExecStopPost = "${podman} rm -f --ignore --cidfile=${run}/ctr-id";
        TimeoutStartSec = 0; # an image pull on first use can take a while
        TimeoutStopSec = 90;
        SuccessExitStatus = [ 143 ];
        Restart = "no"; # a crash surfaces through the shim; llama-swap restarts on the next request
      };
    };

    systemd.tmpfiles.rules = [
      "d ${weightsDir} 0755 llama-swap llama-swap"
    ];
  };
}
