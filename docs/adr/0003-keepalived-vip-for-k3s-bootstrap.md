# Use keepalived VIP for k3s cluster bootstrap and node discovery

All k3s servers point their `serverAddr` to a virtual IP (`192.168.1.200/24`) managed by keepalived via VRRP. The designated first node uses `--cluster-init` with no `--server` flag to bootstrap the embedded etcd datastore; all other nodes join via the VIP. Keepalived preempts toward the designated first node (higher VRRP priority). VRRP auth password stored in sops-nix.

This solves the bootstrap-ordering problem without hardcoding a specific node's IP, and makes every server interchangeable after cluster formation — if the first node goes down, the VIP floats to another node, and a revived first node reads its local etcd state to rejoin.
