{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.mySystem.services.mcp-nixos;

  # v2.4.3 hardcodes ES generations [43..46] in ChannelCache and picks the
  # FIRST live "unstable" match in insertion (= ascending) order, so unstable
  # pins to the oldest surviving snapshot (gen 45, ~4 months stale as of
  # 2026-08-01) and channels first indexed at gen >= 47 (26.05) are invisible.
  # FLAKE_INDEX is pinned to latest-44-group-manual, which no longer exists,
  # so flake search is dead too.
  #
  # Patch = verbatim snapshot (2026-08-01) of unmerged upstream PR
  # https://github.com/utensils/mcp-nixos/pull/159 (commits fe57053 + f9118fa):
  # discovers live aliases via _cat/aliases and resolves each channel to its
  # highest generation. Applies cleanly to v2.4.3 (caches.py blob 533ae9f =
  # patch base). The FLAKE_INDEX wildcard alias is our own fix (PR 159 doesn't
  # touch it); the backend accepts wildcard alias patterns for _search/_count,
  # and only one group-manual generation is live at a time.
  #
  # DROP BOTH once a release containing PR 159 lands (then re-check
  # FLAKE_INDEX upstream — no open PR fixes it as of the snapshot date).
  # --replace-fail + patch-application failure make either change loud if
  # upstream moves first.
  patchedPackage = pkgs.mcp-nixos.overridePythonAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mcp-nixos-pr159-channel-discovery.patch ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace mcp_nixos/config.py \
        --replace-fail 'FLAKE_INDEX = "latest-44-group-manual"' 'FLAKE_INDEX = "latest-*-group-manual"'
    '';
  });
in
{
  options.mySystem.services.mcp-nixos = {
    enable = lib.mkEnableOption "mcp-nixos MCP server over HTTP + Tailscale Funnel";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = "Loopback port for the HTTP MCP endpoint (served at /mcp).";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = patchedPackage;
      description = "mcp-nixos package (default carries the channel-discovery patch, see above).";
    };

    funnel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Publish publicly via Tailscale Funnel. Required for the Claude connector
        (Anthropic fetches it server-side). Set false for tailnet-only.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.mcp-nixos = {
      description = "mcp-nixos MCP server (Streamable HTTP)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      environment = {
        MCP_NIXOS_TRANSPORT = "http";
        MCP_NIXOS_HOST = "127.0.0.1";
        MCP_NIXOS_PORT = toString cfg.port;
        MCP_NIXOS_STATELESS_HTTP = "1"; # no per-client session state — robust behind Funnel
        HOME = "/var/lib/mcp-nixos"; # give the HTTP-cache somewhere writable under DynamicUser
      };

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/mcp-nixos";
        DynamicUser = true;
        StateDirectory = "mcp-nixos";
        Restart = "on-failure";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
      };
    };

    mySystem.proxy.vhosts.mcp-nixos = {
      sub = "mcp";
      upstream = "127.0.0.1:${toString cfg.port}";
      dashboard = {
        name = "mcp-nixos";
        description = "NixOS MCP server";
        path = "/mcp";
      };
    };

    systemd.services.mcp-nixos-funnel = lib.mkIf cfg.funnel {
      description = "Expose mcp-nixos via Tailscale Funnel";
      after = [
        "tailscaled.service"
        "mcp-nixos.service"
      ];
      wants = [
        "tailscaled.service"
        "mcp-nixos.service"
      ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.services.tailscale.package}/bin/tailscale funnel --bg --https=443 http://127.0.0.1:${toString cfg.port}";
        ExecStop = "${config.services.tailscale.package}/bin/tailscale funnel --https=443 off";
      };
    };
  };
}
