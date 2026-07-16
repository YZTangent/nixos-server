# Requirement: Hermes Gateway Service

## Purpose

Add a Hermes Agent gateway service to the NixOS configuration. The service runs on the `ai` host and exposes the agent through a Telegram bot.

## Scope

- New NixOS service module: `services/hermes-gateway`
- systemd service unit for `hermes gateway`
- User provisioned via NixOS
- Secrets — consumer's choice (sops-nix, plain text, etc.)
- Config directory populated by consumer (e.g., `ai.nix` profile)

## Out of scope

- Hermes configuration (config.yaml, SOUL.md, skills, platforms) — consumer-managed
- Docker or other container backend for agent sandboxing — not needed given systemd sandboxing
- k3s / Kubernetes — not applicable to this daemon workload
- Multiple hosts — single instance only on `ai`

## Design

### Architecture

A systemd service running `hermes gateway` as an unprivileged system user. The service reads all configuration from a directory (`/var/lib/hermes/`), which the consumer is responsible for populating.

### Sandboxing

Systemd-level hardening:

- `ProtectSystem = "strict"` — `/usr`, `/boot`, `/efi` read-only
- `ProtectHome = "true"` — `/home`, `/root`, `/run/user` masked
- `NoNewPrivileges = true` — no privilege escalation
- `PrivateTmp = true` — isolated /tmp
- `MemoryMax` — resource limit (prevent CPU/memory exhaustion)
- `CPUQuota` — resource limit (prevent CPU exhaustion)
- Runs as unprivileged system user `hermes`

The terminal tool runs commands as the `hermes` user, which is already confined by the above sandboxing. It cannot modify system files, escalate privileges, affect other users, or stop services. The worst-case impact is self-contained: disk fill-up in its own home, CPU burn, or credential exfiltration via outbound HTTP.

### Configuration

The NixOS module accepts an opaque path to a directory containing all Hermes configuration and secrets. It does not parse or schema-check any files inside — the module just reads whatever is there.

**Options:**

| Option | Type | Description |
|---|---|---|
| `hermesHome` | `path` | Path to the directory containing all Hermes config (config.yaml, SOUL.md, skills/, platforms/, .env, auth.json, etc.) |

The module symlinks or copies the directory contents to `/var/lib/hermes/` via activation.

The NixOS module creates a `systemd.services.hermes-gateway.serviceConfig.Environment = [ "HERMES_HOME=/var/lib/hermes" ]` directive so the `hermes gateway` process reads config from that directory instead of `~/.hermes/`.

### Secrets

No opinion on how the consumer provisions secrets. The module expects `.env` and `auth.json` to exist in the config directory and reads them as-is. Whether the consumer uses sops-nix, a plain text file, or anything else is entirely their choice.

### Runtime Data

Runtime data (`state.db`, `sessions/`, `kanban.db`, `cron/`, `logs/`, `gateway_state.json`, etc.) accumulates in `/var/lib/hermes/` naturally. The NixOS module does not manage or prune this data.

### Git Access

The agent may push its own state (sessions, memory, skills) to a dedicated git repository via `git commit` / `git push`. Access is restricted using a **fine-grained GitHub Personal Access Token** scoped to the single state repository, stored in `.env` and encrypted via sops-nix.

### Consumer Responsibility

The consumer (e.g., `ai.nix`) is responsible for:

1. Setting the `hermesHome` option to point to the directory containing all Hermes config
2. Provisioning all files — config and secrets — into that directory however they choose (sops-nix, plain text, whatever)
3. Populating any additional runtime directories the consumer wishes to pre-seed

## Files to create

- `services/hermes-gateway.nix` — the NixOS service module
- Updated `flake.nix` — expose the module as a NixOS module
- Updated `profiles/ai.nix` — import the module and set `hermesHome` to the config directory

## Verification

- Service starts and is reachable on Telegram
- Agent responds to messages
- Agent can execute terminal commands within sandbox
- `nix flake check` passes
