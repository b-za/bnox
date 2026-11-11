# Job 04: Things core (schema + user + hardening + validators)

**Status:** done
**Iteration:** 1
**Created:** 2026-07-28

## Scope

Define the thing-hosting abstraction's **data model + safety layer**: the `bnox.things.<name>` option schema (multi-component, per Q9.5), per-thing system user creation (Q9.6), the standard hardening bundle + per-thing override option (Q9.7), and the three evaluation-time validators (dep-graph closure, ingressPort uniqueness, natsSubject uniqueness — D-006 §6/§7).

This job is **inert with respect to running services**: it does NOT create Caddy vhosts, NATS streams, containers, or systemd units. Those effects land in Job 05 (shapes + runtimes), which will READ the options defined here and emit config. NixOS module composition makes this a clean option boundary — Job 05 consumes this schema without modifying it.

**Deferred (NOT this job):** the `.bnox/` loader (reads thing-intrinsic fields from the thing's repo at `/srv/<name>/.bnox/`), all 5 shape handlers, both runtime handlers, `modules/platform/static-site.nix`, and the population of `bnox.secrets.fileSlots` (needs runtime unit names from Job 05). For now, all schema fields are host-declarable; the loader (later) will source thing-intrinsic values from `.bnox/`.

**Spec sources (read these):**
- `design/process/06-base-design.md` — `modules/things/` table + the host-config schema sketch + `.bnox/` repo-layout sketch.
- `design/process/05-decisions.md` — D-006 (thing architecture, NATS subject layout `things.<name>.>`, dep-graph validation, port self-declaration + collision check), Q9.5 refinements (multi-component; host vs thing-intrinsic split; secrets interface).
- `design/working/open-questions.md` — Q9.6 (per-thing user, `/var/lib/<thing>/` ownership), Q9.7 (standard hardening bundle — full directive table), Q9.8 (daemon shape), Q9.9 (host-install runtime).
- `design/process/03-requirements.md` — (thing architecture NFRs).

## Files to create / modify

1. `modules/things/default.nix` — the option schema (below) + the three validators (as `assertions`) + imports `user.nix` and `hardening.nix`.
2. `modules/things/user.nix` — per-thing system user creation (Q9.6).
3. `modules/things/hardening.nix` — the standard hardening bundle (Q9.7) as a reusable attrset/function + the `bnox.things.<name>.hardening` override option.
4. **Modify `modules/default.nix`** — add `./things/default.nix` to imports (alongside base + platform + secrets).

## Option schema (define in `modules/things/default.nix`)

```
bnox.things : attrsOf submodule, default {}   # key = thing name
  enable        : bool, default false
  source        : str                          # e.g. "/srv/<name>"; used later by loader + git-sync
  deps          : listOf str, default []       # other thing names this depends on; validated
  secrets       : listOf str, default []       # thing-level slot names declared (mechanism-agnostic; bound to fileSlots in Job 05)
  hardening     : submodule (override) — see hardening.nix below
  components    : attrsOf submodule, default {}   # key = component name
    enable      : bool, default true
    shape       : enum [ "static-site" "webapp" "http-api" "nats-api" "daemon" ]
    runtime     : enum [ "container" "host-install" ], default "container"
    domain      : nullOr str, default null             # if HTTP-exposed
    ingressPort : nullOr int, default null             # validated unique across enabled components
    natsSubject : nullOr str, default null             # e.g. "things.<name>.<component>.>"; validated unique
    secrets     : listOf str, default []               # component-level slot names
```

Use `nullOr` with `null` defaults for fields that only apply to some shapes (domain/ingressPort for HTTP shapes; natsSubject for nats-api). Omit option `description` fields (no-comments lean; semantics live here + `06-base-design.md`).

## Validators (assertions in `modules/things/default.nix`)

Across all **enabled** things/components (thing `enable=true` AND component `enable=true`):
1. **Dep-graph closure**: every name in a thing's `deps` must be an enabled thing on this host. Missing dep → assertion failure with a clear message naming the missing dep + the dependent thing.
2. **ingressPort uniqueness**: no two enabled components may declare the same non-null `ingressPort`. Collision → assertion failure naming both components + the port.
3. **natsSubject uniqueness**: no two enabled components may declare the same non-null `natsSubject`. Collision → assertion failure naming both components + the subject.

Each validator builds its assertion list from `config.bnox.things`. Use `lib.concatMap`/`lib.attrValues` to iterate. Messages must be specific (name the offenders).

## user.nix (Q9.6)

For each enabled thing: create `users.users.<name>` — a system user (`isSystemUser = true`), with `home = "/var/lib/<name>"`, `createHome = true`, `group = <name>`, and a matching `users.groups.<name>`. Default username = thing name. (No per-thing override of username needed day-1; the thing name IS the username.)

## hardening.nix (Q9.7)

Define the **standard hardening bundle** as a reusable attrset (a function returning the systemd directive set, parameterized by the thing's writable paths). This bundle is CONSUMED by Job 05's runtime handlers (which build the actual systemd units) — it has no effect on its own in this job. Directive set (from Q9.7):
- Filesystem: `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths=<thing paths>`, `PrivateTmp=true`, `PrivateDevices=true`
- Privileges: `NoNewPrivileges=true`, `CapabilityBoundingSet=` (empty), `SystemCallFilter=@system-service`, `RestrictAddressFamilies=AF_INET AF_INET6`
- Kernel: `ProtectKernelTunables=true`, `ProtectKernelModules=true`, `ProtectKernelLogs=true`, `ProtectControlGroups=true`, `ProtectClock=true`, `ProtectHostname=true`
- Process: `ProtectProc=invisible`, `ProcSubset=pid`
- Network: `IPAddressDeny=any` (with `IPAddressAllow=` populated per the thing's needs — left empty/overridable)

Also define the **override option** `bnox.things.<name>.hardening` (a submodule with an `network.outboundHTTPS : bool default false`-style field, or a freeform attrset the runtime merges) — minimal day-1; the point is the override hook EXISTS and is visible in host config. Keep it minimal; full override surface can grow later.

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT create shapes/, runtimes/, or platform/static-site.nix (Job 05).
- Do NOT populate `bnox.secrets.fileSlots` (Job 05 wires secrets to runtime units).
- Do NOT implement the `.bnox/` loader (deferred).
- Do NOT touch `modules/base/`, `modules/platform/` (except none), `modules/secrets/`, `lib/`, `home/`, `flake.nix` — only `modules/default.nix` (add things import) + the 3 new things files.

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — `nixosModules.bnox` present.
- Throwaway `nixosSystem` eval (x86_64-linux, `nixosModules.bnox` + stub fs/boot; trick in `design/jobs/01-flake-base.md` checker notes):
  - **Well-formed**: declare two things (A enabled with a component shape=webapp ingressPort=8080 domain="a.test"; B enabled, shape=nats-api, component natsSubject="things.b.b>", with A in B's deps). Confirm `users.users.a`/`users.users.b` (+ groups) exist, `users.users.a.home == "/var/lib/a"`, no assertions fail.
  - **Bad dep**: declare a thing with `deps = ["ghost"]` (ghost not enabled). Confirm the dep-graph assertion fires (expect eval error naming ghost).
  - **Port collision**: two enabled components with the same `ingressPort`. Confirm assertion fires naming both + port.
  - **Subject collision**: two enabled components with the same `natsSubject`. Confirm assertion fires.
- Paste all results.

## Worker notes

**Built (Job 04, iteration 1, 2026-07-28):**

Files created (3) / modified (1):
- `modules/things/default.nix` (new) — `bnox.things : attrsOf submodule` with the full schema + three validators (`config.assertions`); imports `./user.nix`.
- `modules/things/user.nix` (new) — per enabled thing: `users.users.<name>` (system user, home `/var/lib/<name>`, createHome, group `<name>`) + `users.groups.<name>`.
- `modules/things/hardening.nix` (new) — see "Hardening bundle shape" below.
- `modules/default.nix` (modified) — added `./things/default.nix` to imports (alongside base + platform + secrets).

**Thing submodule definition (Job 05 must match):**

```nix
options.bnox.things = lib.mkOption {
  type = lib.types.attrsOf (
    lib.types.submodule [
      thingOptionsModule
      hardening.overrideModule
    ]
  );
  default = { };
};
```

`thingOptionsModule` defines (with no `description` fields, per spec):
- `enable : bool, default false`
- `source : str` (required — no default)
- `deps : listOf str, default []`
- `secrets : listOf str, default []`
- `components : attrsOf submodule, default {}` (component submodule below)

`hardening.overrideModule` (defined in `hardening.nix`) contributes the override hook to the thing submodule:
- `hardening.network.outboundHTTPS : bool, default false` (minimal day-1; nested submodule so future fields land under `hardening.network.*` cleanly).

**Component submodule definition (Job 05 must match):**
- `enable : bool, default true`
- `shape : enum [ "static-site" "webapp" "http-api" "nats-api" "daemon" ]` (required — no default)
- `runtime : enum [ "container" "host-install" ], default "container"`
- `domain : nullOr str, default null`
- `ingressPort : nullOr int, default null`
- `natsSubject : nullOr str, default null`
- `secrets : listOf str, default []`

`source` (thing-level) and `shape` (component-level) have NO defaults — they are required when an enabled thing/component is declared. Disabled things without `source` do NOT fail eval (lazy — `source` is only required when read; my code only reads `.source` for enabled things, and Job 05 will be the first to actually consume it).

**Hardening bundle shape (Job 05 must match):**

`hardening.nix` is a **plain function file** (NOT a NixOS module), signature `{ lib }: { bundle, overrideModule }`. Job 05 imports it via `import ./hardening.nix { inherit lib; }` (same path), then:
- `bundle` is a **function** returning the systemd-directive attrset, parameterized by writable paths and an optional allow-list:
  ```nix
  bundle = { writablePaths, ipAddressAllow ? [] }: {
    ProtectSystem = "strict";
    ProtectHome    = "true";
    ReadWritePaths = lib.concatStringsSep " " writablePaths;  # space-joined string
    ...
    IPAddressDeny  = "any";
    IPAddressAllow = lib.concatStringsSep " " ipAddressAllow; # "" when empty
  };
  ```
  All values are **strings matching systemd unit-file syntax** (so Job 05 can either merge into NixOS `serviceConfig` or write unit-file lines verbatim). Multi-value directives (`ReadWritePaths`, `IPAddressAllow`) are space-joined strings. `CapabilityBoundingSet = ""` (empty) clears all caps (systemd syntax). All 19 directives from the Job-04 spec table are present.
- `overrideModule` is a **NixOS submodule module** (function `{ name, ... }: { options.hardening = ...; }`) placed in the thing submodule's module list alongside `thingOptionsModule`. This is how the override option (`bnox.things.<name>.hardening`) is wired into the thing submodule from `hardening.nix`.

**Why hardening.nix is `import`-ed, not in `imports = [...]`:** the spec requires hardening.nix to contain BOTH (a) the bundle function (a reusable non-module value) AND (b) the override option. A NixOS module file can't naturally export a sibling function value, so hardening.nix is a function returning an attrset `{ bundle, overrideModule }`; `default.nix` does `let hardening = import ./hardening.nix { inherit lib; }; in ...` and uses both pieces. `user.nix` IS in `imports = [...]` (regular NixOS module). The spec's "imports user.nix and hardening.nix" is read with "imports" as "loads/references", since strict NixOS-module interpretation is incompatible with the dual-purpose requirement.

**Validator implementations:**

All three live in `default.nix`'s `let`-bindings; `config.assertions` is built by `map (msg: { assertion = false; message = msg; })` over the concatenated error lists. Only enabled things (`enable = true`) and enabled components (`enable = true`) are scanned.

1. **Dep-graph closure:** for each enabled thing, every name in `deps` is checked against `enabledThingNames`. Missing → `"bnox: thing \"<dependent>\" declares dependency \"<missing>\", but no enabled thing named \"<missing>\" exists"`.
2. **ingressPort uniqueness:** `lib.groupBy (c: toString c.ingressPort)` over enabled components with non-null port; any group with >1 member → `"bnox: ingressPort <port> declared by multiple enabled components: <thing>.<comp>, <thing>.<comp>"`.
3. **natsSubject uniqueness:** `lib.groupBy (c: c.natsSubject)` over enabled components with non-null subject; same shape.

**Key decisions / deviations:**

1. **hardening.nix is a function file, not a NixOS module** (see "Why hardening.nix is `import`-ed" above). Necessary to satisfy the dual-purpose requirement (bundle + override option).
2. **Bundle returns systemd-syntax strings** (not NixOS typed values or lists). Maximally portable for Job 05: works whether Job 05 builds NixOS `serviceConfig` (typed options accept strings) or generates raw unit text. Multi-value directives are pre-joined space-separated strings.
3. **`source` and `shape` have no defaults** (per spec schema — required fields). Lazy eval means disabled things without `source` don't fail; enabled things without `source` fail with the standard "required option not set" NixOS error (expected behavior — every enabled thing must declare where it lives).
4. **Override hook is minimal day-1** — only `network.outboundHTTPS : bool default false`. Nested under `network.*` so future egress overrides (DNS, custom destinations) extend the same `network` submodule without schema churn. Job 05 reads `config.bnox.things.<name>.hardening.network.outboundHTTPS` and, if true, populates `bundle`'s `ipAddressAllow` with `:443` (or whatever the day-1 egress policy is).
5. **`overrideModule` placed in the submodule module list `[ thingOptionsModule hardening.overrideModule ]`** rather than as a free-form option in `thingOptionsModule`. This keeps the override-option definition physically inside `hardening.nix` (per spec: "the `bnox.things.<name>.hardening` override option" lives in hardening.nix). NixOS submodule module-list pattern is the canonical way to split a submodule definition across files.
6. **No `bnox.things` flake-output or top-level wrapper option** — the spec schema is exactly `bnox.things.<name>`, no extra layer. Matches Job 02/Job 03 minimal-surface pattern; `nixosModules.bnox-things` is a planned output per `06-base-design.md` but adding it would require editing `flake.nix`, which Job 04's hard constraints forbid.
7. **Validators are data-only (not eval-time `throw`)**. They emit `config.assertions` entries; NixOS's standard assertion mechanism fires them at build time (loud rebuild failure per D-006 §6/§7). This matches the Job 03 nats-kv-scaffold pattern and lets the system evaluate normally for inspection (`config.assertions` is queryable).

**Validation output:**

- Comment scan: `rg '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' --glob '*.nix' modules/things modules/default.nix` → no matches (hard constraint met).
- `nix flake check` → all outputs OK (only the benign cross-system warning about empty `packages.x86_64-linux` on aarch64-darwin, identical to Job 01/02/03).
- `nix flake show` → `nixosModules.bnox` + `nixosModules.bnox-base` both present.
- **Eval 1 (well-formed, two enabled things A+B with A in B's deps):**
  ```
  {
    "failed_assertions": [],
    "group_a_exists": true,  "group_b_exists": true,
    "user_a_exists": true,   "user_b_exists": true,
    "user_a_home": "/var/lib/a",  "user_b_home": "/var/lib/b",
    "user_a_isSystemUser": true,  "user_a_createHome": true,  "user_a_group": "a"
  }
  ```
  No assertions fire; users/groups a+b exist with correct attributes.
- **Eval 2 (bad dep — thing a deps=["ghost"]):**
  ```
  { "failed_assertions": [
      "bnox: thing \"a\" declares dependency \"ghost\", but no enabled thing named \"ghost\" exists" ] }
  ```
  Dep-graph assertion fires, naming missing dep ("ghost") + dependent ("a").
- **Eval 3 (port collision — a.web + b.api both ingressPort 8080):**
  ```
  { "failed_assertions": [
      "bnox: ingressPort 8080 declared by multiple enabled components: a.web, b.api" ] }
  ```
  Port-uniqueness assertion fires, naming both components + the port.
- **Eval 4 (subject collision — a.x + b.y both natsSubject "things.shared>"):**
  ```
  { "failed_assertions": [
      "bnox: natsSubject \"things.shared>\" declared by multiple enabled components: a.x, b.y" ] }
  ```
  Subject-uniqueness assertion fires, naming both components + the subject.
- **Bundle sanity** (Job-05-preview): `bundle { writablePaths = ["/var/lib/a" "/var/lib/bnox/secrets/a"]; ipAddressAllow = ["1.1.1.1/32" ":443"]; }` returns all 19 directives as systemd-syntax strings (e.g. `ProtectSystem="strict"`, `ReadWritePaths="/var/lib/a /var/lib/bnox/secrets/a"`, `CapabilityBoundingSet=""`, `IPAddressAllow="1.1.1.1/32 :443"`). Override `bnox.things.a.hardening.network.outboundHTTPS = true` round-trips (`config.bnox.things.a.hardening.network.outboundHTTPS == true`); when unset, defaults to `false`.

**For the checker to focus on:**

- **The `hardening.nix`-is-`import`-ed decision (deviation 1).** Is reading "imports user.nix and hardening.nix" loosely (Nix-level `import` for hardening.nix, NixOS `imports` for user.nix) acceptable, or does the checker want a stricter reading? The dual-purpose requirement (bundle function + override option) makes strict NixOS-module interpretation impossible without splitting the bundle into a separate file (which would deviate from "hardening.nix contains both"). My judgment: this is the only constraint-compatible reading.
- **Bundle values as strings (deviation 2).** Strings are maximally portable for Job 05 (works in both NixOS-typed `serviceConfig` and raw unit-file generation). One consequence: `CapabilityBoundingSet = ""` produces `CapabilityBoundingSet=` (empty) in the unit file, which is systemd's "clear all" syntax — confirm this is the desired semantic (vs. e.g. `CapabilityBoundingSet = []` which NixOS would also render as empty).
- **Validators are data-only (deviation 7).** They fire at build time via NixOS's assertion mechanism, not at eval time. The Job-04 eval-test probe (`builtins.filter (a: !a.assertion) config.assertions`) confirms the right entries exist. Confirm this matches the spec's "loud rebuild failure" intent — I read D-006 §6/§7 as build-time failure, which is exactly what `config.assertions` provides.
- **`source` and `shape` required (no defaults) (deviation 3).** The spec schema lists them without defaults; I honored that literally. Confirm this is intended (vs. e.g. `source = mkDefault null`).
- **`secrets : listOf str`** at both thing-level and component-level. The spec schema and the Q9.5 sketch diverge slightly: Q9.5 sketch has `secrets = { <slot> = { source = ...; }; }` (attrset of slot-bindings), while the Job-04 spec schema says `secrets : listOf str` (just slot names). I followed the Job-04 spec schema literally (list of slot-name strings); the actual binding of slot-name → source happens elsewhere (Job 05 wires `bnox.secrets.fileSlots`). Confirm this reading.
- **Test sandbox used `fileSystems."/".fsType = "ext4"`** in addition to `device = "/dev/null"` — the Job-01 checker trick needed extending because NixOS 26.05's ZFS module accesses `fileSystems."/".fsType` during eval. Doesn't affect the module under test; just a stub-fs completeness note for future jobs.

## Checker notes

**VERDICT: PASS** — 2026-07-28 (independent checker, iteration 1).

All 11 checklist items OK. Summary (one line each):

1. **Scope — OK.** `git diff --cached` shows exactly: `modules/default.nix` (one line: `+    ./things/default.nix`) + 3 new files (`modules/things/{default,user,hardening}.nix`). No `shapes/`, no `runtimes/`, no `platform/static-site.nix`, no `.bnox/` loader, no `bnox.secrets.fileSlots` population. No edits to `base/`, `platform/`, `secrets/`, `lib/`, `home/`, `flake.nix`.
2. **No comments / no descriptions — OK.** `rg -n '(^|[^a-zA-Z0-9"])#|/\*|description =' modules/things modules/default.nix` → no matches.
3. **Schema — OK (byte-for-byte).** Thing: `enable bool default false` (default.nix:52-55), `source str` no default (56-58), `deps listOf str default []` (59-62), `secrets listOf str default []` (63-66), `hardening submodule` via overrideModule (130), `components attrsOf submodule default {}` (67-70). Component: `enable bool default true` (9-12), `shape enum[static-site webapp http-api nats-api daemon]` no default (13-21), `runtime enum[container host-install] default "container"` (22-28), `domain nullOr str default null` (29-32), `ingressPort nullOr int default null` (33-36), `natsSubject nullOr str default null` (37-40), `secrets listOf str default []` (41-44). `bnox.things` is `attrsOf submodule default {}` (126-134). All types/defaults match spec.
4. **Validators — OK.** All three scan ONLY enabled things/components (verified via eval7: a disabled thing with `deps=["ghost"]` + a port-8080 component, alongside a disabled component sharing port 8080 → **zero** assertions fire). Messages name offenders in all four reproductions (evals 2-4 below). (a) Dep-graph: missing dep message names dependent + missing (eval2). (b) ingressPort: names both `<thing>.<comp>` + port (eval3). (c) natsSubject: names both + subject (eval4).
5. **user.nix — OK.** Per enabled thing: `users.users.<name>` `isSystemUser=true`, `home="/var/lib/<name>"`, `createHome=true`, `group=<name>` (user.nix:6-14) + `users.groups.<name>` (16-19). Eval1 confirms `user_a_home="/var/lib/a"`, `user_a_isSystemUser=true`, `user_a_createHome=true`, `user_a_group="a"`, groups a+b present.
6. **hardening bundle — OK (all 19 spec directives present).** Eval5 reports `directive_count=19`, `missing_directives=[]`, `extra_directives=[]`. Verified each: ProtectSystem="strict", ProtectHome="true", ReadWritePaths (param), PrivateTmp="true", PrivateDevices="true", NoNewPrivileges="true", CapabilityBoundingSet="" (empty), SystemCallFilter="@system-service", RestrictAddressFamilies="AF_INET AF_INET6", ProtectKernelTunables/Modules/Logs/ControlGroups/Clock/Hostname all "true", ProtectProc="invisible", ProcSubset="pid", IPAddressDeny="any", IPAddressAllow (param hook). Override option `bnox.things.<name>.hardening.network.outboundHTTPS` exists and round-trips (eval6: set→true, unset→false). **Note:** Q9.7's table also has a "Resource caps" row (MemoryMax/CPUQuota/TasksMax) marked "defaults TBD per thing shape" — the Job-04 spec's hardening section deliberately narrows to the 19 directives listed in checker item 6 (which also lists exactly 19). Resource caps are deferred consistently with Q9.7's own "defaults TBD" — NOT a defect; will land with per-shape defaults later.
7. **Deviation — hardening.nix via Nix `import` (item 7): SOUND.** Dual-purpose (bundle function + override submodule) is genuinely incompatible with a single NixOS-module file (a module is `{...}: {options/config}` and cannot also export a sibling function value). `{ lib }: { bundle, overrideModule }` is the canonical Nix pattern. Evidence override is reachable: default.nix:3 binds `hardening = import ./hardening.nix { inherit lib; }`; default.nix:128-131 places `hardening.overrideModule` in the submodule module list alongside `thingOptionsModule`; eval6 confirms `cfg.bnox.things.a.hardening.network.outboundHTTPS` exists and round-trips. Evidence bundle is usable: eval5 calls `hardening.bundle { ... }` → 19-directive attrset. The spec's "imports user.nix and hardening.nix" is read loosely (NixOS `imports` for user.nix, Nix `import` for hardening.nix); this is the only constraint-compatible reading. No flag.
8. **Deviation — validators as `config.assertions` (item 8): SOUND + spec-mandated.** The Job-04 spec EXPLICITLY mandates assertions (spec line 23 "+ the three validators (as `assertions`)"; line 49 "## Validators (assertions ...)"). So the worker is following the authoritative Job-04 spec, not deviating from it; the "deviation" is only relative to D-006 §6's loose "fails evaluation" phrasing. D-006 §6/§7 intent = "loud rebuild failure"; NixOS assertions abort `nixos-rebuild build/switch` with the message — that IS a loud rebuild failure. Confirmed behavior: assertions do NOT throw at pure-eval time (evals 2-4 return the messages via `builtins.filter (a: !a.assertion) config.assertions`); they abort at build time. This is standard NixOS assertion semantics and exactly what the spec requested. No flag.
9. **Deviation — `secrets : listOf str` (item 9): SOUND + spec-mandated.** Job-04 spec line 35 (thing) + line 44 (component) both say `secrets : listOf str` (slot names; mechanism-agnostic; bound to fileSlots in Job 05). Worker implemented both as listOf str. Q9.5's attrset sketch is superseded by the Job-04 spec's narrower listOf-str. Job 05 can consume: iterate `thing.secrets ++ component.secrets` and bind each slot name to a fileSlot. Consistent. No flag.
10. **modules/default.nix — OK.** `./things/default.nix` added (default.nix:6); base (3), platform (4), secrets (5) imports all preserved.
11. **Validation — OK.** `nix flake check` clean (benign cross-system warning only); `nix flake show` exposes `nixosModules.{bnox,bnox-base}`; all four evals reproduce worker output exactly (pasted below).

**Reproduced command output:**

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
(cross-system warning benign — empty `packages.x86_64-linux` on aarch64-darwin host; identical to Job 01/02/03.)

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───lib: unknown
└───nixosModules
    ├───bnox: NixOS module
    └───bnox-base: NixOS module
```

**Eval 1 (well-formed: a=webapp:8080/a.test, b=nats-api subject "things.b.b>", b deps=[a])** — throwaway `nixosSystem` (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`):
```
{ failed_assertions = [ ]; group_a_exists = true; group_b_exists = true;
  user_a_createHome = true; user_a_exists = true; user_a_group = "a";
  user_a_home = "/var/lib/a"; user_a_isSystemUser = true;
  user_b_exists = true; user_b_home = "/var/lib/b"; }
```
No assertions fire; users/groups a+b present with correct attributes; `user_a_home="/var/lib/a"`.

**Eval 2 (bad dep — a.deps=["ghost"])**:
```
{ failed_assertions = [ "bnox: thing \"a\" declares dependency \"ghost\", but no enabled thing named \"ghost\" exists" ]; }
```

**Eval 3 (port collision — a.web + b.api both ingressPort 8080)**:
```
{ failed_assertions = [ "bnox: ingressPort 8080 declared by multiple enabled components: a.web, b.api" ]; }
```

**Eval 4 (subject collision — a.x + b.y both natsSubject "things.shared>")**:
```
{ failed_assertions = [ "bnox: natsSubject \"things.shared>\" declared by multiple enabled components: a.x, b.y" ]; }
```

**Bundle sanity (Job-05 preview)** — `hardening.bundle { writablePaths=["/var/lib/a" "/var/lib/bnox/secrets/a"]; ipAddressAllow=["1.1.1.1/32" ":443"]; }`:
```
{ directive_count = 19; extra_directives = [ ]; missing_directives = [ ];
  sample_ProtectSystem = "strict";
  sample_ReadWritePaths = "/var/lib/a /var/lib/bnox/secrets/a";
  sample_CapabilityBoundingSet = "";
  sample_IPAddressDeny = "any";
  sample_IPAddressAllow = "1.1.1.1/32 :443";
  overrideModule_is_function = true; }
```

**Override round-trip** — `bnox.things.a.hardening.network.outboundHTTPS = true` (b unset):
```
{ override_a_set_true = true; override_b_default = false; override_option_path_exists = true; }
```

**Disabled-scope sanity** — disabled thing w/ bad dep + disabled component w/ colliding port alongside an enabled thing:
```
{ failed_assertions = [ ]; disabled_thing_creates_no_user = true; enabled_thing_creates_user = true; }
```
(Proves validators + user-creation are correctly gated on `enable=true` at both thing and component level.)

No issues found. Approved.

## Sign-off
Approved 2026-07-28 — independent checker, iteration 1, verdict **PASS** (all 11 items OK; `nix flake check` + `nix flake show` reproduced; all four evals reproduced; hardening bundle confirmed complete at 19 directives; all three worker deviations (7/8/9) assessed SOUND). Status field left untouched per checker instructions.
