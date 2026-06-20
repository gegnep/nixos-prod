{ pkgs, ... }:

let
  authorizedKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII09Zaa97OjgN0nsiID4RhNQEsS16W4QY1fA0GzjwVY/ pengeg@blackbox";
in
{
  programs.zsh.enable = true;

  users.users.pengeg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ authorizedKey ];
  };

  users.users.root.openssh.authorizedKeys.keys = [ authorizedKey ];

  security.sudo.wheelNeedsPassword = false;
}
