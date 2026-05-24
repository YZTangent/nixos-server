# Use sops-nix for secrets management

We chose sops-nix over agenix, plain age, or manual out-of-band secrets for this cluster. sops-nix stores structured per-host YAML files encrypted with age keys, committed to git. Decryption happens at NixOS activation into `/run/secrets/` (tmpfs). It adds one flake input and handles key rotation cleanly — adding a new host means editing `.sops.yaml` without touching existing secret files, unlike agenix where every `.age` file must be re-encrypted. Plain age was rejected because it would require hand-rolling activation scripts.
