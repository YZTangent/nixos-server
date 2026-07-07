{ config, pkgs, lib, inputs, ... }:

let
  device-id = import inputs.device-id;
in
{
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ../disko/os-ext4.nix
    ../modules/device-identity.nix
  ];

  assertions = [{
    assertion = device-id.hostname != "unknown";
    message = ''
      device-id input not overridden.
      This closure would be built with hostname="unknown", which is the placeholder default.
      Supply the per-instance device-id at build time:
        nixos-anywhere --flake ".#<host>" --override-input device-id path:/tmp/device-<hash> ...
      See docs/changes/2026-06-25-hardware-derived-identity-requirement.md for the provisioning wrapper.
    '';
  }];

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
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF9bbfpFPn0zjFj6/NTKXWqkAe9avhGTdDY/dBxF7UKH yztangent@nixos"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # sops-nix
  sops = {
    defaultSopsFile = ../secrets/${config.device-identity.role}-${device-id.hostname}.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Trusted caches
  nix.settings.trusted-users = [ "yztangent" ];
  nix.settings.substituters = [ "https://cache.nixos.org" ];

  # Allow unfree where needed
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "jellyfin-ffmpeg"
  ];

  # Cloudflare Host Tunnel (Unique per machine)
  sops.secrets."cloudflared/host-tunnel.json" = {};
  
  services.nixos-server.cloudflare-tunnels = {
    enable = true;
    hostTunnel = {
      enable = true;
      name = "host-${device-id.hostname}";
      credentialsFile = config.sops.secrets."cloudflared/host-tunnel.json".path;
    };
  };
  environment.systemPackages = [ pkgs.cloudflared ];


  system.stateVersion = "26.05";
}
