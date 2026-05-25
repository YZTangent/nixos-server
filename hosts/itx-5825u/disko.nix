{ ... }: {
  imports = [
    ../../disko/os-ext4.nix
    (import ../../disko/zfs-raid.nix {
      diskCount = 4;
      mode = "raidz1";
      poolName = "tank";
    })
  ];
}
