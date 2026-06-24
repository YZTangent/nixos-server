{ inputs, ... }:
{
  networking.hostName = "strix-halo";
  networking.hostId = "b0facade";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/ai.nix
  ];

  services.k3s-server.isFirstNode = true;
}
