# modules/nixos/services/unsloth.nix
{
  config,
  lib,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.unsloth;

  containerDir = ../../../containers/unsloth;
  # store-path hash of the build context: edits to Containerfile*/entrypoint.sh retag -> rebuild
  ctxHash = lib.substring 11 8 (baseNameOf "${containerDir}");

  imageName = {
    cuda = "localhost/unsloth-studio";
    rocm = "localhost/unsloth-studio-rocm";
  };
  containerfile = {
    cuda = "Containerfile";
    rocm = "Containerfile.rocm";
  };
  image =
    if cfg.image != null then
      cfg.image
    else
      "${imageName.${cfg.acceleration}}:${cfg.version}-${ctxHash}";

  gpuFlags = {
    cuda = [ "--device=nvidia.com/gpu=all" ];
    rocm = [
      "--device=/dev/kfd"
      "--device=/dev/dri"
      "--group-add=${toString config.ids.gids.video}"
      "--group-add=${toString config.ids.gids.render}"
    ];
  };

  wheelsDir = "/var/lib/unsloth/wheels";
in
{
  options.mySystem.services.unsloth = {
    enable = lib.mkEnableOption "Unsloth Studio (training + inference UI, containerized)";

    acceleration = lib.mkOption {
      type = lib.types.enum [
        "cuda"
        "rocm"
      ];
      default = "cuda";
      description = "GPU stack";
    };

    image = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Override the container image (skips the owned-image build unit)";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Host port for Unsloth Studio";
    };

    version = lib.mkOption {
      type = lib.types.str;
      description = "unsloth PyPI version pinned into the owned image";
      example = "2026.8.19";
    };

    studioRef = lib.mkOption {
      type = lib.types.str;
      description = "unsloth git tag whose install.sh builds the image (studio release tag)";
      example = "v0.1.801-beta";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.hf-token = { };
    sops.templates."unsloth.env" = {
      content = "HF_TOKEN=${config.sops.placeholder.hf-token}";
      restartUnits = [ "podman-unsloth.service" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/unsloth 0755 root root"
      "d /var/lib/unsloth/work 0755 1001 1001"
      "d /var/lib/unsloth/cache 0755 1001 1001"
      "d /var/lib/unsloth/studio 0755 1001 1001"
      "d /var/lib/unsloth/unsloth-home 0755 1001 1001"
      "d /var/lib/models/hf 0755 1001 1001"
      "d /var/lib/models/gguf 0775 1001 1001"
      "d ${wheelsDir} 0755 root root"
    ];

    # Build the owned image on the box when its tag is absent. Tag = version + build
    # context hash, so a version bump OR a Containerfile edit rebuilds; uv's cache
    # mount and the local wheel dir keep that from re-downloading torch each time.
    systemd.services.unsloth-image = lib.mkIf (cfg.image == null) ({
      description = "Build ${image}";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "podman-unsloth.service" ];
      requiredBy = [ "podman-unsloth.service" ];
      onFailure = [ "notify-unsloth-image-fail.service" ];
      path = [ config.virtualisation.podman.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = "3h";
      };
      script = ''
        if podman image exists ${image}; then exit 0; fi
        podman build \
          -f ${containerDir}/${containerfile.${cfg.acceleration}} \
          -t ${image} \
          -v ${wheelsDir}:/wheels:ro \
          --build-arg UNSLOTH_REF=${cfg.studioRef} \
          --build-arg UNSLOTH_PIP_VERSION=${cfg.version} \
          ${containerDir}
      '';
    });

    systemd.services.notify-unsloth-image-fail = lib.mkIf (cfg.image == null) (mkFailureUnit {
      name = "unsloth-image";
      title = "Unsloth image build FAILED";
      priority = "high";
      tags = "rotating_light,sloth";
      body = "podman build of ${image} failed. Check: journalctl -u unsloth-image";
    });

    virtualisation.oci-containers.containers.unsloth = {
      inherit image;
      autoStart = true;
      pull = "never";

      ports = [ "${toString cfg.port}:8000" ];

      volumes = [
        "/var/lib/unsloth/work:/workspace/work"
        "/var/lib/unsloth/cache:/workspace/.cache"
        "/var/lib/models/hf:/workspace/.cache/huggingface"
        "/var/lib/unsloth/studio:/workspace/studio:ro"
        "/var/lib/unsloth/unsloth-home:/home/unsloth/.unsloth"
        "/var/lib/models/gguf:/home/unsloth/.unsloth/studio/exports"
      ];

      environment = {
        HF_HUB_ENABLE_HF_TRANSFER = "1";
        PYTORCH_ALLOC_CONF = "expandable_segments:True";
        PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
        TOKENIZERS_PARALLELISM = "false";
        HF_XET_HIGH_PERFORMANCE = "1";
      };

      environmentFiles = [ config.sops.templates."unsloth.env".path ];

      extraOptions = [ "--shm-size=8g" ] ++ gpuFlags.${cfg.acceleration};
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

    mySystem.proxy.vhosts.unsloth = {
      sub = "sloth";
      upstream = "127.0.0.1:${toString cfg.port}";
      dashboard = {
        name = "Unsloth Studio";
        description = "Train & run local models";
      };
    };
  };
}
