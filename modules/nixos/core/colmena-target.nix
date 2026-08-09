{ config, lib, ... }:

let
  cfg = config.mySystem.colmenaTarget;
in
{
  options.mySystem.colmenaTarget.enable = lib.mkEnableOption "accept colmena deploys as root (key-only, tailnet)";

  config = lib.mkIf cfg.enable {
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNL0bBsjcl5iel+1vrEMd2SG756pYvEqddrr9UuGHIT"
    ];
  };
}
