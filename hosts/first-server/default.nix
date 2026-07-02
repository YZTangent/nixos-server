args@{ inputs, ... }: import ../mk-host.nix { inherit inputs; } { role = "server"; isFirstNode = true; } args
