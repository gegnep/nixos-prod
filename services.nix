{ config, ... }:

let
  mount = config.mySystem.backup.mountPoint;
in
{
  # Browsable network share of the backup mirror (NFSv4) for your desktop.
  # Mount it on blackbox in your `nixos` repo, e.g.:
  #   fileSystems."/mnt/homelab" = {
  #     device = "homelab:/"; fsType = "nfs4";
  #     options = [ "x-systemd.automount" "noauto" ];
  #   };
  services.nfs.server = {
    enable = true;
    exports = ''
      ${mount} 192.168.1.0/24(rw,sync,no_subtree_check,root_squash)
    '';
  };

  # NFSv4 needs only 2049.
  networking.firewall.allowedTCPPorts = [ 2049 ];

  # Periodic integrity scrub on both btrfs filesystems.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [
      "/"
      mount
    ];
  };
}
