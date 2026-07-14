{ config, lib, ... }:

let
  mount = config.mySystem.backup.mountPoint;
in
{
  config = lib.mkIf config.mySystem.storage.nfs.enable {
    # Mount:
    #   fileSystems."/mnt/homelab" = {
    #     device = "homelab:/"; fsType = "nfs4";
    #     options = [ "x-systemd.automount" "noauto" ];
    #   };
    services.nfs.server = {
      enable = true;
      exports = ''
        ${mount} 192.168.1.0/24(rw,sync,no_subtree_check,root_squash,fsid=0) 100.64.0.0/10(rw,sync,no_subtree_check,root_squash,fsid=0)
      '';
    };
    systemd.tmpfiles.rules = [
      "d /backup 0755 pengeg users -"
    ];

    # NFSv4 needs only 2049.
    networking.firewall.allowedTCPPorts = [ 2049 ];
  };
}
