{ inputs, ... }: import ../mk-host.nix { inherit inputs; } { role = "storage"; }
