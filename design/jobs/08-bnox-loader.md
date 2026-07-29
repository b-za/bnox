# Job 08: `.bnox/` loader (thing-intrinsic fields from thing repos)

**Status:** done
**Iteration:** 1
**Created:** 2026-07-29

## Scope

Build the `.bnox/` loader: for each enabled thing, read thing-intrinsic fields from `${source}/.bnox/{thing.nix,<component>.nix}` and merge them into the existing `bnox.things.*` schema (defined in Job 04) via `lib.mkDefault`. This moves shape/runtime/deps/ports/subject/secrets-slot-names OUT of host config and INTO the thing's own repo, per Q9.5's symmetry rule. Host config retains only host-specific bindings (enable, source, component enable flags, domain, secrets binding sources).

This is a **pure data-source refactor**: the runtime config the rest of the system produces (containers, Caddy vhosts, fileSlots, users, hardening) must be byte-identical before and after the loader lands. The loader populates the same schema Job 04 defined and Jobs 05/07 consume — it does NOT change what is produced, only where the intrinsic data comes from.

**User-confirmed design (this session):**
- **Merge mechanism = `mkDefault` injection.** Loader sets thing-intrinsic fields as `mkDefault`; host config can override (rare escape hatch). The option schema (Job 04) is UNTOUCHED — fields stay, the loader just fills them. No priority-inspecting "host overrode intrinsic field" warning gadget in v1 (out of scope, Q14). The symmetry rule is enforced by convention + the hard-fail assertion below, not by type-level lockdown.
- **`.bnox/` layout = per-component files** (faithful to `06-base-design.md` lines 139-146 + Q9.5 sketch): `.bnox/thing.nix` (manifest + thing-level fields) + `.bnox/<component>.nix` per component.
- **Missing `.bnox/` on an enabled thing = hard assertion failure** (enforces symmetry; catches "enabled but repo not synced"). The validation host (`bnox-dev`) stays eval-green via a **mock thing fixture** shipped under `hosts/bnox-dev/demo-thing/` (also serves as the reference example for thing authors).

