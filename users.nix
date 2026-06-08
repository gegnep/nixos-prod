{ pkgs, ... }:

let
  # NOTE: reconstructed from your wrapped paste. VERIFY this matches
  #   cat ~/.ssh/id_rsa.pub   (on blackbox)
  # byte-for-byte before installing. A typo here = locked out of a headless box.
  authorizedKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCu/jJWWLeynjg+RIMlgsF6Rc6Eay0WwK39v7p1kR+uqqA4LEuonPcKVhIF0MJlo+PY2wI4zG1R3amDU8w/v9+GJxGxhZf7VTrp4C6FT/OXCrMQ+o4p67fgnW6Jt4LXPjbIbppHyLOFDnG99SV8NOyH/R3vw+MJcBwR14t68N1+yg1QaO6Uo9x4BBzx9wUg9o6uW+2nnVjtIjFyVpuIZO9CdifEkz6LfZPdwfBAfCXNWAJbZXqTCQox0JKsX1X2iVhWMpiClr/uUkd1S3xYC+8bm1jchEmyz2lAEgJshPLhIHrFVB7SQwArxtomoLt1W2EolfrSBLfGrpx1EsxZedk5 pengeg@blackbox";
in
{
  programs.zsh.enable = true; # required since pengeg's login shell is zsh

  users.users.pengeg = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    shell = pkgs.zsh;
    openssh.authorizedKeys.keys = [ authorizedKey ];
  };

  # Same key for root so you retain a fallback into a headless box.
  users.users.root.openssh.authorizedKeys.keys = [ authorizedKey ];

  # Key-only login means pengeg has no password → interactive sudo would be
  # impossible. Passwordless wheel keeps the box usable. Tradeoff: anyone with
  # the SSH key has root. Acceptable for key-only homelab access; flip to a
  # hashedPassword setup if you want a sudo password instead.
  security.sudo.wheelNeedsPassword = false;
}
