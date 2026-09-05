# nixos-prod

NixOS flake for my homelab and VPS fleet.

## Hosts

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, R9700 + Arc A310 | Headless server — DNS, dashboards, git, AI (ollama/rocm, Open WebUI, Unsloth Studio), Factorio, backups, nix build farm. |
| **sidecar** | Ryzen 3 3100, RTX 3060 | Second inference node — ollama/cuda. |
| **ovh** | OVH VPS (x86_64, BIOS/GRUB) | Public edge — ACME TLS for `*.pengeg.com`, rustypaste, mcp-nixos, ntfy proxy. |
| **oracle** | Oracle Cloud A1 (aarch64) | Mostly idle — Minecraft pending. Builds on-target. |

Each host is one `mkHost` call in `flake.nix` plus `hosts/<name>/{default.nix, disko.nix, hardware-configuration.nix}`. Every host imports the same auto-discovered module tree; `default.nix` is a flat list of `mySystem.*` enables.

## Options

<details>
<summary>Click to expand</summary>

```text
mySystem
├── notify                             # _lib/notify.nix
│   ├── url                            # ntfy base URL failure alerts POST to (homelab, over tailnet)
│   └── topic
├── proxy                              # _lib/proxy.nix
│   ├── domain                         # homelab | pengeg.com
│   ├── tls / acmeEmail                # ACME on ovh; plain http on homelab
│   ├── vhosts.<key>                   # sub, upstream | rawConfig, dashboard { name description path group }
│   └── externalTiles.<key>            # dashboard tiles for services proxied elsewhere
├── network
│   ├── uplink
│   └── tailscale.exitNode
├── homelabCache.enable                # substitute from Harmonia over tailnet (non-homelab hosts)
├── colmenaTarget.enable               # accept root deploys, key-only, tailnet
├── hardware
│   ├── amd.enable                     # rocm, LACT fan curve
│   ├── intel.enable
│   └── nvidia.enable                  # open driver + container toolkit
├── backup.mountPoint                  # raid1 mirror (homelab)
├── storage
│   ├── snapshots.enable               # btrbk → backup.mountPoint
│   ├── nfs.enable                     # export backup.mountPoint
│   └── scrub.enable                   # monthly btrfs scrub
└── services
    ├── caddy          { enable environmentFile }
    ├── homepage       { enable port settings }
    ├── pihole         { enable image timezone upstreams webPort environment }
    ├── ntfy           { enable port baseUrl settings }
    ├── beszel
    │   ├── hub        { enable port }
    │   └── agent      { enable nvidia amd intel smart containers }
    ├── ollama         { enable acceleration rocmOverrideGfx environment }     # cuda | rocm | cpu
    ├── open-webui     { enable port environment }
    ├── openai-oauth   { enable port }                                        # codex OAuth → openai-compatible, loopback
    ├── tinyfish-search{ enable port }                                        # search/fetch shim for Open WebUI
    ├── unsloth        { enable acceleration image port version studioRef }   # containerized, owned-image build
    ├── cgit           { enable repoDir sshUser package highlightStyle }
    ├── atuin          { enable port openRegistration }
    ├── syncthing      { enable guiPort dataDir lanSync settings }
    ├── factorio       { enable port admins username mods extraSettings }
    ├── rustypaste     { enable port url maxContentLength }
    ├── mcp-nixos      { enable port package funnel }
    ├── fail2ban.enable
    ├── smartd.enable
    ├── buildServer.enable                                                    # harmonia + nixremote
    ├── flake-builder  { enable repoUrl localPath hosts extraSubstituters onCalendar issueRepo issueLabels }
    ├── restic         { enable paths exclude }                               # → B2
    ├── resticServer   { enable port tailnetAddress dataDir clients pruneOnCalendar }
    ├── resticClient   { enable paths exclude onCalendar }                    # → resticServer
    └── unifi-backup   { enable host remotePath localPath onCalendar }
```

</details>

## Layout

<details>
<summary>Click to expand</summary>

