{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";
  console.font = "Lat2-Terminus16";
  console.keyMap = "us";

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Admin user
  users.users.yztangent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: add your public key
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # sops-nix
  sops = {
    defaultSopsFile = ../secrets/${config.networking.hostName}.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Trusted caches
  nix.settings.trusted-users = [ "yztangent" ];
  nix.settings.substituters = [ "https://cache.nixos.org" ];

  # Allow unfree where needed
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "jellyfin-ffmpeg"
  ];

  system.stateVersion = "25.05";
}
