{ config, ... }:

{
  sops.defaultSopsFile = ../../secrets/homelab.yaml;

  sops.secrets.pihole-webpassword = { };
  sops.secrets.open-webui-secret-key = { };
  sops.secrets.harmonia-cache-key = {
    restartUnits = [ "harmonia.service" ];
  };

  sops.templates."pihole.env" = {
    content = "FTLCONF_webserver_api_password=${config.sops.placeholder.pihole-webpassword}";
    restartUnits = [ "podman-pihole.service" ];
  };
  sops.templates."open-webui.env" = {
    content = "WEBUI_SECRET_KEY=${config.sops.placeholder.open-webui-secret-key}";
    restartUnits = [ "open-webui.service" ];
  };
}
