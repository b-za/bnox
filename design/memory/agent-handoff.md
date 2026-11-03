# Agent Handoff

If you're a new agent picking up this project with no prior context, read this first.

## TL;DR

**`bnox`** is a unified, reusable NixOS base distilling best practices from two existing systems: **uqbn** (old MacBook desktop + Docker host) and **snowi-node** (production VPS). One reusable foundation so adding a system means writing a small host-specific override file, not copy-pasting a whole config.

**Status (2026-11-03): D-014 ACCEPTED — host-repo split + versioned bnox product; implementation in progress.** bnox Phase 1 (core) + Phase 2 (`.bnox/` loader, D-011 pipeline, host-install/daemon) were built and committed via Jobs 01-13. D-014 restructures: no hosts in bnox; product ships as frozen complete copies at `versions/<maj>/<min>/<patch>/` (first `0/0/1`); consumer docs + examples at series level (`versions/<maj>/<min>/docs/`); fixtures inside version copies; host repos (bnox-test, bnox-sn, bnox-bg) own auto-discovery and pin bnox by version dir. **D-014 implementation steps 1-4 DONE (2026-11-03):** restructure → host repos → validation all complete; bnox is public, three private host repos pushed. **Remaining: step 5 operator install of `agenthub` (nixos-anywhere from bnox-bg); then Phase 2 runtime validation (deployment roundtrip + Hermes host-install) on agenthub; then Phase 3 (D-012 uqbn migration) in bnox-sn.**

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

- **D-012 Phase 1 (bnox standalone) + Phase 2 (real thing hosting) implementation — COMPLETE & committed (Jobs 01-13).** See `design/process/05-decisions.md` D-014 for the full host-repo-split + versions model (accepted 2026-11-03). Supersedes: Q-D2 in-repo hosts, README "add a host dir" story.
- **`hosts/agent` committed 2026-11-03 (8217437)** as bootstrap — becomes `agenthub` in bnox-bg during D-014 implementation. Host facts: KVM, x86_64 AMD, BIOS-legacy (GRUB + EF02, no systemd-boot), `/dev/sda` 100G, DHCP on ens3, 3.8G RAM + 4G swap (disko).
- **What's built:** `flake.nix` (inputs nixos-26.05/HM/disko/agenix/nixos-hardware; outputs `nixosModules.bnox`+`bnox-base`, auto-discovered `nixosConfigurations`, `profiles.*`, `hardware`, `lib`); `modules/base/` (SSH hardening, user `bh`, Tailscale, firewall, home-manager); `modules/platform/` (podman/caddy/nats, `mkDefault`-enabled); `modules/secrets/` (agenix infra via SSH host key D-008; file backend systemd-path→restart; nats-kv scaffold); `modules/things/` (multi-component schema + dep/port/subject validators; per-thing user Q9.6; hardening bundle Q9.7; HTTP shapes→Caddy; container runtime→oci-containers + hardening + secret wiring; **`.bnox/` loader** Job 08 — thing-intrinsic fields from repos via `mkDefault`, import-function-file pattern avoiding the attrsOf recursion; **host-install runtime** Job 12 — `<thing>-<component>` systemd unit, thing's user, hardening + `:443 :53` egress, `execStart` from `.bnox/`, Hermes path); `modules/profiles/{minimal,server,desktop}`; `modules/deployment/` (**Job 09** webhook-receiver — Python http.server, per-thing HMAC, separate `/var/lib/bnox/deploy/` secret namespace after iter-1 security fix; **Job 10** pipeline — D-013 central `bnox-deploy-dispatcher` sole subscriber + per-thing sync (thing's user) + build (root) oneshots; **Job 11** rollback-prune timer — newest-3 tarballs); `hosts/bnox-dev/` (validation host exercising BOTH runtimes: container `demo` + host-install `mock-daemon`; evaluates to a real `toplevel`).
- **Phase 2 remaining = operator activity on a linux host** — deploy fresh, runtime-validate (webhook→NATS→dispatcher→sync/build→restart roundtrip + a real Hermes host-install). Needs a real thing repo + running NATS + podman. Then Phase 3 (D-012 uqbn migration).
- Migration of uqbn/snowi-node deferred (D-012) — operator activity, not bnox.

## Phase 2 implementation — COMPLETE (Jobs 08-12)

1. **`.bnox/` loader (Job 08, DONE)** — reads `${source}/.bnox/{thing.nix,<component>.nix}`, `mkDefault`-merges thing-intrinsic fields (deps/secrets/shape/runtime/ingressPort/natsSubject/execStart) into `bnox.things.*`; hard-fails on missing `.bnox/`; host opts in per component. Forced deviation (checker-validated, cycle reproduced): `loader.nix` is an `import`-ed function file `{lib}:{topLevel,thingSubmodule,componentSubmodule}` mirroring `hardening.nix` — a plain top-level module writing `config.bnox.things` with keys from `config.bnox.things` hits infinite recursion (attrsOf strict in keys).
2. **Deployment pipeline (Jobs 09-11, DONE — D-011 + D-013 central-dispatcher topology):** webhook-receiver (Python http.server, per-thing HMAC, separate `/var/lib/bnox/deploy/` namespace owned by receiver — iter-1 security fix moved it OUT of thing secrets to avoid receiver joining every thing's group); `bnox-deploy-dispatcher` (sole subscriber to `host.deploy.>`, routes `.changed`→`<name>-sync`, `.synced`→`<name>-build`); per-thing sync oneshot (thing's user, git fetch+reset, publish `.synced`); per-thing build oneshot (root, `nix build /srv/<name>#images.<sys>.<comp>`→`podman load`→retag `:current`→`podman save` tarball→restart, with `-c safe.directory` iter-2 fix); rollback-prune timer (newest-3 tarballs by mtime, NFR-6: no rollback tooling — operator runs `podman load`+`systemctl restart`).
3. **host-install runtime + daemon shape (Job 12, DONE — D-009/Q9.8/Q9.9):** `<thing>-<component>` systemd unit, thing's user (not root), `ExecStart` from `.bnox/` (added `execStart` to schema + loader), full hardening + `:443 :53` egress, fileSlots wired; bnox provides unit+user+secrets+hardening ONLY (no install/update). daemon.nix stays marker `{}`.

**Recurring technical notes from Phase 2:** the comment-scan regex `(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =` is overly broad — it forced workarounds in TWO jobs (Job 09 Caddy `/*` glob → dedicated vhost; Job 10 literal `#` in `nix build /srv/<name>#images...` → `hashSep = "#"` indirection). Worth relaxing the regex's `/\*` (require paired `*/`) and the `}#` case if this keeps recurring. The deployment runtime mechanics (git/nix/podman/restart) are all runtime-deferred — structurally eval-verified but untested on a real linux host.

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
