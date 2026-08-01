# Status

**Last updated:** 2026-07-31 (Phase 2 underway — Jobs 08-11 done: `.bnox/` loader + full D-011 deployment pipeline. D-012 Phase 1 complete: bnox core built & validated end-to-end via `nixosConfigurations.bnox-dev`. Implementation jobs 01-11 done.)

## Current phase

**Implementation — D-012 Phase 2 IN PROGRESS.** Phase 1 (bnox core) complete. Phase 2 underway: **Jobs 08 (`.bnox/` loader) + 09-11 (deployment pipeline: webhook-receiver + dispatcher/sync/build + rollback-prune) DONE** — D-011 deployment pipeline complete (all eval-clean; webhook→NATS→dispatcher→sync/build→restart roundtrip runtime-deferred pending a real thing repo + NATS). **Job 12 (host-install runtime + real daemon shape, D-009 Hermes — fully mock-testable via the loader) remains.** Coordinator model throughout: worker `general` builds, independent `general` checks, loop until sign-off (fix-loops on Jobs 08, 09, 10). Jobs 01-11 done & committed; see `design/jobs/`.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

**D-012 Phase 1 (bnox standalone) — DONE.** Implementation jobs 01-07 complete & verified:
- 01 flake + base · 02 platform · 03 secrets · 04 things core · 05 things shapes + container runtime · 06 profiles · 07 validation host (end-to-end eval)

**Phase 2 (real thing hosting) — IN PROGRESS:** Jobs 08 (`.bnox/` loader) + 09-11 (deployment pipeline) done; next:
1. `.bnox/` loader — **Job 08, DONE**
2. Deployment pipeline (webhook + NATS + rollback, D-011) — **Jobs 09-11, DONE** (pipeline complete; runtime roundtrip deferred)
3. host-install runtime + daemon shape (Hermes, D-009) — **Job 12, next** (fully mock-testable via the loader)

## Blockers / waiting on

None. Phase 2 underway; Jobs 08-11 done, Job 12 (host-install + daemon, D-009) queued next.

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

10 accepted (D-001 `bnox`, D-002 Podman + Nix-only images, D-006 thing hosting, D-007 secrets Hybrid-1 + Hybrid-2-ready, D-008 host key = SSH host key, D-009 Hermes deviation, D-010 NixOS 26.05, D-011 webhook + NATS deployment, D-012 migration scope, D-013 deployment dispatch = central dispatcher). **All blocking questions resolved.** Q6, Q8 non-blocking.
