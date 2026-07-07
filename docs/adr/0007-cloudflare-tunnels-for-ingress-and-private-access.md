# 7. Cloudflare Tunnels for Ingress and Private Access

Date: 2026-07-03

## Status

Accepted

## Context

The NixOS server cluster requires a method for exposing web workloads running in k3s to the public internet (with custom domains) while also providing secure, private access to host-level administrative services (SSH, NFS, Samba) for remote management. 

We need an architecture that supports:
1. High availability and load balancing for k3s workloads across multiple compute nodes.
2. Secure private routing for admin services without exposing them to public hostnames.
3. Declarative infrastructure-as-code management within NixOS.

We considered Tailscale (mesh VPN) for private routing. While Tailscale provides excellent Peer-to-Peer connectivity for internal services, its public ingress features (Tailscale Funnel) are not designed for enterprise-grade load balancing across a Kubernetes cluster. 

## Decision

We will use **Cloudflare Zero Trust (cloudflared)** to handle both public ingress and private network routing via a dual-tunnel topology:

1. **Compute Tunnel (Replica Mode):** All `compute` profile nodes will share a single Cloudflare Tunnel ID. Cloudflare's edge will load-balance public web traffic (`*.apps.domain.com`) across all active nodes, passing traffic to the k3s Traefik ingress controller.
2. **Host Tunnel (Unique):** Every machine will run a unique, host-specific tunnel to advertise its private IP (e.g., `10.0.0.x`) to the Cloudflare Zero Trust network. 

**Note on Public Workloads:** Because the Compute Tunnel routes traffic blindly to the k3s Traefik ingress controller (using a `"*"` wildcard), **all future public-facing services deployed in k3s MUST include a standard Kubernetes `Ingress` YAML manifest.** This manifest allows Traefik to read the HTTP `Host` header (preserved by `cloudflared`) and route the traffic to the correct internal pod.

*(Note: The binding of the k3s Traefik load balancer to port 80/443 on the host is not explicitly configured in our manifests. It is the native, out-of-the-box behavior of k3s, which automatically deploys the Traefik Helm chart and its corresponding `LoadBalancer` service upon startup).*

Operators will use the Cloudflare WARP client to access private admin services (and private k3s services like internal DNS dashboards).

## Consequences

* **Positive:** k3s workloads achieve instant high-availability ingress. Adding new custom domains requires zero changes to the NixOS configuration. Host services are completely isolated from the public internet.
* **Negative:** Private file transfers (NFS/Samba) when remote will incur a latency penalty as traffic must route through a Cloudflare edge server (hub-and-spoke), unlike the direct P2P connections provided by a mesh VPN like Tailscale.
* **Mitigation:** When on the local home network, WARP can be configured via "Managed Networks" to bypass Cloudflare and route locally, restoring full local LAN speeds.
