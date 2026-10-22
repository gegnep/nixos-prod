# Project Maya (github.com/mw00/project-maya): GLM-5.3-Flash on the dual R9700s,
# layer split, experts spilling into a pinned RAM tier. Experimental on AMD,
# text only.
#
# No upstream image: maya-image builds a toolchain image from containers/maya,
# and maya-entrypoint fetches the pinned commit (pins.json) into the cache.
#   maya-setup@<quant>  oneshot: compile, pack, config (ai maya-setup / ai add)
#   maya@<id>           the server, started by llama-swap's engine shim
#
# Everything lives in /var/lib/models/cache/maya (re-creatable: no btrbk, no
# restic) and belongs to llama-swap; the containers run as that uid.
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  inf = config.mySystem.services.inference;
  cfg = inf.maya;
  pins = (lib.importJSON ../../../../pins.json).maya;
  podman = lib.getExe config.virtualisation.podman.package;
  dataDir = "/var/lib/models/cache/maya";
  containerDir = ../../../../containers/maya;
  # store-path hash of the build context: an edit to Containerfile/entrypoint.sh retags -> rebuild
  ctxHash = lib.substring 11 8 (baseNameOf "${containerDir}");
  image = "localhost/maya-rocm:7.2.1-${ctxHash}";

  # podman run flags all three units share. Upstream has no container guide;
  # these follow its AMD notes and Strata's advice: pinned RAM tier (memlock),
  # the ROCm runtime's NUMA calls (seccomp). The network is per unit (mkRun).
  runFlags = [
    "--pull=never"
    "--init"
    "--ulimit=memlock=-1:-1"
    "--shm-size=2g"
    "--security-opt=seccomp=unconfined"
    "--device=/dev/kfd"
    "--device=/dev/dri"
    "--group-add=${toString config.ids.gids.render}"
    "--group-add=${toString config.ids.gids.video}"
    "--env=HOME=/data/home"
    "--volume=${dataDir}:/data"
  ];

  # $1: instance, then fixed args from the unit's ExecStart. ARGS_VAR comes from
  # the unit's EnvironmentFile and is split on whitespace here (set -f: never
  # globbed); ai and the engine shim restrict its characters. llama-swap's uid
  # is read at start: it is not a fixed number.
  mkRun =
    {
      name,
      argsVar,
      podmanArgs,
      entryArgs,
      network ? "host",
    }:
    pkgs.writeShellScript name ''
      set -euo pipefail
      set -f
      inst=$1
      shift
      if [ -z "''${${argsVar}:-}" ]; then
        echo "no ${argsVar}: start this unit through ai or llama-swap, not by hand" >&2
        exit 1
      fi
      uid=$(${pkgs.coreutils}/bin/id -u llama-swap)
      gid=$(${pkgs.coreutils}/bin/id -g llama-swap)
      # shellcheck disable=SC2086 # word splitting of ${argsVar} is the point
      exec ${podman} run ${podmanArgs} --network=${network} \
        ${lib.escapeShellArgs runFlags} --user="$uid:$gid" \
        ${image} ${entryArgs} ''$${argsVar} "$@"
    '';

  setupRun = mkRun {
    name = "maya-setup-run";
    argsVar = "SETUP_ARGS";
    # passthrough: the setup's output goes to this unit's journal once
    podmanArgs = ''--name="maya-setup-$inst" --rm --replace --log-driver=passthrough'';
    entryArgs = lib.escapeShellArgs [
      "setup"
      pins.commit
      "--setup"
      "--backend"
      "hip"
      "--gpus"
      cfg.gpus
      "--models-dir"
      "/data/models"
      "--no-vision" # HIP is text only
      "--yes"
      "--plain"
      "--no-start"
      "--download-model" # files already in /data/models/<quant> are used, not fetched
    ];
  };

  serveRun = mkRun {
    name = "maya-serve-run";
    argsVar = "ENGINE_ARGS";
    podmanArgs = ''--name="maya-$inst" --cidfile="/run/maya-$inst/ctr-id" --cgroups=enabled --sdnotify=conmon -d --replace --rm --log-driver=journald --stop-timeout=150'';
    entryArgs = lib.escapeShellArgs [
      "serve"
      pins.commit
      "--backend"
      "hip"
      "--plain"
    ];
  };

  # maya.sh --bench / --report (CONTRIBUTING.md's speed report). The bench drives
  # the engine over stdin, so no network: its "is Maya running?" probe goes to
  # the config's port 8080, which is Pi-hole's on the host network.
  benchRun = mkRun {
    name = "maya-bench-run";
    argsVar = "BENCH_ARGS";
    network = "none";
    podmanArgs = ''--name="maya-bench-$inst" --rm --replace --log-driver=passthrough'';
    entryArgs = lib.escapeShellArgs [
      "serve"
      pins.commit
      "--backend"
      "hip"
      "--plain"
    ];
  };

  # Both commands write into the checkout and overwrite each other's runs, so
  # each quant's last results are copied to bench/<quant>/.
  benchKeep = pkgs.writeShellScript "maya-bench-keep" ''
    set -euo pipefail
    out=${dataDir}/bench/$1
    ${pkgs.coreutils}/bin/install -d -m 0755 "$out"
    for f in maya-bench.txt maya-report.txt maya-bench.log; do
      ${pkgs.coreutils}/bin/install -m 0644 ${dataDir}/src/${pins.commit}/$f "$out/$f"
    done
  '';

  # llama-swap's second ExecCondition (Studio's is in unsloth.nix).
  benchIdle = pkgs.writeShellScript "llama-swap-maya-bench-idle" ''
    if [ -n "$(${config.systemd.package}/bin/systemctl list-units --plain --no-legend --state=active,activating 'maya-bench@*')" ]; then
      echo "a Maya benchmark holds the GPUs; llama-swap stays down until ai maya-bench starts it"
      exit 1
    fi
  '';
