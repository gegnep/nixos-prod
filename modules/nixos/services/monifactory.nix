{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.monifactory;
  podman = "${config.virtualisation.podman.package}/bin/podman";
  rcon = cmd: "${podman} exec monifactory rcon-cli ${cmd}";
in
{
  options.mySystem.services.monifactory = {
    enable = lib.mkEnableOption "Monifactory server (itzg/minecraft-server, Forge)";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/itzg/minecraft-server:2026.10.1-java17";
      description = "Pinned image. java17: Forge 1.20.1 mods break on newer JVMs. Multi-arch (arm64).";
    };

    packVersion = lib.mkOption {
      type = lib.types.str;
      default = "0.13.8";
      description = "Monifactory release tag; selects the server.zip. The client instance must match.";
    };

    forgeVersion = lib.mkOption {
      type = lib.types.str;
      default = "47.4.13";
      description = "Forge version the pack README names for this release.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 25565;
      description = "Game TCP port (tailnet only).";
    };

    memory = lib.mkOption {
      type = lib.types.str;
      default = "10G";
      description = "JVM heap. On oracle this also keeps memory above the A1 idle-reclaim floor (20%).";
    };

    players = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Usernames to whitelist and op. itzg resolves UUIDs at start.";
    };

    mods = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Extra jar URLs on top of the pack (addons, server-only tools). Anything
        not server-only must be on the client at the same version. Dropping an
        entry deletes that jar on the next start.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        systemd.tmpfiles.rules = [ "d /var/lib/monifactory 0750 1000 1000 -" ];

        virtualisation.oci-containers.containers.monifactory = {
          image = cfg.image;
          autoStart = true;
          extraOptions = [
            "--network=host"
            "--stop-timeout=180"
          ];
          volumes = [ "/var/lib/monifactory:/data" ];
          environment = {
            EULA = "TRUE";
            TYPE = "FORGE";
            VERSION = "1.20.1";
            FORGE_VERSION = cfg.forgeVersion;
            GENERIC_PACK = "https://github.com/Omicron-Industries/Monifactory/releases/download/${cfg.packVersion}/Monifactory-Beta.${cfg.packVersion}-server.zip";

            MEMORY = cfg.memory;
            USE_AIKAR_FLAGS = "true";
            STOP_DURATION = "150";
            TZ = "America/Kentucky/Louisville";

            SERVER_PORT = toString cfg.port;
            MOTD = "monifactory";
            MAX_PLAYERS = "4";
            LEVEL_TYPE = "lostcities:lostcity";
            DIFFICULTY = "peaceful";
            ALLOW_FLIGHT = "TRUE";
            VIEW_DISTANCE = "10";
            SIMULATION_DISTANCE = "8";

            ENABLE_WHITELIST = "TRUE";
            WHITELIST = lib.concatStringsSep "," cfg.players;
            OPS = lib.concatStringsSep "," cfg.players;
          }
          # An empty MODS tells itzg to remove every mod it manages: only set it when non-empty.
          // lib.optionalAttrs (cfg.mods != [ ]) { MODS = lib.concatStringsSep "\n" cfg.mods; };
        };

        systemd.services.podman-monifactory = {
          serviceConfig.TimeoutStopSec = lib.mkForce 210;
          onFailure = [ "notify-monifactory-fail.service" ];
          # The pack ships FTB Backups 2; restic covers backups. Its config is
          # runtime-generated (not pack-managed), so flip it off on every start.
          preStart = lib.mkAfter ''
            f=/var/lib/monifactory/config/ftbbackups2.json
            if [ -f "$f" ]; then
              ${pkgs.gnused}/bin/sed -i -E 's/("enabled"[[:space:]]*:[[:space:]]*)true/\1false/' "$f"
              chown 1000:1000 "$f"
            fi
          '';
        };
        systemd.services."notify-monifactory-fail" = mkFailureUnit {
          name = "monifactory";
          title = "Monifactory server failed";
          body = "podman-monifactory.service entered failed state (crashloop?). Check journalctl -u podman-monifactory.";
          tags = "video_game,warning";
        };

        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
      }

      # Freeze world writes while restic reads them. The restic module runs the
      # cleanup command in postStop, which also fires on failure, so save-on always comes back.
      (lib.mkIf config.mySystem.services.resticClient.enable {
        services.restic.backups.homelab = {
          backupPrepareCommand = ''
            if ${rcon "save-off"}; then
              ${rcon "save-all flush"}
            else
              echo "monifactory not running; backing up cold" >&2
            fi
          '';
          backupCleanupCommand = ''
            ${rcon "save-on"} || true
          '';
        };
      })
    ]
  );
}
