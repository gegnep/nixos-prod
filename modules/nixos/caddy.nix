{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.caddy;
  svc = config.mySystem.services;
  d = cfg.domain;

  has = n: (svc ? ${n}) && svc.${n}.enable;

  vhost = name: port: {
    "http://${name}.${d}".extraConfig = "reverse_proxy 127.0.0.1:${toString port}";
  };
in
{
  options.mySystem.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy (name-based routing for homelab services)";

    domain = lib.mkOption {
      type = lib.types.str;
      default = "homelab";
      description = ''
        Internal suffix. Services are served as <name>.<domain>. These names must
        resolve to this host — add a wildcard record in Pi-hole (see module comment).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      virtualHosts =
        lib.optionalAttrs (has "homepage") (vhost "home" svc.homepage.port)
        // lib.optionalAttrs (has "open-webui") (vhost "ai" svc.open-webui.port)
        // lib.optionalAttrs (has "pihole") (vhost "dns" svc.pihole.webPort)
        // lib.optionalAttrs (has "syncthing") (vhost "sync" svc.syncthing.guiPort)
        // lib.optionalAttrs (has "netdata") (vhost "stats" svc.netdata.port)
        // lib.optionalAttrs (has "ntfy") (vhost "ntfy" svc.ntfy.port);
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
