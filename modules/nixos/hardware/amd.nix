{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.hardware.amd;

  # LACT wants integer curve keys, so the YAML stays hand-written text
  # (pkgs.formats.yaml would quote attr-name keys). '' strings strip common
  # indentation, so each block is re-indented under `gpus:` explicitly.
  indent = s: lib.concatMapStrings (l: "  ${l}\n") (lib.init (lib.splitString "\n" s));
  gpuBlock =
    id:
    indent ''
      "${id}":
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
in
{
  options.mySystem.hardware.amd = {
    enable = lib.mkEnableOption "amd stuffs";

    lactGpus = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "1002:7551-148C:2443-0000:13:00.0" ];
      description = ''
        LACT GPU ids (VENDOR:DEVICE-SUBVENDOR:SUBDEVICE-PCI_SLOT) that get the
        shared R9700 blower fan curve. The PCI slot is part of the id, so a card
        that moves bus after a hardware change silently falls back to stock fans.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.amdgpu = {
      initrd.enable = true;
      overdrive = {
        enable = true;
        ppfeaturemask = "0xfffd7fff";
      };
    };

    services.lact.enable = true;
    systemd.services.lactd.serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/rm -f /run/lactd.sock";

    environment.etc."lact/config.yaml".text = ''
      version: 7
      daemon:
        log_level: info
        admin_group: wheel
      gpus:
    ''
    + lib.concatMapStrings gpuBlock cfg.lactGpus;

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
