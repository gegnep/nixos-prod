{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "homelab";

  system.stateVersion = "26.05";

  mySystem = {
    backup.mountPoint = "/backup";
    services = {
      pihole.enable = true;
      buildServer.enable = true;
    };
  };
}
