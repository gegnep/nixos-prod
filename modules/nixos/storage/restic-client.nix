{
  config,
  lib,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.resticClient;
  host = config.networking.hostName;
in
{
  options.mySystem.services.resticClient = {
    enable = lib.mkEnableOption "restic push to the homelab REST server";

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Paths to back up.";
    };

    exclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "restic --exclude patterns.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "23:00 UTC";
      description = "Keep well clear of the homelab's 02:00 UTC prune (exclusive repo lock).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."restic-repo-url-${host}" = { };
    sops.secrets."restic-repo-password-${host}" = { };

    services.restic.backups.homelab = {
      repositoryFile = config.sops.secrets."restic-repo-url-${host}".path;
      passwordFile = config.sops.secrets."restic-repo-password-${host}".path;
      initialize = true;
      paths = cfg.paths;
      exclude = cfg.exclude;
      extraBackupArgs = [ "--one-file-system" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    systemd.services."restic-backups-homelab".onFailure = [ "notify-restic-client-fail.service" ];
    systemd.services.notify-restic-client-fail = mkFailureUnit {
      name = "restic-client";
      title = "restic push to homelab FAILED";
      priority = "urgent";
      tags = "rotating_light,floppy_disk";
      body = "VPS backup failed. Check: journalctl -u restic-backups-homelab";
    };
  };
}
