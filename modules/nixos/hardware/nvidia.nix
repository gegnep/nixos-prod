{ config, lib, ... }:

let
  cfg = config.mySystem.hardware.nvidia;
in
{
  options.mySystem.hardware.nvidia.enable = lib.mkEnableOption "nvidia stuffs";

  config = lib.mkIf cfg.enable {
    hardware.graphics.enable = true;
    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia = {
      open = true;
      modesetting.enable = true;
      package = config.boot.kernelPackages.nvidiaPackages.production;
      nvidiaSettings = false;
      nvidiaPersistenced = true;
    };
    hardware.nvidia-container-toolkit.enable = true;
  };
}
