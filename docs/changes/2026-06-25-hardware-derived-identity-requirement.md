# Per-instance identity via flake input override

## Problem

Every host file (`hosts/*/default.nix`) hardcodes `networking.hostName` and `networking.hostId`. Two machines of the same role (e.g. three thinkpads deployed as `compute`) cannot share a config without code edits — each needs its own host file with its own hardcoded values. This blocks the "same flake config, same hardware class, zero code changes" scaling goal.

A secondary problem: `profiles/base.nix:38` picks the sops file via `config.networking.hostName`. Once hostname becomes per-instance, that line breaks unless the per-instance value is available at Nix evaluation time.

A tertiary problem: the `first-*` host variants (`first-server`, `first-ai`) are byte-identical to their non-first counterparts except for a single line (`services.k3s-server.isFirstNode = true`). This is duplication that should be collapsed.

## Prior approach (superseded)

The initial version of this requirement doc (2026-06-25) proposed deriving hostname and hostId from the DMI product UUID at provisioning time, persisted to `/var/lib/device-id` on the installed root filesystem, and read by a NixOS activation script at boot that performs drift correction. That approach is superseded because:

- The UUID is not available to Nix at evaluation time — the flake evaluates identically for all compute machines; uniqueness is injected at runtime via the activation script.
- Anything that must be baked into the closure at eval time and that varies per instance cannot depend on the per-instance value.
- The activation-script drift correction is a runtime hack for what is fundamentally a build-time concern.

## Solution

Pass the DMI-derived hash into Nix evaluation as a flake input via `--override-input`. The flake closure is per-instance: `networking.hostName`, `networking.hostId`, and sops file selection are all eval-time resolved. No activation script, no runtime drift correction.

### Identity derivation

- **Source:** `/sys/class/dmi/id/product_uuid` (hardware-bound, survives reinstalls, unique per physical device, root-readable)
- **Hash:** first 8 hex chars of `sha256(device-id)`
- **Hostname:** `${role}-${hash}` (e.g. `compute-a1b2c3d4`, `server-d4e5f6a1`)
- **hostId:** same 8 hex chars (debugging property: hostId matches hostname suffix)
- **Role source:** `device-identity.role` option set per host file (eval-time known) — used for sops file grouping in `.sops.yaml`

### Mechanism: `device-id` flake input

A new non-flake input carries the per-instance hash into Nix eval:

```nix
# flake.nix
inputs.device-id = {
  url = "path:./device-id";   # in-repo placeholder directory
  flake = false;
};
```

The placeholder, committed at `device-id/default.nix`:

```nix
{ hostname = "unknown"; hostId = "00000000"; }
```

At provisioning time, the wrapper generates a per-instance `device-id` file and overrides the input via `--override-input`:

```bash
nixos-anywhere \
  --flake ".#<flake-attr>" \
  --override-input device-id "path:/tmp/device-<hash>" \
  --extra-files "$tmpdir/extra-files" \
  --target-host "root@$target"
```

`--override-input` is supported by `nixos-rebuild`, `nix build`, and `nixos-anywhere` (which passes through to nix). The override takes a `path:` URL pointing to a directory containing the per-instance `default.nix`.

### Default behavior: placeholder + assertion (Option 3)

The placeholder keeps `flake.lock` resolution, `nix flake show`, and IDE tooling working without an override. A NixOS assertion in `profiles/base.nix` fails the build when the placeholder is in effect:

```nix
# profiles/base.nix
assertions = [{
  assertion = (import inputs.device-id).hostname != "unknown";
  message = ''
    device-id input not overridden.
    This closure would be built with hostname="unknown", which is the placeholder default.
    Supply the per-instance device-id at build time:
      nixos-anywhere --flake ".#<host>" --override-input device-id path:/tmp/device-<hash> ...
    See docs/changes/2026-06-25-hardware-derived-identity-requirement.md for the provisioning wrapper.
  '';
}];
```

Behavior matrix:

| Invocation | Result |
|---|---|
| `nix flake show` | Works (flake-lock resolves against placeholder) |
| `nix flake check` | Fails — check forces `system.build.toplevel`, which trips the assertion. Use `nix flake check --override-input device-id path:<real-dir>` to pass. |
| `nixos-rebuild build --flake .#compute` (no override) | Fails at eval with the assertion message |
| Provisioning wrapper (`nix run .#provision`) | Override supplied automatically, builds the real per-instance closure |

### `flake = false` rationale

The `device-id` input is not itself a flake — it's a plain Nix source (a directory containing a `default.nix`). Setting `flake = false` tells the evaluator to treat `inputs.device-id` as a store path rather than looking for a `flake.nix`. The consumer then `import inputs.device-id` to get `{ hostname, hostId }`.

No implications for the flake itself: non-flake inputs are first-class, fully supported, lockable, overridable, and pass `nix flake check`. Mainstream flakes use `flake = false` for vendored Nix expressions, tarballs of `lib/`, etc.

