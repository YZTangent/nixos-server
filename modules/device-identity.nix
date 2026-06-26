{ lib, ... }:
{
  options.device-identity = {
    role = lib.mkOption {
      type = lib.types.str;
      description = "Machine role (compute, server, ai, storage). Used for sops file grouping and hostname prefix.";
    };
  };
}
