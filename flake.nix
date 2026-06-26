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
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, disko, nixos-anywhere, ... } @ inputs: {
    nixosConfigurations = {
      compute = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/compute ];
        specialArgs = { inherit inputs; };
      };
      server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/server ];
        specialArgs = { inherit inputs; };
      };
      storage = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/storage ];
        specialArgs = { inherit inputs; };
      };
      ai = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/ai ];
        specialArgs = { inherit inputs; };
      };
      first-ai = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/first-ai ];
        specialArgs = { inherit inputs; };
      };
      first-server = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/first-server ];
        specialArgs = { inherit inputs; };
      };
    };
    packages.x86_64-linux = {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
    };
  };
}
