{ config, lib, ... }:

let
  cfg = config.mySystem.services.fail2ban;
in
{
  options.mySystem.services.fail2ban.enable =
    lib.mkEnableOption "fail2ban sshd jail for public ip hosts";

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
    };
  };
}
