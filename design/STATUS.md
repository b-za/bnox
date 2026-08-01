# Status

**Last updated:** 2026-07-31 (D-012 Phase 2 IMPLEMENTATION COMPLETE: Jobs 08-12 done — `.bnox/` loader + full D-011 deployment pipeline + host-install/daemon. bnox core built & validated end-to-end via `nixosConfigurations.bnox-dev`. Implementation jobs 01-12 done.)

## Current phase

**Implementation — D-012 Phase 2 IMPLEMENTATION COMPLETE.** Phase 1 (bnox core) + Phase 2 implementation (`.bnox/` loader, D-011 deployment pipeline webhook+NATS+D-013 dispatcher+sync/build+rollback-prune, host-install runtime + daemon shape for D-009 Hermes) are all built, verified eval-clean, and committed. `nixosConfigurations.bnox-dev` exercises both runtimes (container `demo` + host-install `mock-daemon`). **Remaining Phase 2 work is operator activity on a linux host**: deploy bnox fresh, host a real thing end-to-end (runtime-validate the deployment roundtrip + a real Hermes host-install) — needs a real thing repo + running NATS + podman, untestable on the darwin build host. **Then Phase 3 (D-012): uqbn migration** (MacBook wipe, install bnox, Hermes first). Coordinator model throughout: worker `general` builds, independent `general` checks, loop until sign-off (fix-loops on Jobs 08, 09, 10). Jobs 01-12 done & committed; see `design/jobs/`.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

**D-012 Phase 1 (bnox standalone) — DONE.** Implementation jobs 01-07 complete & verified:
- 01 flake + base · 02 platform · 03 secrets · 04 things core · 05 things shapes + container runtime · 06 profiles · 07 validation host (end-to-end eval)

**Phase 2 (real thing hosting) — IMPLEMENTATION COMPLETE (Jobs 08-12):**
1. `.bnox/` loader — **Job 08, DONE**
2. Deployment pipeline (webhook + NATS + rollback, D-011) — **Jobs 09-11, DONE**
3. host-install runtime + daemon shape (Hermes, D-009) — **Job 12, DONE**

**Remaining Phase 2 = operator activity on a linux host**: deploy bnox fresh, runtime-validate the deployment roundtrip (webhook→NATS→sync/build→restart) + a real Hermes host-install. Then **Phase 3 (D-012): uqbn migration** (MacBook wipe, install bnox, Hermes first thing).

## Blockers / waiting on

None. Phase 2 implementation complete (Jobs 01-12). Next is operator activity: deploy bnox on a linux host to runtime-validate, then Phase 3 (uqbn migration, D-012).

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
