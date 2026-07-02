# Expose nixosModules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export reusable service modules as `nixosModules` flake outputs for external consumers, document the usage, and add a check to verify evaluation.

**Architecture:** We will modify `flake.nix` to add a `nixosModules` output containing one attribute per service module, plus `ai` and `default` aggregates. A new evaluation check will be added to ensure these modules don't break when imported externally. The consumer contract will be documented in `README.md`.

**Tech Stack:** Nix, Flakes

---

### Task 1: Add `nixosModules` to `flake.nix`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Update flake outputs argument**
  Modify `flake.nix` to add `self` to the outputs arguments list.
  Change:
  `outputs = { nixpkgs, disko, nixos-anywhere, ... } @ inputs: {`
  To:
  `outputs = { self, nixpkgs, disko, nixos-anywhere, ... } @ inputs: {`

- [ ] **Step 2: Add `nixosModules` output**
  In `flake.nix`, insert the `nixosModules` block right before `nixosConfigurations = let`.

```nix
    nixosModules = {
      llama-server = import ./services/llama-server.nix;
      k3s = import ./services/k3s.nix;
      media-stack = import ./services/media-stack.nix;
      file-sharing = import ./services/file-sharing.nix;
      backup-target = import ./services/backup-target.nix;
      monitoring-agent = import ./services/monitoring-agent.nix;

      ai = { pkgs, ... }: {
        imports = [ ./services/llama-server.nix ];
        environment.systemPackages = [
          inputs.llm-agents.packages.''${pkgs.system}.hermes-agent
        ];
      };

      default = { ... }: {
        imports = [
          ./services/llama-server.nix
          ./services/k3s.nix
          ./services/media-stack.nix
          ./services/file-sharing.nix
          ./services/backup-target.nix
          ./services/monitoring-agent.nix
        ];
      };
    };
```

- [ ] **Step 3: Verify output attribute exists**
  Run: `nix flake show`
  Expected: Command succeeds and lists `nixosModules` along with its sub-attributes.

- [ ] **Step 4: Commit**
```bash
git add flake.nix
git commit -m "flake: expose services as nixosModules"
```

### Task 2: Restructure `device-id` input

**Files:**
- Create: `device-id/default/default.nix`
- Create: `device-id/test/default.nix`
- Modify: `flake.nix`

- [ ] **Step 1: Move default placeholder**
  Run:
  ```bash
  mkdir -p device-id/default device-id/test
  git mv device-id/default.nix device-id/default/
  ```

- [ ] **Step 2: Create test dummy**
  Create `device-id/test/default.nix` with a valid structure but a different hostId.
  ```nix
  { hostname = "fake-host"; hostId = "12345678"; }
  ```

- [ ] **Step 3: Update `flake.nix` input**
  Modify the `device-id` input URL in `flake.nix` to point to the new default location.
  Change:
  `url = "path:./device-id";`
  To:
  `url = "path:./device-id/default";`

- [ ] **Step 4: Commit**
  Run:
  ```bash
  git add device-id flake.nix
  git commit -m "test: restructure device-id input for testing"
  ```

### Task 3: Add Evaluation Check

**Files:**
- Modify: `flake.nix`

- [ ] **Step 1: Add `checks` output**
  In `flake.nix`, add a `checks.x86_64-linux` output block right after `packages.x86_64-linux`. 

```nix
    checks.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      eval = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.default
          self.nixosModules.ai
          {
            boot.loader.grub.devices = [ "nodev" ];
            fileSystems."/" = { device = "nodev"; fsType = "tmpfs"; };
            system.stateVersion = "24.05";
          }
        ];
      };
    in {
      nixos-modules-eval = pkgs.runCommand "eval-check" {
        # This check simulates an external flake importing our service modules.
        # It forces evaluation without the `specialArgs = { inherit inputs; }` that
        # internal hosts get. If a module accidentally references `inputs` directly
        # or relies on other internal repo state, it will break here, preventing 
        # regressions for external consumers.
        passthru.drv = eval.config.system.build.toplevel.drvPath;
      } "touch $out";
    };
```

- [ ] **Step 2: Run the check**
  Run the check using the new `device-id/test` dummy.
  Run: 
  ```bash
  nix flake check --override-input device-id path:./device-id/test
  ```
  Expected: PASS silently.

- [ ] **Step 3: Commit**
  Run:
  ```bash
  git add flake.nix
  git commit -m "test: add nixos-modules-eval check"
  ```

#### Task 4: Document Consumer Contract and Test Args

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Add "Consuming from another flake" section**
  Insert the following content into `README.md` right above the `## Directory Layout` section.

```markdown
### Consuming from another flake

The service modules in this repository are exposed as `nixosModules` flake outputs so they can be consumed by other flakes (e.g., a desktop configuration).

```nix
# desktop flake.nix
inputs.nixos-server.url = "github:YZTangent/nixos-server"; # or a path/git URL

# in the nixosSystem modules list
inputs.nixos-server.nixosModules.ai
inputs.nixos-server.nixosModules.k3s
```

Then configure as on any host in this repo, e.g. `services.llama-server.enable = true;` with a desktop-appropriate instance, and `services.k3s-server.*` options to join the existing cluster.

**Consumer prerequisites:**

- **k3s**: the module references `sops.secrets."k3s-token"` and `sops.secrets."k3s-vrrp-password"`. The consumer must import `sops-nix.nixosModules.sops` and define both keys in its own sops file. 
  - **Interface Binding**: You must explicitly configure `services.k3s-server.flannelIface` (e.g. `enp3s0` or `wlan0` instead of the default `eth0`). This is strictly required so that `keepalived` and k3s don't accidentally bind to virtual interfaces (like Docker bridges) and instead route cluster traffic correctly over your LAN.
  - **Virtual IP (VIP)**: The cluster API address `services.k3s-server.vip` defaults to `192.168.1.200`. You only need to set this if your cluster operates on a different VIP.
  - **Cluster Role**: Set `isFirstNode = false` (the default) to join an existing cluster. Alternatively, you can set `isFirstNode = true` if you are using this machine to bootstrap a brand new cluster (or for disaster recovery if the main servers are down).
- **llama-server / ai**: no external requirements. `unfree` allowances are not needed (llama-cpp and hermes-agent are free).
- **media-stack** (if ever enabled externally): requires allowing unfree `jellyfin-ffmpeg` (this repo does it via `allowUnfreePredicate` in `profiles/base.nix`; the consumer must do the same).
```

- [ ] **Step 2: Update "Build check (dry run)" section**
  In `README.md`, find the text:
  ```markdown
  Without `--override-input` the placeholder device-id triggers a build-time assertion (see `profiles/base.nix`). Supply a real device-id to evaluate:

  ```bash
  nix flake check --override-input device-id path:/tmp/device-<hash>
  ```
  ```
  And replace it with:
  ```markdown
  Without `--override-input` the placeholder device-id triggers a build-time assertion (see `profiles/base.nix`). We provide a dummy test device-id so you can evaluate the entire flake cleanly:

  ```bash
  nix flake check --override-input device-id path:./device-id/test
  ```
  ```

- [ ] **Step 3: Commit**
  Run:
  ```bash
  git add README.md
  git commit -m "docs: document module usage and test args"
  ```
