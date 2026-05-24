{ config, pkgs, lib, ... }:
{
  options.services.file-sharing = {
    enable = lib.mkEnableOption "NFS and Samba file sharing";
  };

  config = lib.mkIf config.services.file-sharing.enable {
    services.nfs.server = {
      enable = true;
      exports = ''
        /data 10.0.0.0/24(rw,sync,no_subtree_check,no_root_squash)
      '';
    };

    services.samba = {
      enable = true;
      openFirewall = true;
      settings = {
        global = {
          workgroup = "WORKGROUP";
          "server string" = "nas";
          "netbios name" = "nas";
          security = "user";
          "map to guest" = "never";
        };
        media = {
          path = "/data/media";
          browseable = "yes";
          "read only" = "no";
          "guest ok" = "no";
          "valid users" = "yztangent";
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 2049 111 139 445 ];
    networking.firewall.allowedUDPPorts = [ 111 137 138 2049 ];

    systemd.services.samba-smbd = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };
  };
}
