# Use keepalived VIP for k3s cluster bootstrap and node discovery

All k3s servers point their `serverAddr` to a virtual IP (`192.168.1.200/24`) managed by keepalived via VRRP. The designated first node uses `--cluster-init` with no `--server` flag to bootstrap the embedded etcd datastore; all other nodes join via the VIP. Keepalived preempts toward the designated first node (higher VRRP priority). VRRP auth password stored in sops-nix.

This solves the bootstrap-ordering problem without hardcoding a specific node's IP, and makes every server interchangeable after cluster formation — if the first node goes down, the VIP floats to another node, and a revived first node reads its local etcd state to rejoin.

## Explicit Interface Binding

The configuration mandates explicitly specifying the physical network interface (e.g. `eth0` via `flannelIface`) for both keepalived and k3s/Flannel, rather than relying on automatic interface detection or default routes.

This is because machines (especially desktops or compute nodes) often possess multiple virtual or physical interfaces (e.g., Docker/Podman bridges like `docker0`, VM networks like `virbr0`, VPN tunnels, or secondary Wi-Fi cards). 

- If k3s or Flannel guesses wrong and binds to a local virtual bridge, cluster traffic will be routed into a black hole, breaking node communication.
- Keepalived strictly requires a named interface to correctly broadcast VRRP heartbeat packets to peers on the local LAN. 

Requiring explicit interface binding ensures both keepalived and k3s securely lock onto the correct physical connection to the LAN.
