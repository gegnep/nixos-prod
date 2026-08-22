{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.beszel;
in
{
  options.mySystem.services.beszel = {
    hub = {
      enable = lib.mkEnableOption "Beszel hub (monitoring dashboard)";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8090;
        description = "Hub web port (localhost; fronted by Caddy as stats.<domain>)";
      };
    };
    agent = {
      enable = lib.mkEnableOption "Beszel agent (reports metrics to a hub)";
      nvidia = lib.mkEnableOption "wire nvidia-smi + GPU device access into the agent unit";
      amd = lib.mkEnableOption "AMD GPU stats via sysfs collector";
      intel = lib.mkEnableOption "Intel GPU stats via intel_gpu_top";
      smart = lib.mkEnableOption "SMART disk monitoring via smartctl";
      containers = lib.mkEnableOption "podman container stats (exposes the docker-compat socket)";
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.hub.enable {
      services.beszel.hub = {
        enable = true;
        host = "127.0.0.1";
        port = cfg.hub.port;
      };

      mySystem.proxy.vhosts.beszel = {
        sub = "stats";
        upstream = "127.0.0.1:${toString cfg.hub.port}";
        dashboard = {
          name = "Beszel";
          description = "Metrics & GPU";
        };
      };
    })

    (lib.mkIf cfg.agent.enable {
      sops.secrets.beszel-agent-env.restartUnits = [ "beszel-agent.service" ];

      services.beszel.agent = {
        enable = true;
        environment = lib.mkMerge [
          (lib.mkIf cfg.agent.containers { DOCKER_HOST = "unix:///run/podman/podman.sock"; })
          # pin intel_gpu_top to the Intel card; a card renumber must not select the AMD GPU
          (lib.mkIf cfg.agent.intel { INTEL_GPU_DEVICE = "pci:vendor=8086"; })
        ];
        environmentFile = config.sops.secrets.beszel-agent-env.path;
        extraPath =
          lib.optional cfg.agent.nvidia (lib.getBin config.hardware.nvidia.package)
          ++ lib.optional cfg.agent.intel pkgs.intel-gpu-tools;
        smartmon.enable = cfg.agent.smart;
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ 45876 ];

      systemd.services.beszel-agent.serviceConfig = lib.mkMerge [
        (lib.mkIf cfg.agent.nvidia {
          PrivateDevices = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
        })
        (lib.mkIf cfg.agent.amd {
          BindReadOnlyPaths = [ "${pkgs.libdrm}/share/libdrm/amdgpu.ids:/usr/share/libdrm/amdgpu.ids" ];
        })
        (lib.mkIf cfg.agent.intel {
          PrivateDevices = lib.mkForce false;
          PrivateUsers = lib.mkForce false;
          SupplementaryGroups = [
            "video"
            "render"
          ];
          AmbientCapabilities = [ "CAP_PERFMON" ]; # i915 PMU
          CapabilityBoundingSet = [ "CAP_PERFMON" ];
          SystemCallFilter = [ "perf_event_open" ]; # @debug, not in @system-service
        })
      ];
    })

    (lib.mkIf (cfg.agent.enable && cfg.agent.containers) {
      virtualisation.podman.dockerSocket.enable = true;
    })
  ];
}
