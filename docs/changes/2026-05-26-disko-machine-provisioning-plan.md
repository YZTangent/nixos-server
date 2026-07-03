# Disko Machine Provisioning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add disko-based declarative disk partitioning to replace static `hardware.nix` stubs, enabling nixos-anywhere remote provisioning and eliminating manual `nixos-generate-config`.

**Architecture:** Two shared disko modules under `disko/` — `os-ext4.nix` (single disk GPT + ext4 + swap, used by all machines) and `zfs-raid.nix` (N-disk ZFS RAIDZ pool, parameterized, used by ITX-5825U and N95). Each machine has a `disko.nix` that composes the relevant modules. The disko NixOS module is imported once in `profiles/base.nix` (alongside sops-nix). `flake.nix` adds `disko` and `nixos-anywhere` inputs but keeps `modules` lists clean.

**Tech Stack:** NixOS 25.05, disko, nixos-anywhere, ZFS

---

### Task 1: Create shared disko modules

**Files:**
- Create: `disko/os-ext4.nix`
- Create: `disko/zfs-raid.nix`

- [ ] **Step 1: Create `disko/` directory**

```bash
mkdir -p disko
```

- [ ] **Step 2: Write `disko/os-ext4.nix`**

Shared single-disk GPT layout with ext4 root, ESP, and swap. Also sets bootloader (common to all machines).

```nix
{ ... }: {
  disko.devices.disk.main = {
    type = "disk";
    device = "$DISK_MAIN";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "512M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
          };
        };
      };
    };
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

- [ ] **Step 3: Write `disko/zfs-raid.nix`**

Parameterized N-disk ZFS RAIDZ pool. Takes `diskCount`, `mode`, and `poolName`. Generates N disk entries and a zpool with standard datasets.

```nix
{ diskCount ? 4, mode ? "raidz1", poolName ? "tank" }:
{
  disko.devices = {
    disk = builtins.listToAttrs (builtins.genList (i: {
      name = "data${toString (i + 1)}";
      value = {
        type = "disk";
        device = "$DISK_DATA${toString (i + 1)}";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = { type = "zfs"; };
            };
          };
        };
      };
    }) diskCount);
    zpool = {
      "${poolName}" = {
        type = "zpool";
        mode = mode;
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        disks = builtins.genList (i: "data${toString (i + 1)}") diskCount;
        datasets = {
          data = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/data";
            options."com.sun:auto-snapshot" = "true";
          };
          media = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/media";
            options."com.sun:auto-snapshot" = "true";
          };
          backups = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/backups";
          };
          containers = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/containers";
          };
        };
      };
    };
  };
}
```

- [ ] **Step 4: Verify the files parse correctly**

```bash
nix-instantiate --eval --expr "(import ./disko/os-ext4.nix {}).disko.devices.disk.main.type"
nix-instantiate --eval --expr "(builtins.length (builtins.attrNames (import ./disko/zfs-raid.nix {}).disko.devices.disk)) == 4"
```

Expected: first prints `"disk"`, second prints `true`.

- [ ] **Step 5: Commit**

```bash
git add disko/
git commit -m "feat(disko): add shared os-ext4 and zfs-raid disko modules"
```

---

### Task 2: Create per-machine disko.nix files

**Files:**
- Create: `hosts/thinkpad/disko.nix`
- Create: `hosts/itx-5825u/disko.nix`

- [ ] **Step 1: Write `hosts/thinkpad/disko.nix`**

ThinkPad only needs the OS disk (ext4). No ZFS data pool.

```nix
{ ... }: {
  imports = [ ../../disko/os-ext4.nix ];
}
```

- [ ] **Step 2: Write `hosts/itx-5825u/disko.nix`**

ITX-5825U needs OS disk (ext4 on SSD) + ZFS pool (4 HDDs in RAIDZ1).

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

- [ ] **Step 3: Verify parse**

```bash
nix-instantiate --eval --expr "(import ./hosts/thinkpad/disko.nix {}).imports == [ ./disko/os-ext4.nix ]"
```

Expected: prints `true`.

- [ ] **Step 4: Commit**

```bash
git add hosts/thinkpad/disko.nix hosts/itx-5825u/disko.nix
git commit -m "feat(disko): add per-machine disko.nix for thinkpad and itx-5825u"
```

---

### Task 3: Update flake.nix — add disko and nixos-anywhere inputs

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add disko and nixos-anywhere inputs**

```nix
{
  description = "NixOS headless server cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, nixos-anywhere, ... } @ inputs: {
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
    packages.x86_64-linux = {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
    };
  };
}
```

- [ ] **Step 2: Verify flake evaluation**

```bash
nix flake show --all-systems 2>&1 | head -30
```

Expected: shows `nixosConfigurations.thinkpad`, `nixosConfigurations.itx-5825u`, `nixosConfigurations.n95`, and `packages.x86_64-linux.nixos-anywhere`.

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(flake): add disko, nixos-anywhere inputs and n95 config"
```

