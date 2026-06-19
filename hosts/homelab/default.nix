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
      open-webui = {
        enable = true;
        port = 3000;
      };
      smartd.enable = true;
      ntfy.enable = true;
      caddy.enable = true;
      homepage.enable = true;
      netdata.enable = false;
      beszel = {
        hub.enable = true;
        agent = {
          enable = true;
          nvidia = true;
          smart = true;
          containers = true;
        };
      };
      atuin = {
        enable = true;
        openRegistration = true;
      };
      restic.enable = true;
    };
  };
}
