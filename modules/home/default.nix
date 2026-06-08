{ inputs, pkgs, ... }:
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

  home.packages = with pkgs; [
    tldr
    git
    github-cli
    curl
    ripgrep
    jq
    file
    which
    tree
    gnused
    gnutar
    gawk
    zstd
    gnupg

    nix-output-monitor

    zip
    unzip
    xz
    p7zip

    iotop
    iftop
    strace
    lsof
    sysstat
    ethtool
    pciutils
    usbutils
    powertop

    mtr
    dnsutils
    nmap
    ipcalc

    cowsay

    fastfetch
    fzf
    nnn
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.bat = {
    enable = true;
    config = {
      style = "numbers,changes,header";
      pager = "less -FR";
      map-syntax = [
        "*.ino:C++"
        "*.conf:INI"
      ];
    };
  };

  programs.btop = {
    enable = true;
    settings = {
      vim_keys = true;
      theme_background = false;
    };
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
    extraOptions = [
      "--group-directories-first"
      "--time-style=relative"
    ];
  };

  programs.tmux = {
    enable = true;
    keyMode = "vi";
    customPaneNavigationAndResize = true;
    prefix = "C-a";
    terminal = "tmux-256color";
    shell = "${pkgs.zsh}/bin/zsh";
    baseIndex = 0;
    escapeTime = 0;
    focusEvents = true;
    historyLimit = 10000;
    mouse = true;
    clock24 = true;
    disableConfirmationPrompt = true;

    plugins = with pkgs; [
      tmuxPlugins.vim-tmux-navigator
      tmuxPlugins.yank
      tmuxPlugins.prefix-highlight
    ];
  };
}
