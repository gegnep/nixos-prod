{ pkgs, ... }:
{
  nix = {
    package = pkgs.lixPackageSets.stable.lix;
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      trusted-users = [
        "root"
        "pengeg"
      ];
    };
  };

  programs.nh = {
    enable = true;
    flake = "/home/pengeg/nixos";
    clean = {
      enable = true;
      extraArgs = "--keep-since 3d --keep 3";
    };
  };
}
