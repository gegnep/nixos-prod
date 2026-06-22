{ pkgs, ... }:
{
  systemd.network = {
    enable = true;
    networks."10-wired" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
    };
  };
  networking.useNetworkd = true;
  networking.useDHCP = false;

  services.resolved.enable = true;

  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--advertise-exit-node"
      "--ssh"
    ];
  };
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  systemd.services.tailscale-gro = {
    description = "Enable UDP GRO forwarding on the uplink for Tailscale exit-node throughput";
    after = [ "sys-subsystem-net-devices-enp34s0.device" ];
    wants = [ "sys-subsystem-net-devices-enp34s0.device" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.ethtool}/bin/ethtool -K enp34s0 rx-udp-gro-forwarding on rx-gro-list off";
    };
  };

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
