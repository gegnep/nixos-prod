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
      mcp-nixos.enable = true;
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
      cgit.enable = true;
      unifi-backup.enable = true;
      factorio = {
        enable = true;
        admins = [ "pengeg" ];
        username = "pengeg";
        mods = [
          #{ name = "<name>"; version = "<version>"; }
          {
            name = "BottleneckLite";
            version = "1.4.0";
          }
          {
            name = "enhanced-shadows";
            version = "1.0.6";
          }
          {
            name = "flib";
            version = "0.17.1";
          }
          {
            name = "FlatUI";
            version = "1.1.10";
          }
          {
            name = "logistics-insights";
            version = "1.1.3";
          }
          {
            name = "long_stack_inserter";
            version = "1.1.1";
          }
          {
            name = "mining-patch-planner";
            version = "1.7.20";
          }
          {
            name = "OilOutpostPlanner";
            version = "1.7.0";
          }
          {
            name = "MoreTooltips";
            version = "1.0.4";
          }
          {
            name = "RateCalculator";
            version = "3.4.0";
          }
          {
            name = "Roboport-Reskin";
            version = "1.0.1";
          }
          {
            name = "squeak-through-2";
            version = "0.2.0";
          }
          {
            name = "aai-loaders";
            version = "0.3.0";
          }
          {
            name = "aai-containers";
            version = "0.4.0";
          }
          {
            name = "bullet-trails";
            version = "0.8.0";
          }
          {
            name = "textplates";
            version = "0.8.0";
          }
          {
            name = "EditorExtensions";
            version = "2.6.0";
          }
          {
            name = "rz-quality-labs";
            version = "0.3.0";
          }
          {
            name = "Better_Starmap_Background";
            version = "2.4.0";
          }
          {
            name = "Wr_Enhanced_Map_Colors";
            version = "1.5.11";
          }
          {
            name = "vtk-armor-reach";
            version = "2.0.1";
          }
          {
            name = "even-distribution";
            version = "2.1.0";
          }
          {
            name = "tree-healing";
            version = "1.2.2";
          }
        ];
      };
    };
  };
}
