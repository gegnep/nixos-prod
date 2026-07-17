{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mySystem.services.rustypaste;
in
{
  options.mySystem.services.rustypaste = {
    enable = lib.mkEnableOption "rustypaste minimal file upload/paste server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8100;
    };

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://p.pengeg.com";
      description = "Public base URL";
    };

    maxContentLength = lib.mkOption {
      type = lib.types.str;
      default = "50MB";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.rustypaste-auth-token = { };

    sops.templates."rustypaste-config.toml" = {
      owner = "rustypaste";
      restartUnits = [ "rustypaste.service" ];
      content = ''
        [config]
        refresh_rate = "1s"

        [server]
        address = "127.0.0.1:${toString cfg.port}"
        url = "${cfg.url}"
        max_content_length = "${cfg.maxContentLength}"
        upload_path = "/var/lib/rustypaste"
        timeout = "30s"
        expose_version = false
        expose_list = false
        auth_tokens = ["${config.sops.placeholder.rustypaste-auth-token}"]
        delete_tokens = ["${config.sops.placeholder.rustypaste-auth-token}"]
        handle_spaces = "replace"

        [landing_page]
        file = "${./rustypaste-index.html}"
        content_type = "text/html; charset=utf-8"

        [paste]
        random_url = { type = "alphanumeric", length = 8 }
        default_extension = "txt"
        duplicate_files = false
        delete_expired_files = { enabled = true, interval = "1h" }
      '';
    };

    users.users.rustypaste = {
      isSystemUser = true;
      group = "rustypaste";
    };
    users.groups.rustypaste = { };

    systemd.services.rustypaste = {
      description = "rustypaste";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment.CONFIG = config.sops.templates."rustypaste-config.toml".path;

      serviceConfig = {
        ExecStart = "${pkgs.rustypaste}/bin/rustypaste";
        User = "rustypaste";
        Group = "rustypaste";
        StateDirectory = "rustypaste"; # uploads → /var/lib/rustypaste, under @var-lib
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    mySystem.proxy.vhosts.rustypaste = {
      sub = "p";
      upstream = "127.0.0.1:${toString cfg.port}";
    };
  };
}
