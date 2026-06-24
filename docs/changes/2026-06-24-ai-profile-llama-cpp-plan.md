# AI Profile llama.cpp Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fill in `profiles/ai.nix` with a llama.cpp inference service (router mode, Vulkan) and install Hermes Agent as a CLI tool.

**Architecture:** A new NixOS service module `services/llama-cpp.nix` runs `llama-server` as a systemd service in router mode — no model pinned, GGUFs dropped into `/var/lib/llama-cpp/models/` are loaded on demand by the `model` field of OpenAI-compatible API requests. The `llama-cpp` package is built with `vulkanSupport = true` via a local overlay. Hermes Agent is installed on the system PATH from the `numtide/llm-agents.nix` flake input (no service). `profiles/ai.nix` imports the module, declares one Vulkan chat instance on port `11434`, and adds `hermes-agent` to `environment.systemPackages`.

**Tech Stack:** NixOS, llama.cpp (nixpkgs `llama-cpp` with Vulkan), systemd, `numtide/llm-agents.nix` flake input

---

### Task 1: Add `llm-agents.nix` flake input

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1.1: Add the input**

Add to the `inputs` attrset in `flake.nix`, after the `nixos-anywhere` input block:

```nix
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 1.2: Verify flake evaluates**

Run: `nix flake lock --update-input llm-agents`
Expected: command exits 0, `flake.lock` gains an `llm-agents` node.

Run: `nix eval .#nixosConfigurations.ai.config.system.build.toplevel.drvPath 2>&1 | head -5`
Expected: no "input not found" error. (Full eval may fail on missing `ai` host in flake outputs if the k3s-VIP change hasn't added it yet — that's fine, we're only checking that the flake input resolves. If `ai` is already present, eval should succeed up to missing-profile symbols introduced by later tasks.)

- [ ] **Step 1.3: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat: add numtide/llm-agents.nix flake input"
```

---

### Task 2: Create `services/llama-cpp.nix` service module — options

**Files:**
- Create: `services/llama-cpp.nix`

- [ ] **Step 2.1: Write the module skeleton with options**

Create `services/llama-cpp.nix` with the following exact content:

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.services.llama-cpp;

  instanceModule = { name, config, ... }: {
    options = {
      modelsDir = lib.mkOption {
        type = lib.types.path;
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
```

- [ ] **Step 2.2: Verify it parses**

Run: `nix eval --file services/llama-cpp.nix 2>&1 | head -10`
Expected: no parse errors (it'll complain about missing module system context, but shouldn't be a syntax error).

- [ ] **Step 2.3: Commit**

```bash
git add services/llama-cpp.nix
git commit -m "feat: add llama-cpp service module options"
```

---

### Task 3: Add Vulkan-enabled `llama-cpp` overlay and package install to the module

**Files:**
- Modify: `services/llama-cpp.nix`

- [ ] **Step 3.1: Add the overlay and config block**

Append to `services/llama-cpp.nix` (after the `options` block, before the closing `}` of the top-level module). The Vulkan-enabled package is produced via `pkgs.llama-cpp.override { vulkanSupport = true; }` — no separate overlay file is needed since the module is the only consumer:

```nix

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
  };
}
```

- [ ] **Step 3.2: Verify the package override builds**

Run: `nix-build -E 'with import <nixpkgs> {}; llama-cpp.override { vulkanSupport = true; }' --dry-run 2>&1 | tail -10`
Expected: no errors. Dry-run just lists what would build. If it succeeds, the override flag is valid for this nixpkgs revision.

- [ ] **Step 3.3: Commit**

```bash
git add services/llama-cpp.nix
git commit -m "feat: add Vulkan overlay, llama user, packages, firewall to llama-cpp module"
```

---

### Task 4: Generate systemd services from `instances`

**Files:**
- Modify: `services/llama-cpp.nix`

- [ ] **Step 4.1: Add `systemd.services` generation**

Insert this block into `services/llama-cpp.nix`'s `config` attrset (right after `networking.firewall.allowedTCPPorts = ...`):

```nix

    systemd.services = lib.mapAttrs' (name: inst:
      lib.nameValuePair "llama-cpp-${name}" {
        description = "llama.cpp inference server (instance: ${name})";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          ExecStart = "${pkgs.llama-cpp-vulkan}/bin/llama-server "
                    + lib.concatStringsSep " " ([
                      "--models-dir" (toString inst.modelsDir)
                      "--host" inst.host
                      "--port" (toString inst.port)
                    ] ++ inst.extraArgs);
          User = inst.user;
          Group = "llama";
          Restart = "on-failure";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          PrivateTmp = true;
          ReadWritePaths = [ "/var/lib/llama-cpp" ];
        };
      }
    ) cfg.instances;
```

- [ ] **Step 4.2: Verify module evaluates standalone**

Run: `nix-instantiate --parse services/llama-cpp.nix > /dev/null && echo OK`
Expected: prints `OK` (syntax check).

- [ ] **Step 4.3: Commit**

```bash
git add services/llama-cpp.nix
git commit -m "feat: generate per-instance systemd services in llama-cpp module"
```

---

### Task 5: Rewrite `profiles/ai.nix`

**Files:**
- Modify: `profiles/ai.nix`

- [ ] **Step 5.1: Replace the skeleton with the real profile**

Overwrite `profiles/ai.nix` with this exact content:

```nix
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
```

- [ ] **Step 5.2: Commit**

```bash
git add profiles/ai.nix
git commit -m "feat: wire up llama-cpp + hermes-agent in ai profile"
```

---

### Task 6: Add `ai` host to the flake outputs (if not already present)

**Files:**
- Modify: `flake.nix`

- [ ] **Step 6.1: Check if `ai` is already a nixosConfiguration**

Run: `nix eval .#nixosConfigurations.ai.config.system.build.toplevel.drvPath 2>&1 | head -3`

If this succeeds (prints a derivation path), `ai` is already wired up — skip this task entirely.

If it errors with "attribute 'ai' missing", continue to Step 6.2.

- [ ] **Step 6.2: Add the `ai` output**

Add this entry to `nixosConfigurations` in `flake.nix`, after the `storage` entry:

```nix
      ai = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ ./hosts/ai ];
        specialArgs = { inherit inputs; };
      };
```

- [ ] **Step 6.3: Commit (only if changed)**

```bash
git add flake.nix
git commit -m "feat: add ai host to flake outputs"
```

---

### Task 7: Build the full system configuration

**Files:** (none — verification task)

- [ ] **Step 7.1: Build the `ai` configuration**

Run: `nix build .#nixosConfigurations.ai.config.system.build.toplevel --dry-run 2>&1 | tail -20`
Expected: command exits 0, lists derivation paths to build/download. Any eval error here means a bug in the module — read the error, fix, re-run.

- [ ] **Step 7.2: Actually build it (not just dry-run)**

Run: `nix build .#nixosConfigurations.ai.config.system.build.toplevel 2>&1 | tail -20`
Expected: command exits 0, produces a `result` symlink. This will take a while (llama-cpp with Vulkan is a real compile).

If the build fails on `llama-cpp-vulkan`:
- Check the override is spelled correctly (`vulkanSupport = true` matches the package.nix arg name — verify by reading `/nix/store/*-source/pkgs/by-name/ll/llama-cpp/package.nix` line 36).
- Check that `vulkan-loader`, `shaderc`, `vulkan-headers`, `spirv-headers` are transitively pulled (they should be — they're in `vulkanBuildInputs` of the package).

- [ ] **Step 7.3: No commit (build artifact)**

`result/` is gitignored (or should be — verify `.gitignore` contains `result`). If not, add it:

```bash
grep -q '^result$' .gitignore || echo 'result' >> .gitignore
git add .gitignore
git commit -m "chore: gitignore nix build result"
```

---

### Task 8: Sanity-check the activation script

**Files:** (none — verification)

- [ ] **Step 8.1: Inspect what would be activated**

Run: `nix build .#nixosConfigurations.ai.config.system.build.toplevel --out-link /tmp/ai-toplevel 2>&1 | tail -5 && ls /tmp/ai-toplevel/`
Expected: directory containing `activate`, `init`, etc.

- [ ] **Step 8.2: Check the systemd unit is generated**

Run: `ls /tmp/ai-toplevel/etc/systemd/system/ | grep llama-cpp`
Expected: prints `llama-cpp-chat.service`.

If empty: the `systemd.services` map isn't being evaluated. Check that `services.llama-cpp.enable = true` and `instances.chat` is set in `profiles/ai.nix`, and that `hosts/ai/default.nix` imports `profiles/ai.nix`.

- [ ] **Step 8.3: Check the ExecStart is correct**

Run: `grep ExecStart /tmp/ai-toplevel/etc/systemd/system/llama-cpp-chat.service`
Expected: a line containing `llama-server --models-dir /var/lib/llama-cpp/models --host 0.0.0.0 --port 11434 -ngl 99 --backend vulkan -c 8192`.

If `--models-dir` shows a different path, the `toString` of the default `lib.types.path` value produced something unexpected — switch the option type to `lib.types.str` and the default to a plain string `"/var/lib/llama-cpp/models"`.

- [ ] **Step 8.4: Check hermes-agent is in the system PATH**

Run: `ls /tmp/ai-toplevel/sw/bin/ | grep -E '^hermes$'`
Expected: prints `hermes`.

If empty: the `inputs.llm-agents.packages.${pkgs.system}.hermes-agent` reference didn't resolve. Check that `flake.nix` has the `llm-agents` input and that `specialArgs = { inherit inputs; }` is set on the `ai` nixosSystem (it should be — same pattern as other hosts).

- [ ] **Step 8.5: No commit (verification only)**

---

## Self-Review Notes

**Spec coverage:**
- `services/llama-cpp.nix` with `enable` + `instances` (Task 2-4) ✓
- `instances.<name>` sub-options: `modelsDir`, `port`, `host`, `extraArgs`, `user` (Task 2) ✓
- `llama` system user + `modelsDir` provisioning via `systemd.tmpfiles.rules` (Task 3) ✓
- Per-instance systemd service with hardening (Task 4) ✓
- `llama-cpp` built with `vulkanSupport = true` (Task 3) ✓
- `python3Packages.huggingface-hub` installed (provides `hf` CLI) (Task 3) ✓
- Firewall port per instance (Task 3) ✓
- `flake.nix` `llm-agents` input (Task 1) ✓
- `profiles/ai.nix` imports module + declares chat instance on 11434 + installs hermes-agent (Task 5) ✓
- `ai` host in flake outputs (Task 6, guarded — only if not already present) ✓

**Out of scope explicitly handled:** NPU backend (deferred via `extraArgs`), additional instances (deferred via attrset), auto-download (deferred — `hf` installed), Ollama (not installed), k8s manifests (host systemd), hermes service (install only).

**Type consistency:** option names match across tasks (`modelsDir`, `port`, `host`, `extraArgs`, `user`). Service name is `llama-cpp-<instance-name>` throughout. `pkgs.llama-cpp-vulkan` is the overlay name used in both the `environment.systemPackages` entry (Task 3) and the `ExecStart` (Task 4).

**Placeholder scan:** none. Every step has the actual content to write or the exact command to run.

## Execution Handoff

Plan complete and saved to `docs/changes/2026-06-24-ai-profile-llama-cpp-plan.md`. Both execution approaches use isolated git worktrees. Two options:

1. **Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration. Uses git worktrees for isolation.
2. **Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints for review. Uses git worktrees for isolation.

Which approach?

Both options REQUIRE:
- **superpowers:using-git-worktrees** — Creates an isolated worktree before any implementation begins
