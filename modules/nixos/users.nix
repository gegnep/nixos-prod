{ pkgs, ... }:

let
  authorizedKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCu/jJWWLeynjg+RIMlgsF6Rc6Eay0WwK39v7p1kR+uqqA4LEuonPcKVhIF0MJlo+PY2wI4zG1R3amDU8w/v9+GJxGxhZf7VTrp4C6FT/OXCrMQ+o4p67fgnW6Jt4LXPjbIbppHyLOFDnG99SV8NOyH/R3vw+MJcBwR14t68N1+yg1QaO6Uo9x4BBzx9wUg9o6uW+2nnVjtIjFyVpuIZO9CdifEkz6LfZPdwfBAfCXNWAJbZXqTCQox0JKsX1X2iVhWMpiClr/uUkd1S3xYC+8bm1jchEmyz2lAEgJshPLhIHrFVB7SQwArxtomoLt1W2EolfrSBLfGrpx1EsxZedk5 pengeg@blackbox";
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
