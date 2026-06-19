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
    ./ollama.nix
    ./open-webui.nix
    ./smartd.nix
    ./ntfy.nix
    ./caddy.nix
    ./homepage.nix
    ./netdata.nix
  ];
}
