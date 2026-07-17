{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "oracle";
  system.stateVersion = "26.05";

  # OCI serial console (Console Connection in the web UI) — aarch64 uses ttyAMA0
  boot.kernelParams = [ "console=ttyAMA0,115200" ];

  mySystem = {
    # failure alerts POST to homelab's ntfy over the tailnet (raw IP on purpose —
    # no DNS dependency in the failure path)
    notify.url = "http://100.68.176.20:2586";

    storage.scrub.enable = true;

    services = {
      fail2ban.enable = true;
    };
  };
}
