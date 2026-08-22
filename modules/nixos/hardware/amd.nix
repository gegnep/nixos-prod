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
    hardware.amdgpu = {
      initrd.enable = true;
      overdrive = {
        enable = true;
        ppfeaturemask = "0xfffd7fff";
      };
    };

    services.lact.enable = true;

    environment.etc."lact/config.yaml".text = ''
      version: 6
      daemon:
        log_level: info
        admin_group: wheel
      gpus:
        "1002:7551-148C:2443-0000:13:00.0":
          fan_control_enabled: true
          fan_control_settings:
            mode: curve
            temperature_key: junction
            interval_ms: 500
            spindown_delay_ms: 5000
            change_threshold: 2
            curve:
              45: 0.20
              60: 0.24
              72: 0.34
              82: 0.55
              92: 0.90
          pmfw_options:
            zero_rpm: false
            minimum_pwm: 20
            target_temperature: 80
    '';

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
