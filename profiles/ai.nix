{ config, pkgs, lib, inputs, ... }:
{
  imports = [
    ../services/llama-cpp.nix
  ];

  services.llama-cpp = {
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
