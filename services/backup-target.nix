{ config, pkgs, lib, ... }:
{
  options.services.backup-target = {
    enable = lib.mkEnableOption "borgbackup SSH server";
  };

  config = lib.mkIf config.services.backup-target.enable {
    users.users.borg = {
      isSystemUser = true;
      home = "/var/lib/borg";
      createHome = true;
      group = "borg";
      shell = pkgs.bash + "/bin/bash";
      openssh.authorizedKeys.keys = [
        # TODO: replace with actual backup source public keys, each prefixed with:
        # command="${pkgs.borgbackup}/bin/borg serve --restrict-to-path /var/lib/borg/repos",restrict
      ];
    };

    users.groups.borg = {};

    systemd.timers.borg-compact = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    systemd.services.borg-compact = {
      serviceConfig = {
        Type = "oneshot";
        User = "borg";
      };
      script = ''
        ${pkgs.borgbackup}/bin/borg compact /var/lib/borg/repos/*
      '';
    };

    networking.firewall.allowedTCPPorts = [ 22 ];
  };
}
