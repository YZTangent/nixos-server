{ inputs, ... }: {
  networking.hostName = "n95";

  imports = [
    ./hardware.nix
    ../../profiles/base.nix
  ];
}
