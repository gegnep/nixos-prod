# nixos-prod

NixOS flake for my homelab and VPS fleet.

## Hosts

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, 64 GB, 2× R9700 + Arc A310 | Headless server: DNS, dashboards, git, model hosting (llama-swap over llama.cpp/ROCm, Radiance, Project Maya; Unsloth Studio on demand), Factorio, backups, nix build farm. |
| **sidecar** | Ryzen 3 3100, RTX 3060 | UI node: Open WebUI, openai-oauth, small models (llama-swap over llama.cpp/CUDA). |
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
│   ├── amd            { enable lactGpus }                                    # rocm, LACT fan curve per card
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
    ├── inference      { enable acceleration cudaArchitectures port listenAddress macros settings }   # llama-swap + llama.cpp, ai CLI
    │   ├── radiance   { enable image }                                       # tensor parallel, image pinned by digest
    │   └── maya       { enable gpus }                                        # GLM-5.3-Flash, owned ROCm image
    ├── open-webui     { enable port environment openaiConnections }
    ├── openai-oauth   { enable port }                                        # codex OAuth → openai-compatible, loopback
    ├── tinyfish-search{ enable port listenAddresses tokenSecrets }           # search/fetch shim for Open WebUI
    ├── unsloth        { enable acceleration image port version studioRef autoStart }   # owned image; ai train on|off
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
    ├── resticClient   { enable paths exclude onCalendar }                    # → resticServer (ovh, sidecar)
    └── unifi-backup   { enable host remotePath localPath onCalendar }
```

</details>

## Layout

<details>
<summary>Click to expand</summary>

```text
.
├── flake.nix / flake.lock             # nixosConfigurations + colmena hive from one mkModules
├── pins.json                          # versions outside nixpkgs: unsloth, radiance, maya, llama.cpp
├── hosts/
│   ├── homelab/                       # + factorio.nix (pinned mods); disko: NVMe + 2×2 TB raid1 → /backup
│   ├── sidecar/                       # Open WebUI + small models; disko: NVMe, nodatacow @models/@containers
│   ├── ovh/                           # public edge; BIOS/GRUB
│   └── oracle/                        # aarch64
├── secrets/<host>.yaml                # sops (age), one per host
├── containers/unsloth/                # Containerfile{,.rocm} + entrypoint + rocm gemm patch
├── containers/maya/                   # ROCm 7.2.1 toolchain image; entrypoint fetches Maya by commit
├── pkgs/openai-oauth/                 # ChatGPT-OAuth → OpenAI-compatible proxy (node)
├── pkgs/update-pins/                  # nix run .#update-pins [name...]: pins.json → latest
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
    │   │   ├── btrbk.nix              # snapshots every 4 h → /backup
    │   │   ├── restic.nix             # /home + /var/lib → B2, ntfy-guarded
    │   │   ├── restic-server.nix      # append-only REST target for the other hosts
    │   │   ├── restic-client.nix      # push to that server (ovh, sidecar)
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
    │   │   ├── inference/             # inference.nix (llama-swap, polkit), ai.sh, engine-shim.sh,
    │   │   │                          #   radiance.nix, maya.nix
    │   │   ├── mcp-nixos.nix          # http transport, funnel optional (ovh)
    │   │   ├── ntfy.nix
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

Names: `home dns ai sloth stats git ntfy atuin sync llm llm-sidecar` under `.homelab` (Pi-hole wildcard). `ai` is Open WebUI on sidecar; `llm` and `llm-sidecar` are the llama-swap UIs. Harmonia `:5000`, restic REST `:8010`, llama-swap `:8180` on homelab and sidecar. Public: `p mcp ntfy` under `.pengeg.com`.

## Models

Engines and the front door are declarative; models are runtime state. Each inference host runs llama-swap on `:8180` (OpenAI `/v1`, Anthropic `/v1/messages`) with one YAML per model in `/var/lib/llama-swap/models.d`, hot-reloaded. The `ai` CLI writes them:

```sh
ai st | ls | up ID | down [ID] | logs [ID] | bench ID               # state and control
ai add ID --from REPO:GLOB [--engine llama|radiance] [-- ARGS]      # pull weights, register
ai add ID --engine maya --from Maya-S24 [-- --context 65536]        # Maya: compile + pack, then register
ai edit ID | rm ID [--purge] | train on|off                         # train: Unsloth Studio takes the GPUs
```

One model holds the GPUs at a time. llama.cpp runs as a llama-swap child; Radiance and Maya run as podman units (`radiance@`, `maya@`) that an engine shim starts and stops; polkit lets the llama-swap user do that and nothing else. Everything re-downloadable lives under `/var/lib/models/cache/` (`@models`: nodatacow, outside btrbk, excluded from restic).

## Inputs

[home-manager](https://github.com/nix-community/home-manager) · [nvf](https://github.com/notashelf/nvf) · [disko](https://github.com/nix-community/disko) · [sops-nix](https://github.com/Mic92/sops-nix) · [colmena](https://github.com/nix-community/colmena) · [catppuccin/nix](https://github.com/catppuccin/nix) · [gegnep/nixos](https://github.com/gegnep/nixos) (`flake = false`, home modules by store path)

## Deployment

[Colmena](https://colmena.cli.rs), stateless, from any checkout. `nixosConfigurations` and the hive share one module list.

```sh
colmena build                              # eval + build every host; nothing activates
colmena apply --on sidecar,ovh,oracle      # push closures over the tailnet, activate
colmena apply-local --sudo                 # homelab itself (targetHost = null, never SSH-to-self)
```

Targets accept the deploy key as root over the tailnet; sops decrypts on-host with each host's age key. oracle builds on-target. Fleet update: `nix flake update && nix run .#update-pins && colmena build`, apply, commit `flake.lock` and `pins.json`.

## Automation

**flake-builder** (homelab) bumps `gegnep/nixos`'s lock nightly, builds both desktop toplevels, pushes only if both succeed, keeps the last good pair as gcroots. **Harmonia** serves the closures to the desktops and VPSes (`fallback = true`). A **nightly Claude scan** triages build failures and files deprecation findings as `gegnep/nixos` issues, checked against the locked input revs via mcp-nixos on ovh. `nixremote` takes offloaded builds from nixpad over ssh-ng.

## Backups

homelab: **btrbk** `@home`/`@var-lib` snapshots every 4 h → raid1 mirror; **restic** `/home` + `/var/lib` → B2; **unifi-backup** pulls UCG `.unf` into `/var/lib` first. The append-only **restic REST server** on the mirror takes pushes from blackbox, nixpad, ovh and sidecar (Open WebUI state), so their state lands in the first two layers too. Client timers avoid the local prune and the B2 window (exclusive repo lock). Re-downloadable weights and engine build trees (`/var/lib/models/cache/`) stay out of every layer; Studio's GGUF exports (`/var/lib/models/gguf/`) go to B2.

## Secrets

sops-nix + age, `secrets/<host>.yaml`, each encrypted to that host's key plus my user key (`.sops.yaml`). Service secrets live in the service's module; shared ones in `modules/nixos/sops.nix`.

## Building

```sh
colmena apply                                       # fleet
nh os switch                                        # single host, on the box
```

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
