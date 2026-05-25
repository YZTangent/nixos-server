{ diskCount ? 4, mode ? "raidz1", poolName ? "tank" }:
{
  disko.devices = {
    disk = builtins.listToAttrs (builtins.genList (i: {
      name = "data${toString (i + 1)}";
      value = {
        type = "disk";
        device = "$DISK_DATA${toString (i + 1)}";
        content = {
          type = "gpt";
          partitions = {
            zfs = {
              size = "100%";
              content = { type = "zfs"; };
            };
          };
        };
      };
    }) diskCount);
    zpool = {
      "${poolName}" = {
        type = "zpool";
        mode = mode;
        options = {
          ashift = "12";
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        datasets = {
          data = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/data";
            options."com.sun:auto-snapshot" = "true";
          };
          media = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/media";
            options."com.sun:auto-snapshot" = "true";
          };
          backups = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/backups";
          };
          containers = {
            type = "zfs_fs";
            mountpoint = "/var/lib/${poolName}/containers";
          };
        };
      };
    };
  };
}
