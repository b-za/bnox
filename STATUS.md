# Status

**Last updated:** 2026-07-27 (project named `bnox`, git initialised)

## Current phase

**Phase 2 of 6 — Requirements synthesis**

Discovery of both existing systems is complete. Initial requirements list and comparison drafted. Awaiting user review before entering decisions phase.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

1. User reviews `process/03-requirements.md` and `process/04-comparison.md`
2. Resolve blocking open questions Q2–Q5 in `working/open-questions.md` (Q1 resolved → D-001 `bnox`):
   - Q2 container runtime (Docker vs Podman)
   - Q3 secrets manager (sops-nix vs agenix vs none)
   - Q4 NixOS version pin (24.11 vs 25.05)
   - Q5 migration scope (new only / retro-fit uqbn / retro-fit snowi-node)
3. Walk through `process/05-decisions.md` one decision at a time
4. Draft `process/06-base-design.md` (target flake + module layout)
5. Draft `process/07-diversions.md` (per-host extension pattern)

## Blockers / waiting on

- User input on Q2–Q5 above. No design work should proceed until at least Q2, Q3, Q4 are resolved.

## Phase tracker

| # | Phase | Status |
|---|---|---|
| 1 | Discovery | done |
| 2 | Requirements | in progress (draft ready for review) |
| 3 | Comparison | draft done (rolled into phase 2 above) |
| 4 | Decisions | not started |
| 5 | Base design | not started |
| 6 | Diversions pattern | not started |

## Decision count

1 accepted (D-001 project name = `bnox`), 0 proposed, 7 open questions (4 blocking).
