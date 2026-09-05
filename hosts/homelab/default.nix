{ inputs, ... }:

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

  environment.systemPackages = [ inputs.colmena.packages.x86_64-linux.colmena ];

  mySystem = {
    backup.mountPoint = "/backup";

    storage = {
      snapshots.enable = true;
      nfs.enable = true;
      scrub.enable = true;
    };

    network = {
      uplink = "enp12s0";
      tailscale.exitNode = true;
    };

    hardware = {
      nvidia.enable = false;
      amd.enable = true;
      intel.enable = true;
    };

    proxy.externalTiles = {
      rustypaste = {
        name = "rustypaste";
        description = "Pastebin";
        href = "https://p.pengeg.com";
        group = "Public";
      };
      ntfy = {
        name = "ntfy";
        description = "Alerts (web UI)";
        href = "https://ntfy.pengeg.com";
        group = "Public";
      };
    };

    services = {
      smartd.enable = true;
      atuin = {
        enable = true;
        openRegistration = true;
      };
      buildServer.enable = true;
      flake-builder.enable = true;
      restic.enable = true;
      resticServer = {
        enable = true;
        port = 8010;
        clients = [
          "blackbox"
          "nixpad"
          "ovh"
        ];
      };
      unifi-backup.enable = true;

      homepage.enable = true;
      caddy.enable = true;
      pihole.enable = true;
      syncthing.enable = true;
      cgit.enable = true;
      ntfy = {
        enable = true;
        baseUrl = "https://ntfy.pengeg.com";
      };
      beszel = {
        hub.enable = true;
        agent = {
          enable = true;
          amd = true;
          intel = true;
          smart = true;
          containers = true;
        };
      };

      ollama = {
        enable = true;
        acceleration = "rocm";
        environment = {
          OLLAMA_CONTEXT_LENGTH = "65536";
          OLLAMA_MAX_LOADED_MODELS = "3";
          OLLAMA_NUM_PARALLEL = "2";
        };
      };
      open-webui = {
        enable = true;
        port = 3010;
      };
      unsloth = {
        enable = true;
        acceleration = "rocm";
        port = 3000;
        version = "2026.9.2";
        studioRef = "v0.1.806-beta";
      };
      openai-oauth.enable = true;
      tinyfish-search.enable = true;
      mcp-nixos.enable = false;
    };
  };
}
