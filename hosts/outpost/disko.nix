# NVMe root: sidecar's subvolume set minus @models/@containers.
# 2x 4 TB SATA (ST4000DM004, SMR): btrfs raid1 -> /data, homelab's mirror pattern.
# btrfs content lives on hdd2 (processed 2nd, alphabetically) and references
# hdd1's part1 (created 1st). This ordering is load-bearing, do not rename.
{
  disko.devices.disk = {
    nvme = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-Samsung_SSD_970_EVO_Plus_1TB_S6S1NS0T606707X";
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
              };
            };
          };
        };
      };
    };

    # First disk of the mirror: partitioned, no content (consumed by hdd2 mkfs)
    hdd1 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST4000DM004-2U9104_ZTT4B47Y";
      content = {
        type = "gpt";
        partitions.data.size = "100%";
      };
    };

    # Second disk: holds the btrfs content, builds the raid1 across both
    hdd2 = {
      type = "disk";
      device = "/dev/disk/by-id/ata-ST4000DM004-2U9104_ZTT4B51L";
      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [
              "-f"
              "-d"
              "raid1"
              "-m"
              "raid1"
              "/dev/disk/by-id/ata-ST4000DM004-2U9104_ZTT4B47Y-part1"
            ];
            subvolumes."@data" = {
              mountpoint = "/data";
              mountOptions = [
                "compress=zstd"
                "noatime"
              ];
            };
          };
        };
      };
    };
  };
}
