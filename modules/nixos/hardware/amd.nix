{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.hardware.amd;
in
{
  options.mySystem.hardware.amd.enable = lib.mkEnableOption "amd stuffs";

  config = lib.mkIf cfg.enable {
    hardware.amdgpu.initrd.enable = true;

    # rocm
    hardware.graphics.enable = true;
    hardware.amdgpu.opencl.enable = true;

    environment.systemPackages = with pkgs; [
      rocmPackages.rocminfo
      rocmPackages.rocm-smi
      amdgpu_top
    ];
  };
}
