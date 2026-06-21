# Profile-Driven Disko Imports

**Date:** 2026-06-19
**Status:** Draft

## Problem

Disk layout is configured per-host via `hosts/<name>/disko.nix`, but the disk layout
is a property of the machine's **role**, not its hardware identity. Every host that
needs a ZFS pool (itx-5825u, n95) duplicates the same import. Adding a new host
requires a new `disko.nix` even when its role is identical to an existing host.

## Solution

Move disko imports from per-host `disko.nix` files into the profiles that
actually need the storage. Profiles own the disk layouts they depend on.

## Mapping

| Profile | Disko import | Rationale |
|---|---|---|
| `base.nix` | `os-ext4.nix` | Every machine needs an OS disk |
| `compute.nix` | none | Compute nodes don't need local persistent storage |
| `nas.nix` | `zfs-raid.nix` | NAS implies a storage pool |
| `first-node.nix` | none | Only overrides k3s serverAddr |

## Per-Host Composition

After the change, hosts are pure composition with no local disko config:

| Host | Imports | Effective disko |
|---|---|---|
| thinkpad | `base` + `compute` + `first-node` | `os-ext4` only |
| itx-5825u | `base` + `compute` + `nas` | `os-ext4` + `zfs-raid` |
| n95 | `base` + `nas` | `os-ext4` + `zfs-raid` |

## Changes

### Delete
- `hosts/thinkpad/disko.nix`
- `hosts/itx-5825u/disko.nix`
- `hosts/n95/disko.nix`

### Modify: `profiles/base.nix`
Add to `imports`:
```nix
../disko/os-ext4.nix
```
No other changes — bootloader config stays in `os-ext4.nix`.

### Modify: `profiles/nas.nix`
Add to `imports`:
```nix
(import ../disko/zfs-raid.nix {})
```
Uses default parameters: `diskCount = 4, mode = "raidz1", poolName = "tank"`.

### Modify: `hosts/n95/default.nix`
Change from importing only `base` to importing `base` + `nas`:
```nix
imports = [
  ./disko.nix          # → removed
  ../../profiles/base.nix
  ../../profiles/nas.nix    # added
];
```

### Modify: `hosts/itx-5825u/default.nix`
Remove `./disko.nix` from imports (already has `nas` which pulls in ZFS).

### Modify: `hosts/thinkpad/default.nix`
Remove `./disko.nix` from imports (only needs OS disk, pulled by `base`).

## Out of Scope

- `networking.hostId` handling (separate concern)
- n95's role definition (was a bare storage node, now explicitly a NAS node)
- Any new profile creation (`storage.nix` no longer needed — NAS covers it)

## References

- [PRD: Disko-Driven Machine Provisioning](../prd/2026-05-26-disko-machine-provisioning.md)
- [PRD: NixOS Server Config](../prd/2026-05-25-nixos-server-config.md)
