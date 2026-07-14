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

    manifests = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options.source = lib.mkOption {
          type = lib.types.path;
          description = "Path to a manifest file or directory to auto-deploy via k3s";
        };
      });
      default = {};
      description = ''
        Manifest files or directories to symlink into /var/lib/rancher/k3s/server/manifests/.
        Keys are used to generate symlinks named nixos-managed-<key>.yaml. K3s applies all YAML
        files found there on startup. Filenames must be unique across all entries — k3s derives
        AddOn names from filenames and requires them to be unique across the full manifest tree.
      '';
    };

    builtinManifests = {
      dns = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Ship the bundled k8s/dns manifests. Disable to manage DNS outside k3s.";
        };
      };
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
      extraFlags = "--flannel-iface=${config.services.k3s-server.flannelIface} --tls-san=${config.services.k3s-server.vip}";
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

    # Derive node-ip at runtime: keepalived places the shared VIP on the same
    # interface as the node's own address, and k3s refuses to autodetect between
    # two global IPs. node-ip must stay out of Nix config so the same profile
    # runs unmodified on every compute node. Written as a config drop-in because
    # k3s merges config.yaml.d with CLI flags, and flags can't be computed here.
    systemd.services.k3s.preStart = lib.mkMerge [ (lib.mkBefore ''
      mkdir -p /etc/rancher/k3s/config.yaml.d
      node_ip=$(${pkgs.iproute2}/bin/ip -o -4 addr show dev ${config.services.k3s-server.flannelIface} scope global \
        | ${pkgs.gawk}/bin/awk '{split($4, a, "/"); print a[1]}' \
        | ${pkgs.gnugrep}/bin/grep -vx '${config.services.k3s-server.vip}' | head -n1)
      if [ -z "$node_ip" ]; then
        echo "k3s preStart: no non-VIP global IPv4 on ${config.services.k3s-server.flannelIface} yet" >&2
        exit 1
      fi
      printf 'node-ip: %s\n' "$node_ip" > /etc/rancher/k3s/config.yaml.d/node-ip.yaml
    '')
    (lib.mkAfter ''
      mkdir -p /var/lib/rancher/k3s/server/manifests
      rm -f /var/lib/rancher/k3s/server/manifests/nixos-managed-*
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: manifest: ''
        ln -sf ${pkgs.runCommand "k3s-manifest-${lib.strings.sanitizeDerivationName name}.yaml" {} ''
          if [ -d "${manifest.source}" ]; then
            # Ensure $out exists even if the directory has no manifests
            touch $out
            find "${manifest.source}" -type f \( -name '*.yaml' -o -name '*.yml' -o -name '*.json' \) -print0 \
              | sort -z \
              | while IFS= read -r -d "" file; do
                echo "---" >> $out
                cat "$file" >> $out
                echo "" >> $out
              done
          else
            cp "${manifest.source}" $out
          fi
        ''} "/var/lib/rancher/k3s/server/manifests/nixos-managed-${name}.yaml"
      '') config.services.k3s-server.manifests)}
    '') ];

    services.k3s-server.manifests = lib.mkIf config.services.k3s-server.builtinManifests.dns.enable {
      "dns".source = ../k8s/dns;
    };
  };
}
