# Job 02: Platform modules

**Status:** done
**Iteration:** 1
**Created:** 2026-07-28

## Scope

Create the platform service modules (`modules/platform/`) — the single-instance-per-host services that things depend on. Also extend the aggregate (`modules/default.nix`) to import them.

**Spec sources (read these):**
- `design/process/06-base-design.md` — "Module breakdown → `modules/platform/`" table (D-002, D-006, FR-5).
- `design/process/05-decisions.md` — D-002 (Podman, Nix-only images, no Docker), D-006 §3 (platform vs thing boundary), D-011 (NATS `host.>` namespace, `host-deploy-logs` stream).
- Reference (adapt patterns): `/Users/bh/code/systems/snowi-node/configuration.nix` lines 183-189 (NATS), 199-220 (Caddy), 224 (Podman).

**Files to create / modify:**

1. `modules/platform/default.nix` — imports `podman.nix`, `caddy.nix`, `nats.nix`.
2. `modules/platform/podman.nix` — `virtualisation.podman.enable = true` (via `lib.mkDefault` so profiles/hosts can override). No Docker. (D-002)
3. `modules/platform/caddy.nix` — `services.caddy.enable = true` (via `lib.mkDefault`). Base Caddy with **no vhosts** — things add vhosts later. Caddy's automatic HTTPS is default-on; do nothing special for it. (D-006, FR-5)
4. `modules/platform/nats.nix` — `services.nats.enable = true` + JetStream enabled + `settings.max_payload = 8388608` (8MB, matches snowi-node). Use `lib.mkDefault` for the enable. (D-006)
5. **Modify** `modules/default.nix` — add `./platform/default.nix` to its imports (alongside the existing base import).

**NOT in this job (deferred):**
- `modules/platform/static-site.nix` — deferred to Job 04 (things/shapes), where its consumer lives. Do NOT create it here.
- NATS subject-namespace reservation (`host.>`, `things.>`) and the `host-deploy-logs` JetStream stream — these are **convention + runtime** concerns (D-006 §8 L0 = NATS open locally; streams are created via the JetStream API at runtime, not in the server config). Do NOT attempt to declare streams or enforce subjects in this module. The design doc captures the convention.

**Key implementation guidance:**
- Use `lib.mkDefault` for the three service `enable` booleans so they're cleanly overridable by profiles (the `minimal` profile will disable platform services) and by individual hosts — without NixOS priority conflicts. The worker may alternatively use `bnox.platform.*.enable` options if it prefers; either is acceptable as long as disabling is clean.
- Caddy vhosts: none in this module. Things (Job 04) and static-site components add them.
- No Docker: do not enable `virtualisation.docker`.

**Constraints:**
- No comments in any Nix file.
- Pin/inputs unchanged (nixos-26.05).
- Do not touch `modules/base/`, `lib/`, `flake.nix`, `home/` (already done in Job 01) beyond the one edit to `modules/default.nix`.

**Validation to run before reporting done:**
- `nix flake check` — must pass.
- `nix flake show` — confirm `nixosModules.bnox` still present.
- Build a throwaway `nixosSystem` from `nixosModules.bnox` and confirm Podman, Caddy, NATS all evaluate to enabled (e.g. `config.virtualisation.podman.enable`, `config.services.caddy.enable`, `config.services.nats.enable`, `config.services.nats.jetstream`). Paste the result.

## Worker notes

**Built (Job 02, iteration 1, 2026-07-28):**

Files created (4) / modified (1):

- `modules/platform/default.nix` — aggregate importing `./podman.nix`, `./caddy.nix`, `./nats.nix`.
- `modules/platform/podman.nix` — `{ virtualisation.podman.enable = lib.mkDefault true; }`. No Docker (D-002 honored — no `virtualisation.docker` reference anywhere).
- `modules/platform/caddy.nix` — `{ services.caddy.enable = lib.mkDefault true; }`. No vhosts (verified `config.services.caddy.virtualHosts = {}` end-to-end). Automatic HTTPS left at upstream default per spec.
- `modules/platform/nats.nix` — NATS enabled via `lib.mkDefault`, `jetstream = true`, `settings.max_payload = 8388608` (mirrors snowi-node configuration.nix:183-189). No streams, no subject-namespace reservation (per spec — these are runtime/convention concerns per D-006 §8 L0 + D-011; the design doc captures the convention).
- `modules/default.nix` — added `./platform/default.nix` to `imports` (the only Job-01-file edit allowed; flake.nix untouched, no `nixosModules.bnox-platform` added since the hard constraint says modify only `modules/default.nix`).

**Key decisions:**

