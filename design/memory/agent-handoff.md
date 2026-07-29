# Agent Handoff

If you're a new agent picking up this project with no prior context, read this first.

## TL;DR

**`bnox`** is a unified, reusable NixOS base distilling best practices from two existing systems: **uqbn** (old MacBook desktop + Docker host) and **snowi-node** (production VPS). One reusable foundation so adding a system means writing a small host-specific override file, not copy-pasting a whole config.

**Status (2026-07-29): D-012 Phase 1 COMPLETE.** The bnox core (base + platform + things + secrets + profiles) is built, verified end-to-end, and committed. `nixosConfigurations.bnox-dev` evaluates to a real system `toplevel`. Phase 2 (real thing hosting) remains.

**Repo layout:** flake product at repo root (`flake.nix` + `modules/` + `hosts/` + `home/` + `lib/`). All design/planning/coordination under `design/` (Nix ignores it). Implementation jobs tracked in `design/jobs/`.

## Where to start

1. **Read `design/STATUS.md` first** — current phase, blockers, what's next.
2. `design/process/06-base-design.md` — the module layout spec (what was built).
3. `design/process/07-diversions.md` — per-host extension pattern.
4. `design/jobs/01..07-*.md` — the per-job worker+checker notes (what each layer does, key decisions).
5. `design/working/open-questions.md` — question state (Q9.5–Q9.9 refinements are accepted; will roll into a future D-006.1).

Source repos (read-only — do not edit): `/Users/bh/code/systems/uqbn/`, `/Users/bh/code/systems/snowi-node/`.

## How to behave

- **Don't make decisions for the user.** Log decisions in `design/process/05-decisions.md` only after the user makes them. Leans OK; frame as leans.
- **Don't edit a prior decision** — supersede with a new entry referencing the old.
- **Update `design/STATUS.md` + `design/memory/changelog.md`** whenever a phase changes, a decision lands, or a job completes. Non-negotiable handoff hygiene.
- **No comments in Nix files** (hard rule, user preference). No option `description` fields either (lean; semantics live in job files + 06-base-design).
- Keep things concise; cite files/line numbers.

## Implementation model (the coordinator pattern — IMPORTANT)

The user requires: **the lead agent does NOT write implementation code.** Work is decomposed into jobs; each job goes through a worker→checker loop:

1. Lead creates a job file in `design/jobs/<NN>-<slug>.md` (scope, constraints, validation steps; see `design/jobs/README.md`).
2. Lead dispatches a **worker** (`general` sub-agent) with a detailed prompt pointing at the job file. Worker builds, self-validates, fills "Worker notes", returns a report. Lead does NOT change Status during the build.
3. Lead sets Status `in-review`, dispatches an independent **checker** (`general` sub-agent) with a verification checklist against the spec.
4. Issues → lead sets Status `needs-fix`, resumes the worker (same `task_id`) with the specific fix; re-dispatch checker. Loop until PASS.
5. Lead sets Status `done`, commits per verified job (`Job NN: ...`), appends changelog.

**Scheduling:** sequential (one job at a time) per user choice. **Commits:** per verified job, per user choice.

**GOTCHA — the `auditor` sub-agent type returns empty results in this environment** (tried twice on Job 01). Use a `general` sub-agent as the independent checker instead — it satisfies the doer/checker separation (different agent instance). This is already the established pattern.

**Nix is available** on this machine (Nix 2.28.4, flakes on; `nixos-rebuild` is NOT — darwin host). Workers/checkers validate with `nix flake check`, `nix flake show`, and throwaway `nixosSystem` evals.

## Current state (snapshot)

- **D-012 Phase 1 (bnox standalone) — COMPLETE & committed.** Jobs 01-07 done.
- **What's built:** `flake.nix` (inputs nixos-26.05/HM/disko/agenix/nixos-hardware; outputs `nixosModules.bnox`+`bnox-base`, auto-discovered `nixosConfigurations`, `profiles.*`, `hardware`, `lib`); `modules/base/` (SSH hardening, user `bh`, Tailscale, firewall, home-manager); `modules/platform/` (podman/caddy/nats, `mkDefault`-enabled); `modules/secrets/` (agenix infra via SSH host key D-008; file backend systemd-path→restart; nats-kv scaffold); `modules/things/` (multi-component schema + dep/port/subject validators; per-thing user Q9.6; hardening bundle Q9.7; HTTP shapes→Caddy; container runtime→oci-containers + hardening + secret wiring); `modules/profiles/{minimal,server,desktop}`; `hosts/bnox-dev/` (validation host, evaluates to a real `toplevel`).
- **Phase 2 (real thing hosting) remains** — see below.
- Migration of uqbn/snowi-node deferred (D-012) — operator activity, not bnox.

## Phase 2 remaining (awaiting user go)

