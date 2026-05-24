{ config, pkgs, lib, ... }:
{
  options.services.monitoring-agent = {
    enable = lib.mkEnableOption "node exporter + promtail";
    lokiUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://loki:3100/loki/api/v1/push";
      description = "Loki push API URL";
    };
  };

  config = lib.mkIf config.services.monitoring-agent.enable {
    services.journald.extraConfig = "Storage=persistent";

    networking.firewall.allowedTCPPorts = [ 9100 9080 ];

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
      port = 9100;
    };

    services.promtail = {
      enable = true;
      configuration = {
        server = { http_listen_port = 9080; grpc_listen_port = 0; };
        positions = { filename = "/var/log/promtail-positions.yml"; };
        clients = [{ url = config.services.monitoring-agent.lokiUrl; }];
        scrape_configs = [{
          job_name = "journal";
          journal = { path = "/var/log/journal"; max_age = "12h"; };
          relabel_configs = [{
            source_labels = [ "__journal__hostname" ];
            target_label = "host";
          }];
        }];
      };
    };
  };
}
