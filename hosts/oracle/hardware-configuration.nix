{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "xhci_pci"
  ];
}
