{ config, lib, ... }:
let
  mirror = config.mySystem.backup.mountPoint;
in
{
  config = lib.mkIf config.mySystem.storage.scrub.enable {
    services.btrfs.autoScrub = {
      enable = true;
      interval = "monthly";
      limit = "100M";
      # The raid1 mirror is the filesystem scrub can actually repair, so it goes
      # in wherever it is mounted (homelab /backup, outpost /data), snapshots or not.
      fileSystems = [ "/" ] ++ lib.optional (config.fileSystems ? ${mirror}) mirror;
    };
  };
}
