# Cloudflare Tunnels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the existing Cloudflare Tunnels configuration into a reusable NixOS module according to the finalized requirements.

**Architecture:** Create `services/cloudflare-tunnels.nix`. Refactor existing `profiles` to consume the new module. Expose the module via `flake.nix`.

**Tech Stack:** NixOS, cloudflared.

---

### Task 1: Create the Cloudflare Tunnels Module

**Files:**
- Create: `services/cloudflare-tunnels.nix`

- [ ] **Step 1: Write the NixOS module**

```nix
{ config, lib, ... }:
let
  cfg = config.services.nixos-server.cloudflare-tunnels;
in {
  options.services.nixos-server.cloudflare-tunnels = {
    enable = lib.mkEnableOption "Cloudflare Tunnels service";
    
    hostTunnel = {
      enable = lib.mkEnableOption "Host tunnel for WARP routing";
      name = lib.mkOption {
        type = lib.types.str;
        default = "host-''${config.networking.hostName}";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the cloudflared credentials JSON file";
      };
    };

    computeTunnel = {
      enable = lib.mkEnableOption "Compute tunnel for ingress";
      name = lib.mkOption {
        type = lib.types.str;
        default = "compute-cluster";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the cloudflared credentials JSON file";
      };
      ingress = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { "*" = "http://localhost:80"; };
        description = "Ingress routing rules mapping hostnames to local endpoints";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.cloudflared = {
      enable = true;
      tunnels = lib.mkMerge [
        (lib.mkIf cfg.hostTunnel.enable {
          "''${cfg.hostTunnel.name}" = {
            credentialsFile = cfg.hostTunnel.credentialsFile;
            default = "http_status:404";
            warp-routing.enabled = true;
          };
        })
        (lib.mkIf cfg.computeTunnel.enable {
          "''${cfg.computeTunnel.name}" = {
            credentialsFile = cfg.computeTunnel.credentialsFile;
            default = "http_status:404";
            ingress = cfg.computeTunnel.ingress;
          };
        })
      ];
    };
  };
}
```

- [ ] **Step 2: Commit**

```bash
git add services/cloudflare-tunnels.nix
git commit -m "feat(services): add cloudflare tunnels module"
```

### Task 2: Refactor Existing Profiles

**Files:**
- Modify: `profiles/base.nix`
- Modify: `profiles/compute.nix`

- [ ] **Step 1: Update base.nix**

In `profiles/base.nix`, locate the existing `services.cloudflared` block and replace it with the new module invocation.
The existing code configures the unique host tunnel.

```nix
  # Cloudflare Host Tunnel (Unique per machine)
  sops.secrets."cloudflared/host-tunnel.json" = {};
  
  services.nixos-server.cloudflare-tunnels = {
    enable = true;
    hostTunnel = {
      enable = true;
      name = "host-''${device-id.hostname}";
      credentialsFile = config.sops.secrets."cloudflared/host-tunnel.json".path;
    };
  };
  environment.systemPackages = [ pkgs.cloudflared ];
```

- [ ] **Step 2: Update compute.nix**

In `profiles/compute.nix`, locate the existing `services.cloudflared.tunnels...` block and replace it with the new module config.

```nix
  # Cloudflare Compute Tunnel (Replica mode for k3s ingress)
  sops.secrets."cloudflared/compute-tunnel.json" = {};

  services.nixos-server.cloudflare-tunnels.computeTunnel = {
    enable = true;
    credentialsFile = config.sops.secrets."cloudflared/compute-tunnel.json".path;
  };
```

- [ ] **Step 3: Commit**

```bash
git add profiles/base.nix profiles/compute.nix
git commit -m "refactor(profiles): migrate to cloudflare-tunnels module"
```

### Task 3: Expose Modules in Flake & Verify

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Export module in flake.nix**

In `flake.nix`, under `outputs.nixosModules`, add:

```nix
      cloudflare-tunnels = ./services/cloudflare-tunnels.nix;
```
And add it to the `default` module imports list:
```nix
        imports = [
          # ... existing modules
          self.nixosModules.cloudflare-tunnels
        ];
```

- [ ] **Step 2: Run flake check**

Verify the flake evaluation passes (this simulates an external consumer importing `default` and building `system.build.toplevel`).

Run: `nix build .#checks.x86_64-linux.nixos-modules-eval`
Expected: Passes without errors.

- [ ] **Step 3: Commit**

```bash
git add flake.nix
git commit -m "feat(flake): expose cloudflare-tunnels module"
```
