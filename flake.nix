{
  description = "NixOS headless server cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    device-id = {
      url = "path:./device-id";
      flake = false;
    };
  };

  outputs = { nixpkgs, disko, nixos-anywhere, ... } @ inputs: {
    nixosConfigurations = let
      lib = nixpkgs.lib;
      hostDirs = builtins.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./hosts));
    in builtins.listToAttrs (map (name: {
      inherit name;
      value = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/${name} ];
        specialArgs = { inherit inputs; };
      };
    }) hostDirs);
    packages.x86_64-linux = {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
    };
  };
}
