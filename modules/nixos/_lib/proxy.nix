# Reverse-proxy + dashboard registry — the write/read contract that decouples
# services from Caddy and Homepage.
#
#   A service WRITES one entry (inside its own mkIf cfg.enable):
#     mySystem.proxy.vhosts.<key> = {
#       sub = "ai";                                   # served as ai.<domain>
#       upstream = "127.0.0.1:${toString cfg.port}";  # plain reverse_proxy target
#       dashboard = { name = "Open WebUI"; description = "..."; };  # optional tile
#     };
#   web/caddy.nix READS it -> services.caddy.virtualHosts (sole writer).
#   web/homepage.nix READS it -> a dashboard tile per entry with dashboard != null.
#
# A disabled/deleted service registers nothing, so its vhost and tile vanish with it.
{ lib, ... }:
let
  dashboardType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "Tile title on the Homepage dashboard.";
      };
      description = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Tile subtitle.";
      };
      path = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''Href suffix appended after http://<sub>.<domain>, e.g. "/admin".'';
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = "Services";
        description = "Dashboard group; needs a matching settings.layout entry in homepage.nix.";
      };
    };
  };

  vhostType = lib.types.submodule {
    options = {
      sub = lib.mkOption {
        type = lib.types.str;
        description = "Subdomain label; the vhost is served as <sub>.<domain>.";
      };
      upstream = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "host:port for a plain reverse_proxy. Ignored when rawConfig is set.";
      };
      rawConfig = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Verbatim Caddyfile vhost body; overrides upstream when non-empty.";
      };
      dashboard = lib.mkOption {
        type = lib.types.nullOr dashboardType;
        default = null;
        description = "Homepage tile for this vhost, or null for no tile.";
      };
    };
  };
in
{
  options.mySystem.proxy = {
    domain = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = ''
        Internal suffix. Services are served as <sub>.<domain> by Caddy. These names
        must resolve to this host (the Pi-hole *.homelab wildcard).
      '';
    };

    vhosts = lib.mkOption {
      type = lib.types.attrsOf vhostType;
      default = { };
      description = ''
        Reverse-proxy + dashboard registry. A service writes ONE entry inside its own
        mkIf cfg.enable; web/caddy.nix folds them into virtualHosts and web/homepage.nix
        renders a tile for entries whose dashboard != null.
      '';
    };

    externalTiles = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            href = lib.mkOption {
              type = lib.types.str;
              description = "Full URL — external tiles aren't derived from this host's domain.";
            };
            name = lib.mkOption { type = lib.types.str; };
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
            };
            group = lib.mkOption {
              type = lib.types.str;
              default = "Services";
            };
          };
        }
      );
      default = { };
      description = ''
        Dashboard tiles for services not proxied by this host (e.g. public vhosts on
        another machine). Rendered by web/homepage.nix alongside registry tiles.
      '';
    };

    tls = lib.mkEnableOption "ACME TLS: vhosts become https://<sub>.<domain> (public hosts). Off = plain-HTTP internal vhosts.";

    acmeEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "ACME account email passed to Caddy; recommended when tls is on.";
    };
  };
}
