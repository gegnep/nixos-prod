# Core One+ (Gen2) camera: go2rtc restream + Prusa Connect snapshot pusher + public edge.
#
# Two roles, one module, so the stream name and upstream port stay coupled:
#   homelab: mySystem.services.printcam.enable
#     go2rtc holds the ONLY RTSP session to the Buddy3D (preloaded, so it stays
#     hot), serves MSE/MP4/MJPEG over /api/ws, and a push loop PUTs a fresh JPEG
#     to Connect's Camera API every `connect.interval` seconds.
#   ovh:     mySystem.services.printcam.edge.enable
#     https://<edge.sub>.pengeg.com, Caddy basic_auth for the listed users, and a
#     path+query allowlist in front of go2rtc. go2rtc's API can create exec:
#     sources, so it must never be exposed unfiltered.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.printcam;
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

      mySystem.proxy.vhosts.printcam = {
        sub = "cam";
        upstream = "127.0.0.1:${toString cfg.port}";
        dashboard = {
          name = "Core One cam";
          description = "go2rtc";
          path = "/stream.html?src=${cfg.stream}";
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

          # Bare domain -> player URL. A redirect, NOT a rewrite: stream.html reads
          # the stream name from the browser's location.search, which a rewrite
          # never changes (rewrite = empty player = black page).
          @root path /
          redir @root /stream.html?src=${cfg.stream}&mode=mse,mp4 302

          @page path /stream.html
          @assets path /video-stream.js /video-rtc.js
          @api {
            path /api/ws /api/frame.jpeg
            query src=${cfg.stream}
          }

          # Inside handle = after basic_auth, so a 401 never carries the cookie.
          handle @page {
            header Set-Cookie "printcam_session={${session}}; Path=/; Max-Age=2592000; Secure; HttpOnly; SameSite=Strict"
            reverse_proxy ${cfg.edge.upstream} {
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
