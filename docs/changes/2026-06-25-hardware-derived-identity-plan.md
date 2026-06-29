# Per-instance identity via flake input override — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pass a DMI-derived hash into Nix eval via `--override-input` on a non-flake `device-id` input, so hostname, hostId, and sops file selection are eval-time resolved per physical machine.

**Architecture:** A new `device-id` flake input (non-flake, `path:./device-id` placeholder dir) is overridden at provisioning time with a per-instance file containing `{ hostname, hostId }`. A Python app (`nix run .#provision`) reads the target's DMI UUID over SSH, generates the override file + age keypair, updates `.sops.yaml` and the per-instance sops file, then invokes `nixos-anywhere`. Host files are collapsed via `hosts/mk-host.nix` (plain Nix function, not a module). Sops files are per-instance, role-prefixed (`secrets/<role>-<hash>.yaml`). An assertion in `profiles/base.nix` catches placeholder builds.

**Tech Stack:** Nix flakes, NixOS module system, sops-nix, nixos-anywhere, Python 3 (packaged via `buildPythonApplication`), pyyaml, age, sops

**Requirement doc:** `docs/changes/2026-06-25-hardware-derived-identity-requirement.md`
**ADR:** `docs/adr/0005-per-instance-identity-via-flake-input-override.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `flake.nix` | Modify | Add `device-id` input; replace manual `nixosConfigurations` with `readDir` auto-discover; add `provision` package |
| `device-id/default.nix` | Create | Placeholder `{ hostname = "unknown"; hostId = "00000000"; }` |
| `modules/device-identity.nix` | Create | `options.device-identity.role` (string, no default) |
| `profiles/base.nix` | Modify | Add assertion; import `device-identity.nix`; change sops file selection to use `device-id` + `device-identity.role` |
| `hosts/mk-host.nix` | Create | Plain Nix function: takes `{ role, isFirstNode, extraProfiles }`, returns a NixOS module attrset |
| `hosts/compute/default.nix` | Rewrite | One-liner calling `mk-host.nix` |
| `hosts/server/default.nix` | Rewrite | One-liner calling `mk-host.nix` |
| `hosts/first-server/default.nix` | Rewrite | One-liner calling `mk-host.nix` with `isFirstNode = true` |
| `hosts/ai/default.nix` | Rewrite | One-liner calling `mk-host.nix` |
| `hosts/first-ai/default.nix` | Rewrite | One-liner calling `mk-host.nix` with `isFirstNode = true` |
| `hosts/storage/default.nix` | Rewrite | One-liner calling `mk-host.nix` |
| `secrets/.sops.yaml` | Modify | New path_regex rules by role; placeholder key entries |
| `scripts/provision/__init__.py` | Create | Empty package marker |
| `scripts/provision/__main__.py` | Create | Python app entry point |
| `scripts/provision/provision.py` | Create | Main provisioning logic |
| `scripts/provision/sops_yaml.py` | Create | `.sops.yaml` manipulation helpers |
| `tests/test_sops_yaml.py` | Create | Tests for sops_yaml helpers |
| `tests/test_provision.py` | Create | Tests for hash derivation + device-id file generation |
| `pyproject.toml` | Create | Python project metadata for `buildPythonApplication` |

---

### Task 1: Add `device-id` flake input + placeholder

**Files:**
- Create: `device-id/default.nix`
- Modify: `flake.nix`

- [ ] **Step 1.1: Create the placeholder `device-id/default.nix`**

```nix
{ hostname = "unknown"; hostId = "00000000"; }
```

- [ ] **Step 1.2: Add `device-id` input to `flake.nix`**

In `flake.nix`, inside the `inputs` attrset (after the `nixos-anywhere` input block, before the closing `}`):

```nix
    device-id = {
      url = "path:./device-id";
      flake = false;
    };
