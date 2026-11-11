# Job 03: Secrets modules

**Status:** done
**Iteration:** 1
**Created:** 2026-07-28

## Scope

Create the secrets layer (`modules/secrets/`): agenix wiring for infra secrets (D-007/D-008) + the swappable things-secrets backend (file = default, nats-kv = scaffold). Define the `fileSlots` interface that the things abstraction (Job 04) will populate.

**Spec sources (read these):**
- `design/process/06-base-design.md` — "Module breakdown → `modules/secrets/`" table.
- `design/process/05-decisions.md` — D-007 (two-layer architecture; file backend default; nats-kv designed-for not built), D-008 (host key = SSH host key `/etc/ssh/ssh_host_ed25519_key`; recovery recipient is a per-host rules-file concern, NOT enforced here).
- `design/working/open-questions.md` — Q9.6 (secret files chown'd to thing's user), Q9.7 (thing paths).

**Files to create / modify:**

1. **Modify `flake.nix`** — add `agenix.nixosModules.default` to the `nixosModules.bnox` imports list (alongside the existing `home-manager.nixosModules.home-manager`). Rationale: `age.*` options require the agenix NixOS module; injecting at the flake keeps `modules/` free of flake-input references (same pattern as home-manager in Job 01). Do NOT add it only to `bnox-base` (base has no secrets). Do NOT add granular `nixosModules.bnox-secrets` output (out of scope; tracked separately).
2. `modules/secrets/default.nix` — imports `infra.nix`, `backends/file.nix`, `backends/nats-kv.nix`; defines the two options below.
3. `modules/secrets/infra.nix` — agenix policy: `age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` and `age.identityPaths` likewise (D-008). No actual `age.secrets.*` declarations (those are per-host, in the host's rules file). No recovery-key handling here (that's a per-host rules-file recipient concern).
4. `modules/secrets/backends/file.nix` — **Hybrid-1 default backend**, active when `bnox.secrets.thingsBackend == "file"`. Implements the slot mechanism (see interface below).
5. `modules/secrets/backends/nats-kv.nix` — **Hybrid-2 scaffold**, active when `bnox.secrets.thingsBackend == "nats-kv"`. NOT implemented day-1 (D-007): emit an `assertions` entry with `assertion = false` and a clear message ("nats-kv secrets backend not implemented yet (D-007 Hybrid-2)"). Gated by `mkIf` so it's inert under the default `file` backend.
6. **Modify `modules/default.nix`** — add `./secrets/default.nix` to imports (alongside base + platform).

## Option interface (define in `modules/secrets/default.nix`)

```nix
bnox.secrets.thingsBackend     # enum [ "file" "nats-kv" ], default "file"
bnox.secrets.fileSlots         # attrsOf submodule, default {} — see below
```

`fileSlots` contract (this is the interface Job 04 consumes):
- Keyed by the slot's path **relative to `/var/lib/bnox/secrets/`** (e.g. `"hermes/discord_token"`).
- Each value is a submodule: `{ owner = str; group = str; restartUnits = listOf str; }`.
- So a declaration `bnox.secrets.fileSlots."hermes/discord_token" = { owner = "hermes"; group = "hermes"; restartUnits = [ "hermes.service" ]; }` means: the secret file at `/var/lib/bnox/secrets/hermes/discord_token` is owned `hermes:hermes`, and a `systemd.path` unit watches it; on change, `hermes.service` is restarted.

