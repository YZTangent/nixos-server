# Profile-Driven Disko Imports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move disko imports from per-host `disko.nix` files into the profiles that own the storage.

**Architecture:** `base.nix` imports `os-ext4.nix` (every machine needs an OS disk). `nas.nix` imports `zfs-raid.nix` (NAS implies a storage pool). Three per-host `disko.nix` files are deleted. The host `default.nix` files lose their `./disko.nix` import line. `n95` additionally gains the `nas` profile import.

**Tech Stack:** NixOS, disko

---

### Task 1: Add os-ext4 import to base.nix

**Files:**
- Modify: `profiles/base.nix:4-7`

- [ ] **Step 1: Add `../disko/os-ext4.nix` to base.nix imports**

Edit `profiles/base.nix` to add the os-ext4 disko module to its imports list:

```nix
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ../disko/os-ext4.nix            # every machine needs an OS disk
  ];
```

- [ ] **Step 2: Commit**

```bash
git add profiles/base.nix
git commit -m "base: import os-ext4 disko module"
```

---

### Task 2: Add ZFS disko import to nas.nix

**Files:**
- Modify: `profiles/nas.nix:3-7`

- [ ] **Step 1: Add ZFS disko import to nas.nix**

Edit `profiles/nas.nix` to import the ZFS raid disko module with default parameters:

```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/file-sharing.nix
    ../services/media-stack.nix
    ../services/backup-target.nix
    (import ../disko/zfs-raid.nix {})   # 4-disk raidz1 pool named "tank"
  ];
```

- [ ] **Step 2: Commit**

```bash
git add profiles/nas.nix
git commit -m "nas: import zfs-raid disko module"
```

---

### Task 3: Clean up thinkpad host config

**Files:**
- Modify: `hosts/thinkpad/default.nix`
- Delete: `hosts/thinkpad/disko.nix`

- [ ] **Step 1: Remove `./disko.nix` from thinkpad imports**

Edit `hosts/thinkpad/default.nix`:

```nix
{ inputs, ... }:
{
  networking.hostName = "thinkpad";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/first-node.nix
  ];
}
```

- [ ] **Step 2: Delete `hosts/thinkpad/disko.nix`**

```bash
rm hosts/thinkpad/disko.nix
```

- [ ] **Step 3: Commit**

```bash
git add hosts/thinkpad/
git commit -m "thinkpad: remove host-level disko.nix (pulled by base profile)"
```

---

### Task 4: Clean up itx-5825u host config

**Files:**
- Modify: `hosts/itx-5825u/default.nix`
- Delete: `hosts/itx-5825u/disko.nix`

- [ ] **Step 1: Remove `./disko.nix` from itx-5825u imports**

Edit `hosts/itx-5825u/default.nix`:

```nix
{ inputs, ... }:
{
  networking.hostName = "itx-5825u";
  networking.hostId = "deadbeef";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];
}
```

- [ ] **Step 2: Delete `hosts/itx-5825u/disko.nix`**

```bash
rm hosts/itx-5825u/disko.nix
```

- [ ] **Step 3: Commit**

```bash
git add hosts/itx-5825u/
git commit -m "itx-5825u: remove host-level disko.nix (pulled by base + nas profiles)"
```

---

### Task 5: Clean up n95 host config and add nas profile

**Files:**
- Modify: `hosts/n95/default.nix`
- Delete: `hosts/n95/disko.nix`

- [ ] **Step 1: Remove `./disko.nix` and add `nas` profile**

Edit `hosts/n95/default.nix`:

```nix
{ ... }:
{
  networking.hostName = "n95";
  networking.hostId = "cafebabe";

  imports = [
    ../../profiles/base.nix
    ../../profiles/nas.nix
  ];
}
```

- [ ] **Step 2: Delete `hosts/n95/disko.nix`**

```bash
rm hosts/n95/disko.nix
```

- [ ] **Step 3: Commit**

```bash
git add hosts/n95/
git commit -m "n95: remove host-level disko.nix, add nas profile"
```

---

### Task 6: Verify with nix flake check

**Files:** None (build verification)

- [ ] **Step 1: Run nix flake check**

```bash
nix flake check --show-trace
```

Expected: success (no errors). If errors occur, debug and fix before proceeding.

- [ ] **Step 2: Commit any fixes**

```bash
git add -A
git commit -m "fixup: address flake check issues"
```
