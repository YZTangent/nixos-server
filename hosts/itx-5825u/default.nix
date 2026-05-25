{ inputs, ... }:
{
  networking.hostName = "itx-5825u";
  networking.hostId = "deadbeef";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];
}
