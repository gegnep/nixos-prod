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

    # Latest mainline kernel — needed for good Intel Arc (DG2) support.
    kernelPackages = pkgs.linuxPackages_latest;

    kernelParams = [
      "console=tty1"
      "quiet"
      "rd.udev.log_level=3"
    ];
    consoleLogLevel = 0;
    initrd.verbose = false;
  };

  # No disk swap (disko has none); 31 GiB RAM + zram is plenty for a server.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  services.fstrim.enable = true;
}
