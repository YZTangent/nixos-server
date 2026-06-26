{ inputs, ... }: { role, isFirstNode ? false, extraProfiles ? [] }:
let
  device-id = import inputs.device-id;
  profileFor = {
    compute = [ ../../profiles/compute.nix ];
    server  = [ ../../profiles/compute.nix ../../profiles/nas.nix ];
    ai      = [ ../../profiles/compute.nix ../../profiles/ai.nix ];
    storage = [ ../../profiles/nas.nix ];
  };
in {
  networking.hostName   = "${role}-${device-id.hostname}";
  networking.hostId      = device-id.hostId;
  device-identity.role   = role;
  imports                = [ ../../profiles/base.nix ] ++ profileFor.${role} ++ extraProfiles;
  services.k3s-server.isFirstNode = isFirstNode;
}
