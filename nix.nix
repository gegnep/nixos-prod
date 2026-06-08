{ pkgs, ... }:
{
  # Lix, not upstream Nix.
  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "pengeg" ];
    };
    # GC handled by programs.nh.clean below (don't also enable nix.gc.automatic).
  };

  programs.nh = {
    enable = true;
    flake = "/home/pengeg/nixos-prod";   # post-install clone location
    clean = {
      enable = true;
      extraArgs = "--keep-since 3d --keep 3";
    };
  };
}
