# K3s First Node VIP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the fake `10.0.0.1` k3s server address with a keepalived VIP + `isFirstNode` flag.

**Architecture:** All k3s nodes run keepalived with a shared VIP. The designated first node uses `--cluster-init` (no `--server`); others join via the VIP. If the first node dies, the VIP floats. Revived nodes rejoin from their local etcd data.

**Tech Stack:** NixOS, k3s (nixpkgs module), keepalived (nixpkgs module), sops-nix

---

### Task 1: Add `vip` and `isFirstNode` options to k3s service module

**Files:**
- Modify: `services/k3s.nix`

- [ ] **Step 1.1: Add `vip` option**

```nix
# After flannelIface option (around line 14)
vip = lib.mkOption {
  type = lib.types.str;
  default = "192.168.1.200";
  description = "Virtual IP for k3s API server, managed by keepalived";
};
```

- [ ] **Step 1.2: Add `isFirstNode` option**

```nix
# After vip option
isFirstNode = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Whether this node bootstraps the k3s cluster with --cluster-init";
};
```

- [ ] **Step 1.3: Update k3s config block to use `isFirstNode`**

Replace the current `services.k3s` config block (lines 22-28):

```nix
services.k3s = {
  enable = true;
  role = "server";
  tokenFile = config.sops.secrets."k3s-token".path;
  serverAddr = if config.services.k3s-server.isFirstNode
               then ""   # no --server flag; first node bootstraps standalone
               else "https://${config.services.k3s-server.vip}:6443";
  clusterInit = config.services.k3s-server.isFirstNode;
  extraFlags = "--flannel-iface=${config.services.k3s-server.flannelIface}";
};
```

- [ ] **Step 1.4: Add keepalived to system packages**

```nix
# In environment.systemPackages, add keepalived:
environment.systemPackages = with pkgs; [ k3s nfs-utils keepalived ];
```

- [ ] **Step 1.5: Add sops secret declaration for VRRP password**

```nix
# After existing sops secrets:
sops.secrets."k3s-vrrp-password" = {};
```

- [ ] **Step 1.6: Add sops template for VRRP env file**

```nix
# After sops secrets:
sops.templates."k3s-vrrp-env" = {
  content = "VRRP_PASSWORD=$k3s-vrrp-password";
};
```

- [ ] **Step 1.7: Add keepalived config**

```nix
# After sops template, inside the config block:
services.keepalived = {
  enable = true;
  openFirewall = true;
  secretFile = config.sops.templates."k3s-vrrp-env".path;
  vrrpInstances.k3s = {
    interface = config.services.k3s-server.flannelIface;
    state = "BACKUP";
    virtualRouterId = 50;
    priority = if config.services.k3s-server.isFirstNode then 150 else 100;
    virtualIps = [{
      addr = "${config.services.k3s-server.vip}/24";
      dev = config.services.k3s-server.flannelIface;
    }];
    extraConfig = ''
      authentication {
          auth_type PASS
          auth_pass ''${VRRP_PASSWORD}
      }
    '';
  };
};
```

Note: `''${VRRP_PASSWORD}` produces literal `${VRRP_PASSWORD}` in the Nix store config, which envsubst replaces at runtime from the `secretFile` env file.

- [ ] **Step 1.8: Keep existing firewall rules (6443, 10250, 2379, 2380, 8472)**

The keepalived `openFirewall = true` adds the VRRP/AH rules automatically, so no changes needed to the existing firewall config.

---

### Task 2: Update `profiles/compute.nix` to use VIP

**Files:**
- Modify: `profiles/compute.nix`

- [ ] **Step 2.1: Remove hardcoded 10.0.0.1 and TODO comment**

Replace the current k3s-server config:

```nix
services.k3s-server = {
  enable = true;
  # serverAddr uses the VIP from the k3s module by default.
  # Override services.k3s-server.vip if your LAN subnet differs.
};
```

The VIP default `192.168.1.200` is set in the module, so `profiles/compute.nix` no longer needs to set `serverAddr` at all. Non-first-node hosts get `serverAddr = https://192.168.1.200:6443` from the module logic automatically.

