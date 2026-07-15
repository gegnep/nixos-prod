{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "ovh";
  system.stateVersion = "26.05";
  boot.kernelParams = [ "console=ttyAMA0,115200" ]; # OVH KVM/rescue console

  mySystem = {
    notify.url = "http://100.68.176.20:2586";
    storage.scrub.enable = true;

    proxy = {
      domain = "pengeg.com";
      tls = true;
      acmeEmail = "noreply@pengeg.com";
    };

    services = {
      caddy.enable = true;
      mcp-nixos = {
        enable = true;
        funnel = false;
      };
      rustypaste.enable = true;
    };
  };
}
