{ inputs, ... }:
{
  imports = [
    inputs.nvf.homeManagerModules.default

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