```

- [ ] **Step 1.3: Verify flake.lock resolves**

Run: `nix flake lock --override-input device-id path:./device-id`
Expected: `flake.lock` updated with a `device-id` node having `flake: false`.

- [ ] **Step 1.4: Verify `nix flake show` works**

Run: `nix flake show`
Expected: lists `nixosConfigurations` (the existing 6) without error. The placeholder is valid.

- [ ] **Step 1.5: Commit**

```bash
git add device-id/default.nix flake.nix flake.lock
git commit -m "feat: add device-id flake input with placeholder"
```

---

### Task 2: Create `device-identity` module

**Files:**
- Create: `modules/device-identity.nix`

- [ ] **Step 2.1: Create the module**

```nix
{ lib, ... }:
{
  options.device-identity = {
    role = lib.mkOption {
      type = lib.types.str;
      description = "Machine role (compute, server, ai, storage). Used for sops file grouping and hostname prefix.";
    };
  };
}
```

Note: no default. Host files must set it. This is intentional — it forces an explicit role declaration.

- [ ] **Step 2.2: Commit**

```bash
git add modules/device-identity.nix
git commit -m "feat: add device-identity module with role option"
```

---

### Task 3: Create `hosts/mk-host.nix` helper

**Files:**
- Create: `hosts/mk-host.nix`

- [ ] **Step 3.1: Create the helper**

```nix
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

- [ ] **Step 3.2: Commit**

```bash
git add hosts/mk-host.nix
git commit -m "feat: add mk-host.nix helper for host file deduplication"
```

---

### Task 4: Rewrite host files to use `mk-host.nix`

**Files:**
- Rewrite: `hosts/compute/default.nix`
- Rewrite: `hosts/server/default.nix`
- Rewrite: `hosts/first-server/default.nix`
- Rewrite: `hosts/ai/default.nix`
- Rewrite: `hosts/first-ai/default.nix`
- Rewrite: `hosts/storage/default.nix`

- [ ] **Step 4.1: Rewrite `hosts/compute/default.nix`**

Replace entire file contents with:

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "compute"; }
```

- [ ] **Step 4.2: Rewrite `hosts/server/default.nix`**

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "server"; }
```

- [ ] **Step 4.3: Rewrite `hosts/first-server/default.nix`**

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "server"; isFirstNode = true; }
```

- [ ] **Step 4.4: Rewrite `hosts/ai/default.nix`**

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "ai"; }
```

- [ ] **Step 4.5: Rewrite `hosts/first-ai/default.nix`**

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "ai"; isFirstNode = true; }
```

- [ ] **Step 4.6: Rewrite `hosts/storage/default.nix`**

```nix
{ inputs, ... }: import ./mk-host.nix { inherit inputs; } { role = "storage"; }
```

- [ ] **Step 4.7: Commit**

```bash
git add hosts/
git commit -m "refactor: collapse host files to mk-host.nix calls"
```

---

### Task 5: Update `profiles/base.nix` — assertion + device-identity import + sops selection

**Files:**
- Modify: `profiles/base.nix`

- [ ] **Step 5.1: Add the `device-identity` import**

In `profiles/base.nix`, update the `imports` list (line 4-8) to include the new module:

```nix
  imports = [
    inputs.sops-nix.nixosModules.sops
    inputs.disko.nixosModules.disko
    ../disko/os-ext4.nix
    ../modules/device-identity.nix
  ];
```

- [ ] **Step 5.2: Add the assertion**

Add immediately after the `imports` block (before the `# Locale` comment):

```nix
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

- [ ] **Step 5.3: Update sops file selection**

Replace line 38 (`defaultSopsFile = ../secrets/${config.networking.hostName}.yaml;`) with:

```nix
    defaultSopsFile = ../secrets/${config.device-identity.role}-${(import inputs.device-id).hostname}.yaml;
```

- [ ] **Step 5.4: Verify the assertion fires on a dry build**

Run: `nixos-rebuild build --flake .#compute`
Expected: FAIL with the assertion message about `device-id input not overridden`.

