{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.unsloth;
  defaultImages = {
    cuda = "localhost/unsloth-studio:${cfg.version}";
    rocm = null; # build a rocm variant post-transplant (UNSLOTH_LLAMA_CPP_BACKEND=rocm etc.)
  };

  image = if cfg.image != null then cfg.image else defaultImages.${cfg.acceleration};
  gpuFlags = {
    cuda = [ "--device=nvidia.com/gpu=all" ];
    rocm = [
      "--device=/dev/kfd"
      "--device=/dev/dri"
      "--group-add=video"
    ];
  };
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
      description = "Override the container image";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Host port for Unsloth Studio";
    };

    version = lib.mkOption {
      type = lib.types.str;
      description = "Owned image tag; Build first: see containers/unsloth/Containerfile";
      example = "2026.8.18";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = image != null;
        message = "mySystem.services.unsloth: no default image for rocm; set services.unsloth.image";
      }
    ];

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
    ];

    virtualisation.oci-containers.containers.unsloth = {
      inherit image;
      autoStart = true;
      pull = "never";

      ports = [ "${toString cfg.port}:8000" ];

      volumes = [
        "/var/lib/unsloth/work:/workspace/work"
        "/var/lib/unsloth/cache:/workspace/.cache"
        "/var/lib/unsloth/studio:/workspace/studio:ro"
        "/var/lib/unsloth/unsloth-home:/home/unsloth/.unsloth"
      ];

      environment = {
        HF_HUB_ENABLE_HF_TRANSFER = "1";
        PYTORCH_ALLOC_CONF = "expandable_segments:True";
        PYTORCH_CUDA_ALLOC_CONF = "expandable_segments:True";
        TOKENIZERS_PARALLELISM = "false";
      };

      environmentFiles = [ config.sops.templates."unsloth.env".path ];

      extraOptions = [
        "--shm-size=8g"
      ]
      ++ gpuFlags.${cfg.acceleration};
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
