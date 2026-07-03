# Disko-Driven Machine Provisioning

**Date:** 2026-05-26
**Status:** Draft

## Problem

Initial machine setup is painful. `hardware.nix` files are placeholders — they define a single ext4 root that doesn't match any real machine's actual disks. Each new machine requires manual `nixos-generate-config` output, hand-editing, and no automated provisioning exists. There is no way to install NixOS on a machine remotely (SSH-only, no physical access to ISO).

## Goals

1. **nixos-anywhere support** — provision any machine remotely over SSH, no physical ISO boot required
2. **Declarative disk config** — disk layouts live in the repo as the single source of truth
3. **Replace `hardware.nix`** — disko NixOS module handles `fileSystems` so `nixos-rebuild switch --target-host` works without a generated hardware config
4. **Shared, composable disk modules** — OS-on-ext4 pattern shared across machines; ZFS pool pattern shared across machines with data storage
5. **Minimal mental overhead** — 3 machines, keep it simple

## Non-Goals

- Converting existing installed machines' disks (machines will be provisioned fresh)
- Complex multi-pool ZFS topologies (single pool per machine)
- Home-manager or user-data integration
- Automated ISO generation

## Architecture

### Directory Layout

```
disko/
├── os-ext4.nix           # Shared: single-disk GPT + ext4 root + swap
└── zfs-raid.nix          # Shared: N-disk ZFS pool in RAIDZ mode
hosts/
├── thinkpad/
│   └── disko.nix          # Imports os-ext4.nix with disk variable
├── itx-5825u/
│   └── disko.nix          # Imports os-ext4.nix + zfs-raid.nix
└── n95/
    └── disko.nix          # Imports os-ext4.nix + zfs-raid.nix
```

### Module: `disko/os-ext4.nix`

Purpose: Declare a single disk with GPT layout, ext4 root, and swap partition.

```
Device variable: $DISK_MAIN

Partition layout (GPT):
  1. ESP — 512MiB, vfat, mount /boot
  2. root — 100% remaining, ext4, mount /
  3. swap — 8GiB, swap
```

Nix interface: A plain NixOS module setting `disko.devices.disk.main`. The `device` attribute uses the string literal `"$DISK_MAIN"` which nixos-anywhere substitutes at provisioning time via `--disk-main <path>`.

### Module: `disko/zfs-raid.nix`

Purpose: Declare N disks in a ZFS RAIDZ pool with standard datasets.

```
Parameters:
  - diskCount: number of data disks (default 4)
  - mode: ZFS vdev mode (default "raidz1")
  - poolName: ZFS pool name (default "tank")

Device variables: $DISK_DATA1, $DISK_DATA2, ... $DISK_DATAN

Layout (each data disk):
  - Single GPT partition, 100%, type zfs

Zpool <poolName>:
  - Mode <mode> across all N disks
  - Datasets:
    - data (general storage, mount /var/lib/tank/data)
    - media (media library, mount /var/lib/tank/media)
    - backups (backup target, mount /var/lib/tank/backups)
    - containers (container storage, mount /var/lib/tank/containers)
```

Implementation note: This is a Nix function (`diskCount -> mode -> poolName -> NixOS module`) rather than a plain module, because the number of disks varies per machine.

### Per-Machine Composition

Each machine has a `disko.nix` that assembles the shared disk layouts:

**`hosts/thinkpad/disko.nix`**:
```nix
{ ... }: {
  imports = [ ../../disko/os-ext4.nix ];
}
```

**`hosts/itx-5825u/disko.nix`**:
```nix
{ ... }: {
  imports = [
    ../../disko/os-ext4.nix
    (import ../../disko/zfs-raid.nix {
      diskCount = 4;
      mode = "raidz1";
      poolName = "tank";
    })
  ];
}
```

**`hosts/n95/disko.nix`**:
```nix
{ ... }: {
  imports = [
    ../../disko/os-ext4.nix
    (import ../../disko/zfs-raid.nix {
      diskCount = 4;
      mode = "raidz1";
      poolName = "tank";
    })
  ];
}
```

Each machine's `default.nix` changes from `imports = [ ./hardware.nix ]` to `imports = [ ./disko.nix ]`. The `hardware.nix` file is deleted.

