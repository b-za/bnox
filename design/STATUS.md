# Status

**Last updated:** 2026-11-03 (D-014 ACCEPTED — host-repo split + versioned bnox product. `agent` host committed in-repo as bootstrap (8217437), to be relocated as `agenthub` → bnox-bg. Next: D-014 implementation — bnox restructure to `versions/0/0/1/`, series docs/examples, three host repos.)

## Current phase

**D-014 implementation (host-repo split + versioned product).** Architecture decided 2026-11-03: bnox loses `hosts/` and the root flake; product ships as frozen complete copies at `versions/<maj>/<min>/<patch>/` (first: `0/0/1` = current tree minus hosts) with per-version manifest; consumer docs + examples live at series level (`versions/0/0/docs/`); fixtures (demo-thing, mock-daemon) move inside version copies as flake outputs. Hosts live in separate repos that own auto-discovery and pin bnox by version dir: **bnox-test** (`bnox-test` host, renamed bnox-dev), **bnox-sn** (`macbook-pro-2014-15` + future uqbn MacBook), **bnox-bg** (`agenthub`, renamed agent). Prior to this: D-012 Phase 1 + Phase 2 implementation complete (Jobs 01-12, all eval-clean via `nixosConfigurations.bnox-dev`). Remaining Phase 2 operator activity (runtime-validate deployment roundtrip + Hermes host-install) now targets `agenthub` via bnox-bg. Then Phase 3 (D-012): uqbn migration → bnox-sn.

## What's done

- [x] Discovery: read uqbn fully (`configuration.nix`, `flake.nix`, `home.nix`, `hardware-configuration.nix`, `modules/`)
- [x] Discovery: read snowi-node fully (`configuration.nix`, `configuration-minimal.nix`, `flake.nix`, `home.nix`, `disk-config.nix`, `lib/default.nix`, representative modules, `README.md`, `AGENTS.md`)
- [x] Requirements list drafted (`process/03-requirements.md`)
- [x] Side-by-side comparison drafted (`process/04-comparison.md`)
- [x] Open questions catalogued (`working/open-questions.md`)

## What's next

**D-014 implementation steps:**
1. Record D-014 — **DONE 2026-11-03** (decisions + STATUS + changelog + handoff)
2. bnox restructure: `versions/0/0/1/` (tree minus hosts + fixtures + manifest), `versions/0/0/docs/` + `docs/examples/`, delete root `flake.nix` + `hosts/`, adapt version flake (drop auto-discovery, add `fixtures` output)
3. Create host repos: bnox-bg (`agenthub`), bnox-test (`bnox-test` + fixtures consumed from pinned input), bnox-sn (`macbook-pro-2014-15`, fix/flag its pre-existing eval breakage); git init + remotes
4. Validate: every host repo evals against pinned `0/0/1`; version copy eval-clean via throwaway eval
5. agenthub install via nixos-anywhere from bnox-bg (operator)

**Remaining Phase 2 = operator activity on a linux host** (`agenthub` via bnox-bg): deploy fresh, runtime-validate the deployment roundtrip (webhook→NATS→sync/build→restart) + a real Hermes host-install. Then **Phase 3 (D-012): uqbn migration** (MacBook wipe, install bnox, Hermes first thing) → bnox-sn.

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

11 accepted (D-001 `bnox`, D-002 Podman + Nix-only images, D-006 thing hosting, D-007 secrets Hybrid-1 + Hybrid-2-ready, D-008 host key = SSH host key, D-009 Hermes deviation, D-010 NixOS 26.05, D-011 webhook + NATS deployment, D-012 migration scope, D-013 deployment dispatch = central dispatcher, D-014 host-repo split + versioned product). **All blocking questions resolved.** Q6, Q8 non-blocking. D-014 supersedes Q-D2 (07-diversions).
