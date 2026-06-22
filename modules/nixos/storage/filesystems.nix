{ ... }:
{
  # Mount the btrfs top-level (subvolid=5) so btrbk can reach the @home/@var-lib
  # subvolumes for snapshotting. nofail so a missing disk never blocks boot.
  fileSystems."/mnt/nvme" = {
    device = "/dev/disk/by-partlabel/disk-nvme-root";
    fsType = "btrfs";
    options = [
      "subvolid=5"
      "noatime"
      "nofail"
    ];
  };
}
