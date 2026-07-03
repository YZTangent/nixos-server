# NixOS Headless Server Cluster — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a single-flake NixOS configuration for a multi-node cluster (Thinkpad compute + ITX 5825U NAS) with k3s orchestration and NixOS-managed storage services.

**Architecture:** Monorepo flake with `hosts/` per machine, `profiles/` for composable machine roles (base, compute, nas), and `services/` for individual NixOS modules. NAS and compute are non-intersecting profiles. k3s replaces podman as the container runtime — every node with the `compute` profile runs a k3s server (control plane + worker). Storage services (file sharing, media, backup) are native NixOS services, not k8s.

**Tech Stack:** NixOS 25.05, k3s, sops-nix, Samba, borgbackup, Jellyfin, AdGuard Home (optional k8s deploy)

---

### Task 1: Scaffold flake, directory tree, and base profile

**Files:**
- Create: `flake.nix`
- Create: `docs/adr/0001-sops-nix-for-secrets.md` (already exists)
- Create: `docs/adr/0002-k3s-as-container-orchestrator.md` (already exists)
- Create: `profiles/base.nix`
- Create: `hosts/thinkpad/default.nix`
- Create: `hosts/thinkpad/hardware.nix`
- Create: `hosts/itx-5825u/default.nix`
- Create: `hosts/itx-5825u/hardware.nix`

- [ ] **Step 1: Create the directory tree**

```bash
mkdir -p hosts/thinkpad hosts/itx-5825u profiles services secrets k8s/dns
```

- [ ] **Step 2: Write `flake.nix`**

```nix
{
  description = "NixOS headless server cluster";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, ... } @ inputs: {
    nixosConfigurations = {
      thinkpad = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/thinkpad ];
        specialArgs = { inherit inputs; };
      };
      itx-5825u = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/itx-5825u ];
        specialArgs = { inherit inputs; };
      };
    };
  };
}
```

- [ ] **Step 3: Write `profiles/base.nix`**

```nix
{ config, pkgs, lib, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  # Locale
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "UTC";
  console.font = "Lat2-Terminus16";
  console.keyMap = "us";

  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
    };
  };

  # Admin user
  users.users.yztangent = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      # TODO: add your public key
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # sops-nix
  sops = {
    defaultSopsFile = ../../secrets/${config.networking.hostName}.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";
  };

  # Trusted caches
  nix.settings.trusted-users = [ "yztangent" ];
  nix.settings.substituters = [ "https://cache.nixos.org" ];

  # Allow unfree where needed
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "jellyfin-ffmpeg"
  ];

  system.stateVersion = "25.05";
}
```

- [ ] **Step 4: Write placeholder `hardware.nix` for each host**

`hosts/thinkpad/hardware.nix`:
```nix
{ ... }:
{
  imports = [
    # Replace this with output of `nixos-generate-config --show-hardware-config`
    <nixpkgs/nixos/modules/hardware/network/broadcom-43xx.nix>
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

`hosts/itx-5825u/hardware.nix`:
```nix
{ ... }:
{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
```

- [ ] **Step 5: Write `hosts/thinkpad/default.nix`**

```nix
{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/base
    ../../profiles/compute
  ];
}
```

`hosts/itx-5825u/default.nix`:
```nix
{ inputs, ... }:
{
  imports = [
    ./hardware.nix
    ../../profiles/base
    ../../profiles/compute
    ../../profiles/nas
  ];
}
```

- [ ] **Step 6: Verify flake evaluates**

Run: `nix flake check`
Expected: No errors (or only warnings about missing inputs).

- [ ] **Step 7: Commit**

```bash
git add flake.nix profiles/ hosts/
git commit -m "feat: scaffold flake, base profile, and host stubs"
```

---

### Task 2: k3s service module

**Files:**
- Create: `services/k3s.nix`

- [ ] **Step 1: Write `services/k3s.nix`**

```nix
{ config, pkgs, lib, ... }:
{
  options.services.k3s-server = {
    enable = lib.mkEnableOption "k3s server node";
    serverAddr = lib.mkOption {
      type = lib.types.str;
      default = "https://127.0.0.1:6443";
      description = "Address of the initial k3s server for cluster join";
    };
  };

  config = lib.mkIf config.services.k3s-server.enable {
    sops.secrets."k3s-token".sopsFile = ../../secrets/${config.networking.hostName}.yaml;

    environment.systemPackages = with pkgs; [ k3s nfs-utils ];

    services.k3s = {
      enable = true;
      role = "server";
      tokenFile = config.sops.secrets."k3s-token".path;
      serverAddr = config.services.k3s-server.serverAddr;
      extraFlags = "--flannel-iface=eth0";
    };

    networking.firewall = {
      allowedTCPPorts = [ 6443 10250 2379 2380 ];
      allowedUDPPorts = [ 8472 ];
    };
  };
}
```

- [ ] **Step 2: Add secret stub to `secrets/`**

Create `secrets/.gitkeep` (empty) — the actual encrypted secrets are generated per-host.

- [ ] **Step 3: Verify flake evaluates**

Run: `nix flake check`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add services/k3s.nix secrets/
git commit -m "feat: add k3s server service module"
```

---

### Task 3: Compute profile

**Files:**
- Create: `profiles/compute.nix`
- Create: `services/monitoring-agent.nix`

- [ ] **Step 1: Write `services/monitoring-agent.nix`**

```nix
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
```

- [ ] **Step 2: Write `profiles/compute.nix`**

