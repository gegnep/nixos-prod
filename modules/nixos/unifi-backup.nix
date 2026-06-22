# modules/nixos/unifi-backup.nix  (new file)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mySystem.services.unifi-backup;
in
{
  options.mySystem.services.unifi-backup = {
    enable = lib.mkEnableOption "Pull UniFi Network .unf autobackups off the Cloud Gateway";

    host = lib.mkOption {
      type = lib.types.str;
      default = "10.0.0.1";
      description = "Cloud Gateway Ultra LAN address.";
    };

    remotePath = lib.mkOption {
      type = lib.types.str;
      default = "/data/unifi/data/backup/";
      description = "Autobackup dir on the gateway. VERIFY over SSH — differs by UniFi OS version.";
    };

    localPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/unifi-backup";
      # Under @var-lib → picked up by btrbk + restic's existing /var/lib path. Don't move it out.
      description = "Local landing dir.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "02:30"; # ahead of restic's 03:00 timer
      description = "When to pull. Keep it before the restic B2 run.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.unifi-ssh-password = { };

    systemd.tmpfiles.rules = [ "d ${cfg.localPath} 0750 root root -" ];

    systemd.services.unifi-backup = {
      description = "Pull UniFi Network autobackups from ${cfg.host}";
      onFailure = [ "notify-unifi-backup-fail.service" ];
      path = [
        pkgs.openssh
        pkgs.sshpass
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        sshpass -f ${config.sops.secrets.unifi-ssh-password.path} \
          scp -O -r \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            "root@${cfg.host}:${cfg.remotePath}/*.unf" \
            ${cfg.localPath}/
      '';
    };

    systemd.timers.unifi-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
      };
    };

    systemd.services.notify-unifi-backup-fail = {
      description = "Notify ntfy that the UniFi backup pull failed";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.curl}/bin/curl -fsS \
          -H "Title: UniFi backup pull FAILED on ${config.networking.hostName}" \
          -H "Priority: high" \
          -H "Tags: rotating_light,satellite" \
          -d "Could not pull .unf autobackups from ${cfg.host}. Check: journalctl -u unifi-backup" \
          http://127.0.0.1:2586/homelab-alerts >/dev/null || true
      '';
    };
  };
}
