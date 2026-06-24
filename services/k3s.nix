{ config, pkgs, lib, ... }:
{
  options.services.k3s-server = {
    enable = lib.mkEnableOption "k3s server node";
    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:6443";
      description = "Address of the initial k3s server for cluster join";
    };
    flannelIface = lib.mkOption {
      type = lib.types.str;
      default = "eth0";
      description = "Network interface for flannel VXLAN traffic";
    };
    vip = lib.mkOption {
      type = lib.types.str;
      default = "192.168.1.200";
      description = "Virtual IP for k3s API server, managed by keepalived";
    };
    isFirstNode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this node bootstraps the k3s cluster with --cluster-init";
    };
  };

  config = lib.mkIf config.services.k3s-server.enable {
    sops.secrets."k3s-token".restartUnits = [ "k3s.service" ];
    sops.secrets."k3s-vrrp-password" = {};

    sops.templates."k3s-vrrp-env" = {
      content = "VRRP_PASSWORD=$k3s-vrrp-password";
    };

    environment.systemPackages = with pkgs; [ k3s nfs-utils keepalived ];

    services.k3s = {
      enable = true;
      role = "server";
      tokenFile = config.sops.secrets."k3s-token".path;
      serverAddr = if config.services.k3s-server.isFirstNode
                   then ""
                   else "https://${config.services.k3s-server.vip}:6443";
      clusterInit = config.services.k3s-server.isFirstNode;
      extraFlags = "--flannel-iface=${config.services.k3s-server.flannelIface}";
    };

    services.keepalived = {
      enable = true;
      openFirewall = true;
      secretFile = config.sops.templates."k3s-vrrp-env".path;
      vrrpInstances.k3s = {
        interface = config.services.k3s-server.flannelIface;
        state = "BACKUP";
        virtualRouterId = 50;
        priority = if config.services.k3s-server.isFirstNode then 150 else 100;
        virtualIps = [{
          addr = "${config.services.k3s-server.vip}/24";
          dev = config.services.k3s-server.flannelIface;
        }];
        extraConfig = ''
          authentication {
              auth_type PASS
              auth_pass ''${VRRP_PASSWORD}
          }
        '';
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ 6443 10250 2379 2380 ];
      allowedUDPPorts = [ 8472 ];
    };
  };
}
