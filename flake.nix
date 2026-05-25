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
  };

  outputs = { nixpkgs, disko, nixos-anywhere, ... } @ inputs: {
    nixosConfigurations = {
      thinkpad = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/thinkpad ];
        specialArgs = { inherit inputs; };
      };
      itx-5825u = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/itx-5825u ];
        specialArgs = { inherit inputs; };
      };
      n95 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/n95 ];
        specialArgs = { inherit inputs; };
      };
    };
    packages.x86_64-linux = {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
    };
  };
}