**Omit `description` fields on options** (per user's no-comments lean + existing repo style). Option semantics live in this job file and `06-base-design.md`.

## file backend behavior (`backends/file.nix`, `mkIf backend == "file"`)

For each entry in `bnox.secrets.fileSlots`:
1. Create the parent directory `/var/lib/bnox/secrets/<dir>` with restrictive ownership via `systemd.tmpfiles.rules` (so the operator can drop the file in and the thing's user can read it). The slot file itself is created by the operator (not by bnox).
2. Generate a `systemd.path` unit watching the slot file (`PathChanged=`).
3. Generate a paired oneshot `systemd.service` that runs `systemctl restart <restartUnits>` (as root), triggered by the path unit.
4. Use sane unit naming derived from the slot key (sanitized). The worker chooses the exact naming; ensure no collisions.

The mechanism is **inert until `fileSlots` is populated** (Job 04 does that). With `{}` (no things yet), it generates nothing and the flake must evaluate clean.

## Constraints

- No comments in any Nix file. No `#`, no `/* */`. Omit option `description` fields.
- Do not touch `modules/base/`, `modules/platform/`, `lib/`, `home/` beyond the two edits above (`flake.nix` agenix injection, `modules/default.nix` secrets import).
- Do not declare any `age.secrets.*` (per-host concern).
- Do not implement the nats-kv backend (scaffold + assertion only).

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — `nixosModules.bnox` present.
- Throwaway `nixosSystem` eval from `nixosModules.bnox` (x86_64-linux, stub fs/boot — mirror the Job 01/02 checker trick): confirm `config.age.sshKeyPaths` == `["/etc/ssh/ssh_host_ed25519_key"]` and `config.bnox.secrets.thingsBackend` == `"file"`.
- Same eval **with one sample `fileSlots` entry** added in the host module: confirm a `systemd.path` unit and a tmpfiles rule are generated for that slot (e.g. `builtins.attrNames config.systemd.paths` contains the generated name; `config.systemd.tmpfiles.rules` contains the dir line). Paste the result.
- Eval with `bnox.secrets.thingsBackend = "nats-kv"`: confirm the not-implemented assertion fires (expect an eval error containing the message — this is desired). Paste the error.

## Worker notes

**Built (Job 03, iteration 1, 2026-07-28):**

Files created/modified (7 total — 5 new + 2 edits):
- `flake.nix` (modified) — added `agenix` to the `outputs` destructure; injected `agenix.nixosModules.default` into `nixosModules.bnox` imports (alongside `home-manager.nixosModules.home-manager`). Same pattern as the Job 01 HM injection: keeps `modules/` free of flake-input references. NOT added to `nixosModules.bnox-base` (base has no secrets).
- `modules/default.nix` (modified) — added `./secrets/default.nix` to imports.
- `modules/secrets/default.nix` (new) — defines `bnox.secrets.thingsBackend` (enum, default `"file"`) and `bnox.secrets.fileSlots` (attrsOf submodule, default `{}`); imports `infra.nix`, `backends/file.nix`, `backends/nats-kv.nix`.
- `modules/secrets/infra.nix` (new) — agenix wiring (see deviation 1 below).
- `modules/secrets/backends/file.nix` (new) — Hybrid-1 default backend; tmpfiles + systemd.path + paired oneshot service per slot.
- `modules/secrets/backends/nats-kv.nix` (new) — Hybrid-2 scaffold; `assertion = false` gated by `mkIf backend == "nats-kv"`.

**`fileSlots` submodule definition (Job 04 must match):**

```nix
fileSlots = lib.mkOption {
  type = lib.types.attrsOf (
    lib.types.submodule {
      options = {
        owner = lib.mkOption {
          type = lib.types.str;
        };
        group = lib.mkOption {
          type = lib.types.str;
        };
        restartUnits = lib.mkOption {
          type = lib.types.listOf lib.types.str;
        };
      };
    }
  );
  default = { };
};
```

All three fields are **required (no defaults)** — Job 04 must set all three explicitly per slot. The spec lists all three in the value shape; making them required forces explicit host-side binding. `restartUnits = []` is valid (slot exists just for dir setup, no restart). `default = {}` on the outer option keeps the mechanism inert when Job 04 hasn't populated any slots yet.

**Systemd unit naming scheme (Job 04 / checker predictability):**

For slot key `<key>` (path relative to `/var/lib/bnox/secrets/`, e.g. `"hermes/discord_token"`):
- **Sanitize:** `builtins.replaceStrings [ "/" ] [ "-" ] key` → e.g. `"hermes/discord_token"` becomes `"hermes-discord_token"`.
- **Unit base name:** `"bnox-secret-" + sanitized` → e.g. `"bnox-secret-hermes-discord_token"`.
- **path unit:** `systemd.paths."bnox-secret-<sanitized>"` → unit file `bnox-secret-<sanitized>.path`.
- **service unit:** `systemd.services."bnox-secret-<sanitized>"` → unit file `bnox-secret-<sanitized>.service` (same base name = systemd path↔service auto-pairing).

Naming collision rules: only `/` is replaced. Slot keys differ → sanitized names differ → no collision. `_` and `.` are preserved (legal in systemd unit names). If Job 04 ever uses a slot key with chars illegal in unit names (e.g. space, `:`), the worker will need to extend the sanitizer — out of scope day-1.

**Tmpfiles rule scheme:**
- Top-level (emitted once when any slot exists): `"d /var/lib/bnox/secrets 0755 root root -"`.
- Per slot with a `/` in key (e.g. `"demo/key"`): `"d /var/lib/bnox/secrets/<parent> 0750 <owner> <group> -"` where `<parent>` is `builtins.dirOf` of the slot's full path. Deduplicated via `lib.unique` (so two slots sharing `<thing>/` parent emit one rule). Slots without a `/` (parent == secretsRoot) skip the per-slot rule — the top-level rule covers them.
- The slot file itself is NOT created by bnox (operator drops it in), per spec.

**Path/service unit details:**
- `systemd.paths.<name>.wantedBy = [ "multi-user.target" ]` (so the path unit starts at boot and actually watches).
- `systemd.paths.<name>.pathConfig.PathChanged = "/var/lib/bnox/secrets/<key>"`.
- `systemd.services.<name>.serviceConfig.Type = "oneshot"`.
- `systemd.services.<name>.serviceConfig.User = "root"` (explicit, per "as root" spec).
- `systemd.services.<name>.script = "systemctl restart <u>\n..."` for each `u` in `restartUnits` (newline-joined).

**Key decisions / deviations:**

1. **Deviation from spec on `infra.nix` (spec said "set both `age.sshKeyPaths` and `age.identityPaths`"; I set only `age.identityPaths`).** The current agenix version (rev `b027ee2`) **renamed `age.sshKeyPaths` → `age.identityPaths`**; `age.sshKeyPaths` is now an obsolete alias that traces a warning. Because they alias to the same backing option, setting **both** with the same value **doubles** the list (`["/etc/ssh/ssh_host_ed25519_key" "/etc/ssh/ssh_host_ed25519_key"]`), which fails the task's explicit validation check `config.age.sshKeyPaths == ["/etc/ssh/ssh_host_ed25519_key"]` (single element). Setting **only `age.identityPaths`** (the modern name) makes **both** `config.age.identityPaths` and `config.age.sshKeyPaths` (via the alias) resolve to the exact single-element list the validation requires, and eliminates the obsolete-option trace. D-008's intent (agenix decrypts using the SSH host key) is fully honored. This is the only way to satisfy the spec's validation; the spec's literal "set both" wording was written before/independent of the rename.

2. **No `description` fields** on any option (per spec). No `lib.mkDefault` on the agenix values (the spec presents them as authoritative policy, not overridable defaults — D-008).

3. **`restartUnits` has no default** (required). Rationale in the submodule section above.

4. **`wantedBy = [ "multi-user.target" ]`** on path units. The spec didn't mandate it but the mechanism can't function without it (path unit must be started to watch). Standard systemd pattern; inert when `fileSlots == {}` (no units generated).

5. **`serviceConfig.User = "root"`** explicit on the restart service. Defaults are already root in NixOS, but explicit documents the spec's "as root" requirement.

6. **Top-level `/var/lib/bnox/secrets/` tmpfiles rule** (mode 0755 root:root) emitted whenever any slot exists. The spec only mentions per-slot parent dirs, but the parent-of-parents must exist for the per-thing dirs to be creatable. Restrictive per-thing subdirs (0750 owner:group) preserve the Q9.6 cross-thing isolation (top-level is traversable by anyone, but per-thing dirs are not).

**Validation output:**

- `nix flake check` → all outputs OK (only the benign cross-system warning about empty `packages.x86_64-linux` on aarch64-darwin, identical to Job 01/02).
- `nix flake show` → `nixosModules.bnox` and `nixosModules.bnox-base` both present.
- Eval 1 (defaults): `config.age.identityPaths == ["/etc/ssh/ssh_host_ed25519_key"]`, `config.age.sshKeyPaths == ["/etc/ssh/ssh_host_ed25519_key"]` (via obsolete alias), `config.bnox.secrets.thingsBackend == "file"`, `config.bnox.secrets.fileSlots == {}`, `attrNames config.systemd.paths == []` (inert). ✓
- Eval 2 (one sample slot `demo/key`): `attrNames config.systemd.paths` contains `"bnox-secret-demo-key"` ✓; path unit `PathChanged = "/var/lib/bnox/secrets/demo/key"`, `wantedBy = ["multi-user.target"]`; service `Type = "oneshot"`, `User = "root"`, `script = "systemctl restart demo.service"`; tmpfiles rules include `"d /var/lib/bnox/secrets 0755 root root -"` and `"d /var/lib/bnox/secrets/demo 0750 demo demo -"`. ✓
- Eval 3 (`thingsBackend = "nats-kv"`): throws `error: nats-kv secrets backend not implemented yet (D-007 Hybrid-2)`. ✓
- Inertness cross-check: under default `file` backend, `failed assertions = 0` and no nats-kv assertion present — the `mkIf` gate holds.
- Comment scan: `rg '(^|[^a-zA-Z0-9"])#|/\*' --glob '*.nix'` across new/modified files → no matches (hard constraint met).

**For the checker to focus on:**
- The `infra.nix` single-option deviation (decision 1) — is reading the obsolete alias to satisfy the validation the right call, or should the spec's "set both" be honored literally at the cost of the doubled list + trace warning? My judgment: the validation check is the tiebreaker and the rename is a real-world constraint the spec didn't account for.
- The systemd path↔service auto-pairing by shared name — confirm NixOS's `systemd.paths.<n>` + `systemd.services.<n>` indeed produce paired `.path`/`.service` units (standard behavior, but load-bearing for the on-change restart to work).
- The tmpfiles top-level rule (0755 root:root) — confirm this doesn't weaken Q9.6 cross-thing isolation. My read: per-thing subdirs at 0750 enforce isolation; the top-level needs to be traversable so each thing's user can reach its own subdir.

## Checker notes

**Verdict: PASS.** Independent checker, iteration 1, 2026-07-28. All 10 checklist items OK; `nix flake check`, `nix flake show`, and three throwaway `nixosSystem` evals reproduced below.

**Checklist results:**

1. **Scope — OK.** `git diff --stat HEAD` shows only `flake.nix` (+2) and `modules/default.nix` (+1) modified; new files under `modules/secrets/{default,infra}.nix` + `modules/secrets/backends/{file,nats-kv}.nix`. No edits to `modules/base/`, `modules/platform/`, `lib/`, `home/`. No granular `nixosModules.bnox-secrets` output added (flake.nix:43-56 still exposes only `bnox` + `bnox-base`). No `age.secrets.*` declarations anywhere.
2. **No comments + no descriptions — OK.** `rg '(^|[^a-zA-Z0-9"])#|/\*|description =' modules/secrets flake.nix modules/default.nix` returns only `flake.nix:2:  description = "bnox — unified NixOS base";` — that's the pre-existing flake-attr description, not an option `description` field. Zero `#`/`/* */` in any new file.
3. **agenix injection — OK.** flake.nix:26 adds `agenix` to the outputs destructure; flake.nix:46 injects `agenix.nixosModules.default` into `nixosModules.bnox` imports (alongside `home-manager.nixosModules.home-manager`). NOT added to `nixosModules.bnox-base` (correct — base has no secrets).
4. **Option interface — OK (byte-for-byte).** `modules/secrets/default.nix:10-16`: `thingsBackend` is `enum ["file" "nats-kv"]` default `"file"`. `default.nix:18-35`: `fileSlots` is `attrsOf submodule` with exactly `{ owner:str; group:str; restartUnits:listOf str }`, outer `default = {}`. All three fields have type-only `mkOption` (no per-field defaults → required). Job 04 can consume this contract as-is.
5. **infra.nix deviation — VERIFIED CORRECT (see dedicated verdict below).**
6. **file backend behavior — OK.** For each slot: (a) tmpfiles parent-dir rule (`backends/file.nix:38-39`, `d <parent> 0750 <owner> <group> -`); (b) `systemd.paths.<name>.pathConfig.PathChanged` (file.nix:15); (c) paired oneshot `systemd.services.<name>` as `User="root"` running `systemctl restart <unit>` per `restartUnits` (file.nix:22-24). Inert when `fileSlots == {}`: eval 1 shows `systemd.paths == []` and no bnox tmpfiles rules.
7. **nats-kv scaffold — OK.** `backends/nats-kv.nix:3-9`: `mkIf backend == "nats-kv"` gates a single `assertions = [{ assertion=false; message="nats-kv secrets backend not implemented yet (D-007 Hybrid-2)"; }]`. Inert under default `file` backend (eval 1 `failedAssertions == []`); fires under nats-kv (eval 3 reproduces the message).
8. **Cross-thing isolation (Q9.6) — OK, mode choices sound.** Top-level `/var/lib/bnox/secrets` is `0755 root:root` (traversable so each thing's user can reach its own subdir; listing reveals thing names — minor, conventional NixOS pattern matching `/var/lib` itself). Per-thing subdirs `0750 owner:group` (file.nix:39). Cross-thing read blocked: thing `demo` cannot traverse `/var/lib/bnox/secrets/hermes/` (not owner, not in `hermes` group → no `x`) → cannot reach `hermes`'s slot files. Top-level needs to be traversable (0755), not 0750, for the per-thing model to work. Slot file itself is operator-created (per spec) — its perms are an operator concern, not bnox's.
9. **modules/default.nix — OK.** `./secrets/default.nix` added (modules/default.nix:5) alongside preserved `./base/default.nix` and `./platform/default.nix`.
10. **Independent validation — OK** (output pasted below).

**Item 5 — infra.nix deviation verdict: the worker's reasoning is CORRECT.**

Evidence (agenix source at the locked rev `b027ee2`, `modules/age.nix`):
- Line ~290 of age.nix: `imports = [ (mkRenamedOptionModule [ "age" "sshKeyPaths" ] [ "age" "identityPaths" ]) ];` — confirms `age.sshKeyPaths` is a `mkRenamedOptionModule` alias of `age.identityPaths`. They back to the same option.
- agenix's decryption shell code reads `${toString cfg.identityPaths}` (the `IDENTITIES` loop in `installSecret`). `age.identityPaths` is the option agenix actually uses; `age.sshKeyPaths` exists only for backwards compatibility.
- `mkRenamedOptionModule` forwards the alias's value into the new option's definitions. Setting both `age.sshKeyPaths = [X]` and `age.identityPaths = [X]` would merge two identical definitions into `age.identityPaths` → list-merge → `[X X]` (doubled), failing the spec's single-element validation. The worker's claim here is accurate.
- Setting only `age.identityPaths = [X]` makes the alias resolve through to the same single value. Eval 1 proves both `config.age.identityPaths` and `config.age.sshKeyPaths` evaluate to exactly `["/etc/ssh/ssh_host_ed25519_key"]` (single element, not doubled).
- D-008 intent ("SSH host key `/etc/ssh/ssh_host_ed25519_key` used for agenix decryption") is fully honored — agenix reads `age.identityPaths`, which the worker sets to exactly that path.

Note: the obsolete-option trace (`Obsolete option 'age.sshKeyPaths' is used. It was renamed to 'age.identityPaths'.`) only fires when something *reads* `config.age.sshKeyPaths` — i.e., it appears in the checker's eval output below because the checker explicitly probes the alias to confirm it resolves. The worker's own `infra.nix` never reads the alias, so under normal operation no trace fires. Sound.

The spec's literal "set both `age.sshKeyPaths` and `age.identityPaths`" wording predates the rename; the worker's single-option choice is the correct reading and is the only way to satisfy both D-008 and the single-element validation. Acceptable deviation.

**Validation output:**

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
Use '--all-systems' to check all.
```

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───lib: unknown
└───nixosModules
    ├───bnox: NixOS module
    └───bnox-base: NixOS module
```

Eval 1 (defaults — `nixosSystem` from `nixosModules.bnox` + stub fs/boot, x86_64-linux):
```
config.age.identityPaths    == [ "/etc/ssh/ssh_host_ed25519_key" ]   (single element)
config.age.sshKeyPaths      == [ "/etc/ssh/ssh_host_ed25519_key" ]   (single element, via alias)
config.bnox.secrets.thingsBackend == "file"
config.bnox.secrets.fileSlots     == {}
attrNames config.systemd.paths    == []   (inert)
failedAssertions                  == []   (no nats-kv assertion under default)
no bnox-secrets entries in config.systemd.tmpfiles.rules
```
(trace line on stderr: `Obsolete option 'age.sshKeyPaths' is used. It was renamed to 'age.identityPaths'.` — fires only because the checker probes the alias; worker code doesn't read it.)

Eval 2 (`bnox.secrets.fileSlots."demo/key" = { owner="demo"; group="demo"; restartUnits=["demo.service"]; }`):
```
attrNames config.systemd.paths     == [ "bnox-secret-demo-key" ]
systemd.paths."bnox-secret-demo-key".pathConfig.PathChanged == "/var/lib/bnox/secrets/demo/key"
systemd.paths."bnox-secret-demo-key".wantedBy               == [ "multi-user.target" ]
systemd.services."bnox-secret-demo-key".serviceConfig.Type  == "oneshot"
systemd.services."bnox-secret-demo-key".serviceConfig.User  == "root"
systemd.services."bnox-secret-demo-key".script              == "systemctl restart demo.service"
config.systemd.tmpfiles.rules contains:
  "d /var/lib/bnox/secrets 0755 root root -"
  "d /var/lib/bnox/secrets/demo 0750 demo demo -"
```

Eval 3 (`bnox.secrets.thingsBackend = "nats-kv"`) — `builtins.filter (a: !a.assertion) config.assertions`:
```
[ { assertion = false; message = "nats-kv secrets backend not implemented yet (D-007 Hybrid-2)"; } ]
```
(A NixOS build of this config would surface this as a hard error with that message — desired per spec.)

## Sign-off

Approved 2026-07-28 — independent checker, iteration 1, verdict PASS. All 10 checklist items OK; `nix flake check` + `nix flake show` + three throwaway `nixosSystem` evals reproduced; the worker's `infra.nix` single-option deviation verified correct against agenix source at rev `b027ee2` (rename confirmed via `mkRenamedOptionModule`); Q9.6 cross-thing isolation preserved by the 0750 per-thing subdir perms; option interface byte-for-byte matches the Job-04 contract.
