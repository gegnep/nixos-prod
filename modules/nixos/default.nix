{ ... }:
{
  imports = [
    ./hardware

    ./options.nix
    ./boot.nix
    ./backup.nix
    ./nix.nix
    ./networking.nix
    ./users.nix

    ./services.nix
    ./pihole.nix
    ./buildserver.nix
    ./syncthing.nix
  ];
}
