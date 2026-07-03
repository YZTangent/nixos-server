# NixOS Headless Server Configuration

## Overview

A NixOS flake-based configuration for a multi-node headless server cluster with three machine roles:

- **Compute nodes**: Run workloads via k3s, no local persistence
- **NAS nodes**: Compute + storage services (file sharing, media, backup)
- **AI nodes**: Compute + self-hosted LLM inference via llama.cpp (router mode, Vulkan backend)

## Machine Inventory

| Host | Hardware | Profiles | k3s role |
|------|----------|----------|----------|
| `thinkpad` | ThinkPad laptop | `base` + `compute` | server (control plane + worker) |
| `itx-5825u` | ITX R7 5825U | `base` + `compute` + `nas` | server (control plane + worker) |
| (future) | N95 + 4 HDDs | `base` + `nas` | none (no compute profile) |

Only nodes with the `compute` profile join the k3s cluster. The `ai` profile is layered on top of `compute` (an AI node is also a compute node) and adds the llama.cpp inference service.

Profiles are **non-intersecting sets** — each composition is explicit in the host config.

## Directory Structure

```
├── flake.nix
├── hosts/
│   ├── thinkpad/
│   │   ├── default.nix         # imports profiles + hardware config
│   │   └── hardware.nix
│   └── itx-5825u/
│       ├── default.nix
│       └── hardware.nix
├── profiles/
│   ├── base.nix                # SSH, users, locale, kernel, sops-nix
│   ├── compute.nix             # k3s server, monitoring agent
│   ├── nas.nix                 # file sharing, media, backup
│   └── ai.nix                  # llama.cpp inference (router mode, Vulkan)
├── services/
│   ├── k3s.nix                 # k3s server install + cluster join
│   ├── monitoring-agent.nix    # node exporter, promtail
│   ├── file-sharing.nix        # samba/nfs
│   ├── media-stack.nix         # jellyfin + *arr
│   ├── backup-target.nix       # borgbackup server
│   └── llama-cpp.nix           # llama-server systemd service (router mode)
├── k8s/
│   └── dns/
│       ├── deployment.yaml     # AdGuard Home Deployment
│       ├── service.yaml        # Service (NodePort for DNS ports)
│       └── pvc.yaml            # PVC backed by NAS NFS export
├── secrets/
│   ├── .sops.yaml              # key mapping
│   ├── thinkpad.yaml
│   └── itx-5825u.yaml
└── docs/
    ├── prd/
    └── adr/
```

## Profiles

### `base.nix` — Common to all machines

- Locale, timezone, console font
- Kernel parameters (hardware-agnostic tuning)
- SSH daemon (passwordless key auth)
- User accounts (admin user with sudo)
- `sops-nix` setup (age key location, /run/secrets/ output)
- Trusted Nix substituters / binary caches

### `compute.nix` — k3s runtime

- Imports `services/k3s.nix`
- Monitoring agent (node exporter)
- No local storage for service data — stateful workloads use NFS-backed PVCs from NAS nodes

### `nas.nix` — Storage services

- Imports `services/file-sharing.nix`
- Imports `services/media-stack.nix`
- Imports `services/backup-target.nix`

### `ai.nix` — LLM inference

- Imports `services/llama-cpp.nix`
- Enables one `llama-server` instance (router mode) on port `11434`, Vulkan backend
- Models live in `/var/lib/llama-cpp/models/` — GGUFs dropped in via the `hf` CLI are loaded on demand by the `model` field of OpenAI-compatible API requests, no service restart
- Daemon is healthy with an empty models dir; no `modelPath` is pinned
- Installs Hermes Agent (from the `numtide/llm-agents.nix` flake input) as a CLI tool on the system PATH — no service, configured interactively by the operator via `hermes setup`

## Services

### `k3s.nix`
- Installs k3s server on every node (all nodes are control plane + worker, default k3s behaviour)
- Cluster join token fetched from sops-nix at `/run/secrets/k3s-token`
- Server address and token configurable per node via the NixOS module options
- NFS client utilities installed so PVCs backed by NAS NFS work from any node

