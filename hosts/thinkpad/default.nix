{ inputs, ... }:
{
  networking.hostName = "thinkpad";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
    ../../profiles/compute.nix
  ];
}
