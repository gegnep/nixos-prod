{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "sidecar";
  system.stateVersion = "26.11";

  mySystem = {
    # raw tailnet IP on purpose: no DNS dependency in the failure path
    notify.url = "http://100.68.176.20:2586";

    homelabCache.enable = true;
    colmenaTarget.enable = true;

    storage.scrub.enable = true;

    hardware = {
      nvidia.enable = true;
    };

    services = {
      smartd.enable = true;
      beszel.agent = {
        enable = true;
        smart = true;
        containers = true;
        nvidia = true;
      };

      ollama = {
        enable = true;
        acceleration = "cuda";
      };
    };
  };
}
