{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mySystem.hardware.intel;
in
{
  options.mySystem.hardware.intel.enable = lib.mkEnableOption "Intel/Arc graphics + media stack";

  config = lib.mkIf cfg.enable {
    hardware.enableRedistributableFirmware = true;
    hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        vpl-gpu-rt
      ];
    };
  };
}
