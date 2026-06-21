{ inputs, ... }:
{
  networking.hostName = "thinkpad";

  imports = [
    ../../profiles/base.nix
    ../../profiles/compute.nix
  ];
}
