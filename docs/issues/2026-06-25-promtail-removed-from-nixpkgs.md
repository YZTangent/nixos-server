# promtail removed from nixpkgs — monitoring-agent.nix log shipping broken

## Status

Open. Workaround applied (promtail block commented out); node exporter still functional.

## Discovery

Surfaced when switching the flake input from `nixos-25.05` to `nixpkgs-unstable` (required to make `hermes-agent` from `numtide/llm-agents.nix` evaluate — its dependency tree needs `fetchPnpmDeps`, absent in 25.05).

## Problem

`services/monitoring-agent.nix` uses `services.promtail.enable`, which was removed from nixpkgs. Promtail reached end of life; the upstream module is gone. Attempting to evaluate any host that imports `profiles/compute.nix` (which imports `services/monitoring-agent.nix`) fails with:

```
Failed assertions:
- The option definition `services.promtail' in `.../services/monitoring-agent.nix' no longer has any effect; please remove it.
```

## Affected hosts

All compute-profile hosts: `compute`, `server`, `storage`, `ai`, `first-ai`, `first-server`.

## Workaround applied

The `services.promtail` block in `services/monitoring-agent.nix` (lines 23-38) is commented out with a TODO. The node exporter on :9100 is unaffected and still ships metrics. Log shipping to Loki is offline until this is resolved.

## Fix options

1. **Migrate to grafana-alloy** (`services.alloy.enable`) — the official promtail replacement. Recommended path per the nixpkgs assertion message. Migration guide: https://grafana.com/docs/alloy/latest/set-up/migrate/
2. **Migrate to fluent-bit** (`services.fluent-bit.enable`) — lighter-weight alternative.
3. **Drop log shipping entirely** — if Loki isn't in use yet, remove the promtail config and the `lokiUrl` option from `monitoring-agent.nix`.

## References

- nixpkgs commit removing promtail module
- https://grafana.com/docs/alloy/latest/set-up/migrate/
- `docs/changes/2026-06-24-ai-profile-llama-cpp-requirement.md` (the change that triggered the channel switch)
