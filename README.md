# NixOS Server Cluster

Single-flake NixOS configuration for a multi-node homelab cluster.

## Machines

| Host | Role | OS Disk | Data Storage |
|------|------|---------|-------------|
| thinkpad | compute (k3s) | ext4 + swap (single disk) | — |
| itx-5825u | compute + NAS | ext4 (NVMe SSD) | 4x HDD ZFS RAIDZ1 |
| n95 | planned NAS | ext4 (SSD) | HDDs in ZFS pool |

## Usage

### First-time provisioning

Boot the target into any Linux with SSH. Disk device paths default per host type — override with `--disk-main` / `--disk-data` if needed:

```bash
# ThinkPad (single disk)
bin/serverctl create thinkpad <ip>

# ITX-5825U (SSD + 4 HDDs)
bin/serverctl create itx-5825u <ip> --user yztangent
```

Defaults:

| Host | `--disk-main` | `--disk-data` |
|------|---------------|---------------|
| thinkpad | `/dev/nvme0n1` | — |
| itx-5825u | `/dev/nvme0n1` | `/dev/sda /dev/sdb /dev/sdc /dev/sdd` |
| n95 | `/dev/nvme0n1` | `/dev/sda /dev/sdb /dev/sdc /dev/sdd` |

### Updating a machine

```bash
bin/serverctl switch thinkpad <ip>
bin/serverctl switch itx-5825u <ip> --user yztangent
```

### Build check (dry run)

```bash
nixos-rebuild build --flake .#<host>
```

## Directory Layout

```
├── bin/serverctl/       # Go CLI tool (source + binary)
├── disko/              # Shared disk partitioning modules
│   ├── os-ext4.nix     #   Single-disk GPT + ext4 root + swap
│   └── zfs-raid.nix    #   N-disk ZFS RAIDZ pool
├── hosts/              # Per-machine configs
│   ├── thinkpad/
│   ├── itx-5825u/
│   └── n95/
├── profiles/           # Composable machine roles
│   ├── base.nix        #   SSH, users, locale, sops-nix, disko
│   ├── compute.nix     #   k3s + monitoring agent
│   └── nas.nix         #   File sharing, media stack, backup
├── services/           # Reusable NixOS service modules
├── secrets/            # SOPS-encrypted per-host secrets
└── flake.nix
```

## Prerequisites

- [Nix](https://nixos.org) with flakes enabled
- For `serverctl switch`: `nixos-rebuild` on `$PATH`
- For `serverctl create`: `ssh` access to target
- For secrets: age key at `/var/lib/sops-nix/key.txt` on each machine

## Adding a New Machine

```bash
mkdir -p hosts/<name>
# create hosts/<name>/disko.nix (compose shared disko modules)
# create hosts/<name>/default.nix (hostname + profile imports)
# add nixosConfiguration entry in flake.nix
bin/serverctl create <name> <ip> --disk-main /dev/<disk>
```

## Secrets

SOPS-encrypted YAML files in `secrets/`. Decrypted at boot by sops-nix. See `docs/adr/0001-sops-nix-for-secrets.md`.
