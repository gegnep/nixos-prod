{ config, lib, ... }:

let
  cfg = config.mySystem.services.syncthing;
in
{
  options.mySystem.services.syncthing = {
    enable = lib.mkEnableOption "Synthing file sync";

    guiPort = lib.mkOption {
      type = lib.types.port;
      default = 8384;
      description = "Web UI Port";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/syncthing";
      description = ''
        syncthing user's working dir.
        under @var-lib so its backed up
      '';
    };

    lanSync = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "set to false for tailnet only";
    };
  };

  config = lib.mkIf cfg.enable {
    services.syncthing = {
      enable = true;
      dataDir = cfg.dataDir;
      configDir = "${cfg.dataDir}/.config/syncthing";

      guiAddress = "0.0.0.0:${toString cfg.guiPort}";
      openDefaultPorts = cfg.lanSync;

      overrideDevices = false;
      overrideFolders = false;

      settings = {
        options.urAccepted = -1;
        gui.insecureSkipHostcheck = true;
        # devices = { };
        # folders = { };
      };
    };
  };
}
