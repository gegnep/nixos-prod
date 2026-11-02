{ config, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "outpost";
  system.stateVersion = "26.11";

  # Joins the tailnet on first boot: it sits on a LAN the homelab can't reach.
  sops.secrets.tailscale-authkey = { };
  services.tailscale.authKeyFile = config.sops.secrets.tailscale-authkey.path;
  # Parents' LAN. Home is 10.0.0.0/24, so no overlap with the homelab side.
  services.tailscale.extraSetFlags = [ "--advertise-routes=192.168.1.0/24" ];

  mySystem = {
    network = {
      uplink = "enp0s31f6";
      tailscale.exitNode = true;
    };

    # raw tailnet IP on purpose: no DNS dependency in the failure path
    notify.url = "http://100.68.176.20:2586";

    homelabCache.enable = true;
    colmenaTarget.enable = true;

    storage.scrub.enable = true;

    services.smartd.enable = true;
  };
}
