# nixos-prod

NixOS flake for my homelab and VPS fleet.

## Hosts

| Host | Machine | Role |
|------|---------|------|
| **homelab** | Ryzen 5 3600, 64 GB, 2× R9700 + Arc A310 | DNS, dashboards, git, inference (llama.cpp/ROCm, Radiance, Maya), Unsloth Studio, printcam, Factorio, backups, build farm. |
| **sidecar** | Ryzen 3 3100, RTX 3060 | Open WebUI, openai-oauth, small models (llama.cpp/CUDA). |
| **ovh** | OVH VPS (x86_64, BIOS/GRUB) | Public edge: ACME for `*.pengeg.com`, rustypaste, mcp-nixos, ntfy proxy, cam. |
| **oracle** | Oracle Cloud A1 (aarch64) | Idle (Minecraft pending). Builds on-target. |

Each host is one `mkHost` call in `flake.nix` plus `hosts/<name>/{default.nix, disko.nix, hardware-configuration.nix}`. `default.nix` is a flat list of `mySystem.*` enables.

## Options

<details>
<summary>Click to expand</summary>

```text
mySystem
├── notify             { url topic }                                          # _lib/notify.nix
├── proxy                                                                     # _lib/proxy.nix
│   ├── domain                         # homelab | pengeg.com
│   ├── tls / acmeEmail                # ACME on ovh; plain http on homelab
│   ├── vhosts.<key>                   # sub, upstream | rawConfig, dashboard { name description path group }
│   └── externalTiles.<key>            # tiles for services proxied elsewhere
├── network            { uplink tailscale.exitNode }
├── homelabCache.enable                # substitute from Harmonia over tailnet
├── colmenaTarget.enable               # root deploys, key-only, tailnet
├── hardware
│   ├── amd            { enable lactGpus }                                    # rocm, LACT fan curve per card
│   ├── intel.enable
│   └── nvidia.enable                  # open driver + container toolkit
├── backup.mountPoint                  # raid1 mirror (homelab)
├── storage            { snapshots nfs scrub }.enable                         # btrbk, NFS export, monthly scrub
└── services
    ├── caddy          { enable environmentFile }
    ├── homepage       { enable port settings }
    ├── pihole         { enable image timezone upstreams webPort environment }
    ├── ntfy           { enable port baseUrl settings }
    ├── beszel
    │   ├── hub        { enable port }
    │   └── agent      { enable nvidia amd intel smart containers }
    ├── inference      { enable acceleration cudaArchitectures port listenAddress macros settings }   # llama-swap + llama.cpp, ai CLI
    │   ├── radiance   { enable image }                                       # image by digest (pins.json)
    │   └── maya       { enable gpus }                                        # owned ROCm image, commit (pins.json)
    ├── open-webui     { enable port environment openaiConnections }
    ├── openai-oauth   { enable port }                                        # codex OAuth → openai-compatible, loopback
    ├── tinyfish-search{ enable port listenAddresses tokenSecrets }           # search/fetch shim for Open WebUI
    ├── unsloth        { enable acceleration image port version studioRef autoStart }   # owned image (pins.json)
    ├── printcam       { enable port stream cameraHost connect collector edge }         # go2rtc, Prusa Connect, telemetry; edge on ovh
    ├── cgit           { enable repoDir sshUser package highlightStyle }
    ├── atuin          { enable port openRegistration }
    ├── syncthing      { enable guiPort dataDir lanSync settings }
    ├── factorio       { enable port admins username mods extraSettings }
    ├── monifactory    { enable image packVersion forgeVersion port memory players mods }
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
├── flake.nix / flake.lock             # nixosConfigurations + colmena hive from one module list
├── pins.json                          # versions outside nixpkgs (see Deployment)
├── hosts/
│   ├── homelab/                       # + factorio.nix; disko: NVMe + 2×2 TB raid1 → /backup
│   ├── sidecar/                       # disko: NVMe, nodatacow @models/@containers
│   ├── ovh/                           # BIOS/GRUB
│   └── oracle/                        # aarch64
├── secrets/<host>.yaml                # sops (age)
├── containers/
│   ├── unsloth/                       # Containerfile{,.rocm}, entrypoint, rocm gemm patch
│   └── maya/                          # ROCm 7.2.1 toolchain; entrypoint fetches Maya by commit
├── pkgs/
│   ├── openai-oauth/                  # ChatGPT OAuth → OpenAI-compatible proxy (node)
│   └── update-pins/                   # nix run .#update-pins
└── modules/
    ├── nixos/
    │   ├── default.nix                # auto-importer
    │   ├── sops.nix                   # defaultSopsFile + shared secrets
    │   ├── _lib/                      # notify.nix (mkFailureUnit), proxy.nix (vhost registry)
    │   ├── core/                      # boot, networking, nix (lix, nh), users, virtualisation (podman),
    │   │                              #   power, pki, colmena-target, homelab-cache
    │   ├── hardware/                  # amd, graphics (intel), nvidia
    │   ├── storage/                   # options, filesystems, btrbk, restic{,-server,-client},
    │   │                              #   unifi-backup, scrub, nfs
    │   ├── services/
    │   │   ├── cgit/                  # + catppuccin css
    │   │   ├── inference/             # inference.nix (llama-swap), radiance.nix, maya.nix,
    │   │   │                          #   ai.sh, engine-shim.sh
    │   │   ├── printcam/              # printcam.nix, collector.py, index.html
    │   │   ├── rustypaste/            # + landing page
    │   │   └── *.nix                  # one file per service (see Options)
    │   └── web/                       # caddy.nix, homepage.nix: the only registry readers
    └── home/                          # nvim (nvf) + zsh from the desktop flake
```

