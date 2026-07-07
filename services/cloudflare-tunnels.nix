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
        defaultText = lib.literalExpression ''"host-\${config.networking.hostName}"'';
        description = "Name of the host tunnel";
        example = "host-my-server";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the cloudflared credentials JSON file";
        example = "/run/secrets/cloudflared-credentials.json";
      };
    };

    computeTunnel = {
      enable = lib.mkEnableOption "Compute tunnel for ingress";
      name = lib.mkOption {
        type = lib.types.str;
        default = "compute-cluster";
        description = "Name of the compute tunnel";
        example = "compute-my-cluster";
      };
      credentialsFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to the cloudflared credentials JSON file";
        example = "/run/secrets/cloudflared-credentials.json";
      };
      ingress = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {};
        description = "Ingress routing rules mapping hostnames to local endpoints";
        example = { "git.example.com" = "http://localhost:8080"; };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.hostTunnel.enable || cfg.hostTunnel.credentialsFile != null;
        message = "hostTunnel is enabled but credentialsFile is not set.";
      }
      {
        assertion = !cfg.computeTunnel.enable || cfg.computeTunnel.credentialsFile != null;
        message = "computeTunnel is enabled but credentialsFile is not set.";
      }
    ];

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
