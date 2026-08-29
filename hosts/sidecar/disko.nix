# Single NVMe. Same subvolume set as homelab's root disk, minus the raid1 mirror.
# @models / @containers are nodatacow: large opaque blobs, CoW just fragments them.
{
  disko.devices.disk.nvme = {
    type = "disk";
    # REPLACE before running disko. `ls -l /dev/disk/by-id/ | grep -i nvme` on the target.
    device = "/dev/disk/by-id/nvme-REPLACE_ME";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "nodiscard"
                ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "nodiscard"
                ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@var-lib" = {
                mountpoint = "/var/lib";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                  "nodiscard"
                ];
              };
              "@snapshots" = {
                mountpoint = "/.snapshots";
                mountOptions = [
                  "compress=zstd"
                  "noatime"
                ];
              };
              "@models" = {
                mountpoint = "/var/lib/models";
                mountOptions = [
                  "noatime"
                  "nodatacow"
                ];
              };
              "@containers" = {
                mountpoint = "/var/lib/containers";
                mountOptions = [
                  "noatime"
                  "nodatacow"
                ];
              };
            };
          };
        };
      };
    };
  };
}