**Deferred (NOT this job):**
- Deployment pipeline (D-011 — webhook + NATS + sync/build units + rollback). Jobs 09-11.
- `host-install` runtime + real `daemon` shape effects (Q9.9/Q9.8, Hermes D-009). Job 12. This job does NOT add an `execStart`/`command` field to the schema; host-install lands its own schema extension when it needs it (the loader's `mkDefault` merge already supports arbitrary fields being added later).
- Auto-derivation of `natsSubject` from a thing-level prefix. `natsSubject` stays component-level and is read verbatim from `.bnox/<component>.nix`. A thing-level prefix field can land with the nats-api/daemon effects job if useful.
- Granular flake output `nixosModules.bnox-things` (unchanged from Phase 1 deferral).

**Spec sources (read these):**
- `design/jobs/04-things-core.md` — the exact schema the loader populates (read the worker's submodule defs in its Worker notes; the field list, types, defaults are authoritative). Loader must NOT redefine any of these options.
- `design/jobs/05-things-shapes-runtimes.md` — how the schema is consumed (container runtime reads `thing.secrets ++ comp.secrets`, `comp.ingressPort`, etc.). The loader's output must drive identical consumption.
- `design/process/06-base-design.md` — `.bnox/` repo-layout sketch (lines 137-148) + host-config schema (lines 113-135) + loader description (line 148).
- `design/working/open-questions.md` Q9.5 — symmetry rule ("host-specific interface is the same shape at thing-level and component-level; thing-intrinsic declared in `.bnox/`, host binds host-specific slots").
- `design/memory/agent-handoff.md` — technical gotchas (the `podman-<name>` service naming, `mkDefault`/`mkForce` precedence, the `fsType="ext4"` stub-eval trick).

## Thing-intrinsic vs host-specific (the Q9.5 split — load-bearing)

| Field | Lives in `.bnox/` (thing-intrinsic) | Lives in host config (host-specific) |
|---|---|---|
| `enable` (thing) | | ✓ |
| `source` | | ✓ |
| `deps` | ✓ | |
| `secrets` (thing-level slot names) | ✓ | |
| `hardening.*` (override) | | ✓ (override only) |
| `components.<c>.enable` | | ✓ |
| `components.<c>.shape` | ✓ | |
| `components.<c>.runtime` | ✓ | |
| `components.<c>.ingressPort` | ✓ | |
| `components.<c>.natsSubject` | ✓ | |
| `components.<c>.secrets` (slot names) | ✓ | |
| `components.<c>.domain` | | ✓ |

The loader sets every field in the left column (via `mkDefault`); the host sets every field in the right column. A host MAY set a left-column field (it overrides the `mkDefault`) but by convention should not.

## `.bnox/` file format (attrsets returned by plain Nix `import`)

### `.bnox/thing.nix` — returns an attrset:

```
{
  deps       = [ <thing-name> ... ];   # optional, default []  → bnox.things.<name>.deps
  secrets    = [ <slot-name> ... ];    # optional, default []  → bnox.things.<name>.secrets (thing-level slot names)
  components = [ <component-name> ... ]; # REQUIRED — manifest of components this thing declares.
                                         #   Each name must have a sibling .bnox/<name>.nix.
                                         #   The host enables a component by referencing it; the
                                         #   loader validates every host-referenced component is
                                         #   in this manifest.
}
```

### `.bnox/<component>.nix` — returns an attrset:

```
{
  shape       = "static-site" | "webapp" | "http-api" | "nats-api" | "daemon";  # REQUIRED
  runtime     = "container" | "host-install";   # optional, default "container"
  ingressPort = <int or null>;                  # optional, default null
  natsSubject = <str or null>;                  # optional, default null  (e.g. "things.<name>.<comp>.>")
  secrets     = [ <slot-name> ... ];            # optional, default []  (component-level slot names)
}
```

These mirror the Job-04 component submodule exactly (same enums, same defaults). A component file may omit any optional field; the loader applies the same defaults the submodule would.

## Loader logic (`modules/things/loader.nix`)

A NixOS module that reads `config.bnox.things` and emits `config.bnox.things` (mkDefault-merged). It reads host-provided fields (`enable`, `source`, component existence/`domain`) and writes thing-intrinsic fields — no field is both read and written by this module, so there is no eval cycle.

For each thing where `config.bnox.things.<name>.enable == true`:

1. **Hard-fail on missing manifest.** If `!builtins.pathExists "${source}/.bnox/thing.nix"` → emit a `config.assertions` entry with `assertion = false` and message:
   `bnox: thing "<name>" is enabled but has no .bnox/thing.nix at "<source>/.bnox/" (expected the thing-intrinsic manifest per Q9.5)`.
   (Use the same `config.assertions` data-only pattern as Job 04's validators — do NOT `throw` at eval time.)

2. **Read manifest.** `let manifest = import "${source}/.bnox/thing.nix"; in ...`. Treat `deps`/`secrets` as defaulting to `[]` if absent; `components` as defaulting to `[]` if absent.

3. **Thing-level merge.** Set `config.bnox.things.<name>.deps = lib.mkDefault manifest.deps;` and `config.bnox.things.<name>.secrets = lib.mkDefault manifest.secrets;` (guard for the absent-key case).

4. **Component validation + merge.** For each component name `c` in `builtins.attrNames config.bnox.things.<name>.components` (i.e. components the HOST has chosen to declare — the host opts in per component):
   - If `c` is not in `manifest.components` → assertion failure:
     `bnox: host declares component "<c>" on thing "<name>", but "<c>" is not in the thing's .bnox manifest ([<manifest list>])`.
   - Else if `!builtins.pathExists "${source}/.bnox/<c>.nix"` → assertion failure:
     `bnox: thing "<name>" manifest lists component "<c>" but "<source>/.bnox/<c>.nix" is missing`.
   - Else read `comp = import "${source}/.bnox/<c>.nix";` and mkDefault-merge every present field: `shape`, `runtime` (default `"container"`), `ingressPort` (default `null`), `natsSubject` (default `null`), `secrets` (default `[]`). `shape` is required in the component file; if absent, let the Job-04 option's "no default" surface the natural eval error (do not synthesize one).

**Host opt-in semantics:** the loader creates NO component entries. The host must reference a component (even as `components.web = {};`) for it to exist; the submodule's existing `enable` default of `true` then enables it. Components in the manifest but unreferenced by the host simply do not exist on that host. This matches the Q9.5 sketch's explicit-enable intent and avoids surprise auto-enablement of multi-component things.

**String-path handling:** `source` is a `str`. Build paths as `"${source}/.bnox/thing.nix"` (string interpolation). `builtins.pathExists` and `import` both accept absolute path strings. For the `bnox-dev` fixture, `source` resolves to an absolute store path at eval (see fixture section) — confirm `pathExists`/`import` work against store paths.

## Files to create / modify

1. **`modules/things/loader.nix`** (new) — the loader module described above. Plain NixOS module `{ lib, config, ... }: { config.assertions = ...; config.bnox.things.<name>... = lib.mkDefault ...; }`. No option declarations (it only populates existing options + assertions).
2. **`modules/things/default.nix`** (modify) — add `./loader.nix` to the existing `imports = [...]` list. Do NOT change the option schema, the validators, or any other import.
3. **`hosts/bnox-dev/demo-thing/.bnox/thing.nix`** (new) — mock fixture manifest:
   `{ deps = []; secrets = []; components = [ "web" ]; }`
4. **`hosts/bnox-dev/demo-thing/.bnox/web.nix`** (new) — mock fixture component (mirrors the current inline `bnox-dev` demo values exactly):
   `{ shape = "webapp"; runtime = "container"; ingressPort = 8080; natsSubject = null; secrets = [ "api_key" ]; }`
5. **`hosts/bnox-dev/configuration.nix`** (modify) — the `bnox.things.demo` block becomes host-specific only:
   ```nix
   bnox.things.demo = {
     enable = true;
     source = toString ./demo-thing;
     components.web.domain = "demo.local";
   };
   ```
   Drop the inline `shape`/`runtime`/`ingressPort`/`secrets` (now sourced from the fixture). `source = toString ./demo-thing;` resolves the repo-relative path to an absolute string at eval (works against the flake's store copy on any host). `components.web.domain` is the only host-specific field for this component. `components.web.enable` is left at its submodule default (`true`).

**Git tracking (load-bearing for eval):** flake source is copied from git-tracked files. The worker MUST `git add` the new fixture files (`hosts/bnox-dev/demo-thing/.bnox/*.nix`) so the flake includes them — otherwise `builtins.pathExists` on the store path returns false and the hard-fail assertion fires. Verify with `git status` before reporting done.

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT modify the Job-04 option schema or validators in `modules/things/default.nix` (add the `./loader.nix` import ONLY).
- Do NOT touch `modules/things/{user,hardening}.nix`, `modules/things/shapes/*`, `modules/things/runtimes/*`, `modules/secrets/*`, `modules/platform/*`, `modules/base/*`, `modules/profiles/*`, `modules/hardware/*`, `lib/*`, `home/*`, `flake.nix`. (Exception: `hosts/bnox-dev/configuration.nix` + the new fixture files under `hosts/bnox-dev/demo-thing/`.)
- Do NOT implement deployment, host-install runtime, daemon effects, natsSubject auto-derivation, or granular flake outputs.
- The loader must be a pure refactor of where intrinsic data comes from — runtime config produced for `bnox-dev` must be identical to pre-loader (validate this explicitly; see below).
- Do NOT add a priority-inspecting "host overrode intrinsic field" warning. The `mkDefault` escape hatch is ungated by design (Q14).

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — outputs unchanged.
- **Pure-refactor proof (the key check):** the `bnox-dev` runtime config must be byte-identical before and after. Via `nix eval .#nixosConfigurations.bnox-dev.config.<path>`, confirm (paste before/after or confirm equality):
  - `virtualisation.oci-containers.containers."demo-web"` — `image`, `user`, `environmentFiles`, `ports` unchanged (`"demo-web:current"`, `"demo"`, `["/var/lib/bnox/secrets/demo/api_key"]`, `["127.0.0.1:8080:8080"]`).
  - `services.caddy.virtualHosts."demo.local".extraConfig` unchanged (`"reverse_proxy 127.0.0.1:8080\n"`).
  - `bnox.secrets.fileSlots."demo/api_key"` — `owner`, `group`, `restartUnits` unchanged (`"demo"`, `"demo"`, `["podman-demo-web"]`).
  - `systemd.services."podman-demo-web".serviceConfig` hardening directives unchanged.
  - `users.users.demo.home` == `"/var/lib/demo"`; `bnox.things.demo.components.web.shape` == `"webapp"`; `.ingressPort` == `8080`; `.secrets` == `["api_key"]`.
- **Throwaway `nixosSystem` evals** (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"` — the Job-04/05 trick):
  - **Missing `.bnox/`:** enabled thing with `source = "/nonexistent/path"` → the hard-fail assertion fires with the exact message naming the thing + the path. Confirm via `builtins.filter (a: !a.assertion) config.assertions`.
  - **Component not in manifest:** fixture `thing.nix` manifest `[ "web" ]`, host declares `components.api = {};` → assertion fires naming `api`, the thing, and the manifest list.
  - **Component file missing:** manifest lists `api`, host declares `components.api = {};`, but no `.bnox/api.nix` → assertion fires naming the thing + the missing file path.
  - **Multi-component:** a mock thing with two components (e.g. `web` + `api`) both populated correctly from their respective `.bnox/<c>.nix`; confirm both `shape`/`ingressPort` merge.
  - **Host override (escape hatch):** host sets `components.web.shape = "http-api";` overriding the fixture's `"webapp"` → effective value is `"http-api"` (mkDefault yields to plain). Confirm.
- Comment scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/things/loader.nix hosts/bnox-dev/` → no matches.

## Worker notes

**Built (Job 08, iteration 1, 2026-07-29):**

Files created (3) / modified (2):
- `modules/things/loader.nix` (new) — `{ lib }: { topLevel, thingSubmodule, componentSubmodule }` (a function file `import`-ed by `default.nix`, mirroring the `hardening.nix` precedent from Job 04). See "Why loader.nix is `import`-ed, not in `imports`" below.
- `modules/things/default.nix` (modified) — wired the loader in (4 points; see "default.nix diff summary"). Option schema (every `mkOption` declaration, type, default) byte-identical to Job 04/05; only wiring + submodule-list additions changed.
- `hosts/bnox-dev/demo-thing/.bnox/thing.nix` (new) — `{ deps = []; secrets = []; components = [ "web" ]; }`.
- `hosts/bnox-dev/demo-thing/.bnox/web.nix` (new) — `{ shape = "webapp"; runtime = "container"; ingressPort = 8080; natsSubject = null; secrets = [ "api_key" ]; }`.
- `hosts/bnox-dev/configuration.nix` (modified) — `bnox.things.demo` now host-specific only: `enable`, `source = toString ./demo-thing`, `components.web.domain`. Inline `shape`/`runtime`/`ingressPort`/`secrets` dropped (now sourced from the fixture).

**CRITICAL DEVIATION — the spec's single top-level module cycles; loader.nix is `import`-ed (function file), not a plain module in `imports`:**

The spec envisioned loader.nix as "a plain NixOS module `{ lib, config, ... }: { config.assertions = ...; config.bnox.things.<name>... = lib.mkDefault ...; }`" added to `imports`. **This is empirically impossible:** a top-level module that writes `config.bnox.things` with attr-names derived from `config.bnox.things` triggers `infinite recursion encountered` (confirmed by direct eval). Root cause: `types.attrsOf` is strict in keys — to merge `bnox.things`, nixpkgs forces every definition's attr-names (via `zipAttrsWith`); the loader's definition's attr-names come from `filterAttrs (_: t: t.enable) config.bnox.things`, which forces `attrNames config.bnox.things`, which re-enters the merge being computed. The spec's claim "no field is both read and written, so there is no eval cycle" is correct at the field level but wrong at the structural (key-collection) level. The cycle is unavoidable for any top-level module that generates `bnox.things.<name>` keys from `config.bnox.things`.

The cycle is only breakable by moving the per-thing / per-component writes into the **submodule instance** (where `name` is supplied by the submodule system per-instance, not by iterating the merged attrset). This requires loader.nix to be a function file returning submodule modules (`{ topLevel, thingSubmodule, componentSubmodule }`) — exactly the dual-purpose pattern Job 04 established for `hardening.nix` (`{ lib }: { bundle, overrideModule }`). `default.nix` then `import ./loader.nix { inherit lib; }` and wires the three pieces in. "Add `./loader.nix` to imports" is read loosely as "load/reference loader.nix" — the same loose reading Job 04's checker approved for hardening.nix (a strict NixOS-module interpretation is incompatible with returning submodule-module values).

**default.nix diff summary (4 changes; schema byte-identical):**
1. `let loader = import ./loader.nix { inherit lib; };` (sibling to `hardening`).
2. `thingOptionsModule`: `{ name, ... }:` → `{ name, config, ... }:` (so `config.source` / `config.enable` are in scope for the component option's `specialArgs`).
3. `components` option type: `attrsOf (submodule componentSubmodule)` → `attrsOf (submoduleWith { modules = [ componentSubmodule loader.componentSubmodule ]; specialArgs = { thingSource = config.source; thingName = name; thingEnable = config.enable; }; })`. The component's user-facing schema (every option/type/default in `componentSubmodule`) is unchanged; `loader.componentSubmodule` only adds `config` defaults via `mkDefault` + receives `thingSource`/`thingName`/`thingEnable` via `specialArgs`. `submoduleWith` is the documented nixpkgs API for passing `specialArgs` to a nested submodule (verified against `nixpkgs/lib/types.nix:1252`); it is the only way a nested component submodule can learn its parent thing's `source` (nested submodules are otherwise isolated from parent config).
4. `imports`: added `loader.topLevel` (the assertions module).
5. Thing submodule list: `[ thingOptionsModule hardening.overrideModule ]` → `[ thingOptionsModule hardening.overrideModule loader.thingSubmodule ]` (one new entry, same shape as how `hardening.overrideModule` was added in Job 04).

**Loader behavior (exactly per spec; three cooperating modules):**

- `topLevel` (top-level NixOS module): emits `config.assertions` for validation. Iterates enabled things only (`filterAttrs (_: t: t.enable)`). Per enabled thing: (a) if `!pathExists "${source}/.bnox/thing.nix"` → assertion with the exact spec message `bnox: thing "<name>" is enabled but has no .bnox/thing.nix at "<source>/.bnox/" (expected the thing-intrinsic manifest per Q9.5)`; (b) for each host-referenced component (`builtins.attrNames config.bnox.things.<name>.components`): if not in `manifest.components` → assertion naming the component, thing, and the manifest list rendered via `builtins.toJSON` (e.g. `(["web"])`); else if `!pathExists "${source}/.bnox/<c>.nix"` → assertion naming the thing + the missing file path. **Critically, `topLevel` writes only `config.assertions` — never `config.bnox.things` — so iterating `config.bnox.things` here does NOT cycle** (the thing/component keys come from the host alone; `thingSubmodule`/`componentSubmodule` add per-instance `config` values, not new attrset keys).
- `thingSubmodule` (thing submodule module, per-instance): `config = lib.mkIf config.enable { deps = lib.mkDefault (manifest.deps or []); secrets = lib.mkDefault (manifest.secrets or []); }`. Reads `${config.source}/.bnox/thing.nix` (guarded by `pathExists`; absent → `{}`). The `mkIf config.enable` guard + the lazy `manifest = if config.enable then readManifest config.source else {}` ensure disabled things never force `config.source` (preserves Job 04's laziness contract: "disabled things without source do NOT fail eval").
- `componentSubmodule` (component submodule module, per-instance; receives `thingSource`, `thingName`, `thingEnable` via `specialArgs`): reads the manifest (memoized via `import`), checks `inManifest = elem name manifestComponents` and `hasFile = pathExists "${thingSource}/.bnox/${name}.nix"`; `config = lib.mkIf (thingEnable && inManifest && hasFile) { shape = mkDefault comp.shape; runtime = mkDefault (comp.runtime or "container"); ingressPort = mkDefault (comp.ingressPort or null); natsSubject = mkDefault (comp.natsSubject or null); secrets = mkDefault (comp.secrets or []); }`. `shape` is read verbatim from the file (no synthesis — if absent in a present file, `comp.shape` throws the natural "attribute missing" error per spec). When not loadable, writes nothing (shape stays default-less → natural eval error if forced; the assertion from `topLevel` is the user-visible failure).

**Conventions chosen:**
1. **Manifest-list rendering in the not-in-manifest message** uses `builtins.toJSON manifestComponents` → e.g. `(["web"])`. The spec wrote `[<manifest list>]`; `toJSON` is the unambiguous Nix-literal rendering and handles the empty case cleanly (`[]`).
2. **Host opt-in honored exactly**: `componentSubmodule` writes per-instance fields only — it creates no component keys. The host must reference a component (even as `components.web = {};`) for it to exist; manifest components the host doesn't reference never instantiate. No auto-enablement.
3. **`mkDefault` escape hatch ungated**: a host MAY set any intrinsic field (e.g. `components.web.shape = "http-api"`) and the plain definition (priority 100) overrides the loader's `mkDefault` (priority 1000). No priority-inspecting warning was added (per spec / Q14).
4. **Redundant manifest reads across `topLevel` + `thingSubmodule` + `componentSubmodule`** are effectively free — Nix's `import` is memoized per path, so the manifest is parsed once and reused.

**Validation output:**

- Comment/description scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/things/loader.nix hosts/bnox-dev/` → exit 1 (no matches; hard constraint met).
- `nix flake check` → clean (only the benign cross-system warning `x86_64-linux` omitted on aarch64-darwin, identical to Jobs 01–07; plus the unchanged `unknown flake output 'profiles'/'hardware'` notes).
- `nix flake show` → `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` all present (outputs unchanged).

- **Pure-refactor proof (the key check) — bnox-dev runtime config byte-identical before/after**, via `nix eval .#nixosConfigurations.bnox-dev.config.<path>`:
  - container `demo-web`: `image="demo-web:current"`, `user="demo"`, `environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]`, `ports=["127.0.0.1:8080:8080"]` — identical.
  - `services.caddy.virtualHosts."demo.local".extraConfig` = `"reverse_proxy 127.0.0.1:8080\n"` — identical.
  - `bnox.secrets.fileSlots."demo/api_key"` = `{"group":"demo","owner":"demo","restartUnits":["podman-demo-web"]}` — identical.
  - `systemd.services."podman-demo-web".serviceConfig`: `ProtectSystem="strict"`, `ReadWritePaths="/var/lib/demo /var/lib/bnox/secrets/demo"`, `NoNewPrivileges="true"`, `IPAddressDeny="any"`, `CapabilityBoundingSet=""` — identical.
  - `users.users.demo.home` = `"/var/lib/demo"`; `bnox.things.demo.components.web.{shape="webapp",ingressPort=8080,secrets=["api_key"],runtime="container",natsSubject=null}`; `bnox.things.demo.{deps=[],secrets=[]}`; `source` resolves to the store path `/nix/store/...-source/hosts/bnox-dev/demo-thing` — all identical to the pre-loader inline values. (Fixture values mirror the prior inline `bnox-dev` block exactly, as the spec required.)

- **Throwaway `nixosSystem` evals** (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`; built via `builtins.getFlake "path:..."` under `--impure` so test things' `source` could point at `/tmp` fixture dirs):
  - **Missing `.bnox/`** (source=`/nonexistent/path`): `[ "bnox: thing \"t\" is enabled but has no .bnox/thing.nix at \"/nonexistent/path/.bnox/\" (expected the thing-intrinsic manifest per Q9.5)" ]` — exact spec message naming thing + path.
  - **Component not in manifest** (manifest `["web"]`, host declares `components.api`): `[ "bnox: host declares component \"api\" on thing \"t\", but \"api\" is not in the thing's .bnox manifest ([\"web\"])" ]` — names component, thing, manifest list.
  - **Component file missing** (manifest `["web","api"]`, host declares `components.api`, no `api.nix`): `[ "bnox: thing \"t\" manifest lists component \"api\" but \"/tmp/.../case-missingfile/.bnox/api.nix\" is missing" ]` — names thing + missing file path.
  - **Multi-component** (manifest `["web","api"]`, both files present): both merge correctly — `webShape="webapp"`, `webPort=8080`, `apiShape="http-api"`, `apiPort=9000`, `apiSecrets=["db"]`, `deps=["other"]` (the `deps=["other"]` value confirms the thing-level manifest merge; Job 04's dep-graph validator then separately fires its own assertion because `other` isn't an enabled thing on the test host — that's Job 04 behavior, not a loader issue).
  - **Host override (escape hatch)** (fixture `web.nix` says `shape="webapp"`; host sets `components.web.shape="http-api"`): effective `shape="http-api"` (plain def overrides `mkDefault`), `port=8080` (still from fixture — host didn't override it). No assertions fire.

  Test-harness note for the checker: the "not-in-manifest" and "file-missing" evals set a dummy `shape="daemon"` on the test component. This is NOT a loader change — it's a test workaround because the platform-default `podman` module writes `config.assertions` whose conditions reference `virtualisation.oci-containers.containers`, which forces `runtimes/container.nix`'s filter (`comp.shape != "static-site"`), which forces `comp.shape`; for a component with no file/manifest-entry the loader correctly leaves `shape` default-less, so without the dummy the eval errors on shape before `config.assertions` can be read. The manifest/file-existence assertions are independent of `shape`, so the dummy doesn't affect what's being verified. (Disabling podman/caddy/nats via `mkForce false` did not help — podman's assertion definitions still force containers regardless of the resolved enable value.)

- Git tracking: `git ls-files hosts/bnox-dev/demo-thing/` → both `.bnox/thing.nix` and `.bnox/web.nix` tracked (staged). Required because flake source is copied from git-tracked files; untracked fixtures would make `builtins.pathExists` return false on the store path and trip the hard-fail assertion.

**For the checker to focus on:**
- **The `import`-ed-function deviation (vs spec's "plain module in imports").** This is forced by the infinite-recursion cycle (empirically reproduced). The fix mirrors Job 04's hardening.nix precedent exactly (function file returning modules; `default.nix` `import`s it). The alternative — a strict single top-level module — does not evaluate. Please confirm this reading is acceptable (it's the only constraint-compatible one that actually works).
- **The `default.nix` wiring (4 changes beyond the literal "add to imports").** All option declarations/types/defaults are byte-identical (`git diff --cached` confirms); only (a) a let-binding, (b) `thingOptionsModule` gaining the `config` arg, (c) the `components` type using `submoduleWith` for specialArgs, (d) `loader.topLevel` in imports, (e) `loader.thingSubmodule` in the thing submodule list. The component submodule gains `loader.componentSubmodule` (config-defaults-only, like `hardening.overrideModule`). Confirm this is "wiring, not schema change".
- **`submoduleWith` + `specialArgs` for parent→child data flow.** This is the documented nixpkgs API (`lib/types.nix:1252`); nested submodules are otherwise isolated from parent config, so it's the only way for the component loader to learn `${thingSource}`. Verified end-to-end (multi-component eval reads both component files via the passed source).
- **Laziness preservation for disabled things.** `thingSubmodule`'s `mkIf config.enable` + lazy `manifest` binding + `componentSubmodule`'s `thingEnable &&` short-circuit ensure a disabled thing without `source` still evaluates (Job 04 contract). Worth a spot-check.
- **The dummy-shape test workaround** for the not-in-manifest / file-missing evals (see test-harness note above). If the checker wants a cleaner isolation, the loader could be tested via a minimal module set excluding platform — but that deviates further from the spec's "use `nixosModules.bnox`" eval instruction. Current approach uses the full bnox module (as the spec's eval pattern specifies) + dummy shape on the synthetic error-component.

## Checker notes

**VERDICT: PASS** — 2026-07-29 (independent checker, iteration 1).

All 10 checklist items OK. The flagged deviation (loader.nix is `import`-ed, not a plain module in `imports`) is SOUND — empirically reproduced the cycle the spec's design would hit; the worker's fix mirrors the hardening.nix precedent exactly and is the only constraint-compatible reading that evaluates. Pure-refactor proof reproduced byte-for-byte; all six hard-fail/laziness evals reproduced.

Per-item results (one line each):

1. **Scope — OK.** `git status --short` + `git diff HEAD --stat -- modules/ hosts/` shows exactly: `modules/things/loader.nix` (new, 80 ln), `modules/things/default.nix` (mod, +14/-2), `hosts/bnox-dev/configuration.nix` (mod, host-specific only), `hosts/bnox-dev/demo-thing/.bnox/{thing,web}.nix` (new). No edits to `user.nix`, `hardening.nix`, `shapes/*`, `runtimes/*`, `secrets/*`, `platform/*`, `base/*`, `profiles/*`, `hardware/*`, `lib/*`, `home/*`, `flake.nix`. (Unstaged `design/STATUS.md` + `design/memory/changelog.md` + untracked `design/jobs/08-bnox-loader.md` are design/ bookkeeping, outside `modules/`+`hosts/` scope and Nix-ignored — not flagged.)

2. **No comments / no descriptions — OK.** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/things/loader.nix modules/things/default.nix hosts/bnox-dev/` → exit 1 (no matches).

3. **Schema preservation — OK (byte-identical to Job 04/05).** `git diff HEAD -- modules/things/default.nix` shows ONLY the 6 expected wiring changes: (a) `let loader = import ./loader.nix { inherit lib; };` (default.nix:4); (b) `thingOptionsModule` gains `config` in args (default.nix:50, `{ name, config, ... }:`); (c) `components` type `attrsOf (submoduleWith { modules = [componentSubmodule loader.componentSubmodule]; specialArgs = { thingSource, thingName, thingEnable }; })` (default.nix:69-76); (d) `loader.topLevel` in `imports` (default.nix:136); (e) `loader.thingSubmodule` in thing submodule list (default.nix:144). Every `mkOption` declaration (type/default) for thing `enable`/`source`/`deps`/`secrets`/`components` and component `enable`/`shape`/`runtime`/`domain`/`ingressPort`/`natsSubject`/`secrets` is unchanged — same enums (`shape` 5 values default.nix:15-21; `runtime` 2 values :24-27), same defaults (`shape`/`source` still no-default :57-59,:14-22), `domain`/`ingressPort`/`natsSubject` still `nullOr … default null`. Validators (`depErrors`/`portCollisions`/`subjectCollisions` → `config.assertions`, default.nix:82-155) byte-identical — diff touches none of those lines.

4. **Pure-refactor proof — OK (byte-for-byte via `nix eval .#nixosConfigurations.bnox-dev.config.*`):**
   - container `demo-web`: `image="demo-web:current"`, `user="demo"`, `environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]`, `ports=["127.0.0.1:8080:8080"]`.
   - `services.caddy.virtualHosts."demo.local".extraConfig = "reverse_proxy 127.0.0.1:8080\n"`.
   - `bnox.secrets.fileSlots."demo/api_key" = { group="demo"; owner="demo"; restartUnits=["podman-demo-web"]; }`.
   - `systemd.services."podman-demo-web".serviceConfig`: `ProtectSystem="strict"`, `NoNewPrivileges="true"`, `ReadWritePaths="/var/lib/demo /var/lib/bnox/secrets/demo"`, `IPAddressDeny="any"`, `CapabilityBoundingSet=""` (all 19 hardening directives present).
   - `users.users.demo.home = "/var/lib/demo"`; `bnox.things.demo.components.web = { domain="demo.local"; enable=true; ingressPort=8080; natsSubject=null; runtime="container"; secrets=["api_key"]; shape="webapp"; }`; `bnox.things.demo.{deps=[],secrets=[]}`; `source` resolves to store path `/nix/store/nq08n8681hhypxa2fiz1z5yk3wsza386-source/hosts/bnox-dev/demo-thing`. `config.assertions` on bnox-dev = `[]` (clean). Matches Job 05/07 sign-off values exactly.

5. **Loader logic correctness — OK.** Read loader.nix end-to-end:
   - `thingSubmodule` (loader.nix:8-18): `manifest = if config.enable then readManifest config.source else {}` is lazy — `config.source` NOT forced when `enable=false` (Job-04 laziness contract preserved; confirmed by case6 below). `config = lib.mkIf config.enable { deps = mkDefault (manifest.deps or []); secrets = mkDefault (manifest.secrets or []); }` — mkDefault + `or []` fallback per spec.
   - `componentSubmodule` (loader.nix:20-39): `loadable = thingEnable && inManifest && hasFile` gates all writes; `comp = if hasFile then import compPath else {}` avoids import-error on absent file; `shape = mkDefault comp.shape` (NO `or null` — loader.nix:33, so a present-but-shapeless file surfaces the natural "attribute missing" error per spec line 99); `runtime`/`ingressPort`/`natsSubject`/`secrets` use `or "container"`/`or null`/`or null`/`or []` defaults per spec. Creates no component keys (host opt-in honored).
   - `topLevel` (loader.nix:41-76): iterates `filterAttrs (_: t: t.enable) config.bnox.things` only; writes ONLY `config.assertions` (never `bnox.things` — so iterating `config.bnox.things` here does not cycle, since the thing/component keys come from host declarations + per-instance submodule config, not from a top-level derived attrset). Three message formats match spec verbatim (loader.nix:59, 64, 66) — the not-in-manifest list renders via `builtins.toJSON manifestComponents` → e.g. `(["web"])`, an unambiguous literal rendering of the spec's `[<manifest list>]` placeholder (worker-documented choice, acceptable).

6. **Deviation SOUND (ruled explicitly).** (a) **Infinite-recursion claim CORRECT — empirically reproduced.** Wrote a minimal plain top-level module `{ lib, config, ... }: { config.bnox.things = lib.mapAttrs (_: t: lib.optionalAttrs t.enable { deps = lib.mkDefault …; }) config.bnox.things; }` and eval'd it: `error: infinite recursion encountered at modules.nix:1167`. Root cause as worker states: `types.attrsOf` merge is `zipAttrsWith` over every definition's keys (strict in keys); a loader definition whose keys come from `config.bnox.things` forces `attrNames config.bnox.things`, re-entering the merge being computed. Unavoidable for any top-level module that generates `bnox.things.<name>` keys from `config.bnox.things`. (b) **`import`-function-file pattern mirrors hardening.nix exactly**: hardening.nix is `{ lib }: { bundle, overrideModule }`; loader.nix is `{ lib }: { topLevel, thingSubmodule, componentSubmodule }` — same dual/return-attrset shape, same `let x = import ./x.nix { inherit lib; }; in …` consumer pattern in default.nix. Job-04 checker already approved this reading. (c) **`submoduleWith` + `specialArgs` is the correct/documented nixpkgs API** for passing parent thing context (`source`/`enable`) to nested component submodule instances — nested submodules are otherwise isolated from parent `config`, and `submoduleWith` is the only `attrsOf (submodule …)` variant that accepts `specialArgs`. (d) **Per-instance writes DO break the cycle**: in a submodule instance, `name` is supplied by the submodule system (the key in the parent attrsOf), NOT by iterating the merged attrset; per-instance `config` writes add values to existing keys, never new attrset keys, so the attrsOf key-collection is never re-entered. `topLevel` writing only `config.assertions` keeps it out of the `bnox.things` merge entirely. **Ruling: SOUND on all four sub-points; the deviation is forced and the fix is the canonical pattern.**

7. **Hard-fail assertion reproduction — OK (all 6 cases reproduced via throwaway `nixosSystem` x86_64-linux, `nixosModules.bnox` + stub fs/boot, `--impure` + `/var/folders/…/T/opencode/08-loader-check/` fixtures):**
   - **Missing `.bnox/`** (source=`/nonexistent/path`, no components): `[ "bnox: thing \"t\" is enabled but has no .bnox/thing.nix at \"/nonexistent/path/.bnox/\" (expected the thing-intrinsic manifest per Q9.5)" ]` — exact spec message.
   - **Component not in manifest** (manifest `["web"]`, host declares `components.api`, dummy `shape="daemon"` on api): `[ "bnox: host declares component \"api\" on thing \"t\", but \"api\" is not in the thing's .bnox manifest ([\"web\"])" ]` — names component + thing + manifest list.
   - **Component file missing** (manifest `["web","api"]`, no `api.nix`, host declares `components.api`, dummy shape): `[ "bnox: thing \"t\" manifest lists component \"api\" but \"…/case-missingfile/.bnox/api.nix\" is missing" ]` — names thing + missing file path.
   - **Host override escape hatch** (fixture `web.nix` shape=`"webapp"`, host plain-sets `components.web.shape="http-api"`): effective `shape="http-api"` (plain priority 100 > mkDefault 1000), `ingressPort=8080` (still from fixture), `config.assertions=[]` (no assertion fires). Confirms ungated mkDefault escape hatch per spec/Q14.
   - **Multi-component** (manifest `["web","api"]`, both files present): `web.{shape="webapp",ingressPort=8080}`, `api.{shape="http-api",ingressPort=9000,secrets=["db"]}`, `deps=["other"]` — both components populate correctly from their respective `.bnox/<c>.nix`; thing-level `deps` manifest merge confirmed.
   - **Disabled-thing laziness** (thing `disabled` with `enable=false`, NO `source`, one component): evaluates without error (`config.bnox.things.disabled.enable == false`); `config.source` never forced. Job-04 laziness contract preserved.
   - **Dummy-shape test-workaround assessment: LEGITIMATE.** Independently confirmed the worker's claim: WITHOUT a dummy `shape` on the synthetic error-case component, `nix eval … config.assertions` errors first with `error: The option \`bnox.things.t.components.api.shape' was accessed but has no value defined` (stack: podman → `oci-containers.containers` → `container.nix:24` filter `comp.shape != "static-site"` → forces `shape`). The loader's manifest/file-existence assertions are computed independently of `shape` (topLevel reads only `pathExists`/`attrNames`/manifest `components`, never `comp.shape`), so the dummy does not affect what is being verified — it only neutralizes an unrelated platform module's eager filter so `config.assertions` becomes readable. The spec's own validation method (`builtins.filter (a: !a.assertion) config.assertions`) presupposes inspectability, which the dummy provides. Not a loader defect; legitimate test isolation.

8. **Not-in-manifest / file-missing UX interaction — ACCEPTABLE (loud either way; no in-scope fix exists).** When a host declares a component that is not-in-manifest or whose file is missing, `loadable=false` → loader writes nothing → `shape` stays default-less → podman's eager filter forces `shape` → natural eval error `option \`bnox.things.t.components.api.shape' was accessed but has no value defined` surfaces BEFORE the loader's friendly assertion message is visible in a real `nixos-rebuild` (eval errors abort before build-time assertion checks). This is a REAL interaction but ACCEPTABLE for v1: (i) the misconfiguration is loud (eval error names the exact option path); (ii) the loader's assertion IS present in `config.assertions` (queryable, just not first-visible); (iii) the spec MANDATES data-only assertions (line 88: "do NOT `throw` at eval time") and EXPLICITLY accepts natural eval errors for shape (line 99: "let the Job-04 option's 'no default' surface the natural eval error"); (iv) no in-scope fix exists — `shape`'s enum type rejects `mkDefault null`/sentinel, and changing `container.nix`'s filter is out of Job-08 scope. **No NEEDS-FIX.** (Future UX improvement, if desired, belongs in a runtime-handler job making `container.nix`'s filter guard on `shape ? _` before forcing it — out of scope here.)

9. **Fixture git-tracked — OK.** `git ls-files hosts/bnox-dev/demo-thing/` → both `hosts/bnox-dev/demo-thing/.bnox/thing.nix` and `hosts/bnox-dev/demo-thing/.bnox/web.nix` tracked (staged `A`). Required for flake source copy; confirmed end-to-end (bnox-dev eval reads them via the store path).

10. **`nix flake check` + `nix flake show` — OK.** Flake check passes (only the benign cross-system warning `The check omitted these incompatible systems: x86_64-linux` + the unchanged `unknown flake output 'profiles'/'hardware'` notes — identical to Jobs 01-07). Flake show outputs unchanged: `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib` all present.

**Reproduced validation output:**

`nix flake check`:
```
warning: Git tree '/Users/bh/code/systems/bnox' is dirty
evaluating flake...
checking flake output 'lib'...
checking flake output 'nixosModules'...
checking NixOS module 'nixosModules.bnox'...
checking NixOS module 'nixosModules.bnox-base'...
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.bnox-dev'...
checking flake output 'profiles'...
warning: unknown flake output 'profiles'
checking flake output 'hardware'...
warning: unknown flake output 'hardware'
checking flake output 'packages'...
warning: The check omitted these incompatible systems: x86_64-linux
```

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───hardware: unknown
├───lib: unknown
├───nixosConfigurations
│   └───bnox-dev: NixOS configuration
├───nixosModules
│   ├───bnox: NixOS module
│   └───bnox-base: NixOS module
└───profiles: unknown
```

Cycle proof (plain top-level loader module writing `config.bnox.things` with keys from `config.bnox.things`):
```
error: infinite recursion encountered
       at /nix/store/…/source/lib/modules.nix:1167:7:
         1167|       value = addErrorContext "while evaluating the option `${showOption loc}':" value;
```

Key bnox-dev evals (pure-refactor proof):
```
demo-web container: image="demo-web:current" user="demo"
  environmentFiles=["/var/lib/bnox/secrets/demo/api_key"] ports=["127.0.0.1:8080:8080"]
caddy "demo.local".extraConfig = "reverse_proxy 127.0.0.1:8080\n"
fileSlots."demo/api_key" = { group="demo"; owner="demo"; restartUnits=["podman-demo-web"] }
podman-demo-web.serviceConfig: ProtectSystem="strict" NoNewPrivileges="true"
  ReadWritePaths="/var/lib/demo /var/lib/bnox/secrets/demo" IPAddressDeny="any" CapabilityBoundingSet=""
users.users.demo.home = "/var/lib/demo"
bnox.things.demo.components.web = { domain="demo.local"; enable=true; ingressPort=8080;
  natsSubject=null; runtime="container"; secrets=["api_key"]; shape="webapp" }
bnox.things.demo.source = "/nix/store/nq08n8681hhypxa2fiz1z5yk3wsza386-source/hosts/bnox-dev/demo-thing"
config.assertions = []
```

Throwaway eval assertions (6 cases — see item 7 for full messages; all reproduce worker output exactly).

No NEEDS-FIX issues. Approved.

## Sign-off
Approved 2026-07-29 — independent checker (`general` sub-agent), iteration 1, verdict **PASS** (all 10 items OK; the `import`-function-file deviation ruled SOUND — checker empirically reproduced the `infinite recursion` the spec's plain-top-level-module design hits; pure-refactor proof byte-for-byte vs Job 05/07; all six hard-fail/laziness evals reproduced; `nix flake check` + `nix flake show` reproduced). The not-in-manifest/file-missing UX interaction (podman's eager filter surfaces a "shape has no value" eval error before the loader's friendly assertion) ruled ACCEPTABLE — loud either way, spec-mandated (data-only assertions + shape-no-default), no in-scope fix.
