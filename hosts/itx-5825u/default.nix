{ inputs, ... }:
{
  networking.hostName = "itx-5825u";

  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
    ../../profiles/nas.nix
  ];
}
