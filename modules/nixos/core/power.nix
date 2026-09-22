{ config, lib, ... }:

let
  cfg = config.mySystem.power;
in
{
  options.mySystem.power.ignorePowerKey = lib.mkEnableOption "ignore the physical power button";

  config = lib.mkIf cfg.ignorePowerKey {
    services.logind.settings.Login.HandlePowerKey = "ignore";
  };
}
