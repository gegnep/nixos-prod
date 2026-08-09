{ config, lib, ... }:

let
  cfg = config.mySystem.homelabCache;
in
{
  options.mySystem.homelabCache.enable = lib.mkEnableOption "substitute from the homelab harmonia cache over tailnet";

  config = lib.mkIf cfg.enable {
    nix.settings = {
      fallback = true;
      connect-timeout = 5;
      substituters = [ "http://homelab:5000" ];
      trusted-public-keys = [ "homelab-1:bmZMt7No1oGvTUNlBBm6OTeD17vRGTN1K6TNyNkSUWI=" ];
    };
  };
}