1. **Used `lib.mkDefault` (not `bnox.platform.*.enable` options).** The literal scope items 2-4 (lines 19-21 of this spec) explicitly say "via `lib.mkDefault`", and the spec's key guidance (line 29) says either approach is acceptable as long as disabling is clean. `mkDefault` is the simpler reading: a profile/host that wants to disable a service just writes `services.caddy.enable = false` (priority 100), which cleanly overrides `mkDefault`'s priority 1000. Verified end-to-end (see validation) — setting all three to false in a throwaway host produces `podman=false caddy=false nats=false` with no priority conflict. The `minimal` profile (later job) will be able to disable all three with three plain `= false` lines. No reason to introduce a parallel `bnox.platform.*` option namespace for the same effect.

2. **`jetstream = true` and `settings.max_payload = 8388608` are plain values, not wrapped in `mkDefault`.** Spec line 21 says "Use `lib.mkDefault` for the enable" — only the enable. A future profile/thing that wants NATS without JetStream is an implausible case, and even if needed, the same priority-100-override rule applies; but I followed the spec literally and left these as plain values to avoid over-generalizing.

3. **Did NOT add `nixosModules.bnox-platform` to flake.nix.** The base-design doc lists it as a planned output, but this job's hard constraints say "Create ONLY: `modules/platform/default.nix`, `podman.nix`, `caddy.nix`, `nats.nix`; and modify `modules/default.nix`". Adding a flake output would be a second edit to `flake.nix`, which the constraints forbid ("Only the one edit to `modules/default.nix`; do not modify other Job 01 files"). `nixosModules.bnox-platform` is left for a later job that's explicitly allowed to touch the flake.

**Validation output:**

- Comment scan: `rg -n '(^|[^a-zA-Z0-9"])#|/\*' --glob '*.nix' modules/platform modules/default.nix` → exit 1 (no matches). Hard constraint met.
- `nix flake check` →
  ```
  checking flake output 'lib'...
  checking flake output 'nixosModules'...
  checking NixOS module 'nixosModules.bnox'...
  checking NixOS module 'nixosModules.bnox-base'...
  checking flake output 'nixosConfigurations'...
  checking flake output 'packages'...
  warning: The check omitted these incompatible systems: x86_64-linux
  ```
  (cross-system warning is the same benign Job-01 noise — empty `packages.x86_64-linux` on an aarch64-darwin host; nothing to check.)
- `nix flake show` →
  ```
  git+file:///Users/bh/code/systems/bnox
  ├───lib: unknown
  └───nixosModules
      ├───bnox: NixOS module
      └───bnox-base: NixOS module
  ```
  (`nixosModules.bnox` still present; `packages` and `nixosConfigurations` empty-attrset → not rendered, as expected.)
