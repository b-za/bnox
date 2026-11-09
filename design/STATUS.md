# Status

**Last updated:** 2026-11-09 (Series 0.2 `0/2/0` DONE and verified on agenthub: repinned bnox-bg, dropped the host-side sudo divergence, rebuilt, fresh boot comes up `running` with stream-init active and the `host-deploy-logs` stream created. D-015 records the rationale. Open follow-up found during verification: consumer `nix flake update bnox` re-resolves bnox's transitive nixpkgs to the nixos-26.05 branch tip instead of the version-frozen tarball — agenthub has been running branch-tip nixpkgs since the 0/1 bumps; fix belongs in host repos (explicit follows) + a series-docs note. Previous: Series 0.1 at patch 2 `0/1/2` DONE — key-only SSH fully enforced.)

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
2. bnox restructure — **DONE** (`6abd885`): `versions/0/0/1/` (product copy, fixtures in, manifest `done`, throwaway eval clean), `versions/0/0/docs/` + `docs/examples/` (8 pages + 3 example hosts), root flake + hosts/ deleted, README rewritten
3. Host repos — **DONE**: bnox-bg (`agenthub`), bnox-test (`bnox-test`, things sourced from `bnox.fixtures.*`), bnox-sn (`macbook-pro-2014-15`, trimmed to fix pre-existing eval breakage: dropped `hardware.camera`/pulseaudio/sddm+plasma5/cpuFreqGovernor/trackpoint — desktop profile's ly+qtile+pipewire stand). All git-init'd, pushed (private)
4. Validate — **DONE**: all three hosts eval to real toplevels against the `github:b-za/bnox?dir=versions/0/0/1` pin; bnox-test exercises both runtimes (`podman-demo-web` + `mock-daemon-main` services resolve). bnox repo made **public** (`gh repo edit --visibility public`; pre-scan of all history for IPs/credentials clean — only slot-name "token" + prose hits). Host-repo remotes stored as `https://github.com/...` because the user's global gitconfig has two circular insteadOf rewrites (https→ssh wins for stored-https, ssh→https breaks stored-ssh) — left global config untouched
5. agenthub install via nixos-anywhere from bnox-bg (operator): `nix run github:numtide/nixos-anywhere -- root@129.121.109.45 --flake .#agenthub`

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
