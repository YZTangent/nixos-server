# Replace fake k3s first-node address with VIP + keepalived

## Problem

All k3s nodes hardcode `serverAddr = "https://10.0.0.1:6443"` — a fake IP. There is no real first node. This means no node can actually bootstrap the cluster, and there's no mechanism for new or revived nodes to discover a working server.

## Solution

Introduce a virtual IP (VIP) managed by keepalived across all k3s server nodes. All nodes point `serverAddr` to the VIP. A designated first node uses `--cluster-init` to bootstrap the embedded etcd datastore; other nodes join via the VIP. If the first node goes down, keepalived moves the VIP to another node. If it comes back, it reads its local etcd state and rejoins the cluster.

## Design

### 1. `services/k3s.nix` changes

- Add `services.k3s-server.vip` (string) — the virtual IP, default `192.168.1.200`.
- Add `services.k3s-server.isFirstNode` (bool, default `false`).
- When `isFirstNode = true`:
  - `services.k3s.clusterInit = true`
  - `services.k3s.serverAddr` is set to `""` (empty, no `--server` flag; k3s reads local etcd data to find peers)
- When `isFirstNode = false`:
  - `services.k3s.clusterInit = false`
  - `services.k3s.serverAddr = "https://${vip}:6443"`
- Configure `services.keepalived`:
  - VRRP instance with VIP = `services.k3s-server.vip`
  - Interface = `services.k3s-server.flannelIface`
  - VRRP priority = 150 if `isFirstNode`, else 100
  - Preemption enabled (higher-priority node claims VIP on restart)
  - Auth password from sops-nix (`k3s-vrrp-password`)
- Add firewall rule for VRRP multicast (`224.0.0.18`, protocol 112).

### 2. `profiles/compute.nix` changes

- Remove the hardcoded `serverAddr = "https://10.0.0.1:6443"`.
- Remove the TODO comment.
- The VIP is set via the module default (or could be overridden per host if needed).
- `isFirstNode` is `false` by default.

### 3. New host configurations

| Flake output | Directory | Machine | `isFirstNode` | Notes |
|---|---|---|---|---|
| `ai` | `hosts/ai/` | strix-halo | `false` | Same as existing but added to flake |
| `first-ai` | `hosts/first-ai/` | strix-halo | `true` | Same profiles as `ai` + first-node role |
| `first-server` | `hosts/first-server/` | itx-5825u | `true` | Same profiles as `server` + first-node role |

Existing hosts (`compute`, `server`, `storage`) remain unchanged — they import `profiles/compute.nix` which handles k3s config.

`hosts/first-ai/` imports the same modules as `hosts/ai/` (`base + compute + ai`), then sets `services.k3s-server.isFirstNode = true`.
`hosts/first-server/` imports the same modules as `hosts/server/` (`base + compute + nas`), then sets `services.k3s-server.isFirstNode = true`.

### 4. Flake changes

Add to `nixosConfigurations`:
- `ai = ./hosts/ai`
- `first-ai = ./hosts/first-ai`
- `first-server = ./hosts/first-server`

### 5. Secrets

Add `k3s-vrrp-password` to each host's sops-nix yaml file.

## Usage

1. Deploy `first-ai` (or `first-server`) to the machine that will bootstrap the cluster.
2. Wait for k3s to start with `--cluster-init`.
3. Deploy all other hosts (`ai`, `compute`, `server`, `storage`) — they join via the VIP.
4. If the first node goes down, keepalived floats the VIP to another node. Cluster stays up.

## Related spec/ADR

- `docs/adr/0002-k3s-as-container-orchestrator.md`