in
{
  options.mySystem.services.inference.maya = {
    enable = lib.mkEnableOption "Project Maya engine units for llama-swap";

    gpus = lib.mkOption {
      type = lib.types.str;
      default = "0,1";
      description = "KFD topology order (`maya.sh --check`). Two cards split the layers; the second also drafts (MTP).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = inf.enable && inf.acceleration == "rocm";
        message = "mySystem.services.inference.maya needs inference enabled with acceleration = \"rocm\"";
      }
    ];

    mySystem.services.inference = {
      engines = [ "maya" ];
      macros.maya = "${lib.getExe inf.engineShim} maya \${MODEL_ID} --host 127.0.0.1 --port \${PORT}";
    };

    # Built on first use (setup or serve), not at deploy: about 10 minutes of
    # base image and ROCm libraries. RemainAfterExit off, so every start of a
    # dependent re-checks the tag and a Containerfile edit rebuilds.
    systemd.services.maya-image = {
      description = "Build ${image}";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      onFailure = [ "notify-maya-image-fail.service" ];
      path = [ config.virtualisation.podman.package ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "1h";
      };
      script = ''
        if podman image exists ${image}; then exit 0; fi
        podman build -t ${image} ${containerDir}
      '';
    };

    systemd.services.notify-maya-image-fail = mkFailureUnit {
      name = "maya-image";
      title = "Maya image build failed";
      body = "podman build of ${image} failed. Check: journalctl -u maya-image";
      tags = "warning";
    };

    # Compiles for the cards, builds the pack next to the weights, writes
    # maya-<quant>-hip.json in the checkout. No GPU work (HIP skips calibration),
    # so llama-swap keeps serving meanwhile. ai writes SETUP_ARGS (--model ...).
    systemd.services."maya-setup@" = {
      description = "Maya setup for %i";
      requires = [ "maya-image.service" ];
      wants = [ "network-online.target" ];
      after = [
        "maya-image.service"
        "network-online.target"
      ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "-/run/maya-setup-%i.env";
        ExecStart = "${setupRun} %i";
        ExecStopPost = "${podman} rm -f --ignore maya-setup-%i";
        TimeoutStartSec = "4h";
      };
    };

    # GPU work: ai maya-bench stops llama-swap first and starts it after. No
    # Conflicts=llama-swap: a deploy starting llama-swap would then stop the
    # bench; the ExecCondition below skips that start instead.
    systemd.services."maya-bench@" = {
      description = "Maya benchmark and report for %i";
      requires = [ "maya-image.service" ];
      after = [ "maya-image.service" ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        EnvironmentFile = "-/run/maya-bench-%i.env";
        ExecStart = [
          "${benchRun} %i --bench"
          "${benchRun} %i --report"
        ];
        ExecStartPost = "${benchKeep} %i";
        ExecStopPost = "${podman} rm -f --ignore maya-bench-%i";
        TimeoutStartSec = "1h";
      };
    };

    systemd.services.llama-swap.serviceConfig.ExecCondition = [ "+${benchIdle}" ];

    # Same shape as radiance@ (see radiance.nix): bound to llama-swap, never
    # restarted by a deploy, env file optional for the stop commands.
    systemd.services."maya@" = {
      description = "Maya engine for model %i";
      bindsTo = [ "llama-swap.service" ];
      requires = [ "maya-image.service" ];
      after = [
        "llama-swap.service"
        "maya-image.service"
      ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "notify";
        NotifyAccess = "all";
        Delegate = true;
        Environment = "PODMAN_SYSTEMD_UNIT=%n";
        EnvironmentFile = "-/run/llama-swap/maya-%i.env";
        RuntimeDirectory = "maya-%i";
        ExecStart = "${serveRun} %i";
        ExecStop = "${podman} stop --ignore --cidfile=/run/maya-%i/ctr-id";
        ExecStopPost = "${podman} rm -f --ignore --cidfile=/run/maya-%i/ctr-id";
        TimeoutStartSec = 0;
        # Maya's stop: up to 40 s to wrap the running answer, 50 s for the engine
        # (MAYA_ENGINE_WRAP_S, MAYA_ENGINE_QUIT_S); podman waits 150.
        TimeoutStopSec = 180;
        SuccessExitStatus = [
          130
          143
        ];
        Restart = "no";
      };
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 llama-swap llama-swap"
      "d ${dataDir}/models 0755 llama-swap llama-swap"
    ];
  };
}
