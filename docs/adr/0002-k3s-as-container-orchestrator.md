# Use k3s as the container orchestrator

We chose k3s over k0s, microk8s, and plain podman for this homogeneous cluster. k3s ships as a single ~50MB binary, uses sqlite3 by default (etcd optional), and every node is control plane + worker with no extra config — matching our requirement that all nodes run workloads and participate in the control plane. Token-based join is simple to manage via sops-nix. k0s was rejected for more opinionated control plane defaults, microk8s for its Snap dependency and Ubuntu-centrism, and plain podman for lacking multi-node orchestration, pod scheduling, and built-in service discovery.

*(Note: For instructions and architectural decisions on how we expose and serve these k3s workloads to the public internet, see [ADR 0007: Cloudflare Tunnels for Ingress and Private Access](./0007-cloudflare-tunnels-for-ingress-and-private-access.md)).*
