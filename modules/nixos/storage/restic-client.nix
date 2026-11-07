{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.resticClient;
  host = config.networking.hostName;
in
{
  options.mySystem.services.resticClient = {
    enable = lib.mkEnableOption "restic push to a fleet REST server";

    server = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = ''
        Host running the target resticServer. Names the backup job
        (restic-backups-<server>) and the alerts; the repo URL itself comes
        from the restic-repo-url-<this host> secret.
      '';
    };

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

    oneFileSystem = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Pass --one-file-system. Off on hosts whose paths span btrfs subvolumes
        that must be included (each subvolume is its own st_dev to restic).
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "23:00 UTC";
      description = "Keep well clear of the server's 02:00 UTC prune (exclusive repo lock).";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."restic-repo-url-${host}" = { };
    sops.secrets."restic-repo-password-${host}" = { };

    programs.fuse.enable = true;
    # nixpkgs 31ecbaca dropped fuse2; restic's anacrolix/fuse execs `fusermount`.
    security.wrappers.fusermount = {
      setuid = true;
      owner = "root";
      group = "root";
      source = "${lib.getBin pkgs.fuse3}/bin/fusermount3";
    };

    services.restic.backups.${cfg.server} = {
      repositoryFile = config.sops.secrets."restic-repo-url-${host}".path;
      passwordFile = config.sops.secrets."restic-repo-password-${host}".path;
      initialize = true;
      paths = cfg.paths;
      exclude = cfg.exclude;
      extraBackupArgs = lib.optional cfg.oneFileSystem "--one-file-system";
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "15min";
      };
    };

    systemd.services."restic-backups-${cfg.server}".onFailure = [ "notify-restic-client-fail.service" ];
    systemd.services.notify-restic-client-fail = mkFailureUnit {
      name = "restic-client";
      title = "restic push to ${cfg.server} FAILED on ${host}";
      priority = "urgent";
      tags = "rotating_light,floppy_disk";
      body = "Backup push failed. Check: journalctl -u restic-backups-${cfg.server}";
    };
  };
}
