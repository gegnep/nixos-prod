{ config, lib, ... }:

let
  cfg = config.mySystem.services.fail2ban;
  caddy = config.services.caddy;
  caddyLogs = map (
    v: "${caddy.logDir}/access-${lib.replaceStrings [ "/" " " ] [ "_" "_" ] v.hostName}.log"
  ) (lib.attrValues caddy.virtualHosts);
in
{
  options.mySystem.services.fail2ban = {
    enable = lib.mkEnableOption "fail2ban sshd jail for public ip hosts";

    caddyAuth =
      lib.mkEnableOption ''
        caddy-auth jail: bans IPs that send WRONG credentials (401 with an
        Authorization header) to any Caddy vhost. The bare 401 a browser gets
        before its login prompt carries no Authorization header, so it never counts.
        Covers basic_auth vhosts (cam, ntfy) and upstream token 401s (rustypaste)
      ''
      // {
        default = config.mySystem.services.caddy.enable && config.mySystem.proxy.tls;
        defaultText = lib.literalExpression "caddy.enable && proxy.tls";
      };
  };

  config = lib.mkIf cfg.enable {
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      ignoreIP = [ "100.64.0.0/10" ];
      bantime = "1h";
      bantime-increment = {
        enable = true;
        factor = "4";
        maxtime = "720h";
      };

      jails.caddy-auth = lib.mkIf cfg.caddyAuth {
        # Matched against Caddy's JSON access log. Tested with fail2ban-regex
        # 1.1.1 on real Caddy 2.10 lines: wrong password = hit; first-visit
        # challenge, successful login, and authed 404s = miss. Caddy redacts the
        # header value, so only the key's presence is visible.
        filter.Definition = {
          failregex = ''^.*"remote_ip":"<HOST>".*"Authorization":\["REDACTED"\].*"status":401\b'';
          ignoreregex = "";
          datepattern = ''"ts":{EPOCH}'';
        };
        settings = {
          # nixpkgs caddy default: one file per vhost, access-<host>.log
          logpath = lib.concatStringsSep "\n  " caddyLogs; # continuation lines
          backend = "auto"; # DEFAULT is systemd/journal; these are plain files
          port = "http,https";
          maxretry = 5;
          findtime = "10m";
        };
      };
    };
    systemd.services.fail2ban.preStart = lib.mkIf cfg.caddyAuth ''
      if [ -d ${caddy.logDir} ]; then
        for f in ${lib.escapeShellArgs caddyLogs}; do
          [ -e "$f" ] || install -m 0640 -o ${caddy.user} -g ${caddy.group} /dev/null "$f"
        done
      fi
    '';
  };
}
