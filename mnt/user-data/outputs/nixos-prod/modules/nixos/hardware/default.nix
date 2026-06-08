{ config, lib, pkgs, ... }:
{
  hardware.enableRedistributableFirmware = true;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Intel Arc A310 (DG2): VA-API ready out of the box (iHD driver) so Jellyfin/
  # Plex hardware transcode works once you add the service later. The oneVPL
  # runtime (vpl-gpu-rt) enables QSV specifically.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };
}
