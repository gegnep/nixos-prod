{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.mySystem.network;
in
{
  options.mySystem.network = {
    uplink = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "NIC for the tailscale UDP-GRO oneshot; null skips the unit entirely.";
    };
    tailscale.exitNode = lib.mkEnableOption "advertise this host as a tailscale exit node";
  };

  config = {
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
      useRoutingFeatures = if cfg.tailscale.exitNode then "server" else "none";
      extraSetFlags = [ "--ssh" ] ++ lib.optionals cfg.tailscale.exitNode [ "--advertise-exit-node" ];
    };
    networking.firewall.trustedInterfaces = [ "tailscale0" ];

    systemd.services.tailscale-gro = lib.mkIf (cfg.uplink != null) {
      description = "Enable UDP GRO forwarding on the uplink for Tailscale exit-node throughput";
      after = [ "sys-subsystem-net-devices-${cfg.uplink}.device" ];
      wants = [ "sys-subsystem-net-devices-${cfg.uplink}.device" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.ethtool}/bin/ethtool -K ${cfg.uplink} rx-udp-gro-forwarding on rx-gro-list off";
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
  };
}