- [ ] **Step 5.5: Verify the assertion passes with an override**

Run: `mkdir -p /tmp/test-device && echo '{ hostname = "a1b2c3d4"; hostId = "a1b2c3d4"; }' > /tmp/test-device/default.nix && nixos-rebuild build --flake .#compute --override-input device-id path:/tmp/test-device`
Expected: build proceeds (may fail later due to missing sops file `secrets/compute-a1b2c3d4.yaml`, but the assertion passes).

- [ ] **Step 5.6: Commit**

```bash
git add profiles/base.nix
git commit -m "feat: add device-id assertion + per-instance sops selection in base.nix"
```

---

### Task 6: Update `flake.nix` — auto-discover hosts via `readDir`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 6.1: Replace the `nixosConfigurations` block**

In `flake.nix`, replace the entire `nixosConfigurations = { ... };` attrset (lines 19-50) with:

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

- [ ] **Step 6.2: Verify auto-discovery**

Run: `nix flake show`
Expected: lists `nixosConfigurations#ai`, `nixosConfigurations#compute`, `nixosConfigurations#first-ai`, `nixosConfigurations#first-server`, `nixosConfigurations#server`, `nixosConfigurations#storage` — all six, derived from `hosts/` directory listing.

- [ ] **Step 6.3: Commit**

```bash
git add flake.nix
git commit -m "refactor: auto-discover hosts from readDir ./hosts"
```

---

### Task 7: Update `secrets/.sops.yaml` — path_regex by role

**Files:**
- Modify: `secrets/.sops.yaml`

- [ ] **Step 7.1: Rewrite `.sops.yaml` with role-based path_regex**

Replace entire contents of `secrets/.sops.yaml` with:

```yaml
keys:
  # Per-instance age public keys are added here by `nix run .#provision`.
  # Format: - &<role>-<hash> age1...
  # Example:
  #   - &compute-a1b2c3d4 age1qzv...

creation_rules:
  - path_regex: secrets/compute-.*\.yaml$
    key_groups:
      - age: []
  - path_regex: secrets/server-.*\.yaml$
    key_groups:
      - age: []
  - path_regex: secrets/ai-.*\.yaml$
    key_groups:
      - age: []
  - path_regex: secrets/storage-.*\.yaml$
    key_groups:
      - age: []
```

Note: the `age: []` empty lists are populated by `provision.py` when adding a new machine. The existing per-host files (`secrets/thinkpad.yaml`, etc.) are not renamed in this task — they're migrated operationally per-host in Task 12. The old `path_regex` rules for them are removed here; until the rename happens, those files won't match any rule and `sops` will error if you try to edit them. This is intentional — it forces the migration to happen via `provision.py` rather than manual `sops edit`.

- [ ] **Step 7.2: Commit**

```bash
git add secrets/.sops.yaml
git commit -m "refactor: sops path_regex by role for per-instance files"
```

---

### Task 8: Create Python project structure for `provision.py`

**Files:**
- Create: `pyproject.toml`
- Create: `scripts/provision/__init__.py`
- Create: `scripts/provision/__main__.py`

- [ ] **Step 8.1: Create `pyproject.toml`**

```toml
[project]
name = "provision"
version = "0.1.0"
description = "Provisioning wrapper for nixos-anywhere with per-instance device-id"
requires-python = ">=3.11"
dependencies = [
    "pyyaml>=6.0",
]

[project.scripts]
provision = "provision.provision:main"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"

[tool.setuptools.packages.find]
where = ["scripts"]
```

- [ ] **Step 8.2: Create `scripts/provision/__init__.py`**

```python
```

(empty file — package marker)

- [ ] **Step 8.3: Create `scripts/provision/__main__.py`**

```python
from provision.provision import main

if __name__ == "__main__":
    main()
