# Shared container runtime. Podman is daemonless, so enabling it unconditionally is
# near-free, and every container service (pihole, beszel's docker-compat socket, and
# future services) can rely on the backend being present.
{ lib, ... }:
{
  virtualisation.podman.enable = lib.mkDefault true;
  virtualisation.oci-containers.backend = lib.mkDefault "podman";
}
