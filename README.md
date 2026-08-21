# nixos-prod

NixOS flake config for my homelab and VPS fleet.
[GitHub](https://github.com/gegnep/nixos-prod) [GitLab](https://gitlab.com/pengeg/nixos-prod)

## Hosts

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, 31 GiB, R9700 + Arc A310 | Headless server — DNS, dashboards, git, AI, game servers, backups, nix build farm |
| **ovh** | OVH VPS (x86_64, BIOS/GRUB) | Public edge — TLS termination for `*.pengeg.com`, pastebin, MCP server |
| **oracle** | Oracle Cloud A1 (aarch64, 4 OCPU / 24 GiB) | Mostly idle — Minecraft pending |

All three are one flake; every host imports the same auto-discovered module tree and differs only in its `hosts/<name>/default.nix` enables. homelab was installed via nixos-anywhere over SSH (disko-partitioned):

- NVMe (1 TB): systemd-boot ESP + btrfs (`@ @nix @home @var-lib @snapshots`)
- 2× 2 TB SATA: btrfs **raid1** mirror → `/backup`, exported over NFSv4
- Lix, key-only SSH
- nvim (nvf) + zsh (p10k) imported from the desktop repo (`github:gegnep/nixos`) as a plain source tree — individual home modules by store path, without inheriting its inputs

## Deployment

[Colmena](https://colmena.cli.rs) (stateless, from any checkout of this repo) — the flake exports both `nixosConfigurations` and a `colmena` hive from one shared module list, so `colmena` and `nh`/`nixos-rebuild` always agree.

```sh
colmena build                 # eval + build every host; nothing activates
colmena apply --on ovh,oracle # push closures over the tailnet, activate
colmena apply-local --sudo    # homelab itself (targetHost = null — never SSH-to-self)
```

- Targets accept the deploy key as root over the tailnet (`core/colmena-target.nix`); sops decrypts on each host with its own age key, so no secrets ever leave the repo or ride the wire.
- **oracle** builds natively on-target (`deployment.buildOnTarget`) — faster than qemu-emulating aarch64 on the homelab, though the homelab keeps `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` for prebuilds when wanted.
- The repo checkouts on the VPSes are vestigial escape hatches; `nh os switch` on a box still works but colmena is the deploy path.

Fleet-wide update, until a homelab flake-builder automates it:

```sh
nix flake update && colmena build      # all hosts must build before the lock is committed
colmena apply --on ovh,oracle && colmena apply-local --sudo
git commit -m "chore: bump flake.lock" flake.lock && git push
```

## Conventions

Everything hangs off `mySystem.*` options; each `hosts/<name>/default.nix` is a flat list of `enable`s. Three repo-wide contracts:

- **Auto-importer** (`modules/nixos/default.nix`) — every `*.nix` under `modules/nixos/` is imported automatically on every host. Add a service = drop a file; delete a service = remove the file. `_`-prefixed files/dirs are skipped (`_lib/` contracts are imported explicitly).
- **Proxy/dashboard registry** (`_lib/proxy.nix`) — a service writes one `mySystem.proxy.vhosts.<key>` entry (subdomain, upstream, optional dashboard tile); `web/caddy.nix` is the sole reader turning entries into vhosts, `web/homepage.nix` turns them into tiles. Disabled service ⇒ vhost and tile vanish with it. Per-host `proxy.domain`/`tls`: plain-HTTP `<sub>.homelab` on the homelab, ACME `https://<sub>.pengeg.com` on ovh. `proxy.externalTiles` adds dashboard tiles for services proxied elsewhere (the public ovh vhosts show up on the homelab homepage).
- **Failure alerts** (`_lib/notify.nix`) — `mkFailureUnit { ... }` module arg gives any unit an `onFailure` hook that POSTs to ntfy; VPS hosts point `mySystem.notify.url` at the homelab's instance over the tailnet.

Internal names resolve via the Pi-hole `*.homelab` wildcard; public names are real DNS on `pengeg.com` terminating at ovh.

## Services

### homelab

| Service | URL | Notes |
|---------|-----|-------|
| Homepage | `home.homelab` | Dashboard; tiles from the proxy registry + external tiles for public vhosts |
| Pi-hole | `dns.homelab` | DNS + `*.homelab` wildcard (podman) |
| Open WebUI | `ai.homelab` | Chat UI over the local ollama backend |
| Beszel | `stats.homelab` | Monitoring hub; agents on all three hosts (nvidia/SMART/containers where present) |
| cgit | `git.homelab` | Git hosting, catppuccin-themed, syntax highlighting |
| ntfy | `ntfy.homelab` / `ntfy.pengeg.com` | Push notifications; all failure alerts land here; public URL proxied via ovh for APNS |
| Atuin | `atuin.homelab` | Shell-history sync (open registration) |
| Syncthing | `sync.homelab` | File sync |
| Factorio | — | Dedicated server, declarative mod list pinned in the host config |
| Harmonia | `:5000` | Binary cache serving the whole store, signed `homelab-1` |
| restic REST | `:8010` | Append-only backup target for blackbox, nixpad, ovh |
| smartd | — | Disk health monitoring |

### ovh

| Service | URL | Notes |
|---------|-----|-------|
| Caddy (public edge) | `*.pengeg.com` | ACME TLS; fail2ban in front |
| rustypaste | `p.pengeg.com` | Pastebin / file host |
| mcp-nixos | `mcp.pengeg.com/mcp` | NixOS MCP server (the Claude connector fetches this) |
| ntfy proxy | `ntfy.pengeg.com` | basic_auth → homelab's ntfy over the tailnet |
| resticClient | — | `/var/lib/{rustypaste,caddy}` → homelab restic REST server |

### oracle

Beszel agent + baseline modules; Minecraft server pending.

## Build farm

The homelab builds so the other machines never have to (`services/buildserver.nix` + `services/flake-builder.nix`):

- **Remote builder** — `nixremote` user + `nix.settings.trusted-users`; nixpad offloads builds over ssh-ng.
- **flake-builder** — nightly timer that maintains an isolated clone of `github:gegnep/nixos`, runs `nix flake update` (all inputs), builds **both** `blackbox` and `nixpad` toplevels, and only if both succeed commits and pushes the lock (`chore: bump flake.lock (automated)`). A failed build never advances the lock — the hosts must evaluate exactly the lock the homelab built, or substitution breaks. Last successful pair of toplevels is kept as gcroots under `/var/lib/flake-builder` so `nh clean` can't evict closures before the hosts pull them. Runs at `Nice=19`/`CPUWeight=25` so nightly kernel compiles don't starve services.
- **Harmonia** serves the resulting store paths. Consumers: the desktops (via their own `mySystem.homelab.cache`) and now the VPSes (`core/homelab-cache.nix`, `http://homelab:5000` over the tailnet with `fallback = true` so a down tailnet never blocks a build). Colmena pushes system closures directly during deploys, so the cache mainly covers ad-hoc `nix shell`/`nix run` on the VPSes.
- **nightly scan** — a scheduled Claude routine that runs after the bump window and reports to `gegnep/nixos` issues. It triages any open build failure first (root cause from the embedded log, snippet-ready fix commented on the issue, labeled `triaged`), then scans the config for deprecated/renamed/removed options and packages — verified against the *locked* input revs via the [mcp-nixos](https://github.com/utensils/mcp-nixos) connector (hosted on ovh, `services/mcp-nixos.nix`), not channel HEAD.

## Storage & backups

Three layers on the homelab:

1. **btrbk** — hourly snapshots of `@home`/`@var-lib` (24h/7d/4w retention) onto the `/backup` raid1 mirror (`mySystem.backup.mountPoint`).
2. **restic** — `/home` + `/var/lib` offsite to Backblaze B2, with ntfy failure alerts.
3. **unifi-backup** — pulls `.unf` autobackups off the UniFi Cloud Gateway into `/var/lib` ahead of the restic run, so they ride along in both layers.

Plus the **restic REST server** (append-only, per-host credentials) that blackbox, nixpad, and ovh push into — VPS state ends up inside layers 1–2 automatically. The mirror is exported over NFSv4 for browsing from the desktop.

## Secrets

sops-nix with age; one file per host (`secrets/<host>.yaml`), each encrypted to that host's key + my user key (`.sops.yaml`). Service-specific secrets are declared in the service's own module, shared ones in `modules/nixos/sops.nix`.

## Structure

<details>
<summary>Click to expand</summary>

```text
.
├── flake.nix                          # nixosConfigurations + colmena hive from one mkModules
├── flake.lock
├── hosts/
│   ├── homelab/
│   │   ├── default.nix                # mySystem.* enables — the whole host at a glance
│   │   ├── disko.nix                  # NVMe + raid1 mirror layout
│   │   ├── factorio.nix               # server + pinned mod list
│   │   └── hardware-configuration.nix
│   ├── ovh/
│   │   ├── default.nix                # public edge: tls + acme, rustypaste, mcp-nixos, fail2ban
│   │   ├── disko.nix
│   │   └── hardware-configuration.nix # BIOS/GRUB (no EFI on this VPS)
│   └── oracle/
│       ├── default.nix                # aarch64
│       ├── disko.nix
│       └── hardware-configuration.nix
├── secrets/
│   ├── homelab.yaml                   # sops (age), one per host
│   ├── ovh.yaml
│   └── oracle.yaml
└── modules/
    ├── nixos/
    │   ├── default.nix                # auto-importer (the only default.nix in the tree)
    │   ├── sops.nix                   # defaultSopsFile + shared secrets
    │   ├── _lib/
    │   │   ├── notify.nix             # mySystem.notify.* + mkFailureUnit contract
    │   │   └── proxy.nix              # mySystem.proxy.vhosts + externalTiles registry contract
    │   ├── core/
    │   │   ├── boot.nix
    │   │   ├── colmena-target.nix     # root deploy key (tailnet, key-only)
    │   │   ├── homelab-cache.nix      # harmonia substituter for non-homelab hosts
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
    │   │   ├── beszel.nix             # hub + agent branches
    │   │   ├── buildserver.nix        # harmonia + nixremote build user
    │   │   ├── cgit/                  # cgit.nix + catppuccin css
    │   │   ├── fail2ban.nix
    │   │   ├── flake-builder.nix      # nightly desktop-flake lock bump + prebuild
    │   │   ├── mcp-nixos.nix          # http transport, funnel optional
    │   │   ├── netdata.nix            # disabled (enshittified)
    │   │   ├── ntfy.nix
    │   │   ├── ollama.nix
    │   │   ├── open-webui.nix
    │   │   ├── pihole.nix
    │   │   ├── rustypaste/            # rustypaste.nix + landing page
    │   │   ├── smartd.nix
    │   │   └── syncthing.nix
    │   └── web/
    │       ├── caddy.nix              # sole reader of the proxy registry (http or acme per host)
    │       └── homepage.nix           # dashboard tiles from the same registry
    └── home/                          # thin: imports nvim/zsh from the desktop tree
```

</details>

## Building

```sh
# Fleet:
colmena apply

# Single host, on the box:
nh os switch
```

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