```

- [ ] **Step 8.4: Commit**

```bash
git add pyproject.toml scripts/provision/__init__.py scripts/provision/__main__.py
git commit -m "feat: scaffold Python project for provision.py"
```

---

### Task 9: Implement `sops_yaml.py` helpers with tests

**Files:**
- Create: `scripts/provision/sops_yaml.py`
- Create: `tests/test_sops_yaml.py`

- [ ] **Step 9.1: Write failing tests for `sops_yaml.py`**

Create `tests/test_sops_yaml.py`:

```python
import pathlib
import textwrap
from provision.sops_yaml import add_age_key, find_role_key_group

SAMPLE_YAML = textwrap.dedent("""\
    keys:
      - &compute-a1b2c3d4 age1qzv...

    creation_rules:
      - path_regex: secrets/compute-.*\.yaml$
        key_groups:
          - age:
              - *compute-a1b2c3d4
      - path_regex: secrets/server-.*\.yaml$
        key_groups:
          - age: []
""")

def test_find_role_key_group_returns_index_for_existing_role(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    idx = find_role_key_group(f, "compute")
    assert idx == 0

def test_find_role_key_group_returns_index_for_server(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    idx = find_role_key_group(f, "server")
    assert idx == 1

def test_find_role_key_group_raises_for_unknown_role(tmp_path):
    import pytest
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    with pytest.raises(ValueError, match="no creation_rule matched role"):
        find_role_key_group(f, "nonexistent")

def test_add_age_key_appends_to_correct_role_group(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    add_age_key(f, "server", "server-deadbeef", "age1newkey...")
    content = f.read_text()
    assert "&server-deadbeef" in content
    assert "age1newkey..." in content
    # The new key should be under the server rule, not compute
    assert "*server-deadbeef" in content

def test_add_age_key_is_idempotent_for_duplicate_anchor(tmp_path):
    f = tmp_path / ".sops.yaml"
    f.write_text(SAMPLE_YAML)
    add_age_key(f, "compute", "compute-a1b2c3d4", "age1qzv...")
    # Should not duplicate the anchor or key
    content = f.read_text()
    assert content.count("&compute-a1b2c3d4") == 1
    assert content.count("age1qzv...") == 1
```

- [ ] **Step 9.2: Run tests to verify they fail**

Run: `cd /home/yztangent/code/nixos-server && python -m pytest tests/test_sops_yaml.py -v`
Expected: FAIL with `ModuleNotFoundError: No module named 'provision'` or `ImportError`.

- [ ] **Step 9.3: Implement `sops_yaml.py`**

Create `scripts/provision/sops_yaml.py`:

```python
"""Helpers for manipulating secrets/.sops.yaml programmatically."""
from __future__ import annotations

import pathlib

import yaml


def find_role_key_group(sops_file: pathlib.Path, role: str) -> int:
    """Return the index into creation_rules for the rule matching `secrets/<role>-.*\\.yaml$`.

    Raises ValueError if no rule matches.
    """
    data = yaml.safe_load(sops_file.read_text())
    rules = data.get("creation_rules", [])
    expected_pattern = f"secrets/{role}-.*\\.yaml$"
    for i, rule in enumerate(rules):
        if rule.get("path_regex") == expected_pattern:
            return i
    raise ValueError(f"no creation_rule matched role {role!r}")


def add_age_key(
    sops_file: pathlib.Path,
    role: str,
    anchor_name: str,
    public_key: str,
) -> None:
    """Add an age public key to the key_group for `role` in .sops.yaml.

    - Adds `- &<anchor_name> <public_key>` to the top-level `keys` list (if not already present).
    - Appends `*<anchor_name>` to the `age` list under the role's key_group (if not already present).
    - Writes the file back, preserving key order. Uses yaml.safe_dump (flow style for age lists).
    """
    data = yaml.safe_load(sops_file.read_text())

    # 1. Add the anchor to the top-level keys list
    keys = data.setdefault("keys", [])
    anchor_entry = {anchor_name: public_key}
    # Check if this anchor already exists (by anchor name)
    existing_anchors = {
        next(iter(k.keys())): next(iter(k.values()))
        for k in keys
        if isinstance(k, dict) and len(k) == 1
    }
    if anchor_name not in existing_anchors:
        keys.append(anchor_entry)

    # 2. Find the role's creation_rule and append the alias reference
    rules = data.get("creation_rules", [])
    expected_pattern = f"secrets/{role}-.*\\.yaml$"
    rule_idx = None
    for i, rule in enumerate(rules):
        if rule.get("path_regex") == expected_pattern:
            rule_idx = i
            break
    if rule_idx is None:
        raise ValueError(f"no creation_rule matched role {role!r}")

    rule = rules[rule_idx]
    key_groups = rule.setdefault("key_groups", [{}])
    if not key_groups:
        key_groups.append({})
    age_list = key_groups[0].setdefault("age", [])

    alias_ref = f"*{anchor_name}"
    if alias_ref not in age_list:
        age_list.append(alias_ref)

    # 3. Write back
    sops_file.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False))
```

- [ ] **Step 9.4: Run tests to verify they pass**

Run: `cd /home/yztangent/code/nixos-server && python -m pytest tests/test_sops_yaml.py -v`
Expected: all 5 tests PASS.

- [ ] **Step 9.5: Commit**

```bash
git add scripts/provision/sops_yaml.py tests/test_sops_yaml.py
git commit -m "feat: sops_yaml helpers for .sops.yaml manipulation + tests"
```

---

### Task 10: Implement `provision.py` main logic with tests

**Files:**
- Create: `scripts/provision/provision.py`
- Create: `tests/test_provision.py`

- [ ] **Step 10.1: Write failing tests for hash derivation + device-id file generation**

Create `tests/test_provision.py`:

```python
import hashlib
import pathlib
from provision.provision import derive_hash, write_device_id_file

SAMPLE_DMI_UUID = "12345678-1234-4623-8234-123456789012"

def test_derive_hash_returns_8_hex_chars():
    h = derive_hash(SAMPLE_DMI_UUID)
    assert len(h) == 8
    assert all(c in "0123456789abcdef" for c in h)

def test_derive_hash_is_deterministic():
    assert derive_hash(SAMPLE_DMI_UUID) == derive_hash(SAMPLE_DMI_UUID)

def test_derive_hash_matches_expected_value():
    expected = hashlib.sha256(SAMPLE_DMI_UUID.encode()).hexdigest()[:8]
    assert derive_hash(SAMPLE_DMI_UUID) == expected

def test_write_device_id_file_creates_valid_nix(tmp_path):
    out_dir = tmp_path / "device-deadbeef"
    write_device_id_file(out_dir, "deadbeef")
    content = (out_dir / "default.nix").read_text()
    assert 'hostname = "deadbeef"' in content
    assert 'hostId = "deadbeef"' in content

def test_write_device_id_file_overwrites_existing(tmp_path):
    out_dir = tmp_path / "device-deadbeef"
    out_dir.mkdir()
    (out_dir / "default.nix").write_text("# old content")
    write_device_id_file(out_dir, "deadbeef")
    content = (out_dir / "default.nix").read_text()
    assert "old content" not in content
    assert 'hostname = "deadbeef"' in content
```

- [ ] **Step 10.2: Run tests to verify they fail**

Run: `cd /home/yztangent/code/nixos-server && python -m pytest tests/test_provision.py -v`
Expected: FAIL with `ImportError: cannot import name 'derive_hash'`.

- [ ] **Step 10.3: Implement `provision.py`**

Create `scripts/provision/provision.py`:

```python
"""Provisioning wrapper: reads DMI UUID, generates device-id, invokes nixos-anywhere."""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import subprocess
import sys
import tempfile

from provision.sops_yaml import add_age_key


def derive_hash(dmi_uuid: str) -> str:
    """Derive an 8-hex-char hash from the DMI product UUID."""
    return hashlib.sha256(dmi_uuid.encode()).hexdigest()[:8]


def write_device_id_file(out_dir: pathlib.Path, hash_value: str) -> None:
    """Write a Nix file returning { hostname, hostId } into out_dir/default.nix."""
    out_dir.mkdir(parents=True, exist_ok=True)
    content = '{ hostname = "%s"; hostId = "%s"; }\n' % (hash_value, hash_value)
    (out_dir / "default.nix").write_text(content)


def read_dmi_uuid(target: str) -> str:
    """Read /sys/class/dmi/id/product_uuid from target over SSH."""
    result = subprocess.run(
        ["ssh", f"root@{target}", "cat", "/sys/class/dmi/id/product_uuid"],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout.strip()


def generate_age_keypair(tmpdir: pathlib.Path) -> tuple[str, pathlib.Path]:
    """Generate an age keypair. Returns (public_key, private_key_path)."""
    key_path = tmpdir / "key.txt"
    subprocess.run(
        ["age-keygen", "-o", str(key_path)],
        check=True,
        capture_output=True,
    )
    result = subprocess.run(
        ["age-keygen", "-y", str(key_path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return (result.stdout.strip(), key_path)


def stage_extra_files(
    extra_files_dir: pathlib.Path,
    age_private_key: pathlib.Path,
) -> None:
    """Stage the age private key at var/lib/sops-nix/key.txt under extra_files_dir."""
    sops_dir = extra_files_dir / "var" / "lib" / "sops-nix"
    sops_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy(age_private_key, sops_dir / "key.txt")


def run_nixos_anywhere(
    flake_attr: str,
    device_id_dir: pathlib.Path,
    extra_files_dir: pathlib.Path,
    target: str,
) -> None:
    """Invoke nixos-anywhere with the device-id override + extra-files."""
    cmd = [
        "nixos-anywhere",
        "--flake", f".#{flake_attr}",
        "--override-input", "device-id", f"path:{device_id_dir}",
        "--extra-files", str(extra_files_dir),
        "--target-host", f"root@{target}",
    ]
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="provision",
        description="Provision a NixOS machine with per-instance device-id.",
    )
    parser.add_argument("role", choices=["compute", "server", "ai", "storage"])
    parser.add_argument("target", help="SSH target IP or hostname")
    parser.add_argument("--first", action="store_true", help="k3s first-node bootstrap")
    args = parser.parse_args()

    flake_attr = f"first-{args.role}" if args.first else args.role

    print(f"Provisioning role={args.role} target={args.target} first={args.first}")

    dmi_uuid = read_dmi_uuid(args.target)
    hash_value = derive_hash(dmi_uuid)
    hostname = f"{args.role}-{hash_value}"
    anchor_name = hostname
    print(f"Derived hostname: {hostname}")

    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = pathlib.Path(tmp)

        # 1. Generate age keypair
        public_key, private_key_path = generate_age_keypair(tmpdir)
        print(f"Generated age keypair (public: {public_key[:16]}...)")

        # 2. Write device-id override file
        device_id_dir = tmpdir / f"device-{hash_value}"
        write_device_id_file(device_id_dir, hash_value)

        # 3. Stage extra-files (age private key)
        extra_files_dir = tmpdir / "extra-files"
        stage_extra_files(extra_files_dir, private_key_path)

        # 4. Update .sops.yaml with the new public key
        repo_root = pathlib.Path(__file__).resolve().parents[2]
        sops_file = repo_root / "secrets" / ".sops.yaml"
        add_age_key(sops_file, args.role, anchor_name, public_key)
        print(f"Added {anchor_name} to {sops_file}")

        # 5. Create or update the per-instance sops file
        sops_secret_file = repo_root / "secrets" / f"{args.role}-{hash_value}.yaml"
        if not sops_secret_file.exists():
            # Copy from a role template if one exists, else create empty
            template = repo_root / "secrets" / f"{args.role}-template.yaml"
            if template.exists():
                shutil.copy(template, sops_secret_file)
            else:
                sops_secret_file.write_text("")
            print(f"Created {sops_secret_file}")
        # Re-encrypt to include the new key
        subprocess.run(["sops", "updatekeys", str(sops_secret_file)], check=True)

        # 6. Commit and push
        subprocess.run(
            ["git", "-C", str(repo_root), "add", "secrets/"],
            check=True,
        )
        subprocess.run(
            ["git", "-C", str(repo_root), "commit", "-m", f"provision: add {hostname}"],
            check=True,
        )
        subprocess.run(["git", "-C", str(repo_root), "push"], check=True)

        # 7. Invoke nixos-anywhere
        run_nixos_anywhere(flake_attr, device_id_dir, extra_files_dir, args.target)

    print("Done.")


if __name__ == "__main__":
    main()
```

- [ ] **Step 10.4: Run tests to verify they pass**

Run: `cd /home/yztangent/code/nixos-server && python -m pytest tests/test_provision.py -v`
Expected: all 5 tests PASS.

- [ ] **Step 10.5: Commit**

```bash
git add scripts/provision/provision.py tests/test_provision.py
git commit -m "feat: provision.py main logic + tests"
```

---

### Task 11: Wire `provision` package into `flake.nix`

**Files:**
- Modify: `flake.nix`

- [ ] **Step 11.1: Add the `provision` package to flake outputs**

In `flake.nix`, update the `packages.x86_64-linux` attrset (line 51-53) to include `provision`:

```nix
    packages.x86_64-linux = let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      inherit (nixos-anywhere.packages.x86_64-linux) nixos-anywhere;
      provision = pkgs.python3Packages.buildPythonApplication {
        pname = "provision";
        version = "0.1.0";
        pyproject = true;
        src = ./.;
        nativeBuildInputs = [ pkgs.python3Packages.setuptools ];
        propagatedBuildInputs = [ pkgs.python3Packages.pyyaml ];
        # Tests need the provision package on the path
        nativeCheckInputs = [ pkgs.python3Packages.pytestCheckHook ];
        # Don't run integration tests that hit the network or shell out to ssh/sops/nixos-anywhere
        pytestFlagsArray = [ "tests/" ];
      };
    };
```

- [ ] **Step 11.2: Verify the package builds**

Run: `nix build .#provision`
Expected: builds successfully, produces a `result/bin/provision` binary.

- [ ] **Step 11.3: Verify `nix run .#provision -- --help` works**

Run: `nix run .#provision -- --help`
Expected: prints the argparse help message showing `role`, `target`, `--first`.

- [ ] **Step 11.4: Verify tests run in the Nix build**

Run: `nix build .#provision -- --print-build-logs 2>&1 | grep -E "PASS|FAIL|test_"`
Expected: the pytest run logs show the 10 tests passing during the build.

- [ ] **Step 11.5: Commit**

```bash
git add flake.nix
git commit -m "feat: wire provision Python app into flake packages"
```

---

### Task 12: Operational migration of existing hosts (per-host, manual)

**Note:** This task is operational, not code. Each step is performed per physical machine. No commits are automated by `provision.py` here — the operator runs the migration manually because it requires SSH access to each physical machine and the machines are already provisioned.

**Files:**
- Rename: `secrets/<hostname>.yaml` → `secrets/<role>-<hash>.yaml` (per host)
- Modify: `secrets/.sops.yaml` (add per-instance public keys — done by `provision.py` on first run, or manually here)

- [ ] **Step 12.1: For each existing host, read its DMI UUID**

For each physical machine (thinkpad, itx-5825u, strix-halo, n95):

```bash
ssh root@<target> cat /sys/class/dmi/id/product_uuid
```

Record the UUID and derive the hash:

```bash
echo -n "<dmi-uuid>" | sha256sum | cut -c1-8
```

- [ ] **Step 12.2: Rename each sops file**

For each host, rename the existing sops file to the new per-instance naming:

```bash
# thinkpad (role: compute)
git mv secrets/thinkpad.yaml secrets/compute-<hash>.yaml

# itx-5825u (role: server)
git mv secrets/itx-5825u.yaml secrets/server-<hash>.yaml

# strix-halo (role: ai)
git mv secrets/strix-halo.yaml secrets/ai-<hash>.yaml

# n95 (role: storage)
git mv secrets/n95.yaml secrets/storage-<hash>.yaml
```

- [ ] **Step 12.3: Update `.sops.yaml` with the actual public keys**

For each host, add the actual age public key (from the machine's `/var/lib/sops-nix/key.txt`) to `secrets/.sops.yaml` under the role's `key_group`. The format:

```yaml
keys:
  - &compute-<hash> age1<actual-pubkey>
  - &server-<hash> age1<actual-pubkey>
  - &ai-<hash> age1<actual-pubkey>
  - &storage-<hash> age1<actual-pubkey>

creation_rules:
  - path_regex: secrets/compute-.*\.yaml$
    key_groups:
      - age:
          - *compute-<hash>
  # ... etc
```

- [ ] **Step 12.4: Run `sops updatekeys` on each renamed file**

```bash
sops updatekeys secrets/compute-<hash>.yaml
sops updatekeys secrets/server-<hash>.yaml
sops updatekeys secrets/ai-<hash>.yaml
sops updatekeys secrets/storage-<hash>.yaml
```

This re-encrypts each file to the new recipient list (the single per-instance age key).

- [ ] **Step 12.5: Commit**

One commit per host (because `sops updatekeys` must run per file and the `.sops.yaml` rule must match the new filename):

```bash
git add secrets/
git commit -m "migrate: rename <old-hostname>.yaml to <role>-<hash>.yaml"
```

- [ ] **Step 12.6: Verify a build succeeds for each host with its override**

For each host, create a temporary device-id file and build:

```bash
mkdir -p /tmp/device-<hash>
echo '{ hostname = "<hash>"; hostId = "<hash>"; }' > /tmp/device-<hash>/default.nix
nixos-rebuild build --flake .#<role> --override-input device-id path:/tmp/device-<hash>
```

Expected: build succeeds (the assertion passes, sops file resolves).

---

## Self-Review

**Spec coverage:**

| Requirement (from requirement doc) | Task |
|---|---|
| New `device-id` flake input (non-flake, `path:./device-id`) | Task 1 |
| New `device-id/default.nix` placeholder | Task 1 |
| Assertion in `profiles/base.nix` | Task 5 |
| New `device-identity` module (`role` option) | Task 2 |
| New `hosts/mk-host.nix` helper | Task 3 |
| Rewrite all 6 host files | Task 4 |
| Sops file rename to `<role>-<hash>.yaml` | Task 12 (operational) |
| `.sops.yaml` path_regex by role | Task 7 |
| `profiles/base.nix` sops file selection by device-id | Task 5 |
| `flake.nix` auto-discover hosts via `readDir` | Task 6 |
| New `scripts/provision.py` Nix-packaged Python app | Tasks 8-11 |
| New flake package: `provision` | Task 11 |
| Per-instance sops files (role-prefixed) | Task 7 (rules), Task 12 (files) |

All requirements covered.

**Placeholder scan:** No TBD/TODO. All code blocks contain complete implementations. The only "operational" steps are in Task 12, which is explicitly marked as manual per-host work.

**Type consistency:** `derive_hash` returns `str`, used as `hash_value` in `write_device_id_file` and `main`. `add_age_key` takes `(sops_file, role, anchor_name, public_key)` — called with `(sops_file, args.role, anchor_name, public_key)` in `main`. `find_role_key_group` returns `int` index — used internally by `add_age_key`. Names and signatures match across tasks.
