# Core One+ (Gen2) camera + telemetry: go2rtc restream, Prusa Connect snapshot
# pusher, telemetry collector + dashboard, public edge.
#
# Two roles, one module, so the stream name and upstream ports stay coupled:
#   homelab: mySystem.services.printcam.enable
#     go2rtc holds the ONLY RTSP session to the Buddy3D (preloaded, so it stays
#     hot), serves MSE/MP4/MJPEG over /api/ws, and a push loop PUTs a fresh JPEG
#     to Connect's Camera API every `connect.interval` seconds.
#     printcam-collector polls PrusaLink, receives the firmware's UDP metrics,
#     keeps a ring buffer, and serves the dashboard (/) plus /printer/* JSON.
#   ovh:     mySystem.services.printcam.edge.enable
#     https://<edge.sub>.pengeg.com, Caddy basic_auth for the listed users, and a
#     path+query allowlist in front of go2rtc and the collector. go2rtc's API can
#     create exec: sources, so it must never be exposed unfiltered.
{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.printcam;
  col = cfg.collector;
  notify = config.mySystem.notify;

  push = pkgs.writeShellApplication {
    name = "printcam-push";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      snap="$RUNTIME_DIRECTORY/snap.jpg"
      token="$(<"$CREDENTIALS_DIRECTORY/token")"
      fails=0
      alerted=0

      alert() {
        curl -fsS -H "Title: [${config.networking.hostName}] printcam $1" -H "Tags: camera" \
          -d "$2" "${notify.url}/${notify.topic}" >/dev/null || true
      }

      while true; do
        # go2rtc 1.9.14 answers a dead source with 200 + EMPTY body (tested), so
        # -f alone is not enough: require a non-empty file before pushing.
        rm -f "$snap"
        if curl -fsS --max-time 8 -o "$snap" \
             "http://127.0.0.1:${toString cfg.port}/api/frame.jpeg?src=${cfg.stream}" \
           && [ -s "$snap" ] \
           && curl -fsS --max-time 15 -o /dev/null -X PUT \
             -H "Token: $token" \
             -H "Fingerprint: ${cfg.connect.fingerprint}" \
             -H "Content-Type: image/jpg" \
             --data-binary @"$snap" \
             https://connect.prusa3d.com/c/snapshot; then
          if [ "$alerted" -eq 1 ]; then
            alert "recovered" "Snapshots flowing to Connect again."
            alerted=0
          fi
          fails=0
        else
          fails=$((fails + 1))
          if [ "$fails" -ge ${toString cfg.connect.alertAfter} ] && [ "$alerted" -eq 0 ]; then
            alert "down" "No snapshot pushed for $fails attempts (camera, go2rtc, or Connect)."
            alerted=1
          fi
        fi
        sleep ${toString cfg.connect.interval}
      done
    '';
  };

  collector = pkgs.writers.writePython3Bin "printcam-collector" {
    flakeIgnore = [
      "E501"
      "E265"
    ];
  } (builtins.readFile ./collector.py);

  # A missing env var is a Caddyfile parse error, and Caddy then refuses the
  # WHOLE config (ntfy, p, mcp go down with the cam). Fall back to a bcrypt hash
  # of a discarded random string, so only that user is locked out.
  # Covers UNSET vars only: a set-but-empty var still fails (Caddy behavior).
  lockedHash = "$2a$14$S6/kG9rl1U2JVbi8eg3vV.lxDfhyTtw.74/uS6Hc.8uLDY2ztcNx6";
  session = "$" + cfg.edge.sessionEnvVar;
  basicAuthUsers = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      user: envVar: "    ${user} {" + "$" + envVar + ":" + lockedHash + "}"
    ) cfg.edge.users
  );
