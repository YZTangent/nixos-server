# Use BindReadOnlyPaths to expose user-owned files to system services

The llama-server module runs as the `llama` system user, which cannot traverse `/home/<user>/` (mode 700). Rather than relaxing home directory permissions or copying files into the store, we expose user-owned paths (dotfiles config, LM Studio models) to the service via systemd `BindReadOnlyPaths`.

`BindReadOnlyPaths` creates bind mounts inside the service's private filesystem namespace before privileges are dropped. Systemd sets up the mounts as root — bypassing the 700 barrier — then drops to the service user via `setuid`/`setgid`. The service user inherits the namespace and sees the files at their mapped system paths (`/etc/llama-server/`, `/var/lib/llama-lmstudio/`) without needing to traverse the home directory. File permissions inside the mount still apply: directories must be `755` and files `644` (the default umask) for the service user to read them.

This keeps the home directory locked down, avoids copying files into the nix store (which would break live editing), and requires no ACLs or supplementary group membership.

## Considered Options

- **`chmod o+x /home/<user>`** — lets the service traverse the home directory, but relaxes permissions system-wide, not just for this service.
- **`environment.etc` store copy** — creates a store-backed `/etc/` entry; edits require `nixos-rebuild` to take effect, defeating the live-edit dotfiles workflow.
- **Symlink at a world-readable path** — a symlink in `/etc/` pointing back into the home directory still requires the service user to follow the link through the 700 directory.
