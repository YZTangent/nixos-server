# Issue: Hermes Gateway Plan Review — Open Items

Reviewed at: 2026-07-21

## 1. `ReadWritePaths` vs `BindPaths` read-only semantics

`BindPaths = [ "${cfg.hermesHome}:/var/lib/hermes" ]` combined with `ReadWritePaths = [ "/var/lib/hermes" ]` makes the entire bind mount read-write, including config/secrets files (`config.yaml`, `SOUL.md`, `.env`, `auth.json`). This is functionally correct (the agent needs to write `state.db`, `sessions/`, etc.), but it means a compromised agent could modify or delete secrets and config.

**Action:** Note for v2 — consider mounting config read-only via `BindReadOnlyPaths` and giving a separate writable path for runtime data.

**Status:** Deferred to v2

---

## 2. `MemoryMax` / `CPUQuota` — no tuning guidance

`MemoryMax = "2G"` and `CPUQuota = "80%"` are fine starting points, but neither the requirement nor the plan documents how to adjust them.

**Action:** Add a comment in the module pointing to where to change these, or document tuning guidance.

**Status:** Low priority, add when first deployed

---

## 3. Task 4, Step 1 — underspecified flake.nix edits

The plan shows the concept for the dummy config dir in the checks block but doesn't show how it fits into the existing check structure. No concrete edit targets are specified.

**Action:** Flesh out Task 4, Step 1 with actual `flake.nix` edit targets before implementation.

**Status:** Blocks Task 4 — needs resolution before execution

---

## 4. Service logging configuration

No `StandardOutput`/`StandardError` configuration in the systemd service. Default is journal, which works, but this should be an explicit decision.

**Action:** Decide whether to add explicit `StandardOutput=journal` / `StandardError=journal`, or `journal+console` for debugging.

**Status:** Optional polish

---

## 5. Health check / reload semantics

No `ExecReload` or health monitoring in the service unit. If the service enters a bad state, there's no signal mechanism.

**Action:** Check if `hermes gateway` supports reload signals. If so, add `ExecReload`. If not, note for v2.

**Status:** Deferred — depends on hermes binary capabilities

---

## Summary

| # | Item | Priority | Status |
|---|------|----------|--------|
| 1 | Config vs runtime data isolation | Medium | Deferred to v2 |
| 2 | Memory/CPU tuning guidance | Low | Add at first deploy |
| 3 | Task 4 concrete edits | High | Blocks implementation |
| 4 | Explicit logging config | Low | Optional |
| 5 | Health/reload semantics | Low | Deferred |
