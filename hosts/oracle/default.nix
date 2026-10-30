{ ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./monifactory.nix
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
    homelabCache.enable = true;
    colmenaTarget.enable = true;

    services = {
      fail2ban.enable = true;
      beszel.agent = {
        enable = true;
        containers = true;
      };
      resticClient = {
        enable = true;
        paths = [ "/var/lib/monifactory" ];
        # all re-downloadable from the pinned pack/forge/mod URLs on next start
        exclude = [
          "/var/lib/monifactory/mods"
          "/var/lib/monifactory/libraries"
          "/var/lib/monifactory/packs"
          "/var/lib/monifactory/logs"
          "/var/lib/monifactory/crash-reports"
          "/var/lib/monifactory/.tmp"
          "/var/lib/monifactory/backups"
          "/var/lib/monifactory/*.jar"
        ];
        # 4x/day; clear of homelab's 02:00 prune and 03:00 B2 run
        onCalendar = "*-*-* 05,11,17,23:00:00 UTC";
      };
    };
  };
}
