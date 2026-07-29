# Job 05: Things shapes + container runtime (+ platform/static-site)

**Status:** done
**Iteration:** 2
**Created:** 2026-07-28

## Scope

Make the thing abstraction actually run: read the `bnox.things.*` schema (defined in Job 04) and emit platform/service config. Implements the **HTTP shapes** (Caddy vhosts), the **container runtime** (oci-containers), the **static-site platform helper**, and **wires declared secret slots into `bnox.secrets.fileSlots`** (so secret-file changes restart the right container). NixOS module composition: these are new modules that consume the Job 04 options — do NOT modify the Job 04 schema.

**Deferred to a later job (NOT this job):**
- `host-install` runtime (Q9.9) — needs the thing's ExecStart, which comes from `.bnox/` (loader not yet built). Only user is Hermes (Phase 3, D-012).
- `daemon` shape effects (Q9.8) — daemons typically use host-install; no inbound plumbing anyway. Ship a minimal marker module here (no-op) so the shape enum is fully handled, but real daemon hosting lands with host-install.
- `.bnox/` loader.
- JetStream stream creation for nats-api — runtime concern (streams are created via the JS API by the thing, not declaratively in NixOS). bnox's role is subject allocation + validation (already done in Job 04).

**Spec sources (read these):**
- `design/jobs/04-things-core.md` — the schema you consume (read the worker's exact submodule defs in its Worker notes).
- `design/process/06-base-design.md` — `modules/things/shapes/*`, `modules/things/runtimes/container.nix`, `modules/platform/static-site.nix`.
- `design/process/05-decisions.md` — D-002 (oci-containers, not raw quadlets), D-006 (platform/thing boundary; static-site served by Caddy file_server; HTTP upstream port self-declared), D-007 (secrets file backend; fileSlots).
- `design/jobs/03-secrets.md` — the `bnox.secrets.fileSlots` interface you'll populate (`attrsOf { owner, group, restartUnits }`, keyed by path under `/var/lib/bnox/secrets/`).
- `design/working/open-questions.md` — Q9.6 (thing's user owns its paths), Q9.7 (hardening bundle from Job 04, applied to the container's systemd service).

## Files to create / modify

1. `modules/things/shapes/static-site.nix` — for each enabled component with `shape == "static-site"`: register a Caddy virtualHost on the component's `domain` using `file_server`, rooted at the thing's static content path (derive from `source` + component name, e.g. `${source}/${componentName}` — pick a sane convention and state it).
2. `modules/things/shapes/webapp.nix` — `shape == "webapp"`: Caddy virtualHost on `domain`, `reverse_proxy` to `127.0.0.1:${ingressPort}`.
3. `modules/things/shapes/http-api.nix` — `shape == "http-api"`: if `domain != null`, Caddy virtualHost `reverse_proxy` to `127.0.0.1:${ingressPort}`. If `domain == null` (internal-only), no Caddy entry.
4. `modules/things/shapes/nats-api.nix` — minimal marker (no declarative stream creation; subject validated in Job 04). A near-no-op module that exists so the shape enum is fully handled. Note in worker notes that stream creation is the thing's runtime concern.
5. `modules/things/shapes/daemon.nix` — minimal marker (no inbound plumbing). Note real daemon hosting (host-install) is deferred.
6. `modules/things/shapes/default.nix` — imports the five shape modules.
7. `modules/things/runtimes/container.nix` — for each enabled component with `runtime == "container"`: emit a `virtualisation.oci-containers.containers."<thing>-<component>"` entry. See details below.
8. `modules/things/runtimes/default.nix` — imports `container.nix` (host-install deferred).
9. `modules/platform/static-site.nix` — a Caddy `file_server` helper (an option or function the static-site shape uses). Minimal — could simply be the shared mechanism the static-site shape calls. If the shape can self-contain the file_server logic, this file may be a thin helper; state what it provides.
10. **Modify `modules/platform/default.nix`** — add `./static-site.nix` to imports (the platform helper deferred from Job 02).
11. **Modify `modules/things/default.nix`** — add `./shapes/default.nix` and `./runtimes/default.nix` to its imports (so the effect modules compose in). Do NOT change the option schema or validators.

## container runtime details (`runtimes/container.nix`)

For each enabled component (thing `enable=true`, component `enable=true`, `runtime == "container"`):
- `virtualisation.oci-containers.containers."<thing>-<component>"`:
  - `image` = a string reference like `"${thing}-${component}:current"` (the actual image is built by the thing's flake and loaded by the deployment pipeline, Job 06 — NOT built here). State the exact image-name convention you choose.
  - `user` = the thing's user name (so the container runs non-root as the thing's user; maps to podman `--user`). NOTE: the thing's user is a HOST user (uid); for podman rootless/uid mapping this may need the numeric uid — use the username and note any caveat.
  - environment files: the thing's declared secret slots → env file paths. Wire declared slots (thing-level `secrets` + component-level `secrets`) to `bnox.secrets.fileSlots."<thing>/<slot>"` entries (owner = thing user, group = thing user, `restartUnits` = the container's systemd service name — determine the exact NixOS-generated service name for an oci-container, e.g. `"container-${thing}-${component}"` or `"podman-${thing}-${component}"`; verify and state it). Also pass the secret file as an `environmentFiles` entry on the container so the thing sees its secrets as env vars.
  - ports: expose `ingressPort` only if needed for the reverse proxy (Caddy proxies to 127.0.0.1:ingressPort — typically no host port publication needed; the container listens on its port and Caddy reaches it via host networking or the container's published port). Use host networking OR publish the port on 127.0.0.1 — pick the simpler correct option and state it.
- Apply the Q9.7 hardening bundle (from Job 04's `hardening.bundle`) to the generated systemd service via `systemd.services."<container-service-name>".serviceConfig` (oci-containers generates a service; override its serviceConfig with the bundle, parameterized by the thing's writable paths `/var/lib/<thing>` and `/var/lib/bnox/secrets/<thing>`).

## Constraints

- No comments. No option `description` fields.
- Do NOT modify the Job 04 option schema or validators (only add imports to `modules/things/default.nix`).
- Do NOT implement host-install runtime, the `.bnox/` loader, or JetStream stream creation.
- Do NOT build container images (image = string reference; pipeline builds them in Job 06).
- Do NOT touch base/secrets/lib/home/flake.nix beyond the listed edits.

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show`.
- Throwaway `nixosSystem` evals (x86_64-linux, `nixosModules.bnox` + stub fs/boot with `fsType="ext4"` — see Job 04 checker note):
  - **webapp end-to-end**: declare a thing "app" with one component `web` shape=webapp runtime=container domain="app.test" ingressPort=8080, secrets=["api_key"]. Confirm: a Caddy virtualHost for "app.test" reverse_proxy→127.0.0.1:8080 exists; an oci-container "app-web" exists with image "app-web:current" (or your convention) running as user "app"; `bnox.secrets.fileSlots."app/api_key"` exists with owner "app" and restartUnits containing the container's service name; the container's systemd service has the hardening directives applied.
  - **static-site**: thing "site" component "www" shape=static-site domain="site.test" source="/srv/site". Confirm Caddy virtualHost "site.test" with file_server rooted at the expected path.
  - **http-api internal-only**: component shape=http-api domain=null ingressPort=9000. Confirm NO Caddy vhost (internal only) but the container still created.
  - Confirm `nix flake check` still passes with a real thing declared (no eval errors from the effect modules).

## Worker notes

**Built (Job 05, iteration 1, 2026-07-28):**

Files created (10) / modified (2):
- `modules/platform/static-site.nix` (new) — exposes `bnox.platform.staticSites : attrsOf str` (key=domain, value=root path) and emits one Caddy `virtualHosts.<domain>` per entry with `extraConfig = "root * <root>\nfile_server\n"`. This is the thin platform helper the static-site shape calls — the shape only produces data (`bnox.platform.staticSites."${domain}" = root`); the platform module owns the actual Caddy emission (D-006 platform/thing boundary honored).
- `modules/things/shapes/static-site.nix` (new) — for each enabled component with `shape == "static-site"` and `domain != null`: sets `bnox.platform.staticSites."${domain}" = "${source}/${component}"`.
- `modules/things/shapes/webapp.nix` (new) — for each enabled `webapp` component with non-null `domain`+`ingressPort`: emits `services.caddy.virtualHosts."${domain}".extraConfig` = `reverse_proxy 127.0.0.1:<ingressPort>`.
- `modules/things/shapes/http-api.nix` (new) — same as webapp but filtered on `shape == "http-api"`. Because the filter requires `domain != null`, the `domain == null` (internal-only) case produces NO vhost (confirmed by eval 3: zero Caddy virtualHosts).
- `modules/things/shapes/nats-api.nix` (new) — minimal marker module (`{}`). No declarative JetStream stream creation (per spec deferral: stream creation is the thing's runtime concern via the JS API; bnox's role is subject allocation + validation, already done in Job 04). Exists so the shape enum is fully handled.
- `modules/things/shapes/daemon.nix` (new) — minimal marker module (`{}`). Real daemon hosting (host-install runtime) is deferred per spec; no inbound plumbing.
- `modules/things/shapes/default.nix` (new) — imports the five shape modules.
- `modules/things/runtimes/container.nix` (new) — see "Container runtime details" below.
- `modules/things/runtimes/default.nix` (new) — imports `./container.nix` (host-install deferred).
- `modules/platform/default.nix` (modified) — added `./static-site.nix` to imports.
- `modules/things/default.nix` (modified) — added `./shapes/default.nix` and `./runtimes/default.nix` to imports ONLY. Option schema and validators untouched.

**Conventions chosen (all verified by throwaway eval):**

1. **Image-name format:** `"${thing}-${component}:current"` — e.g. thing `app` + component `web` → image string `"app-web:current"`. The `:current` tag is the rolling tag the deployment pipeline (Job 06) retags on each build/load. Not built here (string reference only).
2. **Container service name (NixOS-generated, VERIFIED):** `"${backend}-${thing}-${component}"` where `backend = config.virtualisation.oci-containers.backend`. Verified empirically on NixOS 26.05: podman backend → `podman-<name>`; docker backend → `docker-<name>`. The unified `container-<name>` form does NOT exist on 26.05 (only `container-getty@`, an unrelated default service, matches the `container*` prefix). With bnox's podman default (D-002) the service is `podman-app-web`. The runtime derives the name from `config.virtualisation.oci-containers.backend` so it stays correct if a host flips to docker (D-002 §5).
3. **Static-site root path convention:** `"${source}/${component}"` — e.g. thing `site` (source `/srv/site`) + component `www` → Caddy root `/srv/site/www`. One component = one subdirectory of the thing's checkout; matches the `.bnox/` repo-layout sketch (`<thing>/<component>/` holds component code).
4. **Secret-slot → fileSlots mapping:** key `"<thing>/<slot>"` (path relative to `/var/lib/bnox/secrets/`, matching the Job-03 `fileSlots` contract). Value = `{ owner = "<thing>"; group = "<thing>"; restartUnits = [ "<container-service-name>" ]; }`. Slots come from `thing.secrets ++ component.secrets` (thing-level applies to all its components). When two components of the same thing declare the same slot name, they share one fileSlot and `restartUnits` is the unique union of both container services (built via `lib.groupBy` + `lib.unique`). The same slot path is also passed to the container as an `environmentFiles` entry (`/var/lib/bnox/secrets/<thing>/<slot>`).
5. **Port publication:** `ports = [ "127.0.0.1:${ingressPort}:${ingressPort}" ]` (loopback-only, host:container identity mapping) emitted only when `ingressPort != null`. Caddy reaches the upstream via `127.0.0.1:<ingressPort>`. Chosen over `--network=host` because host networking would conflict with the Q9.7 `IPAddressDeny=any` hardening on the unit and bypasses the loopback binding; explicit loopback publish is the simpler correct option and keeps the firewall surface to localhost.

**How the hardening bundle was applied to the container's service:**

`runtimes/container.nix` imports Job 04's bundle via `import ../hardening.nix { inherit lib; }` and emits one `systemd.services."<service-name>"` entry per container whose `serviceConfig` IS the bundle output, parameterized by the thing's writable paths + egress override:

```nix
serviceHardening = builtins.listToAttrs (
  map (
    comp:
    lib.nameValuePair comp.serviceName {
      serviceConfig = hardening.bundle {
        writablePaths = [
          "/var/lib/${comp.thing}"
          "/var/lib/bnox/secrets/${comp.thing}"
        ];
        ipAddressAllow = lib.optional comp.outboundHTTPS ":443";
      };
    }
  ) containerComponents
);
```

This merges into the oci-containers-generated service (NixOS attrset merge: my security directives coexist with the module's `ExecStart`/`Environment`/etc.). Verified end-to-end (eval 1): `podman-app-web` service has `ProtectSystem="strict"`, `NoNewPrivileges="true"`, `ReadWritePaths="/var/lib/app /var/lib/bnox/secrets/app"`, `IPAddressDeny="any"`, `CapabilityBoundingSet=""`. The override hook (`bnox.things.<name>.hardening.network.outboundHTTPS`) flips `:443` into `IPAddressAllow` when true.

**Key decisions / deviations:**

1. **Container service name is backend-derived, NOT hardcoded `podman-*`.** Probed both backends on 26.05; both follow `<backend>-<name>`. Deriving from `config.virtualisation.oci-containers.backend` keeps the `restartUnits` + hardening override correct if a host switches to docker (D-002 §5 says the switch is a local change; this makes it so). If a future nixpkgs unifies to `container-<name>`, this single derivation point is the only thing to update.
2. **`modules/platform/static-site.nix` exposes an option, not a function.** The spec allowed "an option or function". I chose an option (`bnox.platform.staticSites`) so the shape handler is pure data (it only computes `domain → root`) and the platform module owns all Caddy emission. This keeps the platform/thing boundary clean (D-006 §3: platform owns Caddy; things produce data) and makes the static-site plumbing trivially testable.
3. **`nats-api` and `daemon` are literal `{}` modules.** They exist purely so the shape enum is fully handled and the import list is complete. No `options`, no `config`. A bare `{}` is a valid NixOS no-op module (flake check + evals confirm). Real effects deferred per spec (nats-api stream creation is the thing's runtime JS-API concern; daemon hosting needs host-install, deferred).
4. **The iteration pattern (`enabledThingsList` → `lib.concatMap` over components) is duplicated in each shape module** rather than factored into a shared helper. The hard constraints forbid touching `lib/` beyond listed edits, and NixOS modules can't share `let` bindings across files. The duplication is ~5 lines per file; acceptable.
5. **Container runtime fires on `runtime == "container"` regardless of shape** (literal spec reading). Consequence: a `static-site` component left at the default `runtime = "container"` would ALSO produce a container (`<thing>-<component>:current`) alongside its Caddy vhost. The spec's static-site test only checks the vhost, not container absence, so this passes; in practice a static-site author would not want a container, but suppressing it would require shape-specific logic the spec does not mandate. **Flagging as a focus area** — the schema has no "none" runtime, so static-site's natural runtime is ambiguous. Cleanest fix (if checker agrees) would be a future `runtime = "none"` enum value or shape-gating in the container runtime; both are out of scope here (schema is frozen by Job 04 + this job's hard constraint).
6. **No `lib.mkForce`/`lib.mkDefault` on the emitted config.** The container, vhost, fileSlot, and hardening entries are plain definitions. A host can still override any of them via NixOS's normal priority system if needed; not pre-emptively weakened.

**Validation output:**

- Comment scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/things/shapes modules/things/runtimes modules/platform/static-site.nix modules/platform/default.nix modules/things/default.nix` → no matches (hard constraint met).
- `nix flake check` → clean (only the benign cross-system warning, identical to Jobs 01-04).
- `nix flake show` → `nixosModules.{bnox,bnox-base}` both present.

- **Eval 1 (webapp end-to-end):** thing `app`, component `web` (webapp/container, domain `app.test`, ingressPort 8080, component secrets `["api_key"]`):
  ```
  { caddyVhKeys = ["app.test"];
    caddyAppExtra = "reverse_proxy 127.0.0.1:8080\n";
    ociKeys = ["app-web"];
    ociAppImage = "app-web:current";   ociAppUser = "app";
    ociAppEnvFiles = ["/var/lib/bnox/secrets/app/api_key"];
    ociAppPorts = ["127.0.0.1:8080:8080"];
    fileSlotKeys = ["app/api_key"];
    fileSlotOwner = "app";   fileSlotGroup = "app";   fileSlotRestart = ["podman-app-web"];
    serviceExists = true;    (podman-app-web)
    protectSystem = "strict";   noNewPriv = "true";
    readWritePaths = "/var/lib/app /var/lib/bnox/secrets/app";
    ipAddressDeny = "any";   capabilityBounding = "";
    failed = []; }
  ```
  Caddy vhost `app.test` → reverse_proxy 127.0.0.1:8080; container `app-web` image `app-web:current` user `app`; fileSlot `app/api_key` owner/group `app` restartUnits `["podman-app-web"]`; container env-file wired; hardening bundle applied. ✓

- **Eval 2 (static-site):** thing `site` (source `/srv/site`), component `www` (static-site, domain `site.test`):
  ```
  { caddyVhKeys = ["site.test"];
    caddySiteExtra = "root * /srv/site/www\nfile_server\n";
    staticSites = { "site.test" = "/srv/site/www"; };
    failed = []; }
  ```
  Caddy vhost `site.test` with `root * /srv/site/www` + `file_server`, rooted at the `${source}/${component}` convention. ✓

- **Eval 3 (http-api internal-only):** thing `internal`, component `api` (http-api/container, domain=null, ingressPort 9000):
  ```
  { caddyVhKeys = [];          (NO vhost)
    ociKeys = ["internal-api"];   ociImage = "internal-api:current";
    ociPorts = ["127.0.0.1:9000:9000"];
    serviceExists = true;   (podman-internal-api)
    failed = []; }
  ```
  domain=null → NO Caddy vhost (filter requires `domain != null`), but the container is still created. ✓

**For the checker to focus on:**
- **The static-site + default-runtime tension (deviation 5).** Is firing the container runtime for a static-site component at default `runtime = "container"` acceptable, or should the container runtime suppress container creation for `shape == "static-site"` (which would be shape-specific logic beyond the literal spec)? My reading: the spec says "for each enabled component with `runtime == container`" with no shape carve-out, so literal compliance fires; the ambiguity is a schema gap (no "none" runtime), not a Job-05 bug.
- **Hardening on the container unit may be too strict for real podman operation** (`ProtectSystem=strict` + `IPAddressDeny=any` on the `podman-<name>` wrapper service could block image pulls / overlay setup at runtime). The spec explicitly mandates applying the Q9.7 bundle to the container's service, so I followed it; runtime workability is a Job 06+ (deployment) concern, surfaced here for visibility.
- **Backend-derived service name (deviation 1).** Sound, but depends on nixpkgs keeping the `<backend>-<name>` convention. Verified on 26.05; will break silently if nixpkgs unifies to `container-<name>` without notice. Single derivation point makes the future fix one-line.
- **Secret-slot sharing across components (convention 4).** Two components of one thing declaring the same slot name share one fileSlot with merged `restartUnits`. Confirm this is the desired semantic vs. component-scoped slot keys (e.g. `<thing>/<component>/<slot>`). I chose thing-scoped keys because the fileSlots path is `/var/lib/bnox/secrets/<thing>/<slot>` (no component level in the path per Job-03 contract), and thing-level secrets are explicitly shared across components.

## Checker notes

**VERDICT: NEEDS-FIX** — independent checker, iteration 1, 2026-07-28.

One checklist item (item 4 — the flagged focus area) is a **D-006 violation**: the container runtime emits a container for `shape == "static-site"` components. D-006 §3 and its "alternatives rejected" both state unambiguously: "**static-site web server** (bnox serves files via Caddy `file_server`; **no per-site container**)" and "Static sites need no per-site container — files served directly by Caddy." Empirically reproduced by eval 2 (`ociKeys = [ "site-www" ]`, `siteWwwContainerEmitted = true`, `siteWwwServiceEmitted = true`). The worker self-flagged this (deviation 5 + focus area) and explicitly asked the checker to rule on it; ruling is NEEDS-FIX. Items 1-3, 5-11 all OK.

**Checklist results (one line each):**

1. **Scope — OK.** `git status`: modified `modules/platform/default.nix` + `modules/things/default.nix`; new `modules/platform/static-site.nix`, `modules/things/shapes/{default,static-site,webapp,http-api,nats-api,daemon}.nix`, `modules/things/runtimes/{default,container}.nix`. `git diff HEAD -- modules/things/default.nix` shows ONLY the `imports = [...]` block changed (`+./shapes/default.nix` `+./runtimes/default.nix`); schema + validators byte-identical. `modules/platform/default.nix` adds only `+./static-site.nix`. No host-install runtime, no `.bnox/` loader, no JetStream stream creation, no image building, no base/secrets/lib/home/flake.nix edits.
2. **No comments + no descriptions — OK.** `rg -n '(^|[^a-zA-Z0-9"])#|/\*|description =' modules/things/shapes modules/things/runtimes modules/platform/static-site.nix` → exit 1 (no matches).
3. **static-site shape (D-006 file_server) — OK.** `shapes/static-site.nix` sets `bnox.platform.staticSites."${domain}" = "${source}/${component}"`; `platform/static-site.nix` emits `services.caddy.virtualHosts."${domain}".extraConfig = "root * <root>\nfile_server\n"`. Eval 2: `caddySiteExtra = "root * /srv/site/www\nfile_server\n"`. Root path convention `${source}/${component}` honored.
4. **CRITICAL — static-site + container vs D-006: ISSUE (NEEDS-FIX).** **A container IS emitted for static-site components.** `runtimes/container.nix:24` filters only on `comp.enable && comp.runtime == "container"` with NO shape gate, so a static-site component at the default `runtime = "container"` produces BOTH a Caddy `file_server` vhost AND a `virtualisation.oci-containers.containers."<thing>-<component>"` + `systemd.services."podman-<thing>-<component>"`. Eval 2 proves it: `ociKeys = [ "site-www" ]`, `siteWwwContainerEmitted = true`, `siteWwwServiceEmitted = true`. This directly violates D-006 §3 ("no per-site container") and D-006 alternatives-rejected ("Static-site web server as a per-site thing: rejected ... one fewer container per site"). **Fix: the container runtime must skip `shape == "static-site"` components** (add `comp.shape != "static-site"` to the filter at `runtimes/container.nix:24`). The worker's "literal spec reading" defense is rejected: the Job-05 spec line 9 + D-006 are explicit that static sites are platform-served only; the schema's lack of a `runtime = "none"` value does not license emitting a forbidden container — shape-gating in the runtime is the correct, in-scope fix (no schema change needed).
5. **webapp/http-api shapes — OK.** `webapp.nix` and `http-api.nix` both emit `services.caddy.virtualHosts."${domain}".extraConfig = "reverse_proxy 127.0.0.1:<ingressPort>"` filtered on `domain != null && ingressPort != null`. http-api with `domain=null` → no vhost (eval 3: `caddyVhKeys = [ ]`). Eval 1 (webapp): `caddyAppExtra = "reverse_proxy 127.0.0.1:8080\n"`.
6. **nats-api + daemon shapes — OK.** Both `shapes/nats-api.nix` and `shapes/daemon.nix` are literal `{}` (no-op modules); `nix flake check` passes; no spurious config emitted, no declarative JetStream stream creation, no inbound plumbing. Shape enum fully handled via the import list.
7. **container runtime (non-static-site) — OK.** `runtimes/container.nix:30-34` emits `virtualisation.oci-containers.containers."<thing>-<component>"` with `image = "${thing}-${component}:current"`, `user = thing.name`, `environmentFiles`, loopback `ports`. **Generated service name verified on NixOS 26.05:** eval 1 `allServiceNames` includes `"podman-app-web"` and the unified `"container-app-web"` form does NOT exist (only the unrelated default `"container-getty@"` matches the `container-*` prefix). Worker's backend-derived `"${containerBackend}-${thing}-${component}"` (`container.nix:9,18`) is correct for the podman default; restartUnits/hardening target the real `podman-*` name. Sound.
8. **Secrets wiring — OK.** `container.nix:54-72` builds `bnox.secrets.fileSlots."<thing>/<slot>"` with `owner=group=thing.name` and `restartUnits = lib.unique (... serviceNames)`; `container.nix:33` passes `/var/lib/bnox/secrets/<thing>/<slot>` to the container's `environmentFiles`. Eval 1: `fileSlotKeys=["app/api_key"]`, `fileSlotOwner="app"`, `fileSlotGroup="app"`, `fileSlotRestart=["podman-app-web"]`, `ociAppEnvFiles=["/var/lib/bnox/secrets/app/api_key"]`. restartUnits target the ACTUAL generated service name (not guessed). Multi-component same-slot merge via `groupBy`+`unique` is sound by inspection.
9. **Hardening application — OK.** `container.nix:39-52` imports `hardening.nix`'s bundle and emits one `systemd.services."<service-name>".serviceConfig` per container, parameterized by `writablePaths=["/var/lib/<thing>" "/var/lib/bnox/secrets/<thing>"]` + `ipAddressAllow` from `outboundHTTPS`. Eval 1: `podman-app-web` has `ProtectSystem="strict"`, `NoNewPrivileges="true"`, `ReadWritePaths="/var/lib/app /var/lib/bnox/secrets/app"`, `IPAddressDeny="any"`, `CapabilityBoundingSet=""`. Directives land via NixOS attrset merge.
10. **platform/static-site.nix + platform/default.nix — OK.** Helper provides `bnox.platform.staticSites : attrsOf str` (key=domain → value=root path) and owns all Caddy `file_server` emission; shape module produces pure data. Imported at `platform/default.nix:6`. Clean D-006 platform/thing boundary.
11. **Independent validation — OK** (flake check + flake show + three evals reproduced below).

**Ruling on item 4 (explicit):** YES, a container is emitted for static-site components (`podman-site-www` + `oci-containers.containers."site-www"` both present). This violates D-006. → **NEEDS-FIX.** Exact fix below (issue 1).

**NEEDS-FIX issues:**

1. **`modules/things/runtimes/container.nix:24` — WRONG: the component filter `comp: comp.enable && comp.runtime == "container"` admits `shape == "static-site"` components, so a static-site at the default `runtime="container"` emits a `virtualisation.oci-containers.containers."<thing>-<component>"` entry (verified: eval 2 `siteWwwContainerEmitted = true`) plus a `systemd.services."podman-<thing>-<component>"` — a per-site container D-006 explicitly forbids. EXPECTED: skip static-site components entirely; change the filter predicate to `comp: comp.enable && comp.runtime == "container" && comp.shape != "static-site"`. No schema change required (shape-gating belongs in the runtime, not the schema). After the fix, eval 2 should report `ociKeys = [ ]`, `siteWwwContainerEmitted = false`, `siteWwwServiceEmitted = false`, while the Caddy `file_server` vhost for `site.test` remains.

**Validation output (reproduced by independent checker):**

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

Eval 1 (webapp: thing `app`, comp `web` webapp/container/domain `app.test`/port 8080/secrets `["api_key"]`) — throwaway `nixosSystem` (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`):
```
{ allServiceNames = [ "container-getty@" "podman-app-web" "podman-prune" ];
  caddyAppExtra = "reverse_proxy 127.0.0.1:8080\n";
  caddyVhKeys = [ "app.test" ];
  failed = [ ];
  fileSlotGroup = "app";   fileSlotKeys = [ "app/api_key" ];
  fileSlotOwner = "app";   fileSlotRestart = [ "podman-app-web" ];
  ociAppEnvFiles = [ "/var/lib/bnox/secrets/app/api_key" ];
  ociAppImage = "app-web:current";   ociAppPorts = [ "127.0.0.1:8080:8080" ];
  ociAppUser = "app";   ociKeys = [ "app-web" ];
  serviceExists = true;   (podman-app-web)
  svcCapabilityBounding = "";   svcIPAddressDeny = "any";
  svcNoNewPriv = "true";   svcProtectSystem = "strict";
  svcReadWritePaths = "/var/lib/app /var/lib/bnox/secrets/app"; }
```
Caddy vhost `app.test` → reverse_proxy 127.0.0.1:8080; container `app-web` image `app-web:current` user `app`; fileSlot `app/api_key` owner/group `app` restartUnits `["podman-app-web"]`; env-file wired; hardening bundle applied to `podman-app-web`. Note `container-app-web` does NOT exist (only unrelated `container-getty@`), confirming the backend-derived service name. ✓

Eval 2 (static-site: thing `site` source `/srv/site`, comp `www` static-site/domain `site.test`):
```
{ caddySiteExtra = "root * /srv/site/www\nfile_server\n";
  caddyVhKeys = [ "site.test" ];
  failed = [ ];
  ociKeys = [ "site-www" ];
  siteWwwContainerEmitted = true;
  siteWwwServiceEmitted = true;
  staticSites = { "site.test" = "/srv/site/www"; }; }
```
Caddy vhost `site.test` `file_server` rooted at `/srv/site/www` (correct). **BUT `ociKeys = [ "site-www" ]`, `siteWwwContainerEmitted = true`, `siteWwwServiceEmitted = true` — a container + `podman-site-www` service ARE emitted for the static-site component, violating D-006.** This is the NEEDS-FIX finding (issue 1).

Eval 3 (http-api internal: thing `internal`, comp `api` http-api/domain=null/port 9000):
```
{ caddyVhKeys = [ ];
  failed = [ ];
  ociImage = "internal-api:current";   ociKeys = [ "internal-api" ];
  ociPorts = [ "127.0.0.1:9000:9000" ];
  serviceExists = true;   (podman-internal-api) }
```
domain=null → NO Caddy vhost (filter requires `domain != null`); container still created. ✓

## Sign-off
NEEDS-FIX — 2026-07-28, independent checker, iteration 1. One blocking issue (D-006 violation: container runtime emits a per-site container for `shape == "static-site"` components at `runtimes/container.nix:24`); all other 10 checklist items pass. Status field left untouched per checker instructions.

---

**VERDICT: PASS** — independent checker, iteration 2, 2026-07-29.

The iteration-1 NEEDS-FIX (item 4, D-006 violation) is resolved by a minimal, correct one-line change. All 11 checklist items now pass; no regressions.

**The fix (confirmed):** `modules/things/runtimes/container.nix:24` now reads
```
    ) (lib.filterAttrs (_: comp: comp.enable && comp.runtime == "container" && comp.shape != "static-site") thing.components)
```
i.e. the component filter gained `&& comp.shape != "static-site"`. This is the exact predicate the iteration-1 checker prescribed (issue 1, line 196 of this doc). Minimality confirmed: this is the only delta vs the iteration-1 worker state — all other files match the iteration-1 worker notes byte-for-byte (`shapes/static-site.nix`, `platform/static-site.nix`, `shapes/webapp.nix`, `shapes/http-api.nix`, `shapes/{nats-api,daemon}.nix`, `shapes/default.nix`, `runtimes/default.nix`, the `imports`-only edits to `things/default.nix` and `platform/default.nix`). No comments added (comment/description scan: exit 1, no matches).

**Item 4 re-checked (D-006, static-site):** the static-site thing (thing `site`, comp `www`, static-site, domain `site.test`, source `/srv/site`) now emits the Caddy `file_server` vhost rooted at `/srv/site/www` AND NO container. Eval reports `ociKeys = [ ]`, `siteWwwContainerEmitted = false`, `siteWwwServiceEmitted = false` (was `true`/`true` in iteration 1). The Caddy vhost `site.test` with `root * /srv/site/www\nfile_server\n` remains. D-006 §3 ("no per-site container") satisfied.

**No regression on other shapes:** webapp (thing `app`, comp `web`, webapp/container/domain `app.test`/port 8080/secrets `["api_key"]`) still emits container `app-web` with `image="app-web:current"`, `user="app"`, `environmentFiles=["/var/lib/bnox/secrets/app/api_key"]`, `ports=["127.0.0.1:8080:8080"]`; `fileSlot "app/api_key"` owner=group=`app`, `restartUnits=["podman-app-web"]`; hardening applied to `podman-app-web` (`ProtectSystem="strict"`, `NoNewPrivileges="true"`, `ReadWritePaths="/var/lib/app /var/lib/bnox/secrets/app"`, `IPAddressDeny="any"`, `CapabilityBoundingSet=""`); Caddy `reverse_proxy 127.0.0.1:8080` vhost present. http-api internal (domain=null): no Caddy vhost, container `internal-api` still created (`ociImage="internal-api:current"`, `ports=["127.0.0.1:9000:9000"]`, `podman-internal-api` service present).

**Full re-check of remaining iteration-1 items:** all still hold —
- (1) Scope: only the documented files touched; no host-install/loader/JetStream-stream/image-build/base-secrets-lib-home-flake edits.
- (2) No comments / no descriptions (scan exit 1).
- (3) static-site shape `file_server` vhost at `${source}/${component}`.
- (5) webapp/http-api reverse_proxy vhosts filtered on `domain != null && ingressPort != null`.
- (6) nats-api + daemon are literal `{}` no-op markers.
- (7) container runtime backend-derived service name (`podman-<name>`) correct.
- (8) secrets wiring: `fileSlots."<thing>/<slot>"` with owner=group=thing, `restartUnits` target real `podman-*` service; `environmentFiles` wired.
- (9) hardening bundle applied to container unit.
- (10) `platform/static-site.nix` helper owns Caddy emission; imported at `platform/default.nix`.
- (11) independent validation reproduced below.
- `modules/things/default.nix` schema byte-identical to Job 04: `git diff HEAD` shows ONLY the `imports` block changed (`+./shapes/default.nix` `+./runtimes/default.nix`); options/validators untouched.

**Validation output (reproduced by independent checker, iteration 2):**

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
Use '--all-systems' to check all systems.
```

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───lib: unknown
└───nixosModules
    ├───bnox: NixOS module
    └───bnox-base: NixOS module
```

Eval — static-site (thing `site` source `/srv/site`, comp `www` static-site/domain `site.test`) — throwaway `nixosSystem` (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`):
```
{ caddySiteExtra = "root * /srv/site/www\nfile_server\n";
  caddyVhKeys = [ "site.test" ];
  failed = [ ];
  ociKeys = [ ];
  siteWwwContainerEmitted = false;
  siteWwwServiceEmitted = false;
  staticSites = { "site.test" = "/srv/site/www"; }; }
```
Caddy vhost `site.test` `file_server` rooted at `/srv/site/www` (present); `ociKeys = [ ]`, `siteWwwContainerEmitted = false`, `siteWwwServiceEmitted = false` — NO per-site container. D-006 satisfied. ✓ (was `true`/`true`/`["site-www"]` in iteration 1.)