```text
.
├── flake.nix / flake.lock             # nixosConfigurations + colmena hive from one mkModules
├── hosts/
│   ├── homelab/                       # + factorio.nix (pinned mods); disko: NVMe + 2×2 TB raid1 → /backup
│   ├── sidecar/                       # nvidia inference node; disko: NVMe, nodatacow @models/@containers
│   ├── ovh/                           # public edge; BIOS/GRUB
│   └── oracle/                        # aarch64
├── secrets/<host>.yaml                # sops (age), one per host
├── containers/unsloth/                # Containerfile{,.rocm} + entrypoint + rocm gemm patch
├── pkgs/openai-oauth/                 # ChatGPT-OAuth → OpenAI-compatible proxy (node)
└── modules/
    ├── nixos/
    │   ├── default.nix                # auto-importer (the only default.nix in the tree)
    │   ├── sops.nix                   # defaultSopsFile + shared secrets
    │   ├── _lib/
    │   │   ├── notify.nix             # mySystem.notify.* + mkFailureUnit contract
    │   │   └── proxy.nix              # mySystem.proxy.vhosts + externalTiles registry contract
    │   ├── core/                      # boot, networking, nix (lix, nh), users, podman, power,
    │   │                              #   colmena-target, homelab-cache
    │   ├── hardware/                  # amd, graphics (intel), nvidia
    │   ├── storage/
    │   │   ├── options.nix            # mySystem.backup.mountPoint
    │   │   ├── filesystems.nix        # btrfs top-level mount for btrbk
    │   │   ├── btrbk.nix              # hourly snapshots → /backup
    │   │   ├── restic.nix             # /home + /var/lib → B2, ntfy-guarded
    │   │   ├── restic-server.nix      # append-only REST target for the other hosts
    │   │   ├── restic-client.nix      # push to that server (ovh)
    │   │   ├── unifi-backup.nix       # UCG .unf pull, ntfy-guarded
    │   │   ├── scrub.nix
    │   │   └── nfs.nix                # /backup exported
    │   ├── services/
    │   │   ├── atuin.nix
    │   │   ├── beszel.nix             # hub + agent
    │   │   ├── buildserver.nix        # harmonia + nixremote build user
    │   │   ├── cgit/                  # cgit.nix + catppuccin css
    │   │   ├── factorio.nix           # headless server, version pinned by hand
    │   │   ├── fail2ban.nix
    │   │   ├── flake-builder.nix      # nightly desktop-flake lock bump + prebuild
    │   │   ├── mcp-nixos.nix          # http transport, funnel optional (ovh)
    │   │   ├── ntfy.nix
    │   │   ├── ollama.nix             # + ollama-import / ollama-prune helpers
    │   │   ├── open-webui.nix
    │   │   ├── openai-oauth.nix
    │   │   ├── pihole.nix             # DNS + *.homelab wildcard (podman)
    │   │   ├── rustypaste/            # rustypaste.nix + landing page
    │   │   ├── smartd.nix
    │   │   ├── syncthing.nix
    │   │   ├── tinyfish-search.nix
    │   │   └── unsloth.nix
    │   └── web/
    │       ├── caddy.nix              # sole reader of the proxy registry (http or acme per host)
    │       └── homepage.nix           # dashboard tiles from the same registry
    └── home/                          # thin: nvim (nvf) + zsh imported from the desktop tree
```

</details>

Contracts: every `*.nix` under `modules/nixos/` is imported on every host (`_`-prefixed skipped, `_lib/` imported explicitly). A service writes one `proxy.vhosts.<key>`; `caddy.nix` and `homepage.nix` are the only readers. `mkFailureUnit` gives a unit an `onFailure` hook that POSTs to `notify.url`.

Names: `home dns ai sloth stats git ntfy atuin sync` under `.homelab` (Pi-hole wildcard); Harmonia `:5000`, restic REST `:8010`. Public: `p mcp ntfy` under `.pengeg.com`.

## Inputs

[home-manager](https://github.com/nix-community/home-manager) · [nvf](https://github.com/notashelf/nvf) · [disko](https://github.com/nix-community/disko) · [sops-nix](https://github.com/Mic92/sops-nix) · [colmena](https://github.com/nix-community/colmena) · [catppuccin/nix](https://github.com/catppuccin/nix) · [gegnep/nixos](https://github.com/gegnep/nixos) (`flake = false`, home modules by store path)

## Deployment

[Colmena](https://colmena.cli.rs), stateless, from any checkout. `nixosConfigurations` and the hive share one module list.

```sh
colmena build                              # eval + build every host; nothing activates
colmena apply --on sidecar,ovh,oracle      # push closures over the tailnet, activate
colmena apply-local --sudo                 # homelab itself (targetHost = null, never SSH-to-self)
```

Targets accept the deploy key as root over the tailnet; sops decrypts on-host with each host's age key. oracle builds on-target. Fleet update: `nix flake update && colmena build`, apply, commit the lock.

## Automation

**flake-builder** (homelab) bumps `gegnep/nixos`'s lock nightly, builds both desktop toplevels, pushes only if both succeed, keeps the last good pair as gcroots. **Harmonia** serves the closures to the desktops and VPSes (`fallback = true`). A **nightly Claude scan** triages build failures and files deprecation findings as `gegnep/nixos` issues, checked against the locked input revs via mcp-nixos on ovh. `nixremote` takes offloaded builds from nixpad over ssh-ng.

## Backups

homelab: **btrbk** hourly `@home`/`@var-lib` snapshots → raid1 mirror; **restic** `/home` + `/var/lib` → B2; **unifi-backup** pulls UCG `.unf` into `/var/lib` first. The append-only **restic REST server** on the mirror takes pushes from blackbox, nixpad, ovh, so their state lands in the first two layers too. Client timers avoid the local prune and the B2 window (exclusive repo lock).

## Secrets

sops-nix + age, `secrets/<host>.yaml`, each encrypted to that host's key plus my user key (`.sops.yaml`). Service secrets live in the service's module; shared ones in `modules/nixos/sops.nix`.

## Building

```sh
colmena apply                                       # fleet
nh os switch                                        # single host, on the box
```

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
