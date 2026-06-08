{ ... }:
{
  imports = [
    ./hardware

    ./options.nix
    ./boot.nix
    ./nix.nix
    ./networking.nix
    ./users.nix
    ./services.nix
  ];
}
