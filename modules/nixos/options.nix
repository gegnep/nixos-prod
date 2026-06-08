{ lib, ... }:
{
  options.mySystem = {
    backup.mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/backup";
      description = "Mount point of the redundant btrfs-raid1 backup mirror.";
    };
  };
}
