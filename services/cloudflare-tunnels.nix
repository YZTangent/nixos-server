{ config, lib, ... }:
let
  cfg = config.services.nixos-server.cloudflare-tunnels;
in {
  options.services.nixos-server.cloudflare-tunnels = {
    enable = lib.mkEnableOption "Cloudflare Tunnels service";
    
    hostTunnel = {
      enable = lib.mkEnableOption "Host tunnel for WARP routing";
      name = lib.mkOption {
        type = lib.types.str;
        default = "host-${config.networking.hostName}";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the cloudflared credentials JSON file";
      };
    };

    computeTunnel = {
      enable = lib.mkEnableOption "Compute tunnel for ingress";
      name = lib.mkOption {
        type = lib.types.str;
        default = "compute-cluster";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.str;
        description = "Path to the cloudflared credentials JSON file";
      };
      ingress = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { "*" = "http://localhost:80"; };
        description = "Ingress routing rules mapping hostnames to local endpoints";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.cloudflared = {
      enable = true;
      tunnels = lib.mkMerge [
        (lib.mkIf cfg.hostTunnel.enable {
          "${cfg.hostTunnel.name}" = {
            credentialsFile = cfg.hostTunnel.credentialsFile;
            default = "http_status:404";
            warp-routing.enabled = true;
          };
        })
        (lib.mkIf cfg.computeTunnel.enable {
          "${cfg.computeTunnel.name}" = {
            credentialsFile = cfg.computeTunnel.credentialsFile;
            default = "http_status:404";
            ingress = cfg.computeTunnel.ingress;
          };
        })
      ];
    };
  };
}
