{ inputs, ... }:
{
  imports = [
    inputs.nvf.homeManagerModules.default

    # Imported by store path from the desktop source tree (flake = false).
    # Both are self-contained: neovim.nix needs only nvf+pkgs; zsh.nix needs
    # only config+pkgs and sources its .p10k.zsh via a path that resolves
    # inside the desktop store path. NOT importing shell/default.nix (it sets
    # desktop-only sessionVars like VISUAL=neovide).
    "${inputs.desktop}/modules/home/programs/neovim.nix"
    "${inputs.desktop}/modules/home/shell/zsh.nix"
  ];

  home = {
    username = "pengeg";
    homeDirectory = "/home/pengeg";
    stateVersion = "26.05";
  };

  programs.home-manager.enable = true;
}
