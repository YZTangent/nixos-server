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
}
