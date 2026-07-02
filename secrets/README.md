# secrets/

SOPS-encrypted per-instance secret files. Each file is encrypted to exactly one age key — the private key of the machine it belongs to.

## How it works

1. `nix run .#provision <role> <target>` generates a fresh age keypair for the new machine.
2. The public key is added to `.sops.yaml` under the matching `creation_rules` entry for that role.
3. The plaintext `<role>-secrets.yaml` template is encrypted with `sops encrypt --output <role>-<hash>.yaml`.
4. The private key is installed onto the machine at `/var/lib/sops-nix/key.txt` via `nixos-anywhere --extra-files`.
5. At runtime, `sops-nix` uses that private key to decrypt the machine's secret file.

There is no shared admin key. Each encrypted file can only be decrypted by the machine it was provisioned for.

## Files

| Pattern | Description |
|---|---|
| `<role>-<hash>.yaml` | Encrypted secrets for a specific instance. Committed to git. |
| `<role>-secrets.yaml` | Plaintext template with the actual secret values for a role. **Gitignored — never commit.** |
| `.sops.yaml` | SOPS config mapping path regexes to recipient age public keys. |

## Before provisioning a new machine

Create the plaintext template for its role if it doesn't exist:

```
secrets/compute-secrets.yaml
secrets/server-secrets.yaml
secrets/ai-secrets.yaml
secrets/storage-secrets.yaml
```

Example for a compute node:

```yaml
k3s-token: 'your-k3s-cluster-token'
k3s-vrrp-password: 'your-vrrp-password'
```

These files are listed in `.gitignore`. Keep them out of version control.

## Re-provisioning

If a machine is re-provisioned, `provision` will skip creating the secret file if it already exists (keyed by the DMI UUID hash). To force re-encryption, delete the old `<role>-<hash>.yaml` before running `provision`.
