{
  config,
  lib,
  ...
}:

let
  cfg = config.mySystem.services.atuin;
in
{
  options.mySystem.services.atuin = {
    enable = lib.mkEnableOption "Atuin shell-history sync server";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = "Server port (localhost; fronted by Caddy as atuin.<domain>)";
    };
    openRegistration = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow new-account registration (turn on to register, then off)";
    };
  };

  config = lib.mkIf cfg.enable {
    services.atuin = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.port;
      openRegistration = cfg.openRegistration;
      database.createLocally = true;
    };
  };
}
