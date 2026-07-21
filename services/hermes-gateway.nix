{ config, pkgs, lib, inputs, ... }:

let
  cfg = config.services.hermes-gateway;
in
{
  options.services.hermes-gateway = {
    enable = lib.mkEnableOption "Hermes Agent gateway (Telegram bot)";

    hermesHome = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the directory containing all Hermes configuration:
        config.yaml, SOUL.md, skills/, platforms/, .env, auth.json, etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # System user for the service
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      home = "/var/lib/hermes";
      createHome = true;
      shell = "/run/current-system/sw/bin/nologin";
    };
    users.groups.hermes = {};

    # Runtime data directory (created by tmpfiles so systemd can create it before bind-mount)
    systemd.tmpfiles.rules = [
      "d /var/lib/hermes 0755 hermes hermes -"
    ];

    # systemd service
    systemd.services.hermes-gateway = {
      description = "Hermes Agent gateway (Telegram bot)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${inputs.llm-agents.packages.${pkgs.system}.hermes-agent}/bin/hermes gateway";
        User = "hermes";
        Group = "hermes";
        Restart = "on-failure";
        RestartSec = "5";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "true";
        PrivateTmp = true;
        MemoryMax = "2G";
        CPUQuota = "80%";
        BindPaths = [ "${cfg.hermesHome}:/var/lib/hermes" ];
        Environment = [ "HERMES_HOME=/var/lib/hermes" ];
        ReadWritePaths = [ "/var/lib/hermes" ];
      };
    };
  };
}
