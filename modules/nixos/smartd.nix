{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.smartd;

  ntfyMailer = pkgs.writeShellScript "smartd-ntfy.sh" ''
    body="$(${pkgs.coreutils}/bin/cat)"
    subject="$(printf '%s\n' "$body" \
      | ${pkgs.gnugrep}/bin/grep -m1 '^Subject:' \
      | ${pkgs.gnused}/bin/sed 's/^Subject: *//')"
    ${pkgs.curl}/bin/curl -fsS \
      -H "Title: ''${subject:-SMART alert on ${config.networking.hostName}}" \
      -H "Priority: urgent" \
      -H "Tags: rotating_light,floppy_disk" \
      --data-binary "$body" \
      "${cfg.ntfyUrl}/${cfg.ntfyTopic}" >/dev/null || true
  '';
in
{
  options.mySystem.services.smartd = {
    enable = lib.mkEnableOption "smartd SMART disk health monitoring";

    ntfyUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:2586";
      description = "Base URL the ntfy server alerts are sent to (local by default)";
    };

    ntfyTopic = lib.mkOption {
      type = lib.types.str;
      default = "homelab-alerts";
      description = "ntfy topic for SMART alerts";
    };
  };

  config = lib.mkIf cfg.enable {
    services.smartd = {
      enable = true;
      autodetect = true;

      notifications.mail = {
        enable = true;
        recipient = "root";
        mailer = "${ntfyMailer}";
      };

      # Applied to every monitored device (DEFAULT line):
      #   -a            all standard attributes
      #   -o on         enable automatic offline data collection
      #   -S on         enable attribute autosave
      #   -s (S/.../L/) short self-test daily @02:00, long self-test Sat @03:00
      #   -W 0,60,75    temp: don't log every change, info at 60 C, alert at 75 C
      #                 (safe ceiling for both the NVMe and the SATA SSDs)
      defaults.monitored = "-a -o on -S on -s (S/../.././02|L/../../6/03) -W 0,60,75";
    };
    environment.systemPackages = [ pkgs.smartmontools ];
  };
}
