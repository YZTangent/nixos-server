# Expose service modules as `nixosModules` flake outputs

## Problem

strix-halo has been reappropriated from the dedicated AI server into the user's main desktop PC, running NixOS with its own separate flake config. Some of the server components managed by this repo — the llama.cpp inference service, the Hermes agent tooling, and the k3s server module — should also run on that desktop.

Today those components are only reachable through this repo's `nixosConfigurations`: `services/*.nix` modules are imported by relative path from `profiles/*.nix`, and the flake exports nothing reusable (its `packages` output only carries `provision` and `nixos-anywhere`). An external flake has no supported way to consume the service modules. Importing by path (`inputs.nixos-server + "/services/llama-server.nix"`) would work for some modules but makes the internal file layout an implicit API, and breaks for anything referencing `inputs` via `specialArgs` (the ai profile's `hermes-agent` from `inputs.llm-agents`).

## Solution

Export the service modules as standard `nixosModules.*` flake outputs. The desktop flake adds this repo as an input and imports the modules it wants; all modules are gated behind existing `enable` options, so importing is inert until the consumer opts in.

The `ai` host, role, and profile stay in this repo for future dedicated AI hardware. Internal hosts and profiles continue importing by relative path — no behavior change to any existing `nixosConfiguration`.

## Design

### 1. `flake.nix`: add `nixosModules` output

One output per service file, exported as-is (they are already self-contained modules taking only standard args):

| Output | Source |
|---|---|
| `nixosModules.llama-server` | `services/llama-server.nix` |
| `nixosModules.k3s` | `services/k3s.nix` |
| `nixosModules.media-stack` | `services/media-stack.nix` |
| `nixosModules.file-sharing` | `services/file-sharing.nix` |
| `nixosModules.backup-target` | `services/backup-target.nix` |
| `nixosModules.monitoring-agent` | `services/monitoring-agent.nix` |

Plus two composed outputs defined inline in `flake.nix`:

- `nixosModules.ai` — imports `services/llama-server.nix` and adds `inputs.llm-agents.packages.${pkgs.system}.hermes-agent` to `environment.systemPackages`. Defined inline so it closes over this flake's `llm-agents` input — the consumer does not need (and cannot accidentally version-skew) its own `llm-agents` input. It does **not** enable or configure `services.llama-server`; instance count, ports, and backend flags (`-ngl`, `--backend vulkan`, context size) are machine decisions the consumer makes. The Vulkan overlay lives inside the llama-server module itself, so it travels with the import.
- `nixosModules.default` — aggregates all six service modules for consumers who want the whole menu behind one import. Safe because every module is inert until its `enable` option is set.

### 2. Consumer contract

Documented in `README.md` (new "Consuming from another flake" section):

```nix
# desktop flake.nix
inputs.nixos-server.url = "github:YZTangent/nixos-server"; # or a path/git URL

# in the nixosSystem modules list
inputs.nixos-server.nixosModules.ai
inputs.nixos-server.nixosModules.k3s
```

Then configure as on any host in this repo, e.g. `services.llama-server.enable = true;` with a desktop-appropriate instance, and `services.k3s-server.*` options to join the existing cluster.

Consumer prerequisites, stated explicitly in the README:

- **k3s**: the module references `sops.secrets."k3s-token"` and `sops.secrets."k3s-vrrp-password"`. The consumer must import `sops-nix.nixosModules.sops` and define both keys in its own sops file. The sops coupling is kept deliberately (the whole fleet already runs sops; see trade-offs below). The consumer must explicitly configure `services.k3s-server.flannelIface` (e.g. `enp3s0` instead of default `eth0`) to securely lock keepalived and k3s to the correct physical LAN interface. The `services.k3s-server.vip` option defaults to `192.168.1.200` and only needs overriding if the cluster uses a different VIP. The consumer can set `isFirstNode = false` (default) to join the existing cluster, or `isFirstNode = true` if using the desktop to bootstrap the cluster (e.g., for disaster recovery). This nuance and the VIP default must be clearly documented in the `README.md`.
- **llama-server / ai**: no external requirements. `unfree` allowances are not needed (llama-cpp and hermes-agent are free).
- **media-stack** (if ever enabled externally): requires allowing unfree `jellyfin-ffmpeg` (this repo does it via `allowUnfreePredicate` in `profiles/base.nix`; the consumer must do the same).

### 3. Verification

- `nix flake check` — existing `nixosConfigurations` still evaluate.
- New `checks.x86_64-linux.nixos-modules-eval` — evaluates (not builds) a minimal `nixosSystem` that imports `nixosModules.default` and `nixosModules.ai` with everything left disabled. This catches export regressions: a module accidentally growing a dependency on `specialArgs.inputs` or other repo-internal context would fail this check even though internal hosts (which do get `specialArgs`) still pass.
- Restructure `device-id` input to support testing: move the current placeholder to `device-id/default` and create a test device-id structure in `device-id/test` (with `hostname = "fake-host"` and `hostId = "12345678"`). Update `flake.nix` input to point to `device-id/default`.

### 4. Out of scope (explicit)

- **The desktop flake itself** — configuring strix-halo's desktop config is the consumer's side and lives outside this repo.
- **Exposing `llama-cpp-vulkan` as a `packages` output** — the overlay inside the llama-server module covers the NixOS-module use case; a standalone package export has no consumer today.
- **Parameterizing k3s secrets** (plain `tokenFile` path options instead of hardcoded sops references) — rejected for now; both consumers use sops.
- **Exporting `profiles/base.nix` or other profiles** — base is fleet identity/provisioning glue (device-id assertions, sops layout, admin user) and is meaningless on the desktop.
- **Removing the `ai` host/role** — kept for future dedicated AI hardware.
- **monitoring-agent promtail migration** — pre-existing TODO, unrelated.

## Related spec / ADR

- No `docs/spec/` exists yet in this repo; this change does not create one.
- ADR-0004 (llama.cpp as host systemd service) is unaffected: the service still runs as a host systemd unit on strix-halo — the machine's role changed, not the architecture.
- New ADR: expose reusable components as `nixosModules` flake outputs rather than path imports or a separate shared flake (records the rejected alternatives).