Eval — webapp regression (thing `app`, comp `web` webapp/container/domain `app.test`/port 8080/secrets `["api_key"]`):
```
{ appWebContainerEmitted = true;
  appWebServiceEmitted = true;
  caddyAppExtra = "reverse_proxy 127.0.0.1:8080\n";
  caddyVhKeys = [ "app.test" ];
  failed = [ ];
  fileSlotGroup = "app";   fileSlotKeys = [ "app/api_key" ];
  fileSlotOwner = "app";   fileSlotRestart = [ "podman-app-web" ];
  ociAppEnvFiles = [ "/var/lib/bnox/secrets/app/api_key" ];
  ociAppImage = "app-web:current";   ociAppPorts = [ "127.0.0.1:8080:8080" ];
  ociAppUser = "app";   ociKeys = [ "app-web" ];
  svcCapabilityBounding = "";   svcIPAddressDeny = "any";
  svcNoNewPriv = "true";   svcProtectSystem = "strict";
  svcReadWritePaths = "/var/lib/app /var/lib/bnox/secrets/app"; }
```
Container `app-web` unchanged: image `app-web:current`, user `app`, envFiles + ports wired; fileSlot `app/api_key` owner/group `app` restartUnits `["podman-app-web"]`; hardening bundle applied to `podman-app-web`. No regression. ✓

Eval — http-api internal (thing `internal`, comp `api` http-api/domain=null/port 9000):
```
{ caddyVhKeys = [ ];
  failed = [ ];
  ociImage = "internal-api:current";   ociKeys = [ "internal-api" ];
  ociPorts = [ "127.0.0.1:9000:9000" ];
  serviceExists = true;   (podman-internal-api) }
```
domain=null → NO Caddy vhost; container still created. ✓

**Sign-off (iteration 2):** PASS — 2026-07-29, independent checker. The D-006 violation is fixed by a minimal one-line filter change at `runtimes/container.nix:24` (`&& comp.shape != "static-site"`); static-site now serves via Caddy `file_server` only with no per-site container; webapp/http-api/secrets/hardening unchanged. Status field left untouched per checker instructions.
