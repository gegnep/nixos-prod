# nixos-prod

NixOS flake config for my homelab and VPS hosts.
[GitHub](https://github.com/gegnep/nixos-prod) [GitLab](https://gitlab.com/pengeg/nixos-prod)

## Hosts

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, 31 GiB, RTX 3060 + Arc A310 | Headless server — DNS, dashboards, git, AI, game servers, backups, nix build farm |
| **ovh** | OVH VPS (x86_64, BIOS/GRUB) | Public edge — ACME TLS vhosts on `pengeg.com` (MCP, pastebin, ntfy) |
| **oracle** | Oracle Cloud A1 (aarch64) | Spare capacity — monitoring agent only, for now |

All three are `mkHost` calls in `flake.nix` (oracle passes `system = "aarch64-linux"`), installed via nixos-anywhere over SSH (disko-partitioned, btrfs `@ @nix @home @var-lib` everywhere):

- **homelab**: NVMe (1 TB) systemd-boot ESP + btrfs (`+ @snapshots`); 2× 2 TB SATA btrfs **raid1** mirror → `/backup`, exported over NFSv4. Also runs `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` so it can build for oracle.
- **ovh**: single disk, BIOS boot — GRUB via `lib.mkForce` over the systemd-boot default.
- **oracle**: single disk, UEFI.
- Lix, `nh os switch`, key-only SSH, tailscale (`--ssh`) on every host; homelab advertises as an exit node with a UDP-GRO oneshot on the uplink.
- nvim (nvf) + zsh (p10k) imported from the desktop repo (`github:gegnep/nixos`) as a plain source tree — individual home modules by store path, without inheriting its inputs.

## Conventions

Everything hangs off `mySystem.*` options; each `hosts/<name>/default.nix` is a flat list of `enable`s. Three repo-wide contracts:

- **Auto-importer** (`modules/nixos/default.nix`) — every `*.nix` under `modules/nixos/` is imported automatically on every host. Add a service = drop a file; delete a service = remove the file. `_`-prefixed files/dirs are skipped (`_lib/` contracts are imported explicitly).
- **Proxy/dashboard registry** (`_lib/proxy.nix`) — a service writes one `mySystem.proxy.vhosts.<key>` entry (subdomain, upstream or raw Caddy config, optional dashboard tile); `web/caddy.nix` is the sole reader turning entries into vhosts, `web/homepage.nix` turns them into tiles. Disabled service ⇒ vhost and tile vanish with it. `proxy.domain` + `proxy.tls` set the flavor per host: the homelab serves plain-HTTP `<sub>.homelab` (resolved by the Pi-hole wildcard), ovh serves ACME-TLS `<sub>.pengeg.com`. `proxy.externalTiles` adds dashboard tiles for services proxied elsewhere (the public ovh vhosts show up on the homelab dashboard).
- **Failure alerts** (`_lib/notify.nix`) — `mkFailureUnit { ... }` module arg gives any unit an `onFailure` hook that POSTs to ntfy. `mySystem.notify.url` defaults to localhost; the VPS hosts point it at the homelab's ntfy over the tailnet by raw IP — no DNS dependency in the failure path.

## Services

### homelab (`<sub>.homelab`, tailnet-only)

| Service | URL | Notes |
|---------|-----|-------|
| Homepage | `home.homelab` | Dashboard; tiles from the proxy registry + external tiles for the public ovh vhosts |
| Pi-hole | `dns.homelab` | DNS + `*.homelab` wildcard (podman) |
| Open WebUI | `ai.homelab` | Chat UI over the local ollama backend |
| Beszel | `stats.homelab` | Monitoring hub; agents on all three hosts (nvidia, SMART, containers on homelab) |
| cgit | `git.homelab` | Git hosting, catppuccin-themed, syntax highlighting |
| ntfy | `ntfy.homelab` | Push notifications; all failure alerts land here. `baseUrl` is the public `https://ntfy.pengeg.com` (see ovh) |
| Atuin | `atuin.homelab` | Shell-history sync (open registration); client key shared to all hosts via sops |
| Syncthing | `sync.homelab` | File sync |
| Factorio | — | Dedicated server (tailnet-only UDP), pinned mod list in `hosts/homelab/factorio.nix` |
| Harmonia | `:5000` | Binary cache serving the whole store, signed `homelab-1` (key from sops) |
| Restic REST | `:8010` | Append-only backup target for blackbox/nixpad/ovh, tailnet IP only |
| smartd | — | Disk health monitoring |

### ovh (`<sub>.pengeg.com`, public, ACME TLS)

| Service | URL | Notes |
|---------|-----|-------|
| mcp-nixos | `mcp.pengeg.com` | NixOS MCP server (Streamable HTTP, stateless); default package carries the PR159 channel-discovery patch. Module still has a tailscale-funnel option, off here |
| rustypaste | `p.pengeg.com` | Minimal auth-token pastebin, custom landing page |
| ntfy (proxy) | `ntfy.pengeg.com` | Raw-config vhost: basic_auth, then reverse-proxies to the homelab's ntfy over the tailnet (Authorization header stripped) |
| fail2ban | — | sshd jail with incremental bans; tailnet CGNAT range ignored |
| restic client | — | `/var/lib/rustypaste` + `/var/lib/caddy` → homelab REST server nightly |
| Beszel agent | — | Reports to the homelab hub |

### oracle

fail2ban + Beszel agent. Otherwise idle.

## Build farm

The homelab builds so the desktop machines never have to (`services/buildserver.nix` + `services/flake-builder.nix`):

- **Remote builder** — `nixremote` user + `nix.settings.trusted-users`; nixpad offloads builds over ssh-ng.
- **flake-builder** — nightly timer that maintains an isolated clone of `github:gegnep/nixos`, runs `nix flake update` (all inputs), builds **both** `blackbox` and `nixpad` toplevels, and only if both succeed commits and pushes the lock (`chore: bump flake.lock (automated)`). A failed build never advances the lock — the hosts must evaluate exactly the lock the homelab built, or substitution breaks. Failures also open a GitHub issue on the desktop repo (separate fine-grained PAT; the deploy key can't touch the issues API). Last successful pair of toplevels is kept as gcroots under `/var/lib/flake-builder` so `nh clean` can't evict closures before the hosts pull them. Runs at `Nice=19`/`CPUWeight=25` so nightly kernel compiles don't starve services.
- **Harmonia** serves the resulting store paths; the desktops list `http://homelab:5000` + the `homelab-1` key as a substituter.

## Storage & backups

Layered, with a fixed nightly order — clients 23:00 UTC → prune 02:00 → unifi 02:30 → B2 03:00 (client pushes and the prune contend for the same exclusive repo locks; a B2 copy taken mid-prune would be a broken repo copy):

1. **btrbk** — hourly snapshots of `@home`/`@var-lib` (24h/7d/4w retention) onto the `/backup` raid1 mirror (`mySystem.backup.mountPoint`).
2. **Restic REST server** — append-only landing zone on the mirror for blackbox, nixpad, and ovh (`storage/restic-server.nix`). Per-host htpasswd users with `privateRepos`; clients can't delete history, so retention (`forget --prune` + `check`) runs homelab-side at 02:00 against the repos as plain paths.
3. **unifi-backup** — pulls `.unf` autobackups off the UniFi Cloud Gateway into `/var/lib` ahead of the offsite run.
4. **restic → B2** — `/home` + `/var/lib` *and* the REST-server repos offsite to Backblaze B2 at 03:00, so the client backups ride along. ntfy-guarded like everything else.

Plus weekly btrfs scrub on every host (root + the mirror on homelab), NFSv4 export of the mirror for browsing from the desktop, and smartd.

## Secrets

sops-nix with age, one file per host: `secrets/<hostname>.yaml`, selected automatically by `modules/nixos/sops.nix` from `networking.hostName`. Recipients per file are my user key + that host's key (`.sops.yaml`). Service-specific secrets are declared in the service's own module; shared ones (currently the atuin client key) in `sops.nix`.

## Structure

<details>
<summary>Click to expand</summary>

```text
.
├── flake.nix
├── flake.lock
├── .sops.yaml                         # per-host creation rules (age)
├── hosts/
│   ├── homelab/
│   │   ├── default.nix                # mySystem.* enables — the whole host at a glance
│   │   ├── factorio.nix               # factorio enable + pinned mod list
│   │   ├── disko.nix                  # NVMe + raid1 mirror layout
│   │   └── hardware-configuration.nix
│   ├── ovh/
│   │   ├── default.nix                # public TLS vhosts; GRUB override for BIOS boot
│   │   ├── disko.nix
│   │   └── hardware-configuration.nix
│   └── oracle/
│       ├── default.nix                # aarch64
│       ├── disko.nix
│       └── hardware-configuration.nix
├── secrets/
│   ├── homelab.yaml                   # sops (age), one file per host
│   ├── ovh.yaml
│   └── oracle.yaml
└── modules/
    ├── nixos/
    │   ├── default.nix                # auto-importer (the only default.nix in the tree)
    │   ├── sops.nix                   # defaultSopsFile = secrets/<hostname>.yaml + shared secrets
    │   ├── _lib/
    │   │   ├── notify.nix             # mySystem.notify.* + mkFailureUnit contract
    │   │   └── proxy.nix              # mySystem.proxy.{vhosts,externalTiles,domain,tls} contract
    │   ├── core/
    │   │   ├── boot.nix
    │   │   ├── networking.nix         # networkd, tailscale (+ exit node, UDP-GRO oneshot), ssh
    │   │   ├── nix.nix                # lix, substituters, nh + clean
    │   │   ├── users.nix
    │   │   └── virtualisation.nix     # podman as the shared oci backend
    │   ├── hardware/
    │   │   ├── graphics.nix           # mySystem.hardware.intel — Intel/Arc media stack
    │   │   └── nvidia.nix             # mySystem.hardware.nvidia
    │   ├── storage/
    │   │   ├── options.nix            # mySystem.backup.mountPoint + storage.{snapshots,nfs,scrub}
    │   │   ├── filesystems.nix        # btrfs top-level mount for btrbk
    │   │   ├── btrbk.nix              # hourly snapshots → /backup
    │   │   ├── scrub.nix              # weekly btrfs scrub
    │   │   ├── restic.nix             # /home + /var/lib (+ REST repos) → B2, ntfy-guarded
    │   │   ├── restic-server.nix      # append-only REST server + homelab-side prune
    │   │   ├── restic-client.nix      # VPS push to the REST server
    │   │   ├── unifi-backup.nix       # UCG .unf pull, ntfy-guarded
    │   │   └── nfs.nix                # /backup exported
    │   ├── services/
    │   │   ├── atuin.nix
    │   │   ├── beszel.nix             # hub + agent (nvidia, SMART, containers)
    │   │   ├── buildserver.nix        # harmonia + nixremote build user
    │   │   ├── cgit/                  # cgit.nix + catppuccin css
    │   │   ├── factorio.nix           # server + declarative mod fetcher
    │   │   ├── fail2ban.nix           # sshd jail for public-IP hosts
    │   │   ├── flake-builder.nix      # nightly desktop-flake lock bump + prebuild
    │   │   ├── mcp-nixos.nix          # + channel-discovery patch, optional funnel
    │   │   ├── netdata.nix            # disabled (enshittified)
    │   │   ├── ntfy.nix
    │   │   ├── ollama.nix
    │   │   ├── open-webui.nix
    │   │   ├── pihole.nix
    │   │   ├── rustypaste/            # rustypaste.nix + landing page
    │   │   ├── smartd.nix
    │   │   └── syncthing.nix
    │   └── web/
    │       ├── caddy.nix              # sole reader of the proxy registry; ACME when proxy.tls
    │       └── homepage.nix           # tiles from the registry + externalTiles
    └── home/                          # thin: imports nvim/zsh from the desktop tree
```

</details>

## Building

```sh
# On the host:
nh os switch

# Or from anywhere:
sudo nixos-rebuild switch --flake .#<hostname>
```

The homelab has aarch64 binfmt emulation, so `oracle` closures can be prebuilt there.

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
