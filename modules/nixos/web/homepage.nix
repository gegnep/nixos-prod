{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.homepage;
  proxy = config.mySystem.proxy;
  d = proxy.domain;

  # Tiles come from the proxy registry: every vhost whose dashboard != null.
  tiled = lib.filter (v: v.dashboard != null) (lib.attrValues proxy.vhosts);
  sorted = lib.sort (
    a: b:
    if a.dashboard.order != b.dashboard.order then
      a.dashboard.order < b.dashboard.order
    else
      a.dashboard.name < b.dashboard.name
  ) tiled;

  mkTile = v: {
    ${v.dashboard.name} = {
      href = "http://${v.sub}.${d}${v.dashboard.path}";
      description = v.dashboard.description;
    };
  };
  groups = lib.unique (map (v: v.dashboard.group) sorted);
  mkGroup = g: {
    ${g} = map mkTile (lib.filter (v: v.dashboard.group == g) sorted);
  };
in
{
  options.mySystem.services.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Listen port (bound by the upstream module; reached through Caddy)";
    };
  };

  config = lib.mkIf cfg.enable {
    # Homepage is itself proxied as home.<domain> (no tile for itself).
    mySystem.proxy.vhosts.homepage = {
      sub = "home";
      upstream = "127.0.0.1:${toString cfg.port}";
    };

    services.homepage-dashboard = {
      enable = true;
      listenPort = cfg.port;
      allowedHosts = "home.${d},localhost:${toString cfg.port},127.0.0.1:${toString cfg.port}";

      settings = {
        title = "homelab";
        theme = "dark";
        color = "gray";
        headerStyle = "clean";
        layout = [
          {
            Services = {
              style = "row";
              columns = 3;
            };
          }
        ];
      };

      widgets = [
        {
          resources = {
            cpu = true;
            memory = true;
          };
        }
        {
          resources = {
            label = "root";
            disk = "/";
          };
        }
        {
          resources = {
            label = "backup";
            disk = "/backup";
          };
        }
        {
          search = {
            provider = "brave";
            target = "_blank";
          };
        }
      ];

      # Dashboard tiles, folded from the proxy registry (see mkGroup above).
      services = map mkGroup groups;

      customCSS = ''
        /* Catppuccin Mocha — override homepage's gray palette (R G B triplets) */
        .theme-gray {
          --color-200: 205 214 244 !important;  /* text  (#cdd6f4) */
          --color-800: 30 30 46    !important;  /* base  (#1e1e2e) — card/widget bg */
          --color-900: 17 17 27    !important;  /* crust (#11111b) — page bg */
        }
      '';
    };
  };
}
