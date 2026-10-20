{ inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./factorio.nix
    ../../modules/nixos
  ];

  networking.hostName = "homelab";

  boot = {
    binfmt.emulatedSystems = [ "aarch64-linux" ];
    loader.systemd-boot.memtest86.enable = true;
  };

  system.stateVersion = "26.05";

  environment.systemPackages = [ inputs.colmena.packages.x86_64-linux.colmena ];

  mySystem = {
    backup.mountPoint = "/backup";
    power.ignorePowerKey = true;

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
      amd = {
        enable = true;
        lactGpus = [
          "1002:7551-148C:2443-0000:13:00.0" # PCIE1
          "1002:7551-1849:5413-0000:16:00.0" # PCIE3

        ];
      };
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
      printcam = {
        name = "Core One+ (Gen2) Camera";
        description = "Live view (auth)";
        href = "https://cam.pengeg.com";
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
      printcam = {
        enable = true;
        cameraHost = "10.0.0.242"; # Buddy3D Cam
        collector.printerHost = "10.0.0.36"; # Core One+ (PrusaLink + UDP metrics)
        collector.metricsSources = [
          "10.0.0.36"
          "10.0.0.180"
        ]; # eth + wifi
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
      };
      openai-oauth.enable = true;
      tinyfish-search = {
        enable = true;
        listenAddresses = [
          "127.0.0.1"
          "100.68.176.20"
        ];
        tokenSecrets = [
          "owui-search-token"
          "twitch-bot-search-token"
        ];
      };
      mcp-nixos.enable = false;
    };
  };
}
