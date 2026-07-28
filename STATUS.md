# Status

**Last updated:** 2026-07-27 (D-012 migration scope accepted; ALL blocking questions resolved; Phase 4 Decisions complete → ready for Phase 5 Base design)

## Current phase

**Phase 5 of 6 — Base design**

All blocking open questions resolved (D-001 through D-012 accepted). The architecture is fully specified. Ready to draft `process/06-base-design.md` (target flake + module layout) — translating the 12 decisions into concrete Nix code structure.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

1. ~~Resolve blocking open questions~~ — **DONE** (D-001 through D-012)
2. Draft `process/06-base-design.md` (target flake + module layout) — translate the 12 decisions into concrete Nix structure
3. Draft `process/07-diversions.md` (per-host extension pattern)
4. Implementation begins (writing `flake.nix`, modules, etc.)
3. Walk through `process/05-decisions.md` one decision at a time
4. Draft `process/06-base-design.md` (target flake + module layout)
5. Draft `process/07-diversions.md` (per-host extension pattern)

## Blockers / waiting on

None. All blocking questions resolved. Awaiting user authorisation to begin Phase 5 (base design).

## Phase tracker

| # | Phase | Status |
|---|---|---|
| 1 | Discovery | done |
| 2 | Requirements | done |
| 3 | Comparison | done |
| 4 | Decisions | **done** (D-001 through D-012 accepted) |
| 5 | Base design | next |
| 6 | Diversions pattern | pending |

## Decision count

9 accepted (D-001 `bnox`, D-002 Podman + Nix-only images, D-006 thing hosting, D-007 secrets Hybrid-1 + Hybrid-2-ready, D-008 host key = SSH host key, D-009 Hermes deviation, D-010 NixOS 26.05, D-011 webhook + NATS deployment, D-012 migration scope). **All blocking questions resolved.** Q6, Q8 non-blocking.
