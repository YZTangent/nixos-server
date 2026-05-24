{ config, pkgs, lib, ... }:
let
  ports = {
    sonarr = 8989;
    radarr = 7878;
    lidarr = 8686;
    readarr = 8787;
    transmission = 9091;
  };
in
{
  options.services.media-stack = {
    enable = lib.mkEnableOption "Jellyfin, *arr, and torrent client";
  };

  config = lib.mkIf config.services.media-stack.enable {
    services.jellyfin = {
      enable = true;
      openFirewall = true;
    };

    services.sonarr = {
      enable = true;
      openFirewall = true;
      user = "sonarr";
      group = "sonarr";
      dataDir = "/data/media/.arr/sonarr";
    };

    services.radarr = {
      enable = true;
      openFirewall = true;
      user = "radarr";
      group = "radarr";
      dataDir = "/data/media/.arr/radarr";
    };

    services.lidarr = {
      enable = true;
      openFirewall = true;
      user = "lidarr";
      group = "lidarr";
      dataDir = "/data/media/.arr/lidarr";
    };

    services.readarr = {
      enable = true;
      openFirewall = true;
      user = "readarr";
      group = "readarr";
      dataDir = "/data/media/.arr/readarr";
    };

    services.transmission = {
      enable = true;
      openFirewall = true;
      settings = {
        download-dir = "/data/media/torrents/incomplete";
        incomplete-dir = "/data/media/torrents/incomplete";
        rpc-whitelist = "127.0.0.1,10.0.0.*";
      };
    };

    networking.firewall.allowedTCPPorts = builtins.attrValues ports;
  };
}
