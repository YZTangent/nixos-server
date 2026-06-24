# Fill in `profiles/ai.nix` with a llama.cpp inference service

## Problem

`profiles/ai.nix` is a skeleton (`{}: {}`) imported by `hosts/ai/default.nix` (strix-halo, AMD Ryzen AI Max+ 395). It currently contributes nothing to the host's configuration. The `ai` profile needs to actually deliver AI functionality: minimally, the ability to run self-hosted LLMs via llama.cpp.

## Solution

Introduce a NixOS service module `services/llama-cpp.nix` that runs llama.cpp's built-in `llama-server` as a single systemd service in **router mode** — the daemon starts with no model loaded and loads/unloads GGUF models on demand based on the `model` field of incoming OpenAI-compatible API requests. `profiles/ai.nix` imports the module and enables one instance targeting the Vulkan backend on strix-halo's Radeon 8060S iGPU.

Router mode removes the need to pin a `modelPath` or restart the service when models change. Operators drop GGUFs into a models directory (e.g. via the `hf` CLI) and reference them by filename/alias in API requests; the router spins up the right model on demand. The daemon is always healthy, serving nothing until a model is requested.

The module exposes an `instances` attrset so a second router process (e.g. a CPU-only instance for embeddings, or a future NPU instance when the XDNA driver lands in nixpkgs) can be added later as a one-liner — each instance = one router process with its own `modelsDir`/`port`/`backend`. This change ships the module plus one Vulkan chat instance.

