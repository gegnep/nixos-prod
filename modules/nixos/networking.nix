{ ... }:
{
  systemd.network = {
    enable = true;
    networks."10-wired" = {
      matchConfig.Name = "en*";
      networkConfig = {
        #Address = "192.168.1.200/24";
        #Gateway = "192.168.1.254";
        #DNS = "192.168.1.254";
        DHCP = "yes";
      };
    };
  };
  networking.useNetworkd = true;
  networking.useDHCP = false;

  services.resolved.enable = true;

  services.tailscale.enable = true;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
