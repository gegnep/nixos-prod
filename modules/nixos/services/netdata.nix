{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.netdata;
in
{
  options.mySystem.services.netdata = {
    enable = lib.mkEnableOption "netdata real-time system monitoring";

    port = lib.mkOption {
      type = lib.types.port;
      default = 19999;
      description = "netdata web port (bound to localhost; reach it through Caddy)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.netdata = {
      enable = true;
      package = pkgs.netdata.override { withCloudUi = true; };

      config = {
        global = {
          "memory mode" = "dbengine";
        };
        web = {
          "bind to" = "127.0.0.1:${toString cfg.port}";
        };
      };
      configDir."go.d.conf" = pkgs.writeText "netdata-go.d.conf" ''
        modules:
          nvidia_smi: yes
      '';
    };
    systemd.services.netdata.path = lib.optional config.mySystem.hardware.nvidia.enable config.hardware.nvidia.package.bin;
  };
}
