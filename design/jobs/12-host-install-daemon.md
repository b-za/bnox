# Job 12: host-install runtime + daemon shape effects (Hermes path)

**Status:** done
**Iteration:** 1
**Created:** 2026-07-31

## Scope

Implement the **`host-install` runtime (Q9.9)** + the daemon shape's real story (Q9.8) — the path D-009 authorizes for Hermes. For each enabled component with `runtime == "host-install"`, bnox emits a systemd unit that runs the thing's declared `ExecStart` as the thing's user, with the Q9.7 hardening bundle + outbound egress (D-009: HTTPS + DNS), and wires the thing's/thing-component's secret slots to `fileSlots` (restart-on-change). bnox does NOT install the thing (D-009: the operator runs the upstream install once; the thing self-manages via its own update mechanism) — bnox provides the user (already created by Job 04's `user.nix`), the unit, the secrets slot, and the hardening only.

This requires a small **schema + loader extension**: add an `execStart` field to the component schema (the thing-intrinsic start command, sourced from `.bnox/<component>.nix`). The daemon shape itself needs no new inbound plumbing (daemons have no HTTP/NATS interface) — `shapes/daemon.nix` stays a marker; the runtime does the work.

Fully **mock-testable**: a mock `.bnox/` fixture with an `execStart` exercises the whole path via eval (no real Hermes needed, no runtime caveat).

**First/only day-1 user: Hermes (D-009).** `host-install` requires a Q14 deviation per thing; bnox does NOT gate on a "deviation granted" flag (the deviation is a decision-log concern, not a runtime check) — the operator simply doesn't set `runtime = "host-install"` unless a deviation is logged.

