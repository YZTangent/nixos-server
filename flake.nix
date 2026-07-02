{
  description = "NixOS headless server cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
    device-id = {
      url = "path:./device-id";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, disko, nixos-anywhere, ... } @ inputs: {
    nixosModules = {
      llama-server = ./services/llama-server.nix;
      k3s = ./services/k3s.nix;
      media-stack = ./services/media-stack.nix;
      file-sharing = ./services/file-sharing.nix;
      backup-target = ./services/backup-target.nix;
      monitoring-agent = ./services/monitoring-agent.nix;

      ai = { pkgs, ... }: {
        imports = [ self.nixosModules.llama-server ];
        environment.systemPackages = [
          inputs.llm-agents.packages.${pkgs.system}.hermes-agent
        ];
      };

      default = { ... }: {
        imports = [
          self.nixosModules.llama-server
          self.nixosModules.k3s
          self.nixosModules.media-stack
          self.nixosModules.file-sharing
          self.nixosModules.backup-target
          self.nixosModules.monitoring-agent
        ];
      };
    };

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
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
      provision = pkgs.python3Packages.buildPythonApplication {
        pname = "provision";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        nativeBuildInputs = [ pkgs.python3Packages.setuptools ];
        propagatedBuildInputs = [ pkgs.python3Packages.pyyaml ];
        nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ];
        pytestFlagsArray = [ "tests/" ];

        # Runtime dependencies: provision.py shells out to these tools.
        # makeWrapper puts them on PATH so `nix run .#provision` works without
        # the user having them installed separately.
        postInstall = ''
          wrapProgram $out/bin/provision \
            --prefix PATH : ${pkgs.lib.makeBinPath [
              pkgs.age
              pkgs.sops
              nixos-anywhere.packages.x86_64-linux.nixos-anywhere
              pkgs.git
              pkgs.openssh
            ]}
        '';
      };
    };
  };
}
