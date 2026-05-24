{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/k3s.nix
    ../services/monitoring-agent.nix
  ];

  services.k3s-server = {
    enable = true;
    serverAddr = "https://10.0.0.1:6443";  # TODO: set to actual first node IP
  };

  services.monitoring-agent.enable = true;
}
