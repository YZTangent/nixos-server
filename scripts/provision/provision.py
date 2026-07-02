"""Provisioning wrapper: reads DMI UUID, generates device-id, invokes nixos-anywhere."""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import shutil
import subprocess
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
            template = repo_root / "secrets" / f"{args.role}-secrets.yaml"
            if not template.exists():
                raise FileNotFoundError(
                    f"Missing secrets template: {template}\n"
                    f"Create it with the plaintext secrets for role '{args.role}' "
                    f"(it will be gitignored)."
                )
            subprocess.run(
                ["sops", "encrypt", "--output", str(sops_secret_file), str(template)],
                check=True,
            )
            print(f"Created {sops_secret_file}")

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
