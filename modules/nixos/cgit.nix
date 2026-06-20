{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.cgit;
  sock = config.services.fcgiwrap.instances.cgit.socket.address;

  themeDir = pkgs.runCommandLocal "cgit-theme" { } ''
    mkdir -p "$out"
    cat ${./cgit-catppuccin.css} > "$out/theme.css"
  '';

  cgitrc = pkgs.writeText "cgitrc" ''
    root-title=homelab git
    root-desc=personal repositories
    css=/theme.css
    logo=/cgit.png
    favicon=/favicon.ico

    scan-path=${cfg.repoDir}
    remove-suffix=1
    enable-commit-graph=1
    enable-log-filecount=1
    enable-log-linecount=1
    max-stats=year

    clone-url=ssh://${cfg.sshUser}@git.${cfg.domain}${cfg.repoDir}/$CGIT_REPO_URL.git
  '';
in
{
  options.mySystem.services.cgit = {
    enable = lib.mkEnableOption "cgit read-only git web frontend";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = "Served as git.<domain> via Caddy (matches the Pi-hole *.homelab wildcard).";
    };

    repoDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/git";
      description = "Bare repos live here. Under @var-lib → btrbk + restic already cover it.";
    };

    sshUser = lib.mkOption {
      type = lib.types.str;
      default = "pengeg";
      description = "Existing SSH account used for push and shown in clone URLs. No dedicated git user.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.cgit;
      description = "cgit package. Swap to pkgs.cgit-pink for the actively-maintained fork.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.repoDir} 0755 ${cfg.sshUser} ${config.users.users.${cfg.sshUser}.group} - -"
    ];
    environment.systemPackages = [ pkgs.git ];
    environment.etc."gitconfig".text = ''
      [safe]
        directory = *
    '';

    users.users.cgit = {
      isSystemUser = true;
      group = "cgit";
    };
    users.groups.cgit = { };

    services.fcgiwrap.instances.cgit = {
      process = {
        user = "cgit";
        group = "cgit";
      };
      socket = {
        user = "caddy";
        group = "caddy";
      }; # caddy owns the socket so it can connect
    };

    services.caddy.virtualHosts."http://git.${cfg.domain}".extraConfig = ''
      handle /theme.css {
        root * ${themeDir}
        file_server
      }
      @asset path /cgit.png /cgit.js /favicon.ico /robots.txt
      handle @asset {
        root * ${cfg.package}/cgit
        file_server
      }
      handle {
        reverse_proxy unix/${sock} {
          transport fastcgi {
            env SCRIPT_FILENAME ${cfg.package}/cgit/cgit.cgi
            env CGIT_CONFIG ${cgitrc}
            env PATH_INFO {http.request.uri.path}
            env QUERY_STRING {http.request.uri.query}
          }
        }
      }
    '';
  };
}
