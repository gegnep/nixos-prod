# nixos-prod — homelab

Single headless host (`homelab`): Ryzen 5 3600, 31 GiB, Intel Arc A310.

- NVMe (1 TB): systemd-boot ESP + btrfs (`@ @nix @home @var-lib @snapshots`)
- 2× 2 TB SATA: btrfs **raid1** mirror → `/backup`, exported over NFS
- Lix, `nh os switch`, key-only SSH
- nvim (nvf) + zsh (p10k) imported from the `desktop` (`github:gegnep/nixos`) source tree

Installed via nixos-anywhere over SSH. See the install runbook.
