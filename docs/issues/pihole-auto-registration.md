# Issue: Pi-hole Auto-Registration Bootstrapping

## Problem
We need a way for nodes to automatically register their hostname and IP address to the private DNS resolver (Pi-hole) when they boot up, so that WARP clients can access them via `hostname.lan` without manual DNS entry.

However, there is a bootstrapping (chicken-and-egg) problem:
If a cluster cold-boots (e.g., after power loss), the nodes will try to register themselves before the Pi-hole container is actually running or scheduled. 

## Proposed Solutions (Deferred for now)
1. **Eventual Consistency (Systemd Retries)**: Create a systemd `oneshot` service with `Restart=on-failure` and `RestartSec=30s`. It will continuously retry `curl`ing the Pi-hole API until Pi-hole is online and responds with a 200 OK.
2. **Continuous State Sync (Systemd Timer)**: Create a systemd timer that runs every 5 minutes to push the IP to Pi-hole. This solves both cold-boot and DHCP IP drift.
3. **Infrastructure as Code**: Manage the DNS records statically via Terraform Pi-hole provider, rather than relying on nodes to self-register dynamically.

*Note: This feature was deemed too large to include in the Cloudflare Tunnels refactor and has been split out for future implementation.*
