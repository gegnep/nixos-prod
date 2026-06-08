{ lib, ... }:
{
  # Slim mySystem namespace, mirrors the desktop repo's gating pattern.
  # Grow this as services land (e.g. mySystem.services.jellyfin.enable).
  options.mySystem = {
    backup.mountPoint = lib.mkOption {
      type = lib.types.str;
      default = "/backup";
      description = "Mount point of the redundant btrfs-raid1 backup mirror.";
    };
  };
}
