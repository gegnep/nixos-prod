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

      inference = {
        enable = true;
        acceleration = "cuda";
      };

      # UI layer lives here so homelab's RAM goes to inference. homelab's Caddy
      # serves it as ai.homelab (vhost in hosts/homelab).
      open-webui = {
        enable = true;
        port = 3010;
      };
      openai-oauth.enable = true;

      # Open WebUI's database holds config that exists nowhere in the flake.
      resticClient = {
        enable = true;
        paths = [ "/var/lib/private/open-webui" ];
      };
    };
  };
}
