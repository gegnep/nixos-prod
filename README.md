# nixos-prod

NixOS flake config for my homelab.
[GitHub](https://github.com/gegnep/nixos-prod) [GitLab](https://gitlab.com/pengeg/nixos-prod)

## Host

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, 31 GiB, Intel Arc A310 | Headless server — DNS, dashboards, git, game servers, backups, nix build farm |

Single host, installed via nixos-anywhere over SSH (disko-partitioned):

- NVMe (1 TB): systemd-boot ESP + btrfs (`@ @nix @home @var-lib @snapshots`)
- 2× 2 TB SATA: btrfs **raid1** mirror → `/backup`, exported over NFSv4
- Lix, `nh os switch`, key-only SSH
- nvim (nvf) + zsh (p10k) imported from the desktop repo (`github:gegnep/nixos`) as a plain source tree — individual home modules by store path, without inheriting its inputs

## Conventions

Everything hangs off `mySystem.*` options; `hosts/homelab/default.nix` is a flat list of `enable`s. Three repo-wide contracts:

- **Auto-importer** (`modules/nixos/default.nix`) — every `*.nix` under `modules/nixos/` is imported automatically. Add a service = drop a file; delete a service = remove the file. `_`-prefixed files/dirs are skipped (`_lib/` contracts are imported explicitly).
- **Proxy/dashboard registry** (`_lib/proxy.nix`) — a service writes one `mySystem.proxy.vhosts.<key>` entry (subdomain, upstream, optional dashboard tile); `web/caddy.nix` is the sole reader turning entries into vhosts, `web/homepage.nix` turns them into tiles. Disabled service ⇒ vhost and tile vanish with it.
- **Failure alerts** (`_lib/notify.nix`) — `mkFailureUnit { ... }` module arg gives any unit an `onFailure` hook that POSTs to the local ntfy topic.

Names resolve via the Pi-hole `*.homelab` wildcard; Caddy serves `<sub>.homelab`.

## Services

| Service | URL | Notes |
|---------|-----|-------|
| Homepage | `home.homelab` | Dashboard; tiles generated from the proxy registry |
| Pi-hole | `dns.homelab` | DNS + `*.homelab` wildcard (podman) |
| Open WebUI | `ai.homelab` | Chat UI over the local ollama backend |
| Beszel | `stats.homelab` | Monitoring hub + agent (nvidia, SMART, containers) |
| cgit | `git.homelab` | Git hosting, catppuccin-themed, syntax highlighting |
| ntfy | `ntfy.homelab` | Push notifications; all failure alerts land here |
| Atuin | `atuin.homelab` | Shell-history sync (open registration) |
| Syncthing | `sync.homelab` | File sync |
| mcp-nixos | `mcp.homelab` | NixOS MCP server, also published via tailscale funnel |
| Factorio | — | Dedicated server, declarative mod list pinned in the host config |
| Harmonia | `:5000` | Binary cache serving the whole store, signed `homelab-1` |
| smartd | — | Disk health monitoring |

## Build farm

The homelab builds so the desktop machines never have to (`services/buildserver.nix` + `services/flake-builder.nix`):

- **Remote builder** — `nixremote` user + `nix.settings.trusted-users`; nixpad offloads builds over ssh-ng.
- **flake-builder** — nightly timer that maintains an isolated clone of `github:gegnep/nixos`, runs `nix flake update` (all inputs), builds **both** `blackbox` and `nixpad` toplevels, and only if both succeed commits and pushes the lock (`chore: bump flake.lock (automated)`). A failed build never advances the lock — the hosts must evaluate exactly the lock the homelab built, or substitution breaks. Last successful pair of toplevels is kept as gcroots under `/var/lib/flake-builder` so `nh clean` can't evict closures before the hosts pull them. Runs at `Nice=19`/`CPUWeight=25` so nightly kernel compiles don't starve services.
- **Harmonia** serves the resulting store paths; the desktops list `http://homelab:5000` + the `homelab-1` key as a substituter.

## Storage & backups

Three layers:

1. **btrbk** — hourly snapshots of `@home`/`@var-lib` (24h/7d/4w retention) onto the `/backup` raid1 mirror (`mySystem.backup.mountPoint`).
2. **restic** — `/home` + `/var/lib` offsite to Backblaze B2, with ntfy failure alerts.
3. **unifi-backup** — pulls `.unf` autobackups off the UniFi Cloud Gateway into `/var/lib` ahead of the restic run, so they ride along in both layers.

The mirror is exported over NFSv4 for browsing from the desktop.

## Secrets

sops-nix with age; recipients are the host key + my user key (`.sops.yaml`). Secrets live in `secrets/homelab.yaml`; service-specific secrets are declared in the service's own module, shared ones in `modules/nixos/sops.nix`.

## Structure

<details>
<summary>Click to expand</summary>

```text
.
├── flake.nix
├── flake.lock
├── hosts/
│   └── homelab/
│       ├── default.nix                # mySystem.* enables — the whole host at a glance
│       ├── disko.nix                  # NVMe + raid1 mirror layout
│       └── hardware-configuration.nix
├── secrets/
│   └── homelab.yaml                   # sops (age)
└── modules/
    ├── nixos/
    │   ├── default.nix                # auto-importer (the only default.nix in the tree)
    │   ├── sops.nix                   # defaultSopsFile + shared secrets
    │   ├── _lib/
    │   │   ├── notify.nix             # mySystem.notify.* + mkFailureUnit contract
    │   │   └── proxy.nix              # mySystem.proxy.vhosts registry contract
    │   ├── core/
    │   │   ├── boot.nix
    │   │   ├── networking.nix
    │   │   ├── nix.nix                # lix, substituters, nh + clean
    │   │   ├── users.nix
    │   │   └── virtualisation.nix     # podman as the shared oci backend
    │   ├── hardware/
    │   │   ├── graphics.nix
    │   │   └── nvidia.nix
    │   ├── storage/
    │   │   ├── options.nix            # mySystem.backup.mountPoint
    │   │   ├── filesystems.nix        # btrfs top-level mount for btrbk
    │   │   ├── btrbk.nix              # hourly snapshots → /backup
    │   │   ├── restic.nix             # /home + /var/lib → B2, ntfy-guarded
    │   │   ├── unifi-backup.nix       # UCG .unf pull, ntfy-guarded
    │   │   └── nfs.nix                # /backup exported
    │   ├── services/
    │   │   ├── atuin.nix
    │   │   ├── beszel.nix
    │   │   ├── buildserver.nix        # harmonia + nixremote build user
    │   │   ├── cgit/                  # cgit.nix + catppuccin css
    │   │   ├── factorio.nix           # server + declarative mod fetcher
    │   │   ├── flake-builder.nix      # nightly desktop-flake lock bump + prebuild
    │   │   ├── mcp-nixos.nix          # + tailscale funnel
    │   │   ├── netdata.nix            # disabled (enshittified)
    │   │   ├── ntfy.nix
    │   │   ├── ollama.nix
    │   │   ├── open-webui.nix
    │   │   ├── pihole.nix
    │   │   ├── smartd.nix
    │   │   └── syncthing.nix
    │   └── web/
    │       ├── caddy.nix              # sole reader of the proxy registry
    │       └── homepage.nix           # dashboard tiles from the same registry
    └── home/                          # thin: imports nvim/zsh from the desktop tree
```

</details>

## Building

```sh
# On the host:
nh os switch

# Or from anywhere:
sudo nixos-rebuild switch --flake .#homelab
```

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
