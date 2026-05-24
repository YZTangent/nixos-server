{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/file-sharing.nix
    ../services/media-stack.nix
    ../services/backup-target.nix
  ];

  services.file-sharing.enable = true;
  services.media-stack.enable = true;
  services.backup-target.enable = true;
}
