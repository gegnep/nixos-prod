{ lib, config, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "ovh";
  system.stateVersion = "26.05";

  boot.kernelParams = [ "console=ttyS0,115200" ]; # OVH KVM/rescue console
  boot.loader = {
    systemd-boot.enable = lib.mkForce false;
    efi.canTouchEfiVariables = lib.mkForce false;
    grub = {
      enable = lib.mkForce true;
    };
  };

  sops.secrets.caddy-env.restartUnits = [ "caddy.service" ];

  mySystem = {
    notify.url = "http://100.68.176.20:2586";
    storage.scrub.enable = true;

    proxy = {
      domain = "pengeg.com";
      tls = true;
      acmeEmail = "noreply@pengeg.com";
      vhosts.ntfy = {
        sub = "ntfy";
        rawConfig = ''
          basic_auth {
            pen {$NTFY_PASS_HASH}
          }
          reverse_proxy 100.68.176.20:2586
        '';
      };

    };

    services = {
      caddy = {
        enable = true;
        environmentFile = config.sops.secrets.caddy-env.path;
      };
      mcp-nixos = {
        enable = true;
        funnel = false;
      };
      rustypaste.enable = true;
      fail2ban.enable = true;
      resticClient = {
        enable = true;
        paths = [
          "/var/lib/rustypaste"
          "/var/lib/caddy"
        ];
      };
    };
  };
}
