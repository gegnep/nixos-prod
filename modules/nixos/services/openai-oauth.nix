{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.openai-oauth;
  openai-oauth = pkgs.callPackage ../../../pkgs/openai-oauth { };
in
{
  options.mySystem.services.openai-oauth = {
    enable = lib.mkEnableOption "ChatGPT-OAuth OpenAI-compatible proxy";
    port = lib.mkOption {
      type = lib.types.port;
      default = 10531;
      description = "Loopback port for the proxy";
    };
  };

  config = lib.mkIf cfg.enable {
    # Static user: auth.json is placed by hand and rewritten in place on token
    # refresh, so the uid has to be stable across restarts.
    users.users.openai-oauth = {
      isSystemUser = true;
      group = "openai-oauth";
      home = "/var/lib/openai-oauth";
    };
    users.groups.openai-oauth = { };

    # Needed at runtime for model discovery, and by hand for `codex login`.
    environment.systemPackages = [ pkgs.codex ];

    systemd.services.openai-oauth = {
      description = "openai-oauth localhost proxy";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = [ pkgs.codex ];

      environment = {
        CODEX_HOME = "/var/lib/openai-oauth";
        HOME = "/var/lib/openai-oauth";
      };

      serviceConfig = {
        ExecStart = "${lib.getExe openai-oauth} --host 127.0.0.1 --port ${toString cfg.port}";
        Restart = "on-failure";
        RestartSec = 10;

        User = "openai-oauth";
        Group = "openai-oauth";
        StateDirectory = "openai-oauth";
        StateDirectoryMode = "0700";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };
    };

    # Registers with Open WebUI when both run here. Both keys are
    # PersistentConfig upstream: env only seeds a fresh database.
    services.open-webui.environment = lib.mkIf config.mySystem.services.open-webui.enable {
      ENABLE_OPENAI_API = "True";
      OPENAI_API_BASE_URLS = "http://127.0.0.1:${toString cfg.port}/v1";
      OPENAI_API_KEYS = "unused";
    };
  };
}