- **Throwaway `nixosSystem` eval** (x86_64-linux, built from `nixosModules.bnox` with stub `fileSystems`/`boot` so `nixosSystem` evaluates; mirrors the Job-01 checker's stub-filesystem trick):
  ```
  nix eval --impure --raw --expr '…nixosSystem { modules = [ f.nixosModules.bnox { fileSystems."/".device="/dev/null"; … }]; }'
  => { podman=true caddy=true nats=true jetstream=true max_payload=8388608 docker=false caddyVirtualHosts=[] }
  ```
  Podman / Caddy / NATS all enabled; JetStream on; `max_payload` 8MB; Docker NOT installed (D-002); Caddy has zero vhosts (spec — things add them later).
- **Override proof** (same eval, plus `{ virtualisation.podman.enable=false; services.caddy.enable=false; services.nats.enable=false; }` in the host module):
  ```
  => { podman=false caddy=false nats=false }
  ```
  `mkDefault` priority-1000 cleanly overridden by a plain `false` (priority 100) — no conflict. Confirms profiles/hosts can disable cleanly.

## Checker notes

**VERDICT: PASS** — 2026-07-28 (independent checker, iteration 1).

All 9 checklist items OK. One-line result per item:

1. **Scope — OK.** Exactly 4 platform files created (`modules/platform/{default,podman,caddy,nats}.nix`) + the single one-line edit to `modules/default.nix`. No `static-site.nix` (Job 04 deferred). `git status --short` shows only `M modules/default.nix` + untracked `modules/platform/` (4 files) + this job doc. `flake.nix`, `modules/base/`, `lib/`, `home/` all untouched (`git diff HEAD -- flake.nix` empty; `git status --short modules/base/ lib/ home/` empty).
2. **No comments — OK.** `rg -n '(^|[^a-zA-Z0-9"])#|/\*' modules/platform modules/default.nix` → exit 1 (no matches).
3. **podman.nix — OK.** `virtualisation.podman.enable = lib.mkDefault true;` (podman.nix:3). No `virtualisation.docker` reference anywhere in `modules/` (`rg -n 'docker' modules/` → no matches; D-002 honored).
4. **caddy.nix — OK.** `services.caddy.enable = lib.mkDefault true;` (caddy.nix:3). `services.caddy.virtualHosts` empty — verified end-to-end: throwaway eval returns `caddyVirtualHostsCount = 0`.
5. **nats.nix — OK.** `enable = lib.mkDefault true`, `jetstream = true`, `settings.max_payload = 8388608` (nats.nix:3-7). No JetStream streams declared, no subject-namespace reservation (`host.>`/`things.>`) — confirmed by reading the 8-line file end-to-end. Mirrors snowi-node configuration.nix:183-189. D-006 §8 L0 + D-011 boundary honored (streams/subjects are runtime/convention).
6. **modules/default.nix — OK.** Imports BOTH `./base/default.nix` (Job 01, still present at default.nix:3) and `./platform/default.nix` (new, default.nix:4). Base import not clobbered.
7. **mkDefault correctness — OK.** Override repro: throwaway host with `virtualisation.podman.enable = false; services.caddy.enable = false; services.nats.enable = false;` (all plain, priority 100) layered over `nixosModules.bnox` yields `{ podman=false caddy=false nats=false }`. Exit 0, **zero** priority-conflict/warn/error messages in stderr — clean override of `mkDefault`'s priority 1000. Confirms profiles/hosts can disable cleanly.
8. **Independent validation — OK.** All three commands reproduced below; outputs match worker's claims.

   `nix flake check`:
   ```
   warning: Git tree '/Users/bh/code/systems/bnox' is dirty
   evaluating flake...
   checking flake output 'lib'...
   checking flake output 'nixosModules'...
   checking NixOS module 'nixosModules.bnox'...
   checking NixOS module 'nixosModules.bnox-base'...
   checking flake output 'nixosConfigurations'...
   checking flake output 'packages'...
   warning: The check omitted these incompatible systems: x86_64-linux
   ```
   (EXIT 0. The dirty-tree warning is expected — Job 02 changes are uncommitted/in-progress. The x86_64-linux warning is the same benign Job-01 noise: empty `packages.x86_64-linux` on an aarch64-darwin host, nothing to check.)

   `nix flake show`:
   ```
   git+file:///Users/bh/code/systems/bnox
   ├───lib: unknown
   └───nixosModules
       ├───bnox: NixOS module
       └───bnox-base: NixOS module
   ```
   (EXIT 0. `nixosModules.bnox` still present.)

   **Throwaway `nixosSystem` eval** (x86_64-linux, `nixosModules.bnox` + stub `fileSystems`/`boot`, mirrors Job-01 checker trick):
   ```
   {"caddy":true,"caddyVirtualHostsCount":0,"docker":false,"jetstream":true,"max_payload":8388608,"nats":true,"podman":true}
   ```
   Podman / Caddy / NATS all `true`; JetStream `true`; `max_payload = 8388608` (8MB); Docker `false` (D-002); Caddy `virtualHosts` count `0` (spec — things add them later).

   **Override repro** (same eval + all three enables set `false`):
   ```
   {"caddy":false,"nats":false,"podman":false}
   ```
   (EXIT 0, clean stderr — see item 7.)

9. **Worker's flagged interpretation — OK (correct reading).** The worker did NOT add a `nixosModules.bnox-platform` flake output. The job's hard constraint (spec line 36: "Do not touch `modules/base/`, `lib/`, `flake.nix`, `home/` (already done in Job 01) beyond the one edit to `modules/default.nix") explicitly forbids editing `flake.nix`. A `nixosModules.bnox-platform` output can only be added by editing `flake.nix`, so the worker's choice to defer it is the only constraint-compliant reading. `06-base-design.md` lists `nixosModules.bnox-platform` as a *planned* output, but does not assign it to this job; granular isolated outputs are a later-job concern (the platform modules are reachable today via `nixosModules.bnox` → `modules/default.nix` → `modules/platform/default.nix`, which is the primary consumer path). Confirmed `flake.nix` byte-identical to HEAD (`git diff HEAD -- flake.nix` empty) — constraint not silently violated.

No issues found. Approved.

## Sign-off
Approved 2026-07-28 — independent checker, iteration 1, verdict PASS (all 9 items OK; `nix flake check` and throwaway `nixosSystem` evals reproduced; mkDefault-override repro clean; scope/constraint compliance verified via git status/diff).
