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
  };

  config = lib.mkIf config.services.k3s-server.enable {
    sops.secrets."k3s-token".restartUnits = [ "k3s.service" ];

    environment.systemPackages = with pkgs; [ k3s nfs-utils ];

    services.k3s = {
      enable = true;
      role = "server";
      tokenFile = config.sops.secrets."k3s-token".path;
      serverAddr = config.services.k3s-server.serverAddr;
      extraFlags = "--flannel-iface=${config.services.k3s-server.flannelIface}";
    };

    networking.firewall = {
      allowedTCPPorts = [ 6443 10250 2379 2380 ];
      allowedUDPPorts = [ 8472 ];
    };
  };
}
