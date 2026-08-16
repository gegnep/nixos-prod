{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.unsloth;
  defaultImages = {
    cuda = "docker.io/unsloth/unsloth:latest";
    rocm = null; # no upstream ROCm image (unsloth#5405);
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
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = image != null;
        message = "mySystem.services.unsloth: no default image for rocm; set services.unsloth.image";
      }
    ];

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

      ports = [ "${toString cfg.port}:8000" ];

      volumes = [
        "/var/lib/unsloth/work:/workspace/work"
        "/var/lib/unsloth/cache:/workspace/.cache"
        "/var/lib/unsloth/studio:/workspace/studio"
        "/var/lib/unsloth/unsloth-home:/home/unsloth/.unsloth"
      ];

      environment = {
        HF_HUB_ENABLE_HF_TRANSFER = "1";
      };

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