in
{
  options.mySystem.services.printcam = {
    enable = lib.mkEnableOption "go2rtc restream of the Core One Buddy3D camera";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1984;
      description = "go2rtc API/web port. Reachable on loopback and tailscale0 only.";
    };

    stream = lib.mkOption {
      type = lib.types.str;
      default = "coreone";
      description = "go2rtc stream name; also the only src= the public edge allows.";
    };

    cameraHost = lib.mkOption {
      type = lib.types.str;
      example = "10.0.0.242";
      description = "Buddy3D IP. Needs a DHCP reservation and RTSP enabled in the Prusa app.";
    };

    connect = {
      enable = lib.mkEnableOption "pushing snapshots to Prusa Connect's Camera API" // {
        default = true;
      };
      interval = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10;
        description = "Seconds between pushes. Connect's own minimum is 10.";
      };
      fingerprint = lib.mkOption {
        type = lib.types.str;
        default = "homelab-go2rtc-${cfg.stream}";
        description = ''
          Stable camera identity, >= 16 chars. Connect binds the token to the first
          fingerprint it sees; changing this needs a new token.
        '';
      };
      alertAfter = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Consecutive failed pushes before one ntfy alert (30 x 10s = 5 min).";
      };
    };

    collector = {
      enable = lib.mkEnableOption "telemetry collector + dashboard" // {
        default = true;
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 1986;
        description = "Collector HTTP port (dashboard + /printer/* JSON). Loopback and tailscale0.";
      };
      printerHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "10.0.0.36";
        description = ''
          Core One IP: PrusaLink target and the only accepted source of UDP metrics.
          Needs a DHCP reservation. null = collector off.
        '';
      };
      metricsSources = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = lib.optional (col.printerHost != null) col.printerHost;
        defaultText = lib.literalExpression "[ printerHost ]";
        example = [
          "10.0.0.36"
          "10.0.0.180"
        ];
        description = ''
          Source IPs accepted for UDP metrics (firewall + collector). A printer on
          Ethernet AND Wi-Fi answers PrusaLink on one IP but may send metrics from
          the other, so list both.
        '';
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "maker";
        description = "PrusaLink digest user (printer: Settings > Network > PrusaLink).";
      };
      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 8514;
        description = "UDP port the printer's Metrics & Log handler sends to.";
      };
      historyHours = lib.mkOption {
        type = lib.types.ints.positive;
        default = 12;
        description = "Ring buffer length. Must cover the longest print you want graphed whole.";
      };
      udpMap = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr (lib.types.attrsOf lib.types.anything));
        default = { };
        example = {
          mcu = null; # drop a default
          heater_v = {
            m = "heater_voltage";
          };
        };
        description = ''
          Overrides/additions to the collector's page-key -> UDP metric map
          (defaults live in collector.py). m = metric, tags = required tags,
          f = field ("v" plain, "value"/"pwm"/"rpm"/"st" custom), abs, map,
          ranges, scale, agg (mean|max|min for /history buckets). null drops a
          default. A new key also needs a series entry in index.html to show up.
        '';
      };
    };

    edge = {
      enable = lib.mkEnableOption "public auth-gated vhost for the camera (ovh)";
      sub = lib.mkOption {
        type = lib.types.str;
        default = "cam";
      };
      upstream = lib.mkOption {
        type = lib.types.str;
        default = "100.68.176.20:${toString cfg.port}";
        description = "homelab go2rtc over the tailnet.";
      };
      collectorUpstream = lib.mkOption {
        type = lib.types.str;
        default = "100.68.176.20:${toString col.port}";
        description = "homelab printcam-collector over the tailnet.";
      };
      users = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        example = {
          pen = "CAM_PEN_HASH";
        };
        description = ''
          basic_auth user -> caddy-env variable holding its bcrypt hash
          (`caddy hash-password`).
        '';
      };
      sessionEnvVar = lib.mkOption {
        type = lib.types.str;
        default = "CAM_SESSION";
        description = ''
          caddy-env variable holding the session cookie value (`openssl rand -hex 32`).
          Safari does not send basic-auth credentials on WebSockets or ES-module
          script loads, so after one successful basic_auth the page sets this cookie
          and later requests are accepted by cookie instead.
        '';
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      services.go2rtc = {
        enable = true;
        settings = {
          api.listen = ":${toString cfg.port}";
          rtsp.listen = "127.0.0.1:8554"; # nothing external consumes the restream
          streams.${cfg.stream} = "rtsp://${cfg.cameraHost}/live";
          # Keep one session to the camera open at all times: viewers join a warm
          # stream, frame.jpeg answers instantly, and the weak camera SoC never
          # sees connect/disconnect churn every 10 s.
          preload.${cfg.stream} = "video";
        };
      };
      systemd.services.go2rtc.serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ cfg.port ];

      # cam.homelab: dashboard + /printer/* from the collector, everything else
      # (stream.html, the go2rtc UI, /api/*) straight to go2rtc. LAN-only, no auth.
      mySystem.proxy.vhosts.printcam = {
        sub = "cam";
        rawConfig =
          if col.enable && col.printerHost != null then
            ''
              encode zstd gzip
              @collector path / /index.html /printer/*
              handle @collector {
                reverse_proxy 127.0.0.1:${toString col.port}
              }
              handle {
                reverse_proxy 127.0.0.1:${toString cfg.port}
              }
            ''
          else
            "reverse_proxy 127.0.0.1:${toString cfg.port}";
        dashboard = {
          name = "Core One cam";
          description = "go2rtc + telemetry";
          path = if col.enable && col.printerHost != null then "/" else "/stream.html?src=${cfg.stream}";
        };
      };
    })

    (lib.mkIf (cfg.enable && cfg.connect.enable) {
      sops.secrets.prusa-connect-cam-token.restartUnits = [ "printcam-push.service" ];

      systemd.services.printcam-push = {
        description = "Push Core One snapshots to Prusa Connect";
        wantedBy = [ "multi-user.target" ];
        after = [
          "go2rtc.service"
          "network-online.target"
        ];
        wants = [ "network-online.target" ];
        requires = [ "go2rtc.service" ];

        serviceConfig = {
          ExecStart = lib.getExe push;
          Restart = "always";
          RestartSec = 10;
          DynamicUser = true;
          RuntimeDirectory = "printcam-push";
          LoadCredential = [ "token:${config.sops.secrets.prusa-connect-cam-token.path}" ];
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };
    })

    (lib.mkIf (cfg.enable && col.enable && col.printerHost != null) {
      sops.secrets.prusalink-password.restartUnits = [ "printcam-collector.service" ];

      systemd.services.printcam-collector = {
        description = "Core One telemetry collector + dashboard";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        onFailure = [ "notify-printcam-collector-fail.service" ];

        environment = {
          PRINTCAM_PORT = toString col.port;
          PRINTCAM_METRICS_PORT = toString col.metricsPort;
          PRINTCAM_STREAM = cfg.stream;
          PRINTCAM_INDEX = "${./index.html}";
          PRINTCAM_HISTORY_H = toString col.historyHours;
          PRINTCAM_UDP_MAP = builtins.toJSON col.udpMap;
          PRINTCAM_METRICS_FROM = lib.concatStringsSep "," col.metricsSources;
          PRUSALINK_HOST = col.printerHost;
          PRUSALINK_USER = col.user;
          # %d is CREDENTIALS_DIRECTORY: systemd copies the sops secret there
          # as root at start, readable by the dynamic uid.
          PRUSALINK_PASSWORD_FILE = "%d/prusalink";
        };

        serviceConfig = {
          ExecStart = lib.getExe collector;
          Restart = "on-failure";
          RestartSec = 10;
          # SIGTERM -> history.json flush; give it time on a slow disk.
          TimeoutStopSec = 20;

          DynamicUser = true;
          StateDirectory = "printcam-collector";
          LoadCredential = [ "prusalink:${config.sops.secrets.prusalink-password.path}" ];

          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      systemd.services.notify-printcam-collector-fail = mkFailureUnit {
        name = "printcam-collector";
        title = "printcam collector failed";
        body = "printcam-collector.service entered failed state. Check journalctl -u printcam-collector.";
        tags = "camera,warning";
      };

      networking.firewall.interfaces."tailscale0".allowedTCPPorts = [ col.port ];
      # Metrics only from the printer's own IPs, whatever interface they arrive on.
      # nixos-fw is flushed on every reload, so no matching extraStopCommands.
      networking.firewall.extraCommands = lib.concatMapStrings (src: ''
        iptables -w -A nixos-fw -p udp -s ${src} --dport ${toString col.metricsPort} -j nixos-fw-accept
      '') col.metricsSources;
    })

    (lib.mkIf cfg.edge.enable {
      assertions = [
        {
          assertion = cfg.edge.users != { };
          message = "printcam.edge.users is empty: the vhost would be public.";
        }
      ];

      mySystem.proxy.vhosts.printcam = {
        inherit (cfg.edge) sub;
        rawConfig = ''
          # Session cookie -> {printcam_ok}, exact match. Fails CLOSED (tested): if
          # the env var is missing, the line degrades to `yes` with no output, no
          # cookie maps to "yes", and every request falls back to basic_auth.
          map {http.request.cookie.printcam_session} {printcam_ok} {
            {${session}} yes
            default no
          }
          @noSession not vars {printcam_ok} yes

          # Only requests WITHOUT a valid session need basic_auth. Safari drops
          # basic-auth creds on the websocket and module scripts, cookies it keeps.
          basic_auth @noSession {
          ${basicAuthUsers}
          }

          encode zstd gzip

          # Pages: the dashboard (collector) and the bare go2rtc player (fallback).
          @home path /
          @player path /stream.html
          @assets path /video-stream.js /video-rtc.js
          @api {
            path /api/ws /api/frame.jpeg
            query src=${cfg.stream}
          }
          # /printer/metrics (raw UDP dump) stays LAN-only.
          @printer path /printer/status /printer/history /printer/thumb

          # Inside handle = after basic_auth, so a 401 never carries the cookie.
          handle @home {
            header Set-Cookie "printcam_session={${session}}; Path=/; Max-Age=2592000; Secure; HttpOnly; SameSite=Strict"
            reverse_proxy ${cfg.edge.collectorUpstream} {
              header_up -Authorization
              header_up -Cookie
            }
          }
          handle @player {
            header Set-Cookie "printcam_session={${session}}; Path=/; Max-Age=2592000; Secure; HttpOnly; SameSite=Strict"
            reverse_proxy ${cfg.edge.upstream} {
              header_up -Authorization
              header_up -Cookie
            }
          }
          handle @printer {
            reverse_proxy ${cfg.edge.collectorUpstream} {
              header_up -Authorization
              header_up -Cookie
            }
          }
          handle @assets {
            reverse_proxy ${cfg.edge.upstream} {
              header_up -Authorization
              header_up -Cookie
            }
          }
          handle @api {
            reverse_proxy ${cfg.edge.upstream} {
              header_up -Authorization
              header_up -Cookie
            }
          }
          # Everything else (stream editing, exec sources, the go2rtc UI) stays private.
          handle {
            respond 404
          }
        '';
      };
    })
  ];
}
