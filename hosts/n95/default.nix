{ ... }:
{
  networking.hostName = "n95";
  networking.hostId = "cafebabe";

  imports = [
    ../../profiles/base.nix
    ../../profiles/nas.nix
  ];
}