**Spec sources (read these):**
- `design/process/05-decisions.md` — D-009 (Hermes deviation: daemon + host-install; bnox provides user + `$HERMES_HOME` + systemd unit + hardening + egress + secrets; Hermes self-manages code/venv/Playwright/updates; sandbox backends local-only); Q9.8 (daemon shape — long-running stateful, no inbound); Q9.9 (host-install runtime — orthogonal to shape; bnox provides user+unit+secrets+hardening only).
- `design/working/open-questions.md` — Q9.6 (per-thing user owns `/var/lib/<thing>`), Q9.7 (the 19-directive hardening bundle + `hardening.network.outboundHTTPS` override hook).
- `design/process/06-base-design.md` — `modules/things/runtimes/host-install.nix` row + `shapes/daemon.nix` row + runtime paths table.
- `design/jobs/04-things-core.md` — the schema you EXTEND (add `execStart`) + the hardening bundle (`hardening.nix`'s `bundle { writablePaths, ipAddressAllow }`).
- `design/jobs/05-things-shapes-runtimes.md` + `modules/things/runtimes/container.nix` — the container runtime's pattern (iterate enabled components filtered by runtime; emit units; wire `fileSlots` with `restartUnits` = the service name; apply hardening bundle). MIRROR this for host-install.
- `design/jobs/08-bnox-loader.md` + `modules/things/loader.nix` — the loader's `componentSubmodule` you EXTEND (read `execStart` from `.bnox/<component>.nix` via `mkDefault`).
- `design/memory/agent-handoff.md` — gotchas (`hardening.nix` dual-purpose `import`, `mkDefault`/`mkForce`, `fsType="ext4"` stub-eval).

## What to build

### 1. Schema extension — `modules/things/default.nix`

Add ONE option to the component submodule (`componentSubmodule`):
```
execStart : nullOr str, default null
```
Required (non-null) when `runtime == "host-install"` (the host-install runtime reads it; if null, let the natural "ExecStart has no value" or an assertion surface). Unused for `runtime == "container"` components. No other schema changes — the Job-04/08 schema is otherwise frozen.

### 2. Loader extension — `modules/things/loader.nix`

In `componentSubmodule`, add `execStart = lib.mkDefault (comp.execStart or null);` to the `loadable` config block (alongside the existing shape/runtime/ingressPort/natsSubject/secrets merges). The `.bnox/<component>.nix` attrset may now carry an `execStart` string; absent → null (the component submodule's default). No change to `topLevel` or `thingSubmodule`.

### 3. `modules/things/runtimes/host-install.nix` (new)

A NixOS module mirroring `container.nix`'s structure. For each enabled component where `comp.enable && comp.runtime == "host-install"`:
- Emit `systemd.services."<thing>-<component>"`:
  - `wantedBy = ["multi-user.target"]`, `after = ["network.target"]` (daemon, long-running).
  - `serviceConfig.ExecStart = comp.execStart` (the thing-intrinsic command; for Hermes, a path under `/var/lib/<thing>/…` — NOT a nix store path).
  - `serviceConfig.User = <thing>`, `Group = <thing>` (the per-thing user Job 04's `user.nix` created).
  - `serviceConfig.WorkingDirectory = "/var/lib/<thing>"` (the thing's home).
  - `serviceConfig.Restart = "on-failure"`, `RestartSec = 5`.
  - `serviceConfig.Environment = [ "HOME=/var/lib/<thing>" ]` (so the thing's tools find their config in their home; add a `<THING-upper>_HOME` var too if it's conventional, else just HOME).
  - **Hardening bundle** (Q9.7, from `hardening.nix`'s `bundle`): apply via `serviceConfig` — `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths="/var/lib/<thing> /var/lib/bnox/secrets/<thing>"`, `PrivateTmp`, `PrivateDevices`, `NoNewPrivileges`, `CapabilityBoundingSet=` (empty), `SystemCallFilter=@system-service`, the `ProtectKernel*`/`ProtectClock`/`ProtectHostname`/`ProtectProc=invisible`/`ProcSubset=pid` set, `RestrictAddressFamilies=AF_INET AF_INET6`. Mirror how `container.nix` calls `hardening.bundle`.
  - **Network egress (D-009):** `IPAddressDeny=any`, `IPAddressAllow=":443 :53"` (outbound HTTPS + DNS — host-install is purpose-built for outbound daemons like Hermes; D-009 justifies this as the default). HONOR the existing override hook: if `thing.hardening.network.outboundHTTPS` is true, the `:443` is included (it always is for host-install by default); document that a host can tighten via the hardening override if a future host-install thing doesn't need egress.
- Wire `fileSlots`: `thing.secrets ++ comp.secrets` → `bnox.secrets.fileSlots."<thing>/<slot>"` with `owner=group=<thing>` and `restartUnits = ["<thing>-<component>"]` (restart the daemon on secret change). Mirror `container.nix`'s slot-grouping + `lib.unique` on restartUnits (a slot shared between a host-install component and a container component of the same thing merges restartUnits).

### 4. `modules/things/runtimes/default.nix` (modify)

Add `./host-install.nix` to the imports (alongside `./container.nix`).

### 5. `shapes/daemon.nix` — NO change

Stays the marker `{}`. Daemons have no inbound HTTP/NATS interface; the webapp/http-api shapes' vhost filters already skip components with `domain=null`, and nats-api is a separate shape. The daemon shape contributes nothing inbound; the host-install runtime (or container runtime, if a daemon runs in a container) does the work. Confirm no change needed; if the checker finds daemon needs a marker effect, prescribe.

### 6. Mock fixture — `bnox-dev` second thing (so `nix flake check` exercises host-install)

Add a SECOND mock thing to `hosts/bnox-dev/` (alongside `demo`) so the host-install path is exercised by the real flake eval, not only throwaway evals:
- `hosts/bnox-dev/mock-daemon/.bnox/thing.nix` — `{ deps = []; secrets = []; components = [ "main" ]; }`
- `hosts/bnox-dev/mock-daemon/.bnox/main.nix` — `{ shape = "daemon"; runtime = "host-install"; execStart = "/var/lib/mock-daemon/run"; ingressPort = null; natsSubject = null; secrets = [ "token" ]; }`
- `hosts/bnox-dev/configuration.nix` — add `bnox.things.mock-daemon = { enable = true; source = toString ./mock-daemon; };` (host-specific only; the loader sources the rest).

Confirm the resulting `mock-daemon-main` systemd service exists with `ExecStart=/var/lib/mock-daemon/run`, `User=mock-daemon`, hardening applied, `IPAddressAllow=":443 :53"`, and `fileSlots."mock-daemon/token"` with `restartUnits=["mock-daemon-main"]`.

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT implement container-runtime changes (Job 05 — done), webhook/pipeline/rollback (Jobs 09-11 — done), or new shapes. The daemon shape stays a marker unless the checker finds otherwise.
- Do NOT install the thing or manage its updates (D-009 — operator runs upstream install once; thing self-manages). bnox provides unit + user + secrets + hardening ONLY.
- Do NOT touch `modules/base/*`, `modules/platform/*`, `modules/secrets/*` (except consuming `fileSlots`), `modules/profiles/*`, `modules/hardware/*`, `modules/deployment/*`, `lib/*`, `home/*`, `flake.nix`. Existing files you MAY modify: `modules/things/default.nix` (add the `execStart` option ONLY), `modules/things/loader.nix` (add the `execStart` mkDefault merge ONLY), `modules/things/runtimes/default.nix` (add the `./host-install.nix` import ONLY), `hosts/bnox-dev/configuration.nix` (add the second thing). New files: `modules/things/runtimes/host-install.nix`, `hosts/bnox-dev/mock-daemon/.bnox/{thing,main}.nix`.
- Do NOT add a "Q14 deviation granted" gate (D-009 deviations are decision-log concerns, not runtime checks).
- The host-install unit must run as the THING's user (NOT root) — Q9.6 (the daemon runs with the thing's isolation; Hermes runs as `hermes`).
- Mock fixture files must be git-tracked (`git add`) so the flake includes them (else `builtins.pathExists` fails + the loader's hard-fail assertion fires) — same requirement as Job 08.

## Validation to run before reporting done

- `nix flake check` (pass); `nix flake show` (unchanged).
- **bnox-dev end-to-end (the load-bearing check):** via `nix eval .#nixosConfigurations.bnox-dev.config.<path>`:
  - `systemd.services."mock-daemon-main"` exists: `ExecStart="/var/lib/mock-daemon/run"`, `User="mock-daemon"`, `Group="mock-daemon"`, `WorkingDirectory="/var/lib/mock-daemon"`, `Restart="on-failure"`, `wantedBy=["multi-user.target"]`, hardening directives present (`ProtectSystem="strict"`, `ReadWritePaths="/var/lib/mock-daemon /var/lib/bnox/secrets/mock-daemon"`, `IPAddressDeny="any"`, `IPAddressAllow=":443 :53"`, `NoNewPrivileges="true"`, `CapabilityBoundingSet=""`, etc.).
  - `bnox.secrets.fileSlots."mock-daemon/token"` = `{owner="mock-daemon", group="mock-daemon", restartUnits=["mock-daemon-main"]}`.
  - `users.users.mock-daemon` exists (Job 04's user.nix created it from the enabled thing).
  - `bnox.things.mock-daemon.components.main` = `{shape="daemon", runtime="host-install", execStart="/var/lib/mock-daemon/run", enable=true, ...}` (loader populated the intrinsic fields incl. execStart).
  - The existing `demo` thing (container runtime) is UNCHANGED (regression — container/vhost/fileSlot/loader-intrinsic byte-identical to Job 11).
  - `failedAssertions = []`.
- Throwaway eval: a host-install component WITHOUT `execStart` → natural error or assertion (confirm it fails loud, doesn't silently produce a unit with empty ExecStart).
- Comment/description scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/things/runtimes/host-install.nix modules/things/default.nix modules/things/loader.nix modules/things/runtimes/default.nix hosts/bnox-dev/` → empty.
- Confirm the container runtime + the host-install runtime are mutually exclusive per component (a component is one runtime; no double-unit).

## Worker notes

### Files created
- `modules/things/runtimes/host-install.nix` (new) — the host-install runtime module, mirroring `container.nix`.
- `hosts/bnox-dev/mock-daemon/.bnox/thing.nix` (new fixture) — `{ deps=[]; secrets=[]; components=["main"]; }`.
- `hosts/bnox-dev/mock-daemon/.bnox/main.nix` (new fixture) — `{ shape="daemon"; runtime="host-install"; execStart="/var/lib/mock-daemon/run"; ingressPort=null; natsSubject=null; secrets=["token"]; }`.

### Files modified (minimal)
- `modules/things/default.nix` — added `execStart = lib.mkOption { type = nullOr str; default = null; };` to `componentSubmodule` ONLY.
- `modules/things/loader.nix` — added `execStart = lib.mkDefault (comp.execStart or null);` to the `loadable` config block ONLY. `topLevel`/`thingSubmodule` untouched.
- `modules/things/runtimes/default.nix` — added `./host-install.nix` to imports.
- `hosts/bnox-dev/configuration.nix` — added the second thing. **Deviation from the job's exact snippet (necessary):** the job specified `{ enable = true; source = toString ./mock-daemon; }` only, but the loader populates FIELDS of components that already exist in the `attrsOf` — it does NOT auto-create component attrs from the manifest (that would need a `thingSubmodule` change, explicitly out of scope). Added `components.main = { };` to create the component attr so the loader can populate it (same pattern as demo's `components.web.domain = ...`). Without it, `components` stays `{}` and no service/fileSlot is emitted.

### host-install unit design
For each enabled component with `comp.enable && comp.runtime == "host-install"`:
- **Service name:** `<thing>-<component>` (e.g. `mock-daemon-main`) — a plain `systemd.services` entry (no `podman-` prefix; host-install is not a container).
- **Lifecycle:** `wantedBy=["multi-user.target"]`, `after=["network.target"]` (daemon, long-running).
- **Runtime fields:** `serviceConfig.ExecStart=comp.execStart`, `User=<thing>`, `Group=<thing>`, `WorkingDirectory="/var/lib/<thing>"`, `Restart="on-failure"`, `RestartSec=5`, `Environment=["HOME=/var/lib/<thing>"]`.
- **Hardening:** the full Q9.7 19-directive bundle applied via `hardening.bundle` (`import ../hardening.nix { inherit lib; }`), merged into `serviceConfig` with `//`. `writablePaths=["/var/lib/<thing>" "/var/lib/bnox/secrets/<thing>"]`.
- **Egress (D-009):** `ipAddressAllow=[":443" ":53"]` → `IPAddressAllow=":443 :53"` + `IPAddressDeny="any"` (outbound HTTPS + DNS; the host-install default per D-009). Unconditional for host-install (the outboundHTTPS override hook is a container-runtime concern; host-install daemons are purpose-built for outbound — D-009). A host can still tighten per-thing via the hardening override module if a future host-install thing doesn't need egress.
- **fileSlots:** `thing.secrets ++ comp.secrets` → `bnox.secrets.fileSlots."<thing>/<slot>"` with `owner=group=<thing>` and `restartUnits=["<thing>-<component>"]`. Mirrors container.nix's `groupBy` + `lib.unique` so a slot shared across host-install components of the same thing dedups; the module system concatenates restartUnits across runtime modules, so a slot shared with a container component of the same thing also merges cleanly.
- **Loud-fail assertion:** `config.assertions` asserts every host-install component has `execStart != null` (message: `bnox: host-install component "<thing>.<component>" requires execStart`). A host-install component missing execStart fails at eval, not as a silent empty-ExecStart unit.
- **Does NOT install the thing or manage updates** (D-009) — bnox provides unit + user + secrets + hardening ONLY. The host-install unit runs as the THING's user (NOT root) — Q9.6; user.nix already created it.

### execStart schema + loader extension
`execStart : nullOr str` (default null) on the component submodule; loader reads `comp.execStart or null` via `mkDefault` from `.bnox/<component>.nix`. Unused for container components (container.nix never references it; demo regression confirms `execStart=null` for demo's web component is harmless).

### Mock fixture
`mock-daemon` thing (daemon shape, host-install runtime) added alongside `demo`. Exercises the full path via the real flake eval. git-add'd (flake only sees tracked files).

### Validation output
- **`nix flake check`:** PASS (checks nixosModules.bnox, nixosModules.bnox-base, nixosConfigurations.bnox-dev — all clean; only the expected `profiles`/`hardware` "unknown flake output" + dirty-tree warnings).
- **`nix flake show`:** UNCHANGED (same outputs: hardware, lib, nixosConfigurations.bnox-dev, nixosModules.{bnox,bnox-base}, profiles).
- **`mock-daemon-main` service** (`config.systemd.services.mock-daemon-main.serviceConfig`): `ExecStart="/var/lib/mock-daemon/run"`, `User="mock-daemon"`, `Group="mock-daemon"`, `WorkingDirectory="/var/lib/mock-daemon"`, `Restart="on-failure"`, `RestartSec=5`, `Environment=["HOME=/var/lib/mock-daemon"]`; full hardening set present (`ProtectSystem="strict"`, `ProtectHome="true"`, `ReadWritePaths="/var/lib/mock-daemon /var/lib/bnox/secrets/mock-daemon"`, `PrivateTmp/PrivateDevices/NoNewPrivileges="true"`, `CapabilityBoundingSet=""`, `SystemCallFilter="@system-service"`, `RestrictAddressFamilies="AF_INET AF_INET6"`, all `ProtectKernel*/ProtectClock/ProtectHostname/ProtectControlGroups="true"`, `ProtectProc="invisible"`, `ProcSubset="pid"`); `IPAddressDeny="any"`, `IPAddressAllow=":443 :53"`. `wantedBy=["multi-user.target"]`, `after=["network.target"]`.
- **`bnox.secrets.fileSlots`:** `{"demo/api_key":{owner:"demo",group:"demo",restartUnits:["podman-demo-web"]}, "mock-daemon/token":{owner:"mock-daemon",group:"mock-daemon",restartUnits:["mock-daemon-main"]}}`. mock-daemon/token correct; demo/api_key UNCHANGED.
- **`users.users.mock-daemon`:** exists (`isSystemUser=true`, `home="/var/lib/mock-daemon"`, `group="mock-daemon"`, `createHome=true`) — created by user.nix.
- **`bnox.things.mock-daemon.components.main`:** `{shape:"daemon", runtime:"host-install", execStart:"/var/lib/mock-daemon/run", enable:true, ingressPort:null, natsSubject:null, secrets:["token"], domain:null}` — loader populated all intrinsic fields incl. execStart.
- **Demo UNCHANGED (regression):** `bnox.things.demo.components.web` = `{shape:"webapp", runtime:"container", ingressPort:8080, secrets:["api_key"], domain:"demo.local", execStart:null, ...}`; `podman-demo-web` serviceConfig + oci-containers.containers.demo-web + caddy `demo.local` vhost all byte-identical to Job 11 (the only delta is the new harmless `execStart:null` default on the component). mock-daemon adds NO caddy vhost (daemon shape has no inbound).
- **`failedAssertions`:** 0.
- **Throwaway eval — host-install WITHOUT execStart fails loud:** built a throwaway `nixosSystem` overriding a host-install component's `execStart` to null; forcing `system.build.toplevel` throws (`builtins.tryEval` → `success:false`); inspecting failing assertions yields exactly `[{"assertion":false,"message":"bnox: host-install component \"testdaemon.main\" requires execStart"}]`. Not a silent empty-ExecStart unit.
- **Mutual exclusivity:** confirmed a component is one runtime (enum) → matches only one runtime module's filter. `mock-daemon-main` exists as a systemd service; NO `podman-mock-daemon-main` container (`hasPodmanMock:false`); NO `demo-web` host-install unit (`hasHIDemo:false`). No double-unit.
- **Comment/description scan:** `rg '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description ='` over host-install.nix, default.nix, loader.nix, runtimes/default.nix, hosts/bnox-dev/ → empty (exit 1).

### Notes for the checker
- The `components.main = {}` addition in configuration.nix is the one deviation from the job's verbatim snippet; it is necessary and minimal (see "Files modified" above). The demo precedent (`components.web.domain = ...` creates the `web` component attr) confirms this is the established pattern; the loader does not auto-create component attrs and the constraints forbid a thingSubmodule change to add that.
- Whole-service eval via `nix eval config.systemd.services.<name>` (without a sub-path) hits a known NixOS eval quirk on the derived `startLimitBurst` option; use `config.systemd.services.<name>.serviceConfig` / `.wantedBy` / `.after` instead. `nix flake check` (the real system eval) passes clean.
- The `Environment` var is `HOME` only (no `<THING>_HOME`); the job allowed "else just HOME", and the generic host-install runtime is not Hermes-specific.

## Checker notes

**Verdict: PASS.** Job 12 meets the spec; Phase 2 (real thing hosting) is complete. Verified independently 2026-08-01.

### Per-item results

1. **Scope — PASS (one trivial note).** `git status` + `git diff --stat` confirm ONLY the 7 expected files: new `modules/things/runtimes/host-install.nix` (82 lines), new `hosts/bnox-dev/mock-daemon/.bnox/{thing,main}.nix`, modified `modules/things/{default,loader,runtimes/default}.nix` (4/1/1-line diffs), modified `hosts/bnox-dev/configuration.nix` (+6). `design/STATUS.md` also touched (1 line, "next" → "in-progress") — NOT in the MAY-modify list, but it is trivial process metadata, not schema/code; flag for awareness, not blocking.
2. **No comments / descriptions — PASS.** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description ='` over the 5 required paths returns empty (exit 1).
3. **Schema extension — PASS.** `default.nix:46-49` adds ONLY `execStart = lib.mkOption { type = nullOr str; default = null; };` to `componentSubmodule`. `git diff` shows +4 lines, nothing else. Validators `depErrors`/`portCollisions`/`subjectCollisions`, `thingOptionsModule`, `enabledThingsList`/`enabledComponents` byte-identical.
4. **Loader extension — PASS.** `loader.nix:38` adds ONLY `execStart = lib.mkDefault (comp.execStart or null);` to `componentSubmodule`'s `loadable` config block (+1 line). `topLevel` + `thingSubmodule` byte-identical.
5. **host-install runtime correctness — PASS.**
   - Filter at `host-install.nix:20` is `comp.enable && comp.runtime == "host-install"`; mutually exclusive with `container.nix:24` (`runtime == "container"`). One component → one runtime module matches.
   - `host-install.nix:23-49` emits `systemd.services."<thing>-<component>"` with `ExecStart=comp.execStart`, `User=<thing>`, `Group=<thing>` (NOT root — Q9.6), `WorkingDirectory="/var/lib/<thing>"`, `Restart="on-failure"`, `RestartSec=5`, `Environment=["HOME=/var/lib/<thing>"]`, `wantedBy=["multi-user.target"]`, `after=["network.target"]`. All confirmed in mock-daemon-main.
   - `host-install.nix:37-46` applies `hardening.bundle { writablePaths=["/var/lib/<thing>" "/var/lib/bnox/secrets/<thing>"]; ipAddressAllow=[":443" ":53"]; }` via `//`. All 19 directives land (counted in reproduced output).
   - `host-install.nix:51-69` mirrors container.nix's `groupBy` + `lib.unique` slot grouping; `thing.secrets ++ comp.secrets` → `"<thing>/<slot>"`, `owner=group=<thing>`, `restartUnits` dedup'd. The module system concatenates `fileSlots` across runtime modules, so a slot shared with a container component of the same thing merges cleanly.
   - `host-install.nix:76-81` loud-fail assertion is data-only (`config.assertions`), not `throw`. Reproduced: throwaway host-install component with `execStart=null` yields exactly `[{"assertion":false,"message":"bnox: host-install component \"testdaemon.main\" requires execStart"}]`.
6. **D-009 fidelity — PASS.** bnox provides unit + user (already from user.nix) + secrets slot + hardening ONLY. No install logic, no update logic, no root user, no "Q14 deviation granted" gate. egress = `:443 :53` + `Deny=any` (HTTPS + DNS) per D-009.
7. **daemon shape unchanged — PASS.** `shapes/daemon.nix` still `{}` (1 line, no change). mock-daemon (daemon shape) produces NO Caddy vhost — reproduced: `services.caddy.virtualHosts` has only `demo.local` + `bnox-webhook.local`.
8. **Validation reproduction — PASS** (all reproduced below).
9. **Fixture git-tracked — PASS.** `git ls-files hosts/bnox-dev/mock-daemon/` returns both `.bnox/thing.nix` and `.bnox/main.nix` (also staged as `A` in `git status`).
10. **`components.main = {}` deviation — PASS.** Necessary and minimal. The loader's `componentSubmodule` (loader.nix:20-40) only populates FIELDS of components already present in the host-declared `attrsOf`; it does NOT auto-create component attrs from the manifest (that would require a `thingSubmodule` change, explicitly out of scope). Without `components.main={}`, `components` stays `{}` and no service/fileSlot emits. Matches the established `demo` precedent (`components.web.domain=...` creates the `web` attr at configuration.nix:19).

### Minor interpretation note (not NEEDS-FIX)

The spec's "HONOR the existing override hook" language for `:443` could be read as requiring host-install to consult `thing.hardening.network.outboundHTTPS`. The worker hardcoded `:443 :53` for all host-install components (host-install.nix:42-45), noting host-install is "purpose-built for outbound" per D-009 and a host can still tighten per-thing via the hardening override module if a future host-install thing doesn't need egress. This is functionally equivalent to the spec's "it always is for host-install by default" and matches D-009's narrow Hermes authorization. Acceptable.

### Reproduced validation output

**`nix flake check`** — clean (only expected `profiles`/`hardware` unknown-output + dirty-tree warnings):
```
checking NixOS module 'nixosModules.bnox'...
checking NixOS module 'nixosModules.bnox-base'...
checking NixOS configuration 'nixosConfigurations.bnox-dev'...
warning: unknown flake output 'profiles' / 'hardware'
warning: The check omitted these incompatible systems: x86_64-linux
```

**`nix flake show`** — unchanged: `hardware`, `lib`, `nixosConfigurations.bnox-dev`, `nixosModules.{bnox,bnox-base}`, `profiles`.

**`config.systemd.services.mock-daemon-main.serviceConfig`** — all required fields + 19 hardening directives:
```json
{"CapabilityBoundingSet":"","Environment":["HOME=/var/lib/mock-daemon"],"ExecStart":"/var/lib/mock-daemon/run","Group":"mock-daemon","IPAddressAllow":":443 :53","IPAddressDeny":"any","NoNewPrivileges":"true","PrivateDevices":"true","PrivateTmp":"true","ProcSubset":"pid","ProtectClock":"true","ProtectControlGroups":"true","ProtectHome":"true","ProtectHostname":"true","ProtectKernelLogs":"true","ProtectKernelModules":"true","ProtectKernelTunables":"true","ProtectProc":"invisible","ProtectSystem":"strict","ReadWritePaths":"/var/lib/mock-daemon /var/lib/bnox/secrets/mock-daemon","Restart":"on-failure","RestartSec":5,"RestrictAddressFamilies":"AF_INET AF_INET6","SystemCallFilter":"@system-service","User":"mock-daemon","WorkingDirectory":"/var/lib/mock-daemon"}
```
`.wantedBy = [ "multi-user.target" ]`, `.after = [ "network.target" ]`.

**`config.bnox.secrets.fileSlots`** — mock-daemon/token correct, demo/api_key UNCHANGED:
```json
{"demo/api_key":{"group":"demo","owner":"demo","restartUnits":["podman-demo-web"]},"mock-daemon/token":{"group":"mock-daemon","owner":"mock-daemon","restartUnits":["mock-daemon-main"]}}
```

**`config.users.users.mock-daemon`** — exists: `isSystemUser=true`, `home="/var/lib/mock-daemon"`, `group="mock-daemon"`, `createHome=true` (Job 04's user.nix).

**`config.bnox.things.mock-daemon.components.main`** — loader populated execStart:
```json
{"domain":null,"enable":true,"execStart":"/var/lib/mock-daemon/run","ingressPort":null,"natsSubject":null,"runtime":"host-install","secrets":["token"],"shape":"daemon"}
```

**Demo UNCHANGED (regression)** — `bnox.things.demo.components.web` = `{shape:"webapp", runtime:"container", ingressPort:8080, secrets:["api_key"], domain:"demo.local", execStart:null, ...}`. `oci-containers.containers.demo-web` byte-identical (image "demo-web:current", user "demo", envFile "/var/lib/bnox/secrets/demo/api_key", ports "127.0.0.1:8080:8080"). `podman-demo-web.serviceConfig` hardening set unchanged (outboundHTTPS=false → `IPAddressAllow=""`). Only delta is the new harmless `execStart:null` default on the component.

**`failedAssertions = []`** (filtered to `assertion==false`).

**Throwaway — host-install WITHOUT execStart fails loud:**
```json
["bnox: host-install component \"testdaemon.main\" requires execStart"]
```
Not a silent empty-ExecStart unit.

**Mutual exclusivity** — `hasAttr "podman-mock-daemon-main" systemd.services = false`; `hasAttr "demo-web" systemd.services = false`. No double-unit.

## Sign-off
PASS — Job 12 verified independently 2026-08-01. Phase 2 (real thing hosting) is complete; bnox now hosts both container things (Job 05/08/11) and host-install daemon things (Job 12, the D-009 Hermes path) end-to-end via `bnox-dev`.