## Design

### 1. Host file shape: `mk-host.nix` helper

A plain Nix function (not a module) centralizes role→profile mapping, `isFirstNode`, and device-id consumption. Collapses the `first-*` duplication to one-line host files.

```nix
# hosts/mk-host.nix
{ inputs, ... }: { role, isFirstNode ? false, extraProfiles ? [] }:
let
  device-id = import inputs.device-id;
  profileFor = {
    compute = [ ../../profiles/compute.nix ];
    server  = [ ../../profiles/compute.nix ../../profiles/nas.nix ];
    ai      = [ ../../profiles/compute.nix ../../profiles/ai.nix ];
    storage = [ ../../profiles/nas.nix ];
  };
in {
  networking.hostName   = "${role}-${device-id.hostname}";
  networking.hostId      = device-id.hostId;
  device-identity.role   = role;
  imports                = [ ../../profiles/base.nix ] ++ profileFor.${role} ++ extraProfiles;
  services.k3s-server.isFirstNode = isFirstNode;
}
```

Each host file becomes one line:

```nix
# hosts/compute/default.nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "compute"; }

# hosts/first-server/default.nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "server"; isFirstNode = true; }
```

The `first-*` variants remain as distinct flake attrs (one per k3s bootstrap-phase variant) — the helper collapses the *file duplication*, not the *variant existence*. Eliminating the variants entirely is a k3s cluster topology change, out of scope.

### 2. `device-identity` module

Carried over from the superseded 2026-06-25 design: a module declaring `options.device-identity.role` (string, no default — host files set it via `mk-host.nix`). Imported from `profiles/base.nix`. Used for `.sops.yaml` path_regex grouping.

Unlike the superseded design, this module no longer needs activation scripts or `/var/lib/device-id` persistence — hostname and hostId are eval-time via `inputs.device-id`.

### 3. Per-instance sops files

Sops files are keyed per-instance, role-prefixed: `secrets/<role>-<hash>.yaml` (e.g. `secrets/compute-a1b2c3d4.yaml`).

```nix
# profiles/base.nix
sops = {
  defaultSopsFile = ../secrets/${config.device-identity.role}-${(import inputs.device-id).hostname}.yaml;
  age.keyFile = "/var/lib/sops-nix/key.txt";
};
```

**File naming rationale:** role-prefixed (not bare hash) so `ls secrets/` is self-documenting and `.sops.yaml` path_regex can match by role for key grouping.

**`.sops.yaml` path_regex by role:**

```yaml
creation_rules:
  - path_regex: secrets/compute-.*\.yaml$
    key_groups:
      - age: [*compute-...]
  - path_regex: secrets/server-.*\.yaml$
    key_groups:
      - age: [*server-...]
  - path_regex: secrets/ai-.*\.yaml$
    key_groups:
      - age: [*ai-...]
  - path_regex: secrets/storage-.*\.yaml$
    key_groups:
      - age: [*storage-...]
```

Multiple hosts of the same role each get their own sops file with a single age recipient (their per-instance public key). Adding a new host to an existing role = generate keypair, create `secrets/<role>-<hash>.yaml`, append public key to `.sops.yaml` under the role's key_group, `sops updatekeys`, commit, push. No code changes.

### 4. `flake.nix` auto-discover hosts

Replace the 6 manual `nixosConfiguration` entries with a `readDir` + `listToAttrs`:

```nix
nixosConfigurations = let
  hostDirs = builtins.attrNames (builtins.readDir ./hosts);
in builtins.listToAttrs (map (name: {
  inherit name;
  value = nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [ ./hosts/${name} ];
    specialArgs = { inherit inputs; };
  };
}) hostDirs);
```

Drop a new directory in `hosts/<name>/` → it's a flake attr. No `flake.nix` edit.

### 5. Provisioning wrapper: Nix-packaged Python app

A Python application packaged via `pkgs.python3Packages.buildPythonApplication`, exposed as `nix run .#provision`. Deps: `pyyaml`. Shells out to `age-keygen`, `sops`, `nixos-anywhere`, `git` (all available on the workstation via Nix or system).

**Invocation:**
```
nix run .#provision -- <role> <target-ip> [--first]
```

**Flow:**
1. Read DMI UUID from target over SSH (`ssh root@$target cat /sys/class/dmi/id/product_uuid`)
2. Derive hash: `sha256(device-id)[:8]`
3. Generate per-instance age keypair via `age-keygen`
4. Write the `device-id` override file: `{ hostname = "<hash>"; hostId = "<hash>"; }` into a temp dir
5. Stage `extra-files/var/lib/sops-nix/key.txt` (the age private key) for `nixos-anywhere --extra-files`
6. Append the public key to `secrets/.sops.yaml` under the role's `key_group` using `pyyaml`
7. Create `secrets/<role>-<hash>.yaml` (copy from a role template if new, or `sops updatekeys` if exists)
8. `git add secrets/ .sops.yaml && git commit -m "provision: add <role>-<hash>" && git push`
9. Invoke `nixos-anywhere --flake ".#<flake-attr>" --override-input device-id "path:$tmpdir/device-<hash>" --extra-files "$tmpdir/extra-files" --target-host root@$target`
10. Cleanup temp dir

