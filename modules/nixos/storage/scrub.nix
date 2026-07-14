{ config, lib, ... }:
{
  config = lib.mkIf config.mySystem.storage.scrub.enable {
    services.btrfs.autoScrub = {
      enable = true;
      interval = "weekly";
      # snapshots.enable implies the raid1 mirror is present and mounted;
      # scrub it alongside root.
      fileSystems = [
        "/"
      ]
      ++ lib.optional config.mySystem.storage.snapshots.enable config.mySystem.backup.mountPoint;
    };
  };
}
