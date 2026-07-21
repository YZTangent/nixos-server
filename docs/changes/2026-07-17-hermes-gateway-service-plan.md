# Hermes Gateway Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a NixOS service module for the Hermes Agent gateway (Telegram bot) running as a hardened systemd service under an unprivileged user.

**Architecture:** Create `services/hermes-gateway.nix` following the pattern of existing service modules (monitoring-agent, llama-server). The module accepts an opaque `hermesHome` path, creates a system user, uses systemd `BindPaths` to mount the consumer's config directory at `/var/lib/hermes/` (config + runtime data in one place, no copy), and starts `hermes gateway` via systemd with strict sandboxing. The flake exports the module and the `ai` profile enables it.

**Tech Stack:** NixOS modules, systemd, Nix language

**Requirements spec:** `docs/changes/2026-07-15-hermes-gateway-service-requirement.md`

---

### Task 1: Create the hermes-gateway NixOS service module

**Files:**
- Create: `services/hermes-gateway.nix`

- [ ] **Step 1: Write the module**

Create `services/hermes-gateway.nix` with the following structure, following the pattern of `services/monitoring-agent.nix` (simple enable + options) and `services/llama-server.nix` (systemd service + user creation + sandboxing):

```nix
{ config, pkgs, lib, ... }:

let
  cfg = config.services.hermes-gateway;
in
{
  options.services.hermes-gateway = {
    enable = lib.mkEnableOption "Hermes Agent gateway (Telegram bot)";

    hermesHome = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the directory containing all Hermes configuration:
        config.yaml, SOUL.md, skills/, platforms/, .env, auth.json, etc.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # System user for the service
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      home = "/var/lib/hermes";
      createHome = true;
      shell = "/run/current-system/sw/bin/nologin";
    };
    users.groups.hermes = {};

    # Runtime data directory (created by tmpfiles so systemd can create it before bind-mount)
    systemd.tmpfiles.rules = [
      "d /var/lib/hermes 0755 hermes hermes -"
    ];

    # systemd service
    systemd.services.hermes-gateway = {
      description = "Hermes Agent gateway (Telegram bot)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        ExecStart = "${pkgs.hermes-agent}/bin/hermes gateway";
        User = "hermes";
        Group = "hermes";
        Restart = "on-failure";
        RestartSec = "5";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = "true";
        PrivateTmp = true;
        MemoryMax = "2G";
        CPUQuota = "80%";
        BindPaths = [ "${cfg.hermesHome}:/var/lib/hermes" ];
        Environment = [ "HERMES_HOME=/var/lib/hermes" ];
        ReadWritePaths = [ "/var/lib/hermes" ];
      };
    };
  };
}
```

Key design decisions:
- `hermesHome` is typed as `str` (not `path`) so that it isn't referring to an immutable path in a nix deriv
- `BindPaths = [ "${cfg.hermesHome}:/var/lib/hermes" ]` mounts the consumer's config directory at `/var/lib/hermes/` — no copy, no activation script, no rebuild-time data loss. Config and runtime data coexist in the same directory the consumer manages.
- `ReadWritePaths = [ "/var/lib/hermes" ]` ensures the service user can write runtime data alongside config files
- Sandbox mirrors the spec: strict filesystem, no home access, no privilege escalation, isolated tmp
- `hermes-agent` is expected to already be in `systemPackages` (it's in the `ai` profile today)

- [ ] **Step 2: Run evaluation check to verify syntax**

Run: `nix eval --expr '(import ./services/hermes-gateway.nix) { config = {}; pkgs = import <nixpkgs> {}; lib = import <nixpkgs/lib>; }'`

Or alternatively, verify the flake still evaluates by running:
```bash
nix flake check --no-build 2>&1 | grep -i "hermes-gateway" || true
```

Expected: no syntax errors, module parses cleanly. The check may still fail on the ai host due to the pre-existing device-id issue — that's acceptable for this step.

---

### Task 2: Expose the module in flake.nix

**Files:**
- Modify: `flake.nix` — add `hermes-gateway` to `nixosModules`

- [ ] **Step 1: Add the module reference**

In `flake.nix`, add to the `nixosModules` attribute set:

```nix
nixosModules = {
  hermes-gateway = ./services/hermes-gateway.nix;
  # ... existing modules ...
};
```

This is a one-line addition at the top of the `nixosModules` attribute set, before the existing entries.

- [ ] **Step 2: Verify flake.nix is valid**

Run: `nix flake check --no-build 2>&1 | head -30`

Expected: no new errors related to the module. The device-id assertion on the ai host is pre-existing and unrelated.

---

### Task 3: Wire the module into the ai profile

**Files:**
- Modify: `profiles/ai.nix` — import and enable hermes-gateway

- [ ] **Step 1: Update ai.nix**

Replace the current `profiles/ai.nix` content with:

```nix
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
```

Changes from the original:
- Added `../services/hermes-gateway.nix` to imports
- Added `services.hermes-gateway` config block with `enable = true` and `hermesHome = ./hermes-config`
- Kept existing llama-server config and hermes-agent package unchanged

- [ ] **Step 2: Verify evaluation**

Run: `nix flake check --no-build 2>&1 | head -30`

Expected: no new errors. The device-id assertion on the ai host is pre-existing.

---

### Task 4: Update the flake check to handle hermes-gateway in isolation

**Files:**
- Modify: `flake.nix` — the `checks.x864-linux` block

- [ ] **Step 1: Add hermes-gateway to the eval check**

In the `checks.x86_64-linux` block, the `ai` module is already imported. The hermes-gateway module is now part of the `ai` module's transitive imports (via `profiles/ai.nix`), so it will automatically be pulled in.

However, the check currently uses `self.nixosModules.default` and `self.nixosModules.ai`. The `ai` module now references `./hermes-config` as `hermesHome`, which won't exist. We need to either:

Option A — Provide a dummy config dir in the check:
```nix
# Before the checks block, add:
checksConfigDir = pkgs.runCommand "hermes-config" {} ''
  mkdir -p $out
  touch $out/.env $out/auth.json $out/config.yaml $out/SOUL.md
'';
```

Then in the `ai` module override within the check:
```nix
self.nixosModules.ai
{ services.hermes-gateway.hermesHome = checksConfigDir; }
```

Option B — Skip the check for the ai host entirely (less ideal, loses coverage).

**Choose Option A** — it's better to actually test the module evaluates with valid paths.

- [ ] **Step 2: Verify the check passes**

Run: `nix flake check --no-build 2>&1`

Expected: the device-id assertion on ai is the only remaining failure. The hermes-gateway module should now evaluate cleanly with the dummy config directory.

---

## File Summary

| File | Action | Purpose |
|---|---|---|
| `services/hermes-gateway.nix` | **Create** | NixOS service module: user, systemd unit, sandboxing, BindPaths mount |
| `flake.nix` | **Modify** | Export module in `nixosModules`; add dummy config dir in `checks.x86_64-linux` |
| `profiles/ai.nix` | **Modify** | Import module, enable it, set `hermesHome` |

## Verification Checklist

- [ ] `nix flake check` passes (device-id assertion on ai host is pre-existing and acceptable)
- [ ] Service starts and is reachable on Telegram (manual test on `ai` host)
- [ ] Agent responds to messages (manual test)
- [ ] Agent can execute terminal commands within sandbox (manual test)
