# NixOS Server Cluster

Single-flake NixOS configuration for a multi-node homelab cluster.

## Machines

| Role | Hosts | OS Disk | Data Storage |
|------|-------|---------|-------------|
| compute (k3s) | thinkpad | ext4 + swap (single disk) | — |
| compute + NAS | itx-5825u | ext4 (NVMe SSD) | 4x HDD ZFS RAIDZ1 |
| compute + NAS | n95 | ext4 (SSD) | HDDs in ZFS pool |
| server | strix-halo | ext4 | — |
| ai (k3s) | — | (planned) | — |
| storage | — | (planned) | — |

Each physical machine derives its identity (hostname, hostId) from its DMI product UUID at provisioning time. See `docs/changes/2026-06-25-hardware-derived-identity-requirement.md`.

## Usage

### Provision a new machine

Boot the target into any Linux with SSH. The `provision` wrapper reads the target's DMI UUID, hashes it to an 8-char device-id, writes a temporary Nix file, and calls `nixos-anywhere` with `--override-input`:

```bash
nix run .#provision -- compute <ip>
nix run .#provision -- server <ip>
nix run .#provision -- compute <ip> --disk-main /dev/nvme0n1 --disk-data /dev/sda /dev/sdb
nix run .#provision -- server <ip> --first   # bootstrap k3s first node
```

Options:

| Flag | Default | Description |
|------|---------|-------------|
| `--first` | off | Bootstrap as k3s first node (applies `first-<role>` flake attr) |
| `--disk-main` | per-role default | Main OS disk device |
| `--disk-data` | per-role default | Data disk devices (space-separated) |

### Update a machine

```bash
nixos-rebuild switch --flake .#<role> --override-input device-id path:/tmp/device-<hash> --target-host yztangent@<ip>
```

Or use the legacy `serverctl` wrapper:

```bash
bin/serverctl switch <role> <ip>
```

### Build check (dry run)

```bash
nixos-rebuild build --flake .#<role>
```

Without `--override-input` the placeholder device-id triggers a build-time assertion (see `profiles/base.nix`). We provide a dummy test device-id so you can evaluate the entire flake cleanly:

```bash
nix flake check --override-input device-id path:./device-id/test
```

### Consuming from another flake

The service modules in this repository are exposed as `nixosModules` flake outputs so they can be consumed by other flakes (e.g., a desktop configuration).

```nix
# desktop flake.nix
inputs.nixos-server.url = "github:YZTangent/nixos-server"; # or a path/git URL

# in the nixosSystem modules list
inputs.nixos-server.nixosModules.ai
inputs.nixos-server.nixosModules.k3s
```

Then configure as on any host in this repo, e.g. `services.llama-server.enable = true;` with a desktop-appropriate instance, and `services.k3s-server.*` options to join the existing cluster.

**Consumer prerequisites:**

- **k3s**: the module references `sops.secrets."k3s-token"` and `sops.secrets."k3s-vrrp-password"`. The consumer must import `sops-nix.nixosModules.sops` and define both keys in its own sops file. 
  - **Interface Binding**: You must explicitly configure `services.k3s-server.flannelIface` (e.g. `enp3s0` or `wlan0` instead of the default `eth0`). This is strictly required so that `keepalived` and k3s don't accidentally bind to virtual interfaces (like Docker bridges) and instead route cluster traffic correctly over your LAN.
  - **Virtual IP (VIP)**: The cluster API address `services.k3s-server.vip` defaults to `192.168.1.200`. You only need to set this if your cluster operates on a different VIP.
  - **Cluster Role**: Set `isFirstNode = false` (the default) to join an existing cluster. Alternatively, you can set `isFirstNode = true` if you are using this machine to bootstrap a brand new cluster (or for disaster recovery if the main servers are down).
- **llama-server / ai**: no external requirements. `unfree` allowances are not needed (llama-cpp and hermes-agent are free).
- **media-stack** (if ever enabled externally): requires allowing unfree `jellyfin-ffmpeg` (this repo does it via `allowUnfreePredicate` in `profiles/base.nix`; the consumer must do the same).

## Directory Layout

```
├── bin/serverctl/       # Go CLI tool (legacy — source + binary)
├── device-id/           # Placeholder device-id input (non-flake, flake = false)
├── disko/              # Shared disk partitioning modules
│   ├── os-ext4.nix     #   Single-disk GPT + ext4 root + swap
│   └── zfs-raid.nix    #   N-disk ZFS RAIDZ pool
├── docs/               # ADRs and change documentation
├── hosts/              # Per-role configs (one-liners calling mk-host.nix)
│   ├── compute/
│   ├── first-compute/
│   ├── server/
│   ├── first-server/
│   ├── ai/
│   ├── first-ai/
│   ├── storage/
│   └── mk-host.nix     #   Plain Nix helper consuming device-id
├── modules/            # Reusable NixOS modules
│   └── device-identity.nix  #   Declares device-identity.role option
├── profiles/           # Composable machine roles
│   ├── base.nix        #   SSH, users, locale, sops-nix, disko, device assertion
│   ├── compute.nix     #   k3s + monitoring agent
│   └── nas.nix         #   File sharing, media stack, backup
├── scripts/provision/  # Python provisioning app (nix run .#provision)
│   ├── provision.py    #   Main CLI: DMI hash → nixos-anywhere
│   └── sops_yaml.py    #   .sops.yaml helpers (idempotent key insertion)
├── secrets/            # SOPS-encrypted per-instance secrets
│   └── .sops.yaml      #   creation_rules match by role regex
├── services/           # Reusable NixOS service modules
├── tests/              # pytest tests for scripts/provision/
└── flake.nix
```

## Prerequisites

- [Nix](https://nixos.org) with flakes enabled
- For provisioning (`nix run .#provision`): SSH access to target, plus `age`, `sops`, `git`, `openssh` on `$PATH` (wrapped by the build)
- For `serverctl switch`: `nixos-rebuild` on `$PATH`
- For secrets: age key at `/var/lib/sops-nix/key.txt` on each machine

## Adding a New Machine

```bash
# 1. Create host dir:
mkdir -p hosts/<role>

# 2. Create hosts/<role>/default.nix (one-liner calling mk-host.nix):
#    { ... }: (import ../mk-host.nix) { role = "<role>"; isFirstNode = false; }

# 3. (Optional) Create disko/<role>.nix, add disk defaults to
#    scripts/provision/provision.py DISK_DEFAULTS.

# 4. Provision:
nix run .#provision -- <role> <ip> --disk-main /dev/<disk>
```

Hosts are auto-discovered via `builtins.readDir` in `flake.nix` — no flake attr registration needed.

## Secrets

SOPS-encrypted YAML files in `secrets/`, named `secrets/<role>-<hash>.yaml` (e.g. `secrets/compute-a1b2c3d4.yaml`). Decrypted at boot by sops-nix. `.sops.yaml` `creation_rules` match by role regex — adding a new host of an existing role only requires appending its age key to the role's `key_group`.

See `docs/adr/0001-sops-nix-for-secrets.md`.
