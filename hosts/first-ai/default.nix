{ inputs, ... }: import ../mk-host.nix { inherit inputs; } { role = "ai"; isFirstNode = true; }
