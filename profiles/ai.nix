{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ../services/hermes-gateway.nix
    ../services/llama-server.nix
  ];

  services.hermes-gateway = {
    enable = true;
    hermesHome = ./hermes-config;
  };

  services.llama-server = {
    enable = true;
    instances.chat = {
      port = 11434;
      extraArgs = [ "-ngl" "99" "--backend" "vulkan" "-c" "8192" ];
    };
  };

  environment.systemPackages = [
    inputs.llm-agents.packages.${pkgs.system}.hermes-agent
  ];
}
