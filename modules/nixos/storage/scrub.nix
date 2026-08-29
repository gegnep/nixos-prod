{ config, lib, ... }:
{
  config = lib.mkIf config.mySystem.storage.scrub.enable {
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      limit = "100M";
      fileSystems = [
        "/"
      ]
      ++ lib.optional config.mySystem.storage.snapshots.enable config.mySystem.backup.mountPoint;
    };
  };
}
