{ config, pkgs, lib, ... }:

let
  cfg = config.services.llama-server;

  instanceModule = { name, config, ... }: {
    options = {
      modelsDir = lib.mkOption {
        type = lib.types.str;
        default = "/var/lib/llama-cpp/models";
        description = "Directory scanned by the router for GGUF model files";
      };
      port = lib.mkOption {
        type = lib.types.port;
        description = "TCP port for llama-server to listen on";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "0.0.0.0";
        description = "Bind address";
      };
      modelsPreset = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to INI preset file for router mode. When set, replaces --models-dir.";
      };
      bindReadOnlyPaths = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "src:dst bind-mounts (read-only) set up by systemd as root in the service namespace, for reaching paths the service user cannot traverse directly (see ADR-0008).";
      };
      extraArgs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        description = "Extra CLI flags passed to llama-server (e.g. backend, -ngl, -c)";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "llama";
        description = "Unprivileged system user the service runs as";
      };
    };
  };
in
{
  options.services.llama-server = {
    enable = lib.mkEnableOption "llama.cpp inference server (router mode)";

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = {};
      description = "One systemd service + open port per instance";
    };
  };

  config = lib.mkIf cfg.enable {
    # Build llama-cpp with Vulkan support for the Radeon 8060S iGPU
    nixpkgs.overlays = [
      (final: prev: {
        llama-cpp-vulkan = prev.llama-cpp.override { vulkanSupport = true; };
      })
    ];

    environment.systemPackages = with pkgs; [
      llama-cpp-vulkan
      python3Packages.huggingface-hub
    ];

    users.users.llama = {
      isSystemUser = true;
      group = "llama";
      home = "/var/lib/llama-cpp";
      createHome = true;
      shell = "/run/current-system/sw/bin/nologin";
    };
    users.groups.llama = {};

    systemd.tmpfiles.rules = [
      "d /var/lib/llama-cpp/models 0755 llama llama -"
    ];

    networking.firewall.allowedTCPPorts =
      lib.mapAttrsToList (_: i: i.port) cfg.instances;

    systemd.services = lib.mapAttrs' (name: inst:
      lib.nameValuePair "llama-cpp-${name}" {
        description = "llama.cpp inference server (instance: ${name})";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${pkgs.llama-cpp-vulkan}/bin/llama-server "
                    + lib.concatStringsSep " " (
                        (if inst.modelsPreset != null
                         then [ "--models-preset" inst.modelsPreset ]
                         else [ "--models-dir" inst.modelsDir ])
                        ++ [ "--host" inst.host "--port" (toString inst.port) ]
                        ++ inst.extraArgs);
          User = inst.user;
          Group = "llama";
          Restart = "on-failure";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          PrivateTmp = true;
          ReadWritePaths = [ "/var/lib/llama-cpp" ];
          BindReadOnlyPaths = inst.bindReadOnlyPaths;
        };
      }
    ) cfg.instances;
  };
}
