{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/k3s.nix
    ../services/monitoring-agent.nix
  ];

  services.k3s-server = {
    enable = true;
    # serverAddr is auto-configured from services.k3s-server.vip (default 192.168.1.200).
    # Override vip below if your LAN subnet differs.
  };

  services.monitoring-agent.enable = true;

  # Cloudflare Compute Tunnel (Replica mode for k3s ingress)
  sops.secrets."cloudflared/compute-tunnel.json" = {};

  services.cloudflared.tunnels."compute-cluster" = {
    credentialsFile = config.sops.secrets."cloudflared/compute-tunnel.json".path;
    default = "http_status:404";
    ingress = {
      "*" = "http://localhost:80";
    };
  };
}
