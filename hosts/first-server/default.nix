{ inputs, ... }:
{
  networking.hostName = "itx-5825u";
  networking.hostId = "deadbeef";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];

  services.k3s-server.isFirstNode = true;
}
