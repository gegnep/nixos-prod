{
  config,
  lib,
  pkgs,
  mkFailureUnit,
  ...
}:

let
  cfg = config.mySystem.services.flake-builder;
in
{
  options.mySystem.services.flake-builder = {
    enable = lib.mkEnableOption "Nightly lock bump + full build of the desktop flake, served via Harmonia";

    repoUrl = lib.mkOption {
      type = lib.types.str;
      default = "git@github.com:gegnep/nixos.git";
      description = "Desktop flake remote. MUST match the remote the hosts pull from.";
    };

    localPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/flake-builder";
      description = "Working checkout + gcroot location. Under @var-lib (restic/btrbk cover it; harmless).";
    };

    hosts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "blackbox"
        "nixpad"
      ];
      description = ''
        nixosConfigurations attrs whose toplevels must ALL build before the lock
        advances. Add every machine that substitutes from Harmonia, or it will
        end up compiling locally.
      '';
    };

    extraSubstituters = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {
        # chaotic's cache (key verified from chaotic-cx/nyx README 2026-07).
        # The desktop gets this via the nyx-cache module; the homelab doesn't,
        # and without it every nyx package would compile from source here.
        "https://nyx-cache.chaotic.cx/" =
          "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk=";
      };
      description = "substituter URL → public key, passed to the build only (not homelab-wide nix.conf).";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "04:00";
      description = "When to check upstream. Off-hours so it doesn't race your manual commits.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.flake-builder-deploy-key = { };

    systemd.tmpfiles.rules = [ "d ${cfg.localPath} 0700 root root -" ];

    systemd.services.flake-builder = {
      description = "Bump the desktop flake.lock, build ${lib.concatStringsSep "+" cfg.hosts}, then push";
      onFailure = [ "notify-flake-builder-fail.service" ];
      path = with pkgs; [
        git
        openssh
        config.nix.package
        coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "8h"; # two full toplevels incl. a march-override kernel; slow but bounded
        # Root talks to the local store directly (no daemon detour), so the
        # builders fork inside THIS cgroup and these limits actually bind.
        Nice = 19;
        CPUWeight = 25;
        IOWeight = 25;
      };
      environment.GIT_SSH_COMMAND =
        "ssh -i ${config.sops.secrets.flake-builder-deploy-key.path} "
        + "-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new";
      script = ''
        set -euo pipefail
        repo=${cfg.localPath}/src

        [ -d "$repo/.git" ] || git clone ${cfg.repoUrl} "$repo"
        cd "$repo"
        git fetch --prune origin
        git checkout main
        git reset --hard origin/main

        # leftover tmp roots from a crashed run — drop before building
        rm -f ${cfg.localPath}/tmp-*

        # the bot owns the WHOLE lock now — every input, nightly
        nix flake update

        if git diff --quiet -- flake.lock; then
          echo "flake.lock unchanged; nothing to build"
          exit 0
        fi

        # BUILD EVERY HOST FIRST. Harmonia serves whatever lands in the store,
        # signed as homelab-1. tmp- out-links root the new closures without
        # touching result- (the last pair the hosts can still pull) — so a
        # half-failed night never loses roots nh clean would otherwise reap.
        fail=""
        for h in ${toString cfg.hosts}; do
          echo "building $h"
          nix build \
            --option extra-substituters "${toString (lib.attrNames cfg.extraSubstituters)}" \
            --option extra-trusted-public-keys "${toString (lib.attrValues cfg.extraSubstituters)}" \
            --out-link ${cfg.localPath}/tmp-"$h" \
            ".#nixosConfigurations.$h.config.system.build.toplevel" || { fail=$h; break; }
        done

        if [ -n "$fail" ]; then
          echo "build of $fail failed — discarding lock bump, hosts stay on last-good lock"
          git checkout -- flake.lock
          rm -f ${cfg.localPath}/tmp-*
          exit 1
        fi

        # all built: rotate the persistent gcroots to the new pair. Re-building
        # the raw store path just swaps the symlink + auto-root, no re-eval.
        for h in ${toString cfg.hosts}; do
          nix build --out-link ${cfg.localPath}/result-"$h" "$(readlink -f ${cfg.localPath}/tmp-"$h")"
          rm -f ${cfg.localPath}/tmp-"$h"
        done

        # only now advance the lock the hosts will evaluate
        git -c user.name="flake-builder" \
            -c user.email="flake-builder@${config.networking.hostName}" \
            commit -m "chore: bump flake.lock (automated)" -- flake.lock

        for n in 1 2 3; do
          git push origin main && exit 0
          echo "push rejected (try $n) — rebasing onto origin/main"
          git fetch origin
          git rebase origin/main || { git rebase --abort; exit 1; }
        done
        exit 1
      '';
    };

    systemd.timers.flake-builder = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "20min";
      };
    };

    systemd.services.notify-flake-builder-fail = mkFailureUnit {
      name = "flake-builder";
      title = "Nightly desktop-flake build FAILED on ${config.networking.hostName}";
      priority = "default";
      tags = "warning,hammer_and_wrench";
      body = "lock NOT advanced; ${lib.concatStringsSep "+" cfg.hosts} stay on last-good. Check: journalctl -u flake-builder";
    };
  };
}
