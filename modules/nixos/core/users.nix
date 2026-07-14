{ pkgs, ... }:

let
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII09Zaa97OjgN0nsiID4RhNQEsS16W4QY1fA0GzjwVY/ pengeg@blackbox"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNL0bBsjcl5iel+1vrEMd2SG756pYvEqddrr9UuGHIT pengeg@homelab"
  ];
in
{
  programs.zsh.enable = true;

  users.users.pengeg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  users.users.root.openssh.authorizedKeys.keys = authorizedKeys;

  security.sudo.wheelNeedsPassword = false;
}