**`--first` flag:** sets `flake_attr = "first-<role>"` so the built closure has `services.k3s-server.isFirstNode = true`.

**Why Python, not shell:** the wrapper mutates `.sops.yaml` (structured YAML), generates keypairs, orchestrates `nixos-anywhere`, and handles error paths. A shell script with sed/awk/yq piping is fragile for something this load-bearing. Python with `pyyaml` gives structured YAML manipulation, real error handling, and testability.

**Why Nix-packaged:** deps pinned in flake, reproducible across workstations, consistent with the existing `serverctl` Go binary pattern. No workstation prereq beyond Nix.

**`--extra-files` for the age private key:** nixos-anywhere's supported hook for placing files on the installed root filesystem before first boot. The private key lands at `/var/lib/sops-nix/key.txt` on the target.

### 6. `hostId` and ZFS

`networking.hostId` is now set via the NixOS option at eval time. `nixos-install` (invoked by `nixos-anywhere`) writes `/etc/hostid` from this option during installation, so `/etc/hostid` exists on disk before first boot. ZFS pool import in initrd reads `/etc/hostid` before activation runs — this approach is initrd-safe without any special handling.

## Scope

In scope:
- New `device-id` flake input (non-flake, `path:./device-id` placeholder)
- New `device-id/default.nix` placeholder
- Assertion in `profiles/base.nix` (catches placeholder builds)
- New `device-identity` module (the `role` option, imported in `base.nix`)
- New `hosts/mk-host.nix` helper (centralizes role→profile mapping, `isFirstNode`, device-id consumption)
- Rewrite all 6 host files to use `mk-host.nix`
- Sops file rename: `secrets/<hostname>.yaml` → `secrets/<role>-<hash>.yaml` (per-instance, role-prefixed)
- `.sops.yaml` path_regex update (grouped by role)
- `profiles/base.nix` sops file selection by device-id + assertion
- `flake.nix` auto-discover hosts via `readDir ./hosts`
- New `scripts/provision.py` as a Nix-packaged Python app (`nix run .#provision`)
- New flake package: `provision` (Python app with `pyyaml`)

Out of scope:
- Reprovisioning existing physical machines (operational, not code)
- Migrating `serverctl` Go CLI (it already handles `switch`/`create`; `provision.py` is the new provisioning path — `serverctl` may wrap or supersede it later, separate change)
- The k3s first-node topology (keeping `first-*` flake attrs; eliminating them is a k3s cluster topology change)
- ZFS `hostId` timing edge cases (no host uses ZFS yet; the eval-time `networking.hostId` approach handles this correctly anyway)
- Full fleet key rotation policy (separate ADR)
- `nix flake show` / `nix flake check` CI integration (separate change)

## Migration sequence

The change ships the mechanism. Reprovisioning existing hosts is operational. The code migration has ordering constraints because sops files are being renamed and `.sops.yaml` rules change:

1. **Add `device-id` input + placeholder** — `flake.lock` resolves, dry builds hit the assertion (correct)
2. **Add `device-identity` module** — the `role` option, imported in `base.nix`
3. **Add `mk-host.nix` helper** — doesn't touch existing hosts yet
4. **Rewrite host files** to use `mk-host.nix` — all 6 at once, since they share the helper
5. **Update `profiles/base.nix`** — assertion + sops file selection by device-id
6. **Update `flake.nix`** — `genAttrs` over `readDir ./hosts`
7. **Add `scripts/provision.py` + flake package** — the new provisioning path
8. **Rename sops files per host** — for each existing host, read its DMI UUID (operational, on the physical machine), derive hash, rename `secrets/<hostname>.yaml` → `secrets/<role>-<hash>.yaml`, run `sops updatekeys`. One commit per host, because `sops updatekeys` has to run per file and the `.sops.yaml` rule must match the new filename
9. **Update `.sops.yaml`** — path_regex by role, add per-instance public keys (alongside step 8, per host)

Steps 1-7 are one atomic commit (the code migration). Steps 8-9 are per-host commits (operational, one per physical machine, because each requires reading that machine's DMI UUID and running `sops updatekeys` on its file).

## Related spec/ADR

- `docs/adr/0001-sops-nix-for-secrets.md` — sops-nix choice and key model
- New ADR to be created: `docs/adr/0005-per-instance-identity-via-flake-input-override.md` — records the `--override-input` + `flake = false` + placeholder+assertion decision, the per-instance sops file naming, and the rejection of the runtime activation-script approach from the prior version of this doc
