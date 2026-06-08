{ ... }:
{
  # systemd-networkd, DHCP on the wired NIC. Matching en* survives a NIC
  # rename. STRONGLY recommended: add a DHCP reservation on your router for
  # this box's MAC so its IP is stable, OR uncomment the static block below.
  systemd.network = {
    enable = true;
    networks."10-wired" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
      # --- static alternative (matches the old Proxmox .200) ---
      # address = [ "192.168.1.200/24" ];
      # routes = [ { Gateway = "192.168.1.254"; } ];
      # networkConfig.DHCP = "no";
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
      PermitRootLogin = "prohibit-password"; # key-only root, no password login
    };
  };

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ];
  };
}
