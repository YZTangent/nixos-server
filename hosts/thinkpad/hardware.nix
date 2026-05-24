{ modulesPath, ... }:
{
  imports = [
    # Replace this with output of `nixos-generate-config --show-hardware-config`
    "${modulesPath}/hardware/network/broadcom-43xx.nix"
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