</details>

Contracts: every `*.nix` under `modules/nixos/` is imported on every host (`_`-prefixed skipped, `_lib/` imported explicitly). A service writes one `proxy.vhosts.<key>`; `caddy.nix` and `homepage.nix` read it. `mkFailureUnit` gives a unit an `onFailure` hook that POSTs to `notify.url`.

Names: `home dns ai sloth stats git ntfy atuin sync llm llm-sidecar` under `.homelab` (Pi-hole wildcard). Public: `p mcp ntfy cam` under `.pengeg.com`. Ports: Harmonia `:5000`, restic REST `:8010`, llama-swap `:8180`.

## Models

Engines are declarative; models are runtime state. llama-swap on `:8180` (OpenAI `/v1`, Anthropic `/v1/messages`) reads one YAML per model from `/var/lib/llama-swap/models.d`, hot-reloaded. The `ai` CLI writes them:

```sh
ai st | ls | up ID | down [ID] | logs [ID] | bench ID               # state and control
ai add ID --from REPO:GLOB [--engine llama|radiance] [-- ARGS]      # pull weights, register
ai add ID --engine maya --from Maya-S24 [-- --context 65536]        # compile + pack, register
ai maya-setup QUANT | maya-bench QUANT                              # re-run Maya setup / bench
ai edit ID | rm ID [--purge] | train on|off                         # train: Studio takes the GPUs
```

One model holds the GPUs at a time. Radiance and Maya run as podman units (`radiance@`, `maya@`) started by an engine shim; polkit scopes the llama-swap user to those units. Re-downloadable state lives in `/var/lib/models/cache/` (nodatacow, outside every backup layer).

## Inputs

[home-manager](https://github.com/nix-community/home-manager) · [nvf](https://github.com/notashelf/nvf) · [disko](https://github.com/nix-community/disko) · [sops-nix](https://github.com/Mic92/sops-nix) · [colmena](https://github.com/nix-community/colmena) · [catppuccin/nix](https://github.com/catppuccin/nix) · [gegnep/nixos](https://github.com/gegnep/nixos) (`flake = false`, home modules by store path)

## Deployment

[Colmena](https://colmena.cli.rs), from any checkout. Targets take the deploy key as root over the tailnet; sops decrypts on-host.

```sh
colmena build                              # eval + build every host, nothing activates
colmena apply --on sidecar,ovh,oracle      # push over tailnet, activate
colmena apply-local --sudo                 # homelab itself (never SSH-to-self)
nh os switch                               # single host, on the box
```

### Updates

```sh
nix flake update                           # nixpkgs + inputs → flake.lock
nix run .#update-pins [NAME...]            # pins.json → latest upstream (default: every non-null pin)
colmena build                              # then apply as above
```

| Pin | Source | After apply |
|-----|--------|-------------|
| `unsloth` | PyPI version + studio tag | Image rebuilds on next `ai train on` (~10 min, `journalctl -fu unsloth-image`). |
| `radiance` | Docker Hub `latest` digest | `radiance-image` pulls at deploy, non-blocking. |
| `maya` | git tag + commit | `ai maya-setup QUANT` before serving; serve refuses a commit with no checkout. |
| `pihole` | Docker Hub release tag | Container restarts on switch. |
| Base images | `FROM` in `containers/*/Containerfile*` | Hand-bumped. Any edit retags and rebuilds. |

Old images: `sudo podman image prune -f`. Never `podman system prune` (kills the uv cache mount).

## Automation

**flake-builder** (homelab) bumps `gegnep/nixos`'s lock nightly, builds both desktop toplevels, pushes only if both succeed, keeps the last good pair as gcroots. **Harmonia** serves closures to the desktops and VPSes (`fallback = true`). A **nightly Claude scan** triages build failures and files deprecation findings as `gegnep/nixos` issues, checked against the locked revs via mcp-nixos. `nixremote` takes offloaded builds from nixpad over ssh-ng.

## Backups

| Layer | What | Where |
|-------|------|-------|
| btrbk | `@home`, `@var-lib` every 4 h | raid1 mirror |
| restic | `/home`, `/var/lib` | B2 |
| unifi-backup | UCG `.unf` | `/var/lib` (then the layers above) |
| restic REST | blackbox, nixpad, ovh, sidecar | mirror (append-only) |

Client timers avoid the local prune and the B2 window. Studio GGUF exports (`/var/lib/models/gguf/`) go to B2; `/var/lib/models/cache/` goes nowhere.

## Secrets

sops-nix + age. `secrets/<host>.yaml` is encrypted to that host's key plus my user key (`.sops.yaml`). Service secrets live in the service's module; shared ones in `modules/nixos/sops.nix`.

---
*portions of this configuration were developed in collaboration with [Claude](https://claude.ai); AI suggestions should never replace your own understanding of your system*
