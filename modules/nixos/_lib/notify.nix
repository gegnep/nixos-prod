# Shared ntfy failure-alert plumbing.
#   mySystem.notify.{url,topic} — one source of truth for the alert endpoint.
#   mkFailureUnit { ... }       — module arg returning a oneshot systemd *service
#                                 definition* that POSTs an alert to ntfy. Assign it to
#                                 systemd.services."notify-<name>-fail" and point the
#                                 guarded unit's onFailure at "notify-<name>-fail.service".
{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.mySystem.notify = {
    url = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:2586";
      description = "Base URL of the ntfy server failure alerts are POSTed to.";
    };
    topic = lib.mkOption {
      type = lib.types.str;
      default = "homelab-alerts";
      description = "ntfy topic for homelab failure alerts.";
    };
  };

  config._module.args.mkFailureUnit =
    {
      name,
      title,
      body,
      priority ? "high",
      tags ? "",
    }:
    {
      description = "Notify ntfy that ${name} failed";
      serviceConfig.Type = "oneshot";
      script = ''
        ${pkgs.curl}/bin/curl -fsS \
          -H "Title: [${config.networking.hostName}] ${title}" \
          -H "Priority: ${priority}" \
          -H "Tags: ${tags}" \
          -d "${body}" \
          ${config.mySystem.notify.url}/${config.mySystem.notify.topic} >/dev/null || true
      '';
    };
}
