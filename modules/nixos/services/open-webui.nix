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
    enable = lib.mkEnableOption "Open WebUI chat frontend";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Open WebUI HTTP Port";
    };
    openaiConnections = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "OpenAI-compatible base URL, ending in /v1.";
            };
            key = lib.mkOption {
              type = lib.types.str;
              default = "unused";
              description = "API key sent to that URL.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        OpenAI-compatible connections seeded into a fresh database. Modules and
        hosts append to it. PersistentConfig: an existing database ignores env,
        so on a live instance the Admin Panel is the source of truth.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.open-webui-secret-key = { };
    sops.templates."open-webui.env" = {
      content = "WEBUI_SECRET_KEY=${config.sops.placeholder.open-webui-secret-key}";
      restartUnits = [ "open-webui.service" ];
    };

    services.open-webui = {
      enable = true;
      # nixpkgs#543976 enabled __structuredAttrs for buildPythonPackage. The
      # upstream single-string makeWrapperArgs then reaches makeWrapper as one
      # argument and fails in fixupPhase. Drop this override once nixpkgs#576893
      # is in nixos-unstable; upstream then ships the same list.
      package = pkgs.open-webui.overridePythonAttrs (old: {
        makeWrapperArgs = [
          "--set"
          "FRONTEND_BUILD_DIR"
          "${old.passthru.frontend}/share/open-webui"
        ];
      });

      host = "0.0.0.0";
      port = cfg.port;

      environment = {
        ENABLE_OLLAMA_API = "False";
        ENABLE_OPENAI_API = "True";
        OPENAI_API_BASE_URLS = lib.concatMapStringsSep ";" (c: c.url) cfg.openaiConnections;
        OPENAI_API_KEYS = lib.concatMapStringsSep ";" (c: c.key) cfg.openaiConnections;
        WEBUI_URL = "http${lib.optionalString config.mySystem.proxy.tls "s"}://ai.${config.mySystem.proxy.domain}";

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
        description = "Chat frontend";
      };
    };
  };
}
