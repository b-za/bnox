# Status

**Last updated:** 2026-07-29 (D-012 Phase 1 complete: bnox core built & validated end-to-end via `nixosConfigurations.bnox-dev`. Implementation jobs 01-07 done.)

## Current phase

**Implementation — D-012 Phase 1 COMPLETE.** bnox core (base + platform + things + secrets + profiles) is built and proven to compose end-to-end into a real NixOS system config (`nixosConfigurations.bnox-dev` evaluates to a real `toplevel` derivation). Coordinator model throughout: worker `general` builds, independent `general` checks, loop until sign-off (fix-loops on Jobs 05 & 07). Jobs 01-07 done & committed; see `design/jobs/`.

**Phase 2 (real thing hosting) remaining:** `.bnox/` loader, deployment pipeline (webhook + NATS + rollback, D-011), host-install runtime + daemon shape (Hermes, D-009).

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

**D-012 Phase 1 (bnox standalone) — DONE.** Implementation jobs 01-07 complete & verified:
- 01 flake + base · 02 platform · 03 secrets · 04 things core · 05 things shapes + container runtime · 06 profiles · 07 validation host (end-to-end eval)

**Phase 2 (real thing hosting) — awaiting user go:**
1. `.bnox/` loader (thing-intrinsic fields from thing repos)
2. Deployment pipeline (webhook + NATS + rollback, D-011)
3. host-install runtime + daemon shape (Hermes, D-009)

## Blockers / waiting on

None. D-012 Phase 1 complete. Phase 2 awaits user authorisation.

## Phase tracker

| # | Phase | Status |
|---|---|---|
| 1 | Discovery | done |
| 2 | Requirements | done |
| 3 | Comparison | done |
| 4 | Decisions | **done** (D-001 through D-012 accepted) |
| 5 | Base design | **done** (draft in review) |
| 6 | Diversions pattern | **done** (draft in review) |

## Decision count

9 accepted (D-001 `bnox`, D-002 Podman + Nix-only images, D-006 thing hosting, D-007 secrets Hybrid-1 + Hybrid-2-ready, D-008 host key = SSH host key, D-009 Hermes deviation, D-010 NixOS 26.05, D-011 webhook + NATS deployment, D-012 migration scope). **All blocking questions resolved.** Q6, Q8 non-blocking.
