{ pkgs, ... }:
{
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        editor = false;
        configurationLimit = 10;
      };
      grub.enable = false;
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };
    };

    kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      "console=tty1"
      "quiet"
      "rd.udev.log_level=3"
    ];
    consoleLogLevel = 0;
    initrd.verbose = false;
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  services.fstrim.enable = true;
}
