# Restic REST server: append-only landing zone for client backups (homelab:
# desktops, laptop, VPSes; outpost: homelab itself, offsite).
# Repos live under <backup mirror>/restic/<host>; clients auth via per-host
# htpasswd users (privateRepos = user X can only touch /X). Clients cannot
# delete history (--append-only); retention is enforced by the local prune
# timer below, which accesses the repos as plain paths (bypasses rest-server,
# so append-only doesn't block it).
#
# Port 8010 (mcp-nixos wrapper holds 127.0.0.1:8000; also in use — 2586 ntfy,
# 3000 open-webui, 5000 harmonia, 8080 pihole, 8384 syncthing, 8888 atuin).
# Bound to the host's tailnet IP only. The nixpkgs module is socket-activated with
# FreeBind=true, so binding the tailnet IP before tailscaled is up is fine.
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.resticServer;
  defaultRetention = [
    "--keep-daily 7"
    "--keep-weekly 4"
    "--keep-monthly 6"
  ];
in
{
  options.mySystem.services.resticServer = {
    enable = lib.mkEnableOption "Restic REST server for client host backups";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8010;
      description = "Listen port on the tailnet address.";
    };

    tailnetAddress = lib.mkOption {
      type = lib.types.str;
      example = "100.68.176.20";
      description = "This host's tailnet IP. Tailnet-only by construction (FreeBind socket).";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.mySystem.backup.mountPoint}/restic";
      description = "Repo root on the raid1 mirror. One subdir per client host.";
    };

    retention = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      example = {
        dad-pc = [
          "--keep-daily 14"
          "--keep-monthly 24"
          "--keep-yearly 10"
        ];
      };
      description = ''
        Per-client `restic forget` policy; clients not listed get
        defaultRetention. A file deleted on the client leaves the repo once
        the last snapshot holding it ages out, so records with a legal
        retention period need a --keep-yearly here.
      '';
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
    # A wrong address still binds (FreeBind) and then never receives a packet,
    # so catch the obvious mistakes at eval.
    assertions = [
      {
        assertion = builtins.match "100\\.[0-9]+\\.[0-9]+\\.[0-9]+" cfg.tailnetAddress != null;
        message = "mySystem.services.resticServer.tailnetAddress must be this host's tailnet IPv4 (100.x.y.z), got \"${cfg.tailnetAddress}\"";
      }
    ];

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
      body = "Client backups (${lib.concatStringsSep ", " cfg.clients}) have no target. Check: journalctl -u restic-rest-server";
    };

    # Server-side retention: clients are append-only, so forget/prune runs
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
          restic forget ${lib.concatStringsSep " " (cfg.retention.${h} or defaultRetention)} --prune
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

    # mkIf on the attrset, not on b2's fields: the latter still defines a b2
    # job (no repo, no password) on a server host without B2, like outpost.
    services.restic.backups = lib.mkIf config.mySystem.services.restic.enable {
      b2.paths = [ cfg.dataDir ];
      b2.exclude = [ "${cfg.dataDir}/.cache" ];
    };
  };
}
