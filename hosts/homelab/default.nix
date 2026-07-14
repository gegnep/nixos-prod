{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./factorio.nix
    ../../modules/nixos
  ];

  networking.hostName = "homelab";

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  system.stateVersion = "26.05";

  mySystem = {
    backup.mountPoint = "/backup";
    storage = {
      snapshots.enable = true;
      nfs.enable = true;
      scrub.enable = true;
    };
    network = {
      uplink = "enp34s0";
      tailscale.exitNode = true;
    };
    hardware = {
      nvidia.enable = true;
      intel.enable = true;
    };
    services = {
      pihole.enable = true;
      buildServer.enable = true;
      flake-builder.enable = true;
      syncthing.enable = true;
      ollama.enable = true;
      open-webui = {
        enable = true;
        port = 3000;
      };
      mcp-nixos.enable = false;
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
      resticServer = {
        enable = true;
        port = 8010;
      };
      cgit.enable = true;
      unifi-backup.enable = true;
    };
  };
}
