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
    hardware = {
      nvidia.enable = true;
    };
    services = {
      pihole.enable = true;
      buildServer.enable = true;
      syncthing.enable = true;
      ollama.enable = true;
    };
  };
}
