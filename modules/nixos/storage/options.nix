{ lib, ... }:
{
  options.mySystem = {
    backup.mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/backup";
      description = "Mount point of the redundant btrfs-raid1 backup mirror.";
    };

    storage = {
      snapshots.enable = lib.mkEnableOption "btrbk hourly snapshots (+ the top-level mount)";
      nfs.enable = lib.mkEnableOption "NFSv4 export of the backup mount";
      scrub.enable = lib.mkEnableOption "weekly btrfs scrub"; # on for all btrfs hosts
    };
  };
}
