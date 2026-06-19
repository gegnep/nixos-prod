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
    })

    (lib.mkIf cfg.agent.enable {
      sops.secrets.beszel-agent-env.restartUnits = [ "beszel-agent.service" ];

      services.beszel.agent = {
        enable = true;
        environment.DOCKER_HOST = "unix:///run/podman/podman.sock";
        environmentFile = config.sops.secrets.beszel-agent-env.path;
        extraPath = lib.optional cfg.agent.nvidia (lib.getBin config.hardware.nvidia.package);
        smartmon.enable = cfg.agent.smart;
      };

      systemd.services.beszel-agent.serviceConfig = lib.mkIf cfg.agent.nvidia {
        PrivateDevices = lib.mkForce false;
        PrivateUsers = lib.mkForce false;
      };
    })

    (lib.mkIf (cfg.agent.enable && cfg.agent.containers) {
      virtualisation.podman.dockerSocket.enable = true;
    })
  ];
}
