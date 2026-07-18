{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.caddy;
  proxy = config.mySystem.proxy;
in
{
  options.mySystem.services.caddy = {
    enable = lib.mkEnableOption "Caddy reverse proxy (folds the mySystem.proxy.vhosts registry)";
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "EnvironmentFile for Caddyfile subst.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;
      email = proxy.acmeEmail;
      environmentFile = cfg.environmentFile;

      virtualHosts = lib.mapAttrs' (
        _: v:
        lib.nameValuePair (
          if proxy.tls then "${v.sub}.${proxy.domain}" else "http://${v.sub}.${proxy.domain}"
        ) { extraConfig = if v.rawConfig != "" then v.rawConfig else "reverse_proxy ${v.upstream}"; }
      ) proxy.vhosts;
    };

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional proxy.tls 443;
  };
}
