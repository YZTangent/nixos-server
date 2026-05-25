{ ... }:
{
  networking.hostName = "n95";
  networking.hostId = "cafebabe";

  imports = [
    ./disko.nix
    ../../profiles/base.nix
  ];
}
