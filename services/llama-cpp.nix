{ config, pkgs, lib, ... }:

let
  cfg = config.services.llama-cpp;

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
  options.services.llama-cpp = {
    enable = lib.mkEnableOption "llama.cpp inference server (router mode)";

    instances = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule instanceModule);
      default = {};
      description = "One systemd service + open port per instance";
    };
  };
}
