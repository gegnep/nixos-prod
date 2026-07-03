# Restic REST server: append-only landing zone for blackbox/nixpad backups.
# Repos live under <backup mirror>/restic/<host>; clients auth via per-host
# htpasswd users (privateRepos = user X can only touch /X). Clients cannot
# delete history (--append-only); retention is enforced by the local prune
# timer below, which accesses the repos as plain paths (bypasses rest-server,
# so append-only doesn't block it).
#
# Port 8010 (mcp-nixos wrapper holds 127.0.0.1:8000; also in use — 2586 ntfy,
# 3000 open-webui, 5000 harmonia, 8080 pihole, 8384 syncthing, 8888 atuin).
# Bound to the tailnet IP only. The nixpkgs module is socket-activated with
# FreeBind=true, so binding 100.68.176.20 before tailscaled is up is fine.
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.resticServer;
in
{
  options.mySystem.services.resticServer = {
    enable = lib.mkEnableOption "Restic REST server for desktop/laptop backups";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8010;
      description = "Listen port on the tailnet address.";
    };

    tailnetAddress = lib.mkOption {
      type = lib.types.str;
      default = "100.68.176.20";
      description = "Tailnet IP to bind to. Tailnet-only by construction (FreeBind socket).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.mySystem.backup.mountPoint}/restic";
      description = "Repo root on the raid1 mirror. One subdir per client host.";
    };

    clients = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "blackbox"
        "nixpad"
      ];
      description = "Client hostnames. Each gets an htpasswd user + repo + prune pass.";
    };

    pruneOnCalendar = lib.mkOption {
      type = lib.types.str;
      default = "02:00";
      description = ''
        When retention runs. Must finish before the B2 offsite run (03:00 +
        45m jitter) — a B2 copy taken mid-prune is a broken repo copy — and
        must not overlap client backup timers (exclusive repo lock).
        Order: clients (evening) → prune 02:00 → unifi 02:30 → B2 03:00.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets = {
      # Full htpasswd file (all client lines, bcrypt) as one secret.
      restic-server-htpasswd = {
        owner = "restic";
        restartUnits = [ "restic-rest-server.service" ];
      };
    }
    # Per-repo encryption passwords — needed here only for the prune job.
    // lib.genAttrs (map (h: "restic-repo-password-${h}") cfg.clients) (_: {
      owner = "restic";
    });

    services.restic.server = {
      enable = true;
      dataDir = cfg.dataDir;
      listenAddress = "${cfg.tailnetAddress}:${toString cfg.port}";
      appendOnly = true;
      privateRepos = true;
      htpasswd-file = config.sops.secrets.restic-server-htpasswd.path;
    };

    systemd.services.restic-rest-server.onFailure = [ "notify-restic-server-fail.service" ];
    systemd.services.notify-restic-server-fail = mkFailureUnit {
      name = "restic-rest-server";
      title = "Restic REST server DOWN on ${config.networking.hostName}";
      priority = "urgent";
      tags = "rotating_light,floppy_disk";
      body = "Desktop/laptop backups have no target. Check: journalctl -u restic-rest-server";
    };

    # Homelab-side retention: clients are append-only, so forget/prune runs
    # here, directly against the filesystem repos.
    systemd.services.restic-server-prune = {
      description = "Retention (forget --prune) on client restic repos";
      onFailure = [ "notify-restic-server-prune-fail.service" ];
      path = [ pkgs.restic ];
      serviceConfig = {
        Type = "oneshot";
        User = "restic";
        Group = "restic";
      };
      script = lib.concatMapStringsSep "\n" (h: ''
        if [ -f ${cfg.dataDir}/${h}/config ]; then
          echo "=== ${h} ==="
          export RESTIC_REPOSITORY=${cfg.dataDir}/${h}
          export RESTIC_PASSWORD_FILE=${config.sops.secrets."restic-repo-password-${h}".path}
          restic unlock   # stale locks only; won't touch a live one
          restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
          restic check
        else
          echo "=== ${h}: repo not initialized yet, skipping ==="
        fi
      '') cfg.clients;
    };

    systemd.timers.restic-server-prune = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.pruneOnCalendar;
        Persistent = true;
      };
    };

    systemd.services.notify-restic-server-prune-fail = mkFailureUnit {
      name = "restic-server-prune";
      title = "Restic repo prune FAILED on ${config.networking.hostName}";
      priority = "high";
      tags = "warning,floppy_disk";
      body = "forget/prune/check failed on a client repo (lock contention or corruption). Check: journalctl -u restic-server-prune";
    };

    services.restic.backups.b2.paths = lib.mkIf config.mySystem.services.restic.enable [
      cfg.dataDir
    ];
  };
}
