# Open Questions

Things needing the user's input before we can finalize decisions. Ordered by blocking priority.

## Q1: Project name ✅ RESOLVED → D-001

**Resolved 2026-07-27:** name is **`bnox`**. See `process/05-decisions.md` D-001 for rationale. Other candidates that were considered and rejected: `baseos` (placeholder), `noxos` (collision with active NoxOS-org), `snowi-os` (too host-specific), `bhos`, `keystone`, `rootstockos`, `nyxos`.

---

## Q2: Container runtime (blocking — affects module pattern)

- **Docker** — what uqbn uses; familiar; Portainer ecosystem; widely documented.
- **Podman + quadlets** — what snowi-node uses; daemonless; systemd-native; more Nix-idiomatic; works seamlessly with Nix-built images via `mkQuadlet`.

Either way, the `dockerTools.streamLayeredImage` image-build pattern from snowi-node works (both runtimes can load the resulting tarball).

**Need from user:** pick one. Recommendation: **Podman + quadlets** unless there's a specific Docker-only tool the user needs (e.g. Portainer, specific compose files).

---

## Q3: Secrets manager (blocking — affects flake inputs + module pattern)

Neither system uses one. Options:
- **sops-nix** — most popular; uses SOPS + age/PGP; supports remote keys; mature.
- **agenix** — age-based; simpler; widely used.
- **none (env files on target)** — what snowi-node does today; works but not encrypted at rest in the repo.

**Need from user:** pick one. Recommendation: **sops-nix with age** for maturity and flexibility.

---

## Q4: NixOS version (blocking — affects all inputs)

- **snowi-node:** 24.11 (stable, what production runs today)
- **uqbn:** 25.05 (newer)

**Need from user:** pin one for the base. Recommendation: **24.11** for now (matches production; 25.05 is bleeding edge). Re-evaluate when 25.11 lands.

---

## Q5: Migration scope (blocking for some design decisions)

- **Option A:** Base is for **new systems only**. Existing uqbn and snowi-node stay as-is.
- **Option B:** Base is the target; **retro-fit snowi-node** onto it (high effort, production risk).
- **Option C:** Base is the target; **retro-fit uqbn** onto it (medium effort, low risk).

**Need from user:** pick a scope. Recommendation: **A initially** (base for new systems only), with **C** as a near-term follow-up (uqbn is low-risk to migrate) and **B** as a long-term goal.

---

## Q6: macOS build capability (non-blocking but design-relevant)

snowi-node explicitly says "Cannot run nixos-rebuild from macOS — must build on the VPS itself." This is partly because of the Go service image builds. The base could:
- **Option A:** Standardize on **remote build** (rsync + build on target) — matches snowi-node today.
- **Option B:** Standardize on **cross-build from macOS** (set up a remote builder for aarch64-darwin → x86_64-linux).
- **Option C:** Document both, pick per-host.

**Need from user:** preference. Recommendation: **A** for simplicity; revisit if/when build latency becomes painful.

---

## Q7: nixpkgs channel size (non-blocking)

snowi-node uses `nixos-24.11-small`. uqbn uses `nixpkgs/nixos-25.05`. The `-small` channel is faster to fetch but excludes some packages. Should the base use `-small`?

**Need from user:** preference. Recommendation: **no `-small`** for the base (more packages available; matches uqbn; only matters at fetch time).

---

## Q8: uqbn role trajectory (context only)

Not blocking, but worth noting: uqbn's role may evolve. If the user wants it headless eventually, the base's desktop profile becomes optional. If they want to keep it as a desktop, the desktop profile is load-bearing.

**Need from user:** confirm uqbn's role trajectory (stays desktop / goes headless / both at different times).
