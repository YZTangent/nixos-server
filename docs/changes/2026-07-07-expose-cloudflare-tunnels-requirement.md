# Requirement: Expose Cloudflare Tunnels as a Reusable Service

## Purpose
Expose the existing dual-tunnel Cloudflare setup (Host Tunnel and Compute Tunnel) as a reusable NixOS module. This allows external consumers of the flake to easily integrate the same Zero Trust network access and public ingress topology without needing to inherit the opinionated `profiles/base.nix` or `profiles/compute.nix`.

## Scope
* Create a new NixOS module at `services/cloudflare-tunnels.nix`.
* Parameterize the existing hardcoded Cloudflare tunnel settings.
* Refactor `profiles/base.nix` and `profiles/compute.nix` to use this new module instead of configuring `services.cloudflared` directly.
* Expose the new module in `flake.nix` under `nixosModules.cloudflare-tunnels` and add it to `nixosModules.default`.

## Operational Prerequisites (Out of Scope for this module)
To actually use this module, the operator must perform the following external actions:

1. **Cloudflare Dashboard (or Terraform) Setup**:
   * Create the tunnels to generate the UUIDs and credentials.
   * Add the credentials to `sops-nix` (`cloudflared/host-tunnel.json` and `cloudflared/compute-tunnel.json`).
   * For the Compute Tunnel: Create public DNS CNAME records (e.g., `*.apps.domain.com`) pointing to the tunnel's `.cfargotunnel.com` UUID.


## Architecture & Configuration
The module will define the following option tree under `services.nixos-server.cloudflare-tunnels`:

* `enable` (bool, default `false`): Master toggle for the entire service.
* `hostTunnel.enable` (bool, default `false`): Enables the unique per-machine WARP routing tunnel for private admin access (e.g., SSH).
* `hostTunnel.name` (string, default `"host-${config.networking.hostName}"`): The name of the host tunnel.
* `hostTunnel.credentialsFile` (string, required): The absolute path to the cloudflared credentials JSON file for the host tunnel.
* `computeTunnel.enable` (bool, default `false`): Enables the shared replica tunnel for public web ingress.
* `computeTunnel.name` (string, default `"compute-cluster"`): The name of the compute tunnel.
* `computeTunnel.credentialsFile` (string, required): The absolute path to the cloudflared credentials JSON file for the compute tunnel.
* `computeTunnel.ingress` (attribute set, default `{"*" = "http://localhost:80";}`): The ingress routing rules mapping hostnames to local endpoints.

## Data Flow & Integration
1. **Host Tunnel**: When enabled, it will configure `services.cloudflared.tunnels.<name>` with `warp-routing.enabled = true` and `default = "http_status:404"`.
2. **Compute Tunnel**: When enabled, configures `services.cloudflared.tunnels.<name>` with `ingress = cfg.computeTunnel.ingress` and `default = "http_status:404"`.

## Routing Architecture: Cloudflare vs Kubernetes Ingress
It is critical to distinguish between the Cloudflare Tunnel ingress configuration in NixOS and the Kubernetes `Ingress` YAML manifests used by the cluster:

1. **Cloudflare Tunnel (The Outer Proxy)**: Runs natively on NixOS (outside k3s). Its job is to securely tunnel traffic from the public internet into the server. The default `"*"` rule catches all traffic and dumps it onto `localhost:80` while strictly preserving the HTTP `Host` header (e.g., `Host: myapp.domain.com`).
2. **Kubernetes Ingress (The Inner Router)**: Inside k3s, Traefik listens on `localhost:80`. When it receives the traffic from the tunnel, it reads the preserved `Host` header and relies on standard **Kubernetes `Ingress` YAML manifests** (e.g., your app deployments) to route the request to the correct internal pod.

*This separation of concerns allows us to easily route traffic to both native NixOS services (via Cloudflare ingress rules) and k3s services (via Kubernetes Ingress YAMLs) simultaneously.*
3. **Internal Usage**: 
   * `profiles/base.nix` will enable the service, enable the `hostTunnel`, set the credentials path, and explicitly set the tunnel name to `"host-${device-id.hostname}"`.
   * `profiles/compute.nix` will enable the `computeTunnel` and set its credentials path.

## Testing
* The internal flake checks (`checks.x86_64-linux.nixos-modules-eval`) will automatically verify that the new module evaluates correctly when imported by an external consumer without internal `specialArgs`.
