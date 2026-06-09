{ config, lib, ... }:

let
  cfg = config.mySystem.services.buildServer;
in
{
  options.mySystem.services.buildServer.enable =
    lib.mkEnableOption "Remote build server + Binary cache";

  config = lib.mkIf cfg.enable {
    users.users.nixremote = {
      isNormalUser = true;
      description = "Remote Nix build user";
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL1PISMdQmn7r/XOOLDXjrQvtMw0uIOiw4LHXsUv1cyJ root@nixpad"
      ];
    };
    nix.settings.trusted-users = [ "nixremote" ];

    services.harmonia.cache = {
      enable = true;
      signKeyPaths = [ "/var/lib/harmonia/cache-priv-key.pem" ];
      settings.bind = "[::]:5000";
    };
  };
}
