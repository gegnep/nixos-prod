{ config, lib, ... }:
{
  config = lib.mkIf config.mySystem.storage.snapshots.enable {
    # Mount the btrfs top-level (subvolid=5) so btrbk can reach @home/@var-lib.
    fileSystems."/mnt/nvme" = {
      device = "/dev/disk/by-partlabel/disk-nvme-root";
      fsType = "btrfs";
      options = [
        "subvolid=5"
        "noatime"
        "nofail"
      ];
    };
  };
}
