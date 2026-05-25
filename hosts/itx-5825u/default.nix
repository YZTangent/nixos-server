{ inputs, ... }:
{
  networking.hostName = "itx-5825u";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];
}