Additionally, `profiles/ai.nix` installs [Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research's self-improving AI agent) as a CLI tool. Hermes is not packaged in nixpkgs, so it is consumed from the `numtide/llm-agents.nix` flake input. Hermes is installed on the system PATH only — no systemd service, no `~/.hermes/` provisioning. The operator runs `hermes setup` interactively over SSH to configure it (provider, messaging tokens, etc.) and launches `hermes` / `hermes gateway` manually in a tmux session or similar. This matches the user's stated intent: have the tool available on the host, wire up services later.

## Design

### 1. `services/llama-cpp.nix` (new)

A NixOS module following the existing flat `services/*.nix` convention (parallel to `services/k3s.nix`, `services/monitoring-agent.nix`). Exposes:

- `services.llama-cpp.enable` (bool, default `false`) — master switch.
- `services.llama-cpp.instances` (attrsOf submodule) — one systemd service + open port per entry. Each instance has:
  - `modelsDir` (path, default `"/var/lib/llama-cpp/models"`) — directory scanned by the router for GGUF files.
  - `port` (int, required) — TCP port for `llama-server` to listen on.
  - `host` (string, default `"0.0.0.0"`) — bind address.
  - `extraArgs` (list of strings, default `[]`) — backend flags passed through to `llama-server` (e.g. `-ngl 99`, `--backend vulkan`, `-c 8192`).
  - `user` (string, default `"llama"`) — unprivileged system user the service runs as.

Behavior when `enable = true`:

- Creates a `llama` system user (`isSystemUser`, no shell, home `/var/lib/llama-cpp`).
- Ensures `modelsDir` exists and is owned by the `llama` user (via `systemd.tmpfiles.rules`).
- For each instance `<name>`, declares `systemd.services.llama-cpp-<name>`:
  - `serviceConfig.ExecStart = "${pkgs.llama-cpp}/bin/llama-server --models-dir <modelsDir> --host <host> --port <port> <extraArgs...>"`.
  - `Restart = on-failure`, `WantedBy = ["multi-user.target"]`.
  - Hardening: `NoNewPrivileges`, `ProtectSystem = strict`, `PrivateTmp`, `ReadWritePaths = ["/var/lib/llama-cpp"]`.
- Opens each instance's port in `networking.firewall.allowedTCPPorts`.
- Installs `llama-cpp` built with `vulkanSupport = true` (full package — provides `llama-server`, `llama-cli`, `llama-bench`, `llama-quantize`, etc. on the system PATH for ad-hoc use) and `python3Packages.huggingface-hub` (provides the `hf` CLI for pulling GGUFs). The Vulkan-enabled `llama-cpp` is produced via a `config.allowUnfree`/package override in the module's `nixpkgs.config` or a `pkgs` overlay local to the module.

### 2. `flake.nix` changes

Add `llm-agents` as a flake input and pass it through `specialArgs` so modules can reference `inputs.llm-agents.packages.${pkgs.system}.hermes-agent`:

```nix
inputs = {
  # ... existing inputs ...
  llm-agents.url = "github:numtide/llm-agents.nix";
  llm-agents.inputs.nixpkgs.follows = "nixpkgs";
};
```

And in each `nixosSystem` call (or globally in the `outputs` attrset), `specialArgs = { inherit inputs; };` already exists — `inputs.llm-agents` is reachable from any module that takes `inputs` as an argument. No per-host `specialArgs` change needed since the existing `specialArgs = { inherit inputs; }` already passes the whole `inputs` set.

### 3. `profiles/ai.nix` (rewrite)

```nix
{ config, pkgs, lib, inputs, ... }:
{
  imports = [ ../services/llama-cpp.nix ];

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
```

- `profiles/ai.nix` now takes `inputs` as an argument (matching `hosts/ai/default.nix` which already receives `inputs` via `specialArgs`).
- Port `11434` (Ollama's default port) — recognizable as "the LLM port" and unlikely to collide with anything else on strix-halo.
- `modelsDir` defaults to `/var/lib/llama-cpp/models` — no per-instance override needed.
- The daemon starts healthy with an empty models dir. After first boot the operator drops real GGUFs in via `hf download ... --local-dir /var/lib/llama-cpp/models/` and references them by filename in API requests; no service restart required.
- Hermes is installed on the system PATH. No `~/.hermes/` provisioning, no systemd service — the operator runs `hermes setup` interactively over SSH (as their own user) to configure it, then launches `hermes` in a tmux session.
- Storage fallback to NFS is not pre-wired. The module takes an absolute path, so pointing `modelsDir` at an NFS mount later (when local disk is tight) is a one-line per-host override with no module edit.

### 4. Out of scope (explicit)

- **NPU/XDNA backend** — the XDNA driver + userspace is not in nixpkgs stable yet. Revisit when it lands; adding an NPU instance then is a one-liner via `instances.<name>.extraArgs`.
- **Additional llama.cpp instances** (embeddings, second chat model on CPU) — the module supports them via the `instances` attrset; this change declares only the Vulkan chat instance.
- **Auto-download of a default model** — the operator pulls GGUFs manually with the `hf` CLI (installed by the module). No HuggingFace token needs to live in sops right now.
- **Ollama** — not installed; `llama-server` covers the OpenAI-compatible REST API need.
- **k8s manifests** — llama.cpp runs as a host systemd service on strix-halo. k3s pods on other nodes reach it over the LAN at `strix-halo:11434`.
- **Hermes as a service** — hermes is installed on PATH only. Wiring it up as a systemd service (gateway, cron, dashboard) with sops-managed config is a separate future change.
- **Hermes config provisioning** — no `~/.hermes/` provisioning, no sops secrets for hermes. The operator runs `hermes setup` interactively after first boot.

## Usage

1. Deploy the `ai` (or `first-ai`) configuration to strix-halo.
2. After first boot, `ssh` in and pull GGUFs, e.g.:
   ```
   hf download <org>/<repo> <file.gguf> --local-dir /var/lib/llama-cpp/models/
   ```
3. The router picks them up automatically — no service restart.
4. Hit the OpenAI-compatible API from any LAN host or k3s pod:
   ```
   curl http://strix-halo:11434/v1/chat/completions \
     -H "Content-Type: application/json" \
     -d '{"model":"<file.gguf>","messages":[{"role":"user","content":"hi"}]}'
   ```
5. To use Hermes: `ssh` in as your user, run `hermes setup` to configure provider/model/messaging, then `hermes` to start chatting. Point it at the local llama-server by setting the provider to OpenAI-compatible with base URL `http://127.0.0.1:11434/v1`.

## Related spec / ADR

- Updates `docs/prd/2026-05-25-nixos-server-config.md` — adds the `ai` profile and `services/llama-cpp.nix` to the inventory/structure.
- New ADR `docs/adr/0004-llama-cpp-as-host-systemd-service.md` — records why llama.cpp runs as a host systemd service in router mode rather than a k3s workload, and why Vulkan over NPU for now.
