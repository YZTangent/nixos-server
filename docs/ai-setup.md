# AI Profile Setup Guide

Guide for using the llama.cpp inference service and Hermes Agent on strix-halo (the `ai` profile host).

## Prerequisites

- strix-halo deployed with the `ai` (or `first-ai`) configuration
- SSH access to strix-halo as your user

## llama.cpp Inference Service

The `llama-server` daemon runs in router mode — it starts healthy with an empty models directory and loads GGUF models on demand based on the `model` field of API requests. No service restart is needed when adding or removing models.

### Pull a model

SSH into strix-halo and use the `hf` CLI (installed system-wide) to download GGUF files:

```bash
ssh yztangent@strix-halo
hf download <org>/<repo> <file.gguf> --local-dir /var/lib/llama-cpp/models/
```

Example:

```bash
hf download NousResearch/Hermes-3-Llama-3.1-8B-GGUF Hermes-3-Llama-3.1-8B.Q4_K_M.gguf --local-dir /var/lib/llama-cpp/models/
```

The `llama` system user owns the models directory. If you get a permission error, fix ownership:

```bash
sudo chown -R llama:llama /var/lib/llama-cpp/models/
```

### Query the API

The OpenAI-compatible API is available on the LAN at `http://strix-halo:11434/v1/...`:

```bash
curl http://strix-halo:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Hermes-3-Llama-3.1-8B.Q4_K_M.gguf",
    "messages": [{"role": "user", "content": "hello"}]
  }'
```

The `model` field is the filename of the GGUF in `/var/lib/llama-cpp/models/`. The router loads it on demand.

### Swap models

Drop a new GGUF into `/var/lib/llama-cpp/models/` and reference it by filename in the next API request. Remove a GGUF to stop serving it. No restart needed.

### Service management

```bash
sudo systemctl status llama-cpp-chat    # check status
sudo systemctl restart llama-cpp-chat   # restart if needed
journalctl -u llama-cpp-chat -f         # tail logs
```

### Ad-hoc CLI tools

The `llama-cpp` package is installed on the system PATH, giving you `llama-cli`, `llama-bench`, `llama-quantize`, etc. for ad-hoc use:

```bash
llama-bench -m /var/lib/llama-cpp/models/<file.gguf> --backend vulkan
```

## Hermes Agent

Hermes Agent (Nous Research) is installed on the system PATH as `hermes`. It is not run as a service — configure and launch it interactively.

### First-time setup

```bash
ssh yztangent@strix-halo
hermes setup
```

This runs the setup wizard to configure:
- LLM provider and model
- API keys
- Messaging platform tokens (Telegram, Discord, etc.) — optional
- Tools and toolsets

### Use the local llama.cpp backend

During `hermes setup` (or via `hermes model` after), set the provider to an OpenAI-compatible endpoint pointing at the local llama-server:

- **Provider:** OpenAI-compatible
- **Base URL:** `http://127.0.0.1:11434/v1`
- **Model:** the filename of a GGUF in `/var/lib/llama-cpp/models/`
- **API key:** any non-empty string (llama-server doesn't require one)

### Start Hermes

```bash
hermes              # interactive TUI
hermes gateway      # start the messaging gateway (Telegram/Discord/etc.)
```

For long-running sessions, use a terminal multiplexer:

```bash
tmux new -s hermes
hermes
# detach with Ctrl+B then D
tmux attach -t hermes
```

## Backends

The current configuration uses the **Vulkan** backend (targeting the Radeon 8060S iGPU). The NPU (XDNA) backend is not yet available in nixpkgs stable; when it lands, add an NPU instance via `services.llama-server.instances.<name>.extraArgs`.

To run a second instance with a different backend (e.g. CPU for embeddings), add another entry to `services.llama-server.instances` in `profiles/ai.nix`:

```nix
services.llama-server = {
  enable = true;
  instances.chat = {
    port = 11434;
    extraArgs = [ "-ngl" "99" "--backend" "vulkan" "-c" "8192" ];
  };
  instances.embeddings = {
    port = 11435;
    extraArgs = [ "--backend" "cpu" "-c" "2048" ];
  };
};
```
