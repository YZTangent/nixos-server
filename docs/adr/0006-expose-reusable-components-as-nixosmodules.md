# Expose Reusable Components as nixosModules

We need a way for external flakes (like a desktop flake) to consume the service modules in this repository (e.g., llama-server, k3s, etc.) without duplicating them or relying on brittle file paths.

We decided to expose the reusable components as standard `nixosModules.*` flake outputs directly from this flake.

We considered:
1. **Importing by relative path (`inputs.nixos-server + "/services/llama-server.nix"`)**: This would work for some modules, but it makes the internal file layout an implicit API and breaks for anything referencing `inputs` via `specialArgs` (e.g., the ai profile's `hermes-agent` from `inputs.llm-agents`).
2. **Creating a separate shared flake**: Overkill for the current scale and would unnecessarily complicate the workflow of updating a service and deploying it to the cluster in one step.

By exporting `nixosModules`, the internal hosts can continue importing by relative path (no behavioral change to existing configurations), while external consumers get a clean, supported interface that properly closes over external inputs.
