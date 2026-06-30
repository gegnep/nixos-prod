{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.factorio;

  # nixpkgs pins 2.0.76; experimental client is 2.1.7 → must pin ourselves.
  # Refresh on each experimental bump:
  #   curl -fsSL https://factorio.com/get-download/<ver>/headless/linux64 | sha256sum
  # (hex output — versions.json wants hex, NOT nix-prefetch-url base32)
  factorioVersions =
    let
      dist = {
        name = "factorio_headless_x64-2.1.9.tar.xz";
        version = "2.1.9";
        tarDirectory = "x64";
        url = "https://factorio.com/get-download/2.1.9/headless/linux64";
        sha256 = "2cf94327877c92b95857356f7629f674a1314abd2c09e5c992f345707d165980";
        needsAuth = false;
      };
    in
    {
      x86_64-linux.headless = {
        experimental = dist;
        stable = dist;
      };
    };

  factorioHeadless = pkgs.factorio-headless-experimental.override {
    versionsJson = pkgs.writeText "factorio-versions.json" (builtins.toJSON factorioVersions);
  };
in
{
  options.mySystem.services.factorio = {
    enable = lib.mkEnableOption "Factorio headless server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 34197;
      description = "Game UDP Port";
    };

    admins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "factorio.com usernames granded /admin";
    };

    username = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "factorio.com username (not secret). Token comes from sops.";
    };

    mods = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            version = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
              description = "Pin a release; null = latest. Unpinned drifts.";
            };
          };
        }
      );
      default = [ ];
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.factorio-token = { };

    services.factorio = {
      enable = true;
      package = factorioHeadless;
      port = cfg.port;

      # all connection done over tailnet
      openFirewall = false;
      lan = false;
      public = false;
      requireUserVerification = false;

      admins = cfg.admins;
      game-name = "homelab";
      description = "private tailnet server";

      loadLatestSave = true;
      autosave-interval = 10;
      nonBlockingSaving = false;

      extraSettings = {
        max_players = 2;
      };
    };

    networking.firewall.interfaces."tailscale0".allowedUDPPorts = [ cfg.port ];

    # Leave services.factorio.mods UNSET (default []) so the module does NOT
    # pass --mod-directory; factorio then uses <write-data>/mods =
    # /var/lib/factorio/mods, which this oneshot populates at runtime.
    systemd.services.factorio-mods = lib.mkIf (cfg.mods != [ ]) {
      description = "Fetch Factorio mods from the portal (token from sops)";
      before = [ "factorio.service" ];
      requiredBy = [ "factorio.service" ];
      path = with pkgs; [
        curl
        jq
        coreutils
      ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -euo pipefail
        token="$(cat ${config.sops.secrets.factorio-token.path})"
        user=${lib.escapeShellArg cfg.username}
        moddir=/var/lib/factorio/mods
        mkdir -p "$moddir"
        declare -A keep

        fetch() {  # $1=name  $2=version|""
          echo "fetching $1 ''${2:-latest}" >&2
          local meta rel fn url
          meta="$(curl -fsSL "https://mods.factorio.com/api/mods/$1/full")"
          if [ -n "''${2:-}" ]; then
            rel="$(jq -c --arg v "$2" 'first(.releases[]|select(.version==$v))' <<<"$meta")"
          else
            rel="$(jq -c '.releases[-1]' <<<"$meta")"
          fi
          [ "$rel" != null ] && [ -n "$rel" ] || { echo "no release: $1 ''${2:-latest}" >&2; exit 1; }
          fn="$(jq -r '.file_name' <<<"$rel")"
          url="$(jq -r '.download_url' <<<"$rel")"
          keep[$fn]=1
          if [ ! -e "$moddir/$fn" ]; then
            curl -fsSL "https://mods.factorio.com''${url}?username=$user&token=$token" \
              -o "$moddir/$fn.part"
            mv "$moddir/$fn.part" "$moddir/$fn"
          fi
        }

        ${lib.concatMapStringsSep "\n        " (
          m: "fetch ${lib.escapeShellArg m.name} ${lib.escapeShellArg (toString (m.version or ""))}"
        ) cfg.mods}

        # prune zips no longer in the desired set (removed/repinned mods)
        for z in "$moddir"/*.zip; do
          [ -e "$z" ] || continue
          [ -n "''${keep[$(basename "$z")]:-}" ] || rm -f "$z"
        done
        chmod -R u=rwX,go=rX "$moddir"
      '';
    };

    systemd.services.factorio.onFailure = [ "notify-factorio-fail.service" ];
    systemd.services."notify-factorio-fail" = mkFailureUnit {
      name = "factorio";
      title = "Factorio server failed";
      body = "factorio.service entered failed state (crashloop?). Check journalctl -u factorio.";
      tags = "video_game,warning";
    };
  };
}
