{ inputs, ... }:
{
  networking.hostName = "strix-halo";
  networking.hostId = "beefcake";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/ai.nix
  ];
}
