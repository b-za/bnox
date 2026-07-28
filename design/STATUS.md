# Status

**Last updated:** 2026-07-28 (Repo reorganized: design material moved under `design/`; product will live at repo root. Both design docs in review; ready for implementation)

## Current phase

**Phase 6 of 6 — Diversions pattern** (draft in review)

`process/07-diversions.md` drafted — per-host extension pattern (3 orthogonal diversion axes: profile × hardware × things; auto-discovered host enumeration; ~30-line host config). Resolved Q-D1 (explicit profile import), Q-D2 (auto-discovery), Q-D3 (3-profile set: minimal/server/desktop). Both design docs (`06-base-design.md`, `07-diversions.md`) now complete and in review. Implementation can begin once user signs off.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

1. ~~Resolve blocking open questions~~ — **DONE** (D-001 through D-012)
2. ~~Draft `process/06-base-design.md` (target flake + module layout)~~ — **DONE**
3. ~~Draft `process/07-diversions.md` (per-host extension pattern)~~ — **DONE**
4. User reviews both design docs; revise if needed
5. **Implementation begins** — writing `flake.nix`, `modules/`, first host config

## Blockers / waiting on

None. Awaiting user sign-off on `process/06-base-design.md` + `process/07-diversions.md` before implementation begins.

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
