{ config, ... }:
let
  target = config.mySystem.backup.mountPoint;
in
{
  fileSystems."/mnt/nvme" = {
    device = "/dev/disk/by-partlabel/disk-nvme-root";
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "noatime"
      "nofail"
    ];
  };

  services.btrbk.instances.homelab = {
    onCalendar = "hourly";
    settings = {
      snapshot_preserve_min = "latest";
      snapshot_preserve = "24h 7d 4w";
      target_preserve_min = "no";
      target_preserve = "24h 7d 4w";
      snapshot_dir = "@snapshots";
      volume."/mnt/nvme" = {
        target = "${target}/btrbk";
        subvolume = {
          "@var-lib" = { };
          "@home" = { };
        };
      };
    };
  };

  systemd.tmpfiles.rules = [ "d ${target}/btrbk 0755 root root -" ];
}
