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
  options.mySystem.services.caddy.enable =
    lib.mkEnableOption "Caddy reverse proxy (folds the mySystem.proxy.vhosts registry)";

  config = lib.mkIf cfg.enable {
    services.caddy = {
      enable = true;

      # Sole writer of virtualHosts: one vhost per registry entry. A plain entry
      # becomes `reverse_proxy <upstream>`; an entry with rawConfig uses it verbatim.
      virtualHosts = lib.mapAttrs' (
        _: v:
        lib.nameValuePair "http://${v.sub}.${proxy.domain}" {
          extraConfig = if v.rawConfig != "" then v.rawConfig else "reverse_proxy ${v.upstream}";
        }
      ) proxy.vhosts;
    };

    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
