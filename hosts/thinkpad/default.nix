{ inputs, ... }:
{
  networking.hostName = "thinkpad";

  imports = [
    ./hardware.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
  ];
}
