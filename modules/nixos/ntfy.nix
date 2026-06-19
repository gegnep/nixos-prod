{ config, lib, ... }:

let
  cfg = config.mySystem.services.ntfy;
in
{
  options.mySystem.services.ntfy = {
    enable = lib.mkEnableOption "ntfy self-hosted push notification server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2586;
      description = ''
        HTTP listen port. Deliberately NOT 80 — ntfy's own default is :80, which
        would collide with Caddy. Caddy fronts this on :80 as the public URL.
      '';
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://ntfy.homelab";
      description = "Public base URL ntfy is served under (must match the Caddy vhost)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = cfg.baseUrl;
        listen-http = ":${toString cfg.port}";
        behind-proxy = true; # trust X-Forwarded-* from Caddy
        upstream-base-url = "https://ntfy.sh";
      };
    };

    networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];
  };
}
