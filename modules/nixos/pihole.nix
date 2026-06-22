{ config, lib, ... }:

let
  cfg = config.mySystem.services.pihole;
in
{
  options.mySystem.services.pihole = {
    enable = lib.mkEnableOption "Pi-hole DNS adblocker";

    image = lib.mkOption {
      type = lib.types.str;
      default = "pihole/pihole:2026.05.0";
      description = "Pinned Pi-hole container image";
    };

    timezone = lib.mkOption {
      type = lib.types.str;
      default = "America/Kentucky/Louisville";
      description = "Container timezone";
    };

    upstreams = lib.mkOption {
      type = lib.types.str;
      default = "1.1.1.1;1.0.0.1";
      description = "Upstream resolvers (';' seperated)";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Pi-hole web UI port";
    };
  };

  config = lib.mkIf cfg.enable {
    services.resolved.settings.Resolve.DNSStubListener = "no";

    # podman + oci backend live in virtualisation.nix (shared container runtime).
    virtualisation.oci-containers.containers.pihole = {
      image = cfg.image;
      autoStart = true;
      extraOptions = [ "--network=host" ];

      environment = {
        TZ = cfg.timezone;
        FTLCONF_dns_upstreams = cfg.upstreams;
        FTLCONF_dns_listeningMode = "all";
        FTLCONF_webserver_port = toString cfg.webPort;
        FTLCONF_webserver_domain = "dns.homelab";
        FTLCONF_misc_dnsmasq_lines = "address=/homelab/100.68.176.20";
      };

      # Admin/API password lives OUTSIDE the world-readable Nix store.
      # Create /var/lib/pihole/secret.env (root-only) containing:
      #   FTLCONF_webserver_api_password=<your-password>
      environmentFiles = [ config.sops.templates."pihole.env".path ];

      volumes = [ "/var/lib/pihole/etc-pihole:/etc/pihole" ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/pihole 0750 root root -"
      "d /var/lib/pihole/etc-pihole 0755 root root -"
    ];

    networking.firewall = {
      allowedTCPPorts = [
        53
        cfg.webPort
      ];
      allowedUDPPorts = [ 53 ];
    };

    mySystem.proxy.vhosts.pihole = {
      sub = "dns";
      upstream = "127.0.0.1:${toString cfg.webPort}";
      dashboard = {
        name = "Pi-hole";
        description = "DNS / adblock";
        path = "/admin";
        order = 20;
      };
    };
  };
}