### Module Registration in base.nix

The disko NixOS module is imported once in `profiles/base.nix`, right alongside sops-nix — every machine imports base, so no duplication:

```nix
{ config, pkgs, lib, inputs, ... }: {
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ];
  # ... rest of base.nix
}
```

### Flake Integration

Add two new inputs:

```nix
inputs = {
  # ... existing nixpkgs, sops-nix ...
  disko = {
    url = "github:nix-community/disko";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  nixos-anywhere = {
    url = "github:nix-community/nixos-anywhere";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

The `nixosConfiguration` entries stay clean — the disko module is imported in `profiles/base.nix` alongside sops-nix. N95 is included here as a stub (`default.nix` + `disko.nix`, no profile activation until ready):

```nix
nixosConfigurations = {
  thinkpad = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/thinkpad ];
    specialArgs = { inherit inputs; };
  };
  itx-5825u = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/itx-5825u ];
    specialArgs = { inherit inputs; };
  };
  n95 = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/n95 ];
    specialArgs = { inherit inputs; };
  };
};
```

Add `nixos-anywhere` to the `packages.x86_64-linux` output so it's available as `nix run .#nixos-anywhere`.

### Migration: Removing hardware.nix

Current files to delete:
- `hosts/thinkpad/hardware.nix`
- `hosts/itx-5825u/hardware.nix`

Each `default.nix` changes `./hardware.nix` → `./disko.nix`.

The disko NixOS module sets `boot.loader` and `fileSystems` options, so the old hardware.nix values are redundant. The bootloader config moves into `os-ext4.nix` (systemd-boot, common to all machines).

## Workflows

### Initial Provisioning (nixos-anywhere)

Target machine must be booted into any Linux with SSH access (NixOS minimal ISO, Ubuntu live, etc.).

```bash
# ThinkPad
nix run .#nixos-anywhere -- \
  --flake .#thinkpad \
  --disk-main /dev/nvme0n1 \
  root@<thinkpad-ip>

# ITX-5825U
nix run .#nixos-anywhere -- \
  --flake .#itx-5825u \
  --disk-main /dev/nvme0n1 \
  --disk-data1 /dev/sda \
  --disk-data2 /dev/sdb \
  --disk-data3 /dev/sdc \
  --disk-data4 /dev/sdd \
  root@<itx-ip>
```

nixos-anywhere will:
1. Copy the flake to the target
2. Run `disko` to partition/format all disks
3. Install NixOS to the target disks
4. Reboot into the installed system

### Ongoing Updates (nixos-rebuild)

No change to existing workflow:

```bash
nixos-rebuild switch --flake .#<host> --target-host <user>@<host>
```

The disko NixOS module is imported as part of the system config, so `fileSystems` and `boot.loader` are correctly configured without any generated `hardware-configuration.nix`.

### Adding a New Machine

1. Create `hosts/<name>/default.nix` with profile imports
2. Create `hosts/<name>/disko.nix` composing the needed disko modules
3. Add `nixosConfiguration` entry in `flake.nix`
4. Run nixos-anywhere with appropriate `--disk-*` flags

If the new machine needs a different disk layout, create a new disko module in `disko/`.

## Device Path Notes

Disk device paths (`/dev/nvme0n1`, `/dev/sda`, etc.) vary per boot. Best practice for nixos-anywhere:
- Use stable paths from `/dev/disk/by-id/` or `/dev/disk/by-path/` when possible
- nixos-anywhere resolves the path before passing to disko
- After provisioning, disko sets `fileSystems` using `by-label` or `by-uuid` for stability

The `os-ext4.nix` module labels the root partition (`nixos`) and uses `by-label` in `fileSystems` options for reboots.

## Open Questions

- Should `zfs-raid.nix` use a fixed set of dataset names or accept them as a parameter? (Current design: fixed set)
- N95 disk count is unknown — parameterize at the call site when known

## Related Documents

- [PRD: NixOS Server Config](../prd/2026-05-25-nixos-server-config.md)
- [ADR: sops-nix for secrets](../adr/0001-sops-nix-for-secrets.md)
- [Plan: Initial implementation plan](../superpowers/plans/2026-05-25-nixos-server-config.md)
