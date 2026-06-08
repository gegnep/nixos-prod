# Validated: generates ONE `mkfs.btrfs -d raid1 -m raid1` consuming both SATA
# partitions, and both partitions are created before that mkfs runs.
# btrfs content lives on backup2 (processed 2nd, alphabetically) and references
# backup1's part1 (created 1st) — this ordering is load-bearing, do not rename.
{
  disko.devices.disk = {
    nvme = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_1TB_S59ANMFNA00350X";
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
                "@"          = { mountpoint = "/";           mountOptions = [ "compress=zstd" "noatime" ]; };
                "@nix"       = { mountpoint = "/nix";        mountOptions = [ "compress=zstd" "noatime" ]; };
                "@home"      = { mountpoint = "/home";       mountOptions = [ "compress=zstd" "noatime" ]; };
                "@var-lib"   = { mountpoint = "/var/lib";    mountOptions = [ "compress=zstd" "noatime" ]; };
                "@snapshots" = { mountpoint = "/.snapshots"; mountOptions = [ "compress=zstd" "noatime" ]; };
              };
            };
          };
        };
      };
    };

    # First disk of the mirror: partitioned, no content (consumed by backup2 mkfs)
    backup1 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-CT2000BX500SSD1_2525E9C3D2D2";
      content = {
        type = "gpt";
        partitions.backup.size = "100%";
      };
    };

    # Second disk: holds the btrfs content, builds the raid1 across both
    backup2 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-CT2000BX500SSD1_2525E9C3D342";
      content = {
        type = "gpt";
        partitions.backup = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" "-d" "raid1" "-m" "raid1" "/dev/disk/by-id/ata-CT2000BX500SSD1_2525E9C3D2D2-part1" ];
            subvolumes."@backup" = { mountpoint = "/backup"; mountOptions = [ "compress=zstd" "noatime" ]; };
          };
        };
      };
    };
  };
}