1. **`.bnox/` loader** — read thing-intrinsic fields (shape/runtime/deps/ports) from the thing's repo at `/srv/<name>/.bnox/` and merge into the `bnox.things.*` schema. Currently things are declared inline in host config. Self-contained, testable with a mock thing repo.
2. **Deployment pipeline** (D-011) — webhook receiver + NATS event bus + per-thing sync/build units + rollback tarballs. **Caveat:** genuinely needs a real thing repo + running NATS to validate end-to-end; building it blind has diminishing returns.
3. **host-install runtime + daemon shape effects** (Q9.9/Q9.8) — Hermes's path (D-009); coupled to the loader (needs the thing's ExecStart from `.bnox/`).

## Minor follow-ups (deferred, low priority)

- Granular flake outputs `nixosModules.bnox-platform/things/secrets` (planned in 06; fiddly coupling; marginal value).
- home dotfile expansion (FR-7) — `home/default.nix` is currently minimal.
- `modules/profiles/server.nix` could defensively set `services.xserver.enable = mkDefault false` (checker suggestion).
- NATS JetStream stream creation for nats-api shapes is the thing's runtime concern (not declarative).
- A future D-006.1 should fold in the locked Q9.5–Q9.9 refinements (multi-component, user isolation, hardening, daemon, host-install).

## Technical gotchas (learned this build — read before evaluating)

- **NixOS 26.05 eval requires `fsType` on stub filesystems.** A throwaway `nixosSystem` eval with a stub `fileSystems."/"` needs `fsType = "ext4"` — the ZFS module accesses `.fsType` during eval and errors without it.
- **Throwaway eval trick** (how workers/checkers validate without a real host): build a `nixosSystem` from `nixosModules.bnox` on `x86_64-linux` with a stub `{ fileSystems."/".fsType = "ext4"; boot.loader.systemd-boot.enable = true; }`, then `nix eval` specific `config.*` paths. See any job's checker notes for the pattern.
- **Container service name** (NixOS 26.05, podman): an `oci-containers.containers.<name>` entry generates `systemd.services."podman-<name>"` (NOT `container-<name>`). The things container runtime + secret `restartUnits` rely on this.
- **`hardening.nix` is a dual-purpose Nix file**, not a NixOS module — it's `{ lib }: { bundle, overrideModule }`, loaded via `import` (the bundle is a function; `overrideModule` is wired into the thing submodule list). Don't try to make it a plain module.
- **`mkDefault`/`mkForce` precedence** is the profile/platform override mechanism: platform services are `mkDefault true`; `minimal` profile overrides with `mkForce false`; hosts/profiles override with plain values.
- **The validation host:** `nix eval .#nixosConfigurations.bnox-dev.config.<path>` exercises the full stack via the real flake output. `nix flake check` deep-checks it (`checking NixOS configuration 'nixosConfigurations.bnox-dev'...`).
- **Host configs use `{ bnox, ... }:`** (bnox is a `specialArg` that must be destructured) — NOT `{ ... }:`, which would be an unbound-variable error when referencing `bnox.profiles.*`.
- **Flake auto-discovery path** (`flake.nix`): uses `./hosts/${name}/configuration.nix` — a literal `./hosts/` prefix is required (Nix path interpolation can't start with `${`). A prior form `hostsDir/${name}/...` was a latent bug (treated `hostsDir` as literal text); fixed in Job 07.

## Key user communication preferences (observed)

- **Concise responses** (1-3 sentences unless detail requested; tables OK). No preamble/postamble.
- **Don't railroad** — present tradeoffs honestly; a "lean" is not the answer. Positive mentions aren't commitments.
- **Collaborative and decisive** — likes a clear menu, picks fast, moves on. Don't over-explore.
- **Update STATUS + changelog** on every decision/phase/job. **No emojis** unless requested.

## What an agent should NOT do

- Don't re-litigate D-001 through D-012 (+ locked Q9.5–Q9.9). Wrong? Raise a new open question, don't silently work around.
- Don't write implementation code directly as the lead — use the coordinator pattern (worker + checker sub-agents).
- Don't migrate uqbn/snowi-node until explicitly asked (D-012).
- Don't edit the source repos. Don't run `nixos-rebuild` against them.
- Don't add comments to Nix files.

## File map

| Path | Purpose |
|---|---|
| `README.md` | (repo root) Product overview, user-facing. |
| `flake.nix`, `modules/`, `hosts/`, `home/`, `lib/`, `secrets/` | (repo root) The bnox product. |
| `design/README.md` | Design workspace navigation. |
| `design/STATUS.md` | Current phase, blockers, what's next. **Update often.** |
| `design/process/01..07-*.md` | Vision → inventory → requirements → comparison → decisions → base-design → diversions. |
| `design/working/open-questions.md` | Question state (authoritative). |
| `design/memory/agent-handoff.md` | This file. |
| `design/memory/changelog.md` | Append-only workspace change log. |
| `design/jobs/` | Implementation job tracking (one file per job; `README.md` has the format + workflow). |
