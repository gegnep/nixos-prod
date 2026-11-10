# Immich: phone photo backup + browsable library.
# Originals on the bulk mirror (<backup mirror>/immich); Postgres and the ML
# model cache stay on the NVMe (/var/lib, /var/cache). Immich writes its own
# nightly pg_dumpall into <mediaLocation>/backups, so backing up mediaLocation
# covers the DB without touching live PG files.
#
# Port 2283 (upstream default; nothing else on outpost uses it). Listens on all
# interfaces but the port is NOT opened in the firewall: tailscale0 is a
# trusted interface, so it is tailnet-only. No FreeBind here, so binding the
# tailnet IP directly would race tailscaled at boot.
{ config, lib, ... }:

let
  cfg = config.mySystem.services.immich;
in
{
  options.mySystem.services.immich = {
    enable = lib.mkEnableOption "Immich photo backup (tailnet-only)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2283;
      description = "Listen port. Reachable over tailscale0 only.";
    };

    mediaLocation = lib.mkOption {
      type = lib.types.str;
      default = "${config.mySystem.backup.mountPoint}/immich";
      description = "Originals, thumbs, transcodes and Immich's own DB dumps.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.immich = {
      enable = true;
      host = "0.0.0.0";
      port = cfg.port;
      openFirewall = false;
      mediaLocation = cfg.mediaLocation;
      # CPU inference (CLIP search, faces). No GPU passthrough.
      accelerationDevices = [ ];
      # null = configure in the web UI (storage template, jobs, API keys).
      settings = null;
    };

    # The nixpkgs module only adjusts an existing mediaLocation (tmpfiles `e`);
    # a non-default path has to be created. "10-" sorts before the module's
    # immich.conf so this `d` line is the one that applies.
    systemd.tmpfiles.settings."10-immich-media".${cfg.mediaLocation}.d = {
      user = config.services.immich.user;
      group = config.services.immich.group;
      mode = "0700";
    };

    # Don't start against an unmounted mirror and fill the NVMe root.
    systemd.services.immich-server.unitConfig.RequiresMountsFor = [ cfg.mediaLocation ];
  };
}
