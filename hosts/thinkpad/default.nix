{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
  ];
}
