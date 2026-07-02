# Requirement: Cloudflare Tunnel Topology and Integration

## 1. Objective
Enable `cloudflared` as the primary connection method for the server cluster, ensuring secure, high-availability ingress for public services and private access for admin services, while supporting the multi-node architecture (mapping many machines to few URLs).

## 2. Context & Constraints
* **Spec context:** Relates to `docs/prd/2026-05-25-nixos-server-config.md`.
* The cluster contains multiple roles (`compute`, `nas`, `ai`), and can have multiple machines of the same type.
* k3s workloads require high availability across `compute` nodes.
* Host-level services (SSH, NFS, Samba) require secure, private access without public exposure.

## 3. Architecture Design

### 3.1. Tunnel Topology (Dual-Tunnel Approach)
To support both host-level isolation and cluster-level high availability, machines will run up to two concurrent tunnels:

1. **Host Tunnel (Unique per machine)**
   * **Scope:** Runs on *all* machines via `profiles/base.nix`.
   * **Tunnel ID:** Unique to each physical machine (e.g., `tunnel-thinkpad`, `tunnel-itx-5825u`).
   * **Purpose:** Exposes host-level admin services (SSH, NFS, Samba) to the private Cloudflare Zero Trust network (WARP). Used for direct, secure host management. No public hostnames are mapped to these services.
   
2. **Compute Tunnel (Replica Mode)**
   * **Scope:** Runs on all k3s cluster nodes via `profiles/compute.nix`.
   * **Tunnel ID:** A single, shared Tunnel ID across all compute nodes.
   * **Purpose:** Handles public web ingress for k3s workloads (e.g., `*.apps.domain.com`). Cloudflare will automatically load-balance incoming requests across all active replica tunnels, and k3s will route the traffic internally to the correct pods.

### 3.2. NixOS Configuration (The "Hardware" Side)
The implementation will leverage the `services.cloudflared.tunnels` NixOS option, which allows defining multiple tunnels concurrently.

* **In `profiles/base.nix`:**
  * Define `services.cloudflared.tunnels."host-${config.networking.hostName}"`.
  * Configure it to read its unique credentials from sops-nix (e.g., `/run/secrets/cloudflared/host-tunnel.json`).
  * (Optional) Configure ingress rules for host-specific services (like `llama-server` on AI nodes, if exposed publicly).

* **In `profiles/compute.nix`:**
  * Define `services.cloudflared.tunnels."compute-cluster"`.
  * Configure it to read the shared credentials from sops-nix (e.g., `/run/secrets/cloudflared/compute-tunnel.json`).
  * Configure default ingress to point to the k3s Traefik ingress controller (`http://localhost:80`).

### 3.3. Secrets Management
* Cloudflare Tunnel credentials (JSON files containing the Account Tag, Tunnel ID, and Secret) will be managed via the existing `sops-nix` infrastructure.
* Each host's `secrets/<hostname>.yaml` will need to be updated to include the necessary tunnel credentials.

## 4. Scope and Out of Scope
* **In Scope:** Modifying NixOS profiles (`base.nix`, `compute.nix`) to support the dual-tunnel architecture. Setting up the sops-nix integration for the credentials.
* **Out of Scope:** Actually creating the tunnels in the Cloudflare dashboard or generating the UUIDs/credentials (this requires manual operator action via the `cloudflared` CLI or dashboard).

## 5. Ambiguity Check & Notes
* **Tunnel provisioning:** The NixOS configuration will assume the tunnels have already been created via Cloudflare. The operator will need to provision them and inject the credentials into `sops-nix` before the services will start successfully. We should document this process in the PRD.
