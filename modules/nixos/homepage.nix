{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.homepage;
  svc = config.mySystem.services;
  d = cfg.domain;

  has = n: (svc ? ${n}) && svc.${n}.enable;
in
{
  options.mySystem.services.homepage = {
    enable = lib.mkEnableOption "Homepage dashboard";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8082;
      description = "Listen port (bound by the upstream module; reached through Caddy)";
    };

    domain = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = "Internal suffix used to build service links (must match Caddy)";
    };
  };

  config = lib.mkIf cfg.enable {
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

      services = [
        {
          Services = builtins.concatLists [
            (lib.optional (has "open-webui") {
              "Open WebUI" = {
                href = "http://ai.${d}";
                description = "Ollama chat frontend";
              };
            })
            (lib.optional (has "pihole") {
              "Pi-hole" = {
                href = "http://dns.${d}/admin";
                description = "DNS / adblock";
              };
            })
            (lib.optional (has "syncthing") {
              "Syncthing" = {
                href = "http://sync.${d}";
                description = "File sync";
              };
            })
            (lib.optional ((svc ? beszel) && svc.beszel.hub.enable) {
              "Beszel" = {
                href = "http://stats.${d}";
                description = "Metrics & GPU";
              };
            })
            (lib.optional (has "atuin") {
              "Atuin" = {
                href = "http://atuin.homelab";
                description = "Shell history sync";
              };
            })
            (lib.optional (has "cgit") {
              "cgit" = {
                href = "http://git.${d}";
                description = "Git repositories";
              };
            })
            (lib.optional (has "ntfy") {
              "ntfy" = {
                href = "http://ntfy.${d}";
                description = "Push notifications";
              };
            })
          ];
        }
      ];

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
