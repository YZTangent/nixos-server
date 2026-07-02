{ inputs, ... }: { role, isFirstNode ? false, extraProfiles ? [] }:
{ lib, ... }:
let
  device-id = import inputs.device-id;
  profileFor = {
    compute = [ ../profiles/compute.nix ];
    server  = [ ../profiles/compute.nix ../profiles/nas.nix ];
    ai      = [ ../profiles/compute.nix ../profiles/ai.nix ];
    storage = [ ../profiles/nas.nix ];
  };
  hasK3s = builtins.elem ../profiles/compute.nix (profileFor.${role} ++ extraProfiles);
in {
  imports = [ ../profiles/base.nix ] ++ profileFor.${role} ++ extraProfiles;

  config = lib.mkMerge [
    {
      networking.hostName   = "${role}-${device-id.hostname}";
      networking.hostId      = device-id.hostId;
      device-identity.role   = role;
    }
    (lib.optionalAttrs hasK3s {
      services.k3s-server.isFirstNode = isFirstNode;
    })
  ];
}