---

### Task 3: Create first-node host configurations

**Files:**
- Create: `hosts/first-ai/default.nix`
- Create: `hosts/first-server/default.nix`

- [ ] **Step 3.1: Create `hosts/first-ai/default.nix`**

```nix
{ inputs, ... }:
{
  networking.hostName = "strix-halo";
  networking.hostId = "beefcake";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/ai.nix
  ];

  services.k3s-server.isFirstNode = true;
}
```

- [ ] **Step 3.2: Create `hosts/first-server/default.nix`**

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

  services.k3s-server.isFirstNode = true;
}
```

---

### Task 4: Add new hosts to flake

**Files:**
- Modify: `flake.nix`

- [ ] **Step 4.1: Add `ai`, `first-ai`, `first-server` to `nixosConfigurations`**

```nix
nixosConfigurations = {
  compute = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/compute ];
    specialArgs = { inherit inputs; };
  };
  server = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/server ];
    specialArgs = { inherit inputs; };
  };
  storage = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/storage ];
    specialArgs = { inherit inputs; };
  };
  ai = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/ai ];
    specialArgs = { inherit inputs; };
  };
  first-ai = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/first-ai ];
    specialArgs = { inherit inputs; };
  };
  first-server = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/first-server ];
    specialArgs = { inherit inputs; };
  };
};
```

---

### Task 5: Add sops keys and secrets for new hosts

**Files:**
- Modify: `secrets/.sops.yaml`
- Create: `secrets/strix-halo.yaml`

- [ ] **Step 5.1: Add strix-halo key to `.sops.yaml`**

```yaml
keys:
  - &thinkpad age1abc...  # unchanged
  - &itx age1def...       # unchanged
  - &strix-halo age1xyz...  # replace with actual strix-halo key
  - &n95 age1uvw...         # replace with actual n95 key

creation_rules:
  - path_regex: secrets/thinkpad.yaml$
    key_groups:
      - age:
        - *thinkpad
        - *strix-halo
        - *itx
        - *n95
  - path_regex: secrets/itx-5825u.yaml$
    key_groups:
      - age:
        - *itx
        - *thinkpad
        - *strix-halo
        - *n95
  - path_regex: secrets/strix-halo.yaml$
    key_groups:
      - age:
        - *strix-halo
        - *thinkpad
        - *itx
        - *n95
  - path_regex: secrets/n95.yaml$
    key_groups:
      - age:
        - *n95
        - *thinkpad
        - *strix-halo
        - *itx
```

- [ ] **Step 5.2: Initialize `secrets/strix-halo.yaml` and `secrets/n95.yaml`**

Both start as empty files (same pattern as the existing secrets/thinkpad.yaml and secrets/itx-5825u.yaml).

- [ ] **Step 5.3: Add `k3s-vrrp-password` to all host secrets**

Run `sops` on each host's yaml to add:
```yaml
k3s-vrrp-password: <generated-random-password>
```

Then update `profiles/base.nix` (or each host config) to add the `k3s-vrrp-password` to sops secrets for all hosts. This should be done in `services/k3s.nix` which already declares sops secrets (step 1.5).

---

### Verification

- [ ] **Verify k3s module logic**

Confirm with `nix-instantiate --eval` or `nix eval` that:
- `isFirstNode = true` → `services.k3s.clusterInit = true`, `services.k3s.serverAddr = ""`
- `isFirstNode = false` → `services.k3s.clusterInit = false`, `services.k3s.serverAddr = "https://192.168.1.200:6443"`

- [ ] **Verify flake builds**

```bash
nix build .#nixosConfigurations.first-ai.config.system.build.toplevel
nix build .#nixosConfigurations.first-server.config.system.build.toplevel
nix build .#nixosConfigurations.ai.config.system.build.toplevel
```

- [ ] **Check keepalived config output**

```bash
nix build .#nixosConfigurations.first-ai.config.services.keepalived  # verify VRRP config
```