```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/k3s.nix
    ../services/monitoring-agent.nix
  ];

  services.k3s-server = {
    enable = true;
    serverAddr = "https://10.0.0.1:6443";  # TODO: set to actual first node IP
  };

  services.monitoring-agent.enable = true;
}
```

- [ ] **Step 3: Verify flake evaluates**

Run: `nix flake check`
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add profiles/compute.nix services/monitoring-agent.nix
git commit -m "feat: add compute profile with k3s and monitoring"
```

---

### Task 4: NAS service modules

**Files:**
- Create: `services/file-sharing.nix`
- Create: `services/media-stack.nix`
- Create: `services/backup-target.nix`
- Create: `profiles/nas.nix`

- [ ] **Step 1: Write `services/file-sharing.nix`**

```nix
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
```

- [ ] **Step 2: Write `services/media-stack.nix`**

```nix
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
```

- [ ] **Step 3: Write `services/backup-target.nix`**

```nix
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
      shell = pkgs.borgbackup + "/bin/borg serve --restrict-to-path /var/lib/borg/repos";
      openssh.authorizedKeys.keys = [
        # TODO: add backup source public keys
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
```

- [ ] **Step 4: Write `profiles/nas.nix`**

```nix
{ config, pkgs, lib, ... }:
{
  imports = [
    ../services/file-sharing.nix
    ../services/media-stack.nix
    ../services/backup-target.nix
  ];

  services.file-sharing.enable = true;
  services.media-stack.enable = true;
  services.backup-target.enable = true;
}
```

- [ ] **Step 5: Verify flake evaluates**

Run: `nix flake check`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add services/file-sharing.nix services/media-stack.nix services/backup-target.nix profiles/nas.nix
git commit -m "feat: add NAS profile with file sharing, media, backup services"
```

---

### Task 5: AdGuard Home k8s manifests (optional DNS)

**Files:**
- Create: `k8s/dns/namespace.yaml`
- Create: `k8s/dns/pvc.yaml`
- Create: `k8s/dns/deployment.yaml`
- Create: `k8s/dns/service.yaml`

- [ ] **Step 1: Write `k8s/dns/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: dns
```

- [ ] **Step 2: Write `k8s/dns/pvc.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: adguard-data
  namespace: dns
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

- [ ] **Step 3: Write `k8s/dns/deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: adguard-home
  namespace: dns
spec:
  replicas: 1
  selector:
    matchLabels:
      app: adguard-home
  template:
    metadata:
      labels:
        app: adguard-home
    spec:
      containers:
      - name: adguard
        image: adguard/adguardhome:latest
        ports:
        - containerPort: 53
          protocol: UDP
        - containerPort: 53
          protocol: TCP
        - containerPort: 3000
        volumeMounts:
        - name: data
          mountPath: /opt/adguardhome/work
        - name: conf
          mountPath: /opt/adguardhome/conf
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: adguard-data
      - name: conf
        emptyDir: {}
```

- [ ] **Step 4: Write `k8s/dns/service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: adguard-home
  namespace: dns
spec:
  type: NodePort
  ports:
  - port: 53
    targetPort: 53
    protocol: UDP
    name: dns-udp
  - port: 53
    targetPort: 53
    protocol: TCP
    name: dns-tcp
  - port: 3000
    targetPort: 3000
    protocol: TCP
    name: admin
  selector:
    app: adguard-home
```

- [ ] **Step 5: Commit**

```bash
git add k8s/dns/
git commit -m "feat: add AdGuard Home k8s manifests for optional DNS"
```

---

### Task 6: sops-nix secrets and finalize

**Files:**
- Create: `secrets/.sops.yaml`
- Modify: `hosts/thinkpad/hardware.nix` (real hardware config)
- Modify: `hosts/itx-5825u/hardware.nix` (real hardware config)

- [ ] **Step 1: On each machine, generate age key**

```bash
# Run on each machine
sudo mkdir -p /var/lib/sops-nix
nix shell nixpkgs#age -c age-keygen -o /var/lib/sops-nix/key.txt
nix shell nixpkgs#age -c age-keygen -y /var/lib/sops-nix/key.txt
```

Record the public key output.

- [ ] **Step 2: Write `secrets/.sops.yaml`**

```yaml
keys:
  - &thinkpad age1abc...  # replace with actual thinkpad public key
  - &itx age1def...       # replace with actual itx public key

creation_rules:
  - path_regex: secrets/thinkpad.yaml$
    key_groups:
      - age:
        - *thinkpad
  - path_regex: secrets/itx-5825u.yaml$
    key_groups:
      - age:
        - *itx
```

- [ ] **Step 3: Generate encrypted secret files**

```bash
# Create stub secrets, then encrypt
echo "k3s-token: $(openssl rand -hex 32)" > secrets/thinkpad-plain.yaml
sops --encrypt secrets/thinkpad-plain.yaml > secrets/thinkpad.yaml
rm secrets/thinkpad-plain.yaml

echo "k3s-token: $(openssl rand -hex 32)" > secrets/itx-plain.yaml
sops --encrypt secrets/itx-plain.yaml > secrets/itx-5825u.yaml
rm secrets/itx-plain.yaml
```

Note: Both machines need the **same** k3s token to join the same cluster. Decide on a single shared token, or set `serverAddr` on the second node to point at the first.

- [ ] **Step 4: Replace placeholder hardware configs**

Run `nixos-generate-config --show-hardware-config` on each machine and replace `hosts/*/hardware.nix` with the output.

- [ ] **Step 5: Final flake check**

Run: `nix flake check`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add secrets/ hosts/thinkpad/hardware.nix hosts/itx-5825u/hardware.nix
git commit -m "feat: add encrypted secrets and hardware configs"
```