### `monitoring-agent.nix`
- prometheus node exporter on :9100
- promtail for log shipping to Loki

### `file-sharing.nix`
- NFS server (exports `/data` for k3s PVCs and general network mounts)
- Samba share for bulk media access
- Credentials from sops-nix

### `media-stack.nix`
- Jellyfin for video streaming
- *arr suite (Sonarr, Radarr, Lidarr, Readarr)
- qBittorrent or Transmission (VPN-bound via WireGuard container)
- Media directory layout: `/data/media/{movies,shows,music,books,torrents}`

### `backup-target.nix`
- borgbackup server (SSH-based, append-only repos)
- Separate borg user with restricted shell
- Backup schedules via systemd timers

### `llama-cpp.nix`
- Runs llama.cpp's `llama-server` as a host systemd service in router mode (`--models-dir`, no pinned `-m`)
- Daemon starts healthy with an empty models directory; GGUFs dropped into `/var/lib/llama-cpp/models/` are loaded on demand based on the `model` field of OpenAI-compatible API requests
- `services.llama-cpp.instances` (attrsOf) — one systemd service + open port per instance, each with its own `modelsDir`/`port`/`extraArgs` (backend flags like `-ngl 99`, `--backend vulkan`)
- Runs as an unprivileged `llama` system user with systemd hardening (`ProtectSystem=strict`, `PrivateTmp`, etc.)
- Installs `llama-cpp` built with Vulkan support (full package — `llama-server`, `llama-cli`, `llama-bench`, `llama-quantize`) and `python3Packages.huggingface-hub` (provides the `hf` CLI) for ad-hoc model pulls

## Additional Flake Inputs

### `numtide/llm-agents.nix`

A daily-updated flake providing Nix packages for AI coding agents and tools not yet in nixpkgs. Used to install Hermes Agent (Nous Research) on AI-profile hosts. Follows `nixpkgs` to avoid a second copy of nixpkgs in the closure.

### DNS (k3s deployment, optional)

AdGuard Home runs as a k3s Deployment, not a NixOS service. Applied via `kubectl apply -f k8s/dns/`. It uses a PVC backed by NAS NFS for persistent query logs and config. Exposed via NodePort on port 53 (DNS) and 3000 (admin UI).

Manifests in `k8s/dns/`:
- `pvc.yaml` — PersistentVolumeClaim
- `deployment.yaml` — AdGuard Home container
- `service.yaml` — NodePort for DNS (53) and admin UI (3000)

## Secrets Management

Approach: **sops-nix with age encryption**

- Each host's **public age key** is documented in `secrets/.sops.yaml`
- Encrypted per-host `secrets/<hostname>.yaml` files are committed to git
- Decryption happens at NixOS activation, outputs to `/run/secrets/`
- Host private key stored locally at `/var/lib/sops-nix/key.txt`
- Secrets include: SSH host keys, Samba credentials, k3s cluster token, API tokens

### Key Generation

For each new host:
```bash
mkdir -p /var/lib/sops-nix
nix shell nixpkgs#age -c age-keygen -o /var/lib/sops-nix/key.txt
# Extract public key
nix shell nixpkgs#age -c age-keygen -y /var/lib/sops-nix/key.txt
```

## Flake Layout

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, ... } @ inputs: {
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
    };
  };
}
```

## ADRs

### ADR-0001 — Why sops-nix

- Alternatives considered: agenix, plain age, manual out-of-band
- Why sops-nix: single flake input, YAML-structured secrets, easy key rotation, wide community use
- Why not agenix: adding new hosts requires re-encrypting all secret files
- Why not plain age: manual activation script, no module integration

### ADR-0002 — Why k3s

- Alternatives considered: k0s, microk8s, plain podman
- Why k3s: single binary, low resource usage (ideal for Thinkpad), built-in etcd or sqlite3 backend, all nodes are control plane + worker by default, simple token-based join
- Why not k0s: more opinionated about control plane setup
- Why not microk8s: snaps, heavier, Ubuntu-centric
- Why not podman: no cluster orchestration, no pod scheduling across nodes, no built-in service discovery
