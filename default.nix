{ ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ../../modules/nixos
  ];

  networking.hostName = "homelab";

  # Fresh install (Jun 2026). 26.05 = current stable at install time.
  system.stateVersion = "26.05";

  mySystem = {
    backup.mountPoint = "/backup";
  };
}