---

### Task 4: Update profiles/base.nix to import disko module

**Files:**
- Modify: `profiles/base.nix`

- [ ] **Step 1: Add disko module import alongside sops-nix**

```nix
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";
  console.font = "Lat2-Terminus16";
  console.keyMap = "us";

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Admin user
  users.users.yztangent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: add your public key
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # sops-nix
  sops = {
    defaultSopsFile = ../secrets/${config.networking.hostName}.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Trusted caches
  nix.settings.trusted-users = [ "yztangent" ];
  nix.settings.substituters = [ "https://cache.nixos.org" ];

  # Allow unfree where needed
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "jellyfin-ffmpeg"
  ];

  system.stateVersion = "25.05";
}
```

- [ ] **Step 2: Update flake.lock to fetch new inputs**

```bash
nix flake lock
```

Expected: exits 0, adds `disko` and `nixos-anywhere` entries to `flake.lock`.

- [ ] **Step 3: Verify the full config evaluates**

```bash
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel 2>&1 | head -5
```

Expected: starts printing a derivation path (long calculation, may take a moment).

- [ ] **Step 4: Commit**

```bash
git add profiles/base.nix flake.lock
git commit -m "feat(base): import disko nixos module"
```

---

### Task 5: Update machine default.nix files and delete hardware.nix

**Files:**
- Modify: `hosts/thinkpad/default.nix`
- Modify: `hosts/itx-5825u/default.nix`
- Delete: `hosts/thinkpad/hardware.nix`
- Delete: `hosts/itx-5825u/hardware.nix`

- [ ] **Step 1: Update `hosts/thinkpad/default.nix`**

Replace `./hardware.nix` import with `./disko.nix`:

```nix
{ inputs, ... }:
{
  networking.hostName = "thinkpad";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
  ];
}
```

- [ ] **Step 2: Update `hosts/itx-5825u/default.nix`**

Replace `./hardware.nix` import with `./disko.nix`:

```nix
{ inputs, ... }:
{
  networking.hostName = "itx-5825u";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];
}
```

- [ ] **Step 3: Delete old hardware.nix files**

```bash
git rm hosts/thinkpad/hardware.nix hosts/itx-5825u/hardware.nix
```

- [ ] **Step 4: Verify config still evaluates**

```bash
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel 2>&1 | head -5
nix eval .#nixosConfigurations.itx-5825u.config.system.build.toplevel 2>&1 | head -5
```

Expected: both print derivation paths without errors.

- [ ] **Step 5: Commit**

```bash
git add hosts/thinkpad/default.nix hosts/itx-5825u/default.nix
git commit -m "refactor: replace hardware.nix with disko.nix for thinkpad and itx-5825u"
```

---

### Task 6: Create N95 machine stub

**Files:**
- Create: `hosts/n95/default.nix`
- Create: `hosts/n95/disko.nix`

- [ ] **Step 1: Write `hosts/n95/disko.nix`**

Same layout as ITX-5825U (SSD OS + ZFS pool). Disk count is a guess — adjust when hardware arrives.

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

- [ ] **Step 2: Write `hosts/n95/default.nix`**

Minimal stub with hostname and base profile only. No compute/NAS profiles until hardware is ready.

```nix
{ ... }:
{
  networking.hostName = "n95";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
  ];
}
```

- [ ] **Step 3: Verify all configs evaluate**

```bash
nix eval .#nixosConfigurations.n95.config.system.build.toplevel 2>&1 | head -5
```

Expected: prints a derivation path.

- [ ] **Step 4: Commit**

```bash
git add hosts/n95/
git commit -m "feat(hosts): add n95 machine stub with disko config"
```

---

### Post-Implementation Verification

- [ ] **Verify all three configs evaluate without errors**

```bash
nix eval .#nixosConfigurations.thinkpad.config.system.build.toplevel 2>&1
nix eval .#nixosConfigurations.itx-5825u.config.system.build.toplevel 2>&1
nix eval .#nixosConfigurations.n95.config.system.build.toplevel 2>&1
```

Expected: each prints a `/nix/store/...` derivation path.

- [ ] **Confirm nixos-anywhere is usable**

```bash
nix run .#nixos-anywhere -- --help | head -5
```

Expected: prints nixos-anywhere help text.

- [ ] **Show final directory tree**

```bash
find . -not -path './.git/*' -not -name '*.lock' | sort
```

Expected: disko/ directory present, no hardware.nix files, n95/ directory present.
