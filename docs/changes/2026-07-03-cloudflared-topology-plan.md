# Cloudflare Tunnel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the dual-tunnel Cloudflare configuration (Host Tunnel + Compute Tunnel) in the NixOS profiles.

**Architecture:** We will modify `profiles/base.nix` to define a unique host tunnel for every machine using `sops-nix` for credentials. We will modify `profiles/compute.nix` to define a shared compute tunnel for all k3s nodes.

**Tech Stack:** NixOS, cloudflared, sops-nix

---

### Task 1: Add Host Tunnel to `profiles/base.nix`

**Files:**
- Modify: `profiles/base.nix`

- [ ] **Step 1: Write minimal implementation**

We will add the `services.cloudflared` configuration to `base.nix`. Since `device-id.hostname` is available, we will use it for the tunnel name and the credentials file path.

```nix
  # Cloudflare Host Tunnel (Unique per machine)
  sops.secrets."cloudflared/host-tunnel.json" = {};
  
  services.cloudflared = {
    enable = true;
    tunnels = {
      "host-${device-id.hostname}" = {
        credentialsFile = config.sops.secrets."cloudflared/host-tunnel.json".path;
        default = "http_status:404";
        warp-routing.enabled = true;
      };
    };
  };
  environment.systemPackages = [ pkgs.cloudflared ];
```

Modify `profiles/base.nix` by adding the above block before the `system.stateVersion = "26.05";` line.

- [ ] **Step 2: Run test to verify it passes**

Run: `nix-instantiate --parse profiles/base.nix`
Expected: Output of the parsed syntax without errors.

- [ ] **Step 3: Commit**

```bash
git add profiles/base.nix
git commit -m "feat(profiles/base): add unique host-level cloudflared tunnel"
```

---

### Task 2: Add Compute Tunnel to `profiles/compute.nix`

**Files:**
- Modify: `profiles/compute.nix`

- [ ] **Step 1: Write minimal implementation**

We will add the compute tunnel to `compute.nix`. This tunnel will route to the k3s Traefik ingress (port 80).

```nix
  # Cloudflare Compute Tunnel (Replica mode for k3s ingress)
  sops.secrets."cloudflared/compute-tunnel.json" = {};

  services.cloudflared.tunnels."compute-cluster" = {
    credentialsFile = config.sops.secrets."cloudflared/compute-tunnel.json".path;
    default = "http_status:404";
    ingress = {
      "*" = "http://localhost:80";
    };
  };
```

Modify `profiles/compute.nix` by adding the above block before the closing brace `}`.

- [ ] **Step 2: Run test to verify it passes**

Run: `nix-instantiate --parse profiles/compute.nix`
Expected: Output of the parsed syntax without errors.

- [ ] **Step 3: Commit**

```bash
git add profiles/compute.nix
git commit -m "feat(profiles/compute): add shared compute-cluster cloudflared tunnel"
```
