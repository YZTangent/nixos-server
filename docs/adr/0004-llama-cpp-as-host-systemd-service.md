# Run llama.cpp as a host systemd service in router mode; install Hermes via llm-agents.nix flake input

llama.cpp's `llama-server` runs as a host systemd service on strix-halo (not as a k3s workload), in router mode (no pinned `-m`). Models are configured via `--models-preset` pointing to a live INI file tracked in the dotfiles repo (see ADR-0008); the original `--models-dir` approach was replaced to give explicit per-model control over paths and context sizes. Models load on demand based on the `model` field of OpenAI-compatible API requests, with no service restart.

This choice gives the daemon direct host access to the Vulkan backend (Radeon 8060S iGPU) without container passthrough complexity, and lets models be added/removed at runtime without redeploying. The trade-off is that llama.cpp state lives outside the k3s cluster — it's reachable at `strix-halo:11434` over the LAN rather than as a k8s Service, and the configuration is NixOS-native rather than a k8s manifest.

Vulkan is chosen over the Ryzen AI NPU (XDNA) for now because the XDNA driver and userspace are not yet in nixpkgs stable. The module's `extraArgs` makes adding an NPU instance a one-liner once the driver lands.

Hermes Agent (Nous Research) is installed as a CLI tool only — no systemd service. It is not packaged in nixpkgs, so it is consumed from the `numtide/llm-agents.nix` flake input (a daily-updated collection of AI tooling packages). This is preferred over vendoring a custom derivation or using Hermes's own installer script, which would bypass Nix's purity guarantees. Wiring Hermes up as a managed service with sops-managed config is deferred to a future change.
