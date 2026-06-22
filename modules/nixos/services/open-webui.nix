{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.open-webui;
in
{
  options.mySystem.services.open-webui = {
    enable = lib.mkEnableOption "Open WebUI frontend for Ollama";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Open WebUI HTTP Port";
    };
  };

  config = lib.mkIf cfg.enable {
    services.open-webui = {
      enable = true;
      package = pkgs.open-webui;

      host = "0.0.0.0";
      port = cfg.port;

      environment = {
        OLLAMA_BASE_URL = "http://127.0.0.1:11434";

        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
      };
    };
    systemd.services.open-webui.serviceConfig.EnvironmentFile =
      config.sops.templates."open-webui.env".path;
    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

    mySystem.proxy.vhosts.open-webui = {
      sub = "ai";
      upstream = "127.0.0.1:${toString cfg.port}";
      dashboard = {
        name = "Open WebUI";
        description = "Ollama chat frontend";
        order = 10;
      };
    };
  };
}
