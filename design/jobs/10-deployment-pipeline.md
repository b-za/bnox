# Job 10: Deployment — pipeline (dispatcher + per-thing sync/build)

**Status:** done
**Iteration:** 2
**Created:** 2026-07-31

## Scope

Build the **D-011 pipeline's execution layer** per the **D-013 central-dispatcher topology**: one global `bnox-deploy-dispatcher` (the sole subscriber to `host.deploy.>`) routes events to per-thing oneshot units — `<name>-sync.service` (on `.changed`) and `<name>-build.service` (on `.synced`). Events still flow through NATS + the `host-deploy-logs` stream (D-011 §2/§3 audit intent preserved; the dispatcher is a router, not a bus replacement).

This job consumes what Job 09 produced (`.changed` on the bus) and produces `.synced` / `.built` / `.deployed` / `.failed`. It does NOT receive webhooks (Job 09), does NOT retain/prune tarballs or implement the rollback command (Job 11), and does NOT touch the thing schema/loader/shapes/runtimes.

**Validation limit (the handoff's acknowledged caveat, restated concretely):** the systemd unit STRUCTURE, the scripts, the NATS subject routing, the per-thing wiring, and the dispatcher's subscription all eval-clean. The actual git fetch/reset, `nix build` of a thing flake, `podman load`, and `systemctl restart` roundtrip are **runtime-deferred** — they cannot be proven without a real thing repo (with a flake exposing `images.<system>.<component>`) + running NATS + podman. Build the structure correctly, document the assumed mechanics + privilege model, note the runtime gap. Do not attempt to runtime-test.

**Spec sources (read these):**
- `design/process/05-decisions.md` — D-011 §2 (subjects), §4 (functional units: sync/build/container), §5 (multi-component: one sync+build per thing, rebuilds all components), §7 (build invocation: thing flake exposes `images.<system>.<component>`; bnox invokes `nix build /srv/<name>#images.x86_64-linux.<component>`), §8 (tarballs at `/var/lib/<thing>/images/<git-sha>.tar` — this job WRITES them; Job 11 prunes); D-013 (dispatcher topology; per-thing sync/build are oneshots).
- `design/jobs/09-deployment-webhook-receiver.md` — the `.changed` publisher (this job subscribes) + the normalized envelope shape `{thing, ref, before, after, repo, head_commit}` (the dispatcher/sync may read `after` as the new SHA).
- `design/jobs/05-things-shapes-runtimes.md` + `modules/things/runtimes/container.nix` — how containers are named (`<thing>-<component>`, service `podman-<thing>-<component>`, image `<thing>-<component>:current`). The build unit restarts these services + loads the `:current` tag.
- `design/jobs/08-bnox-loader.md` + `modules/things/default.nix` — enabled-things enumeration + per-thing components (the build unit iterates components to build each image).
- `design/process/06-base-design.md` — `modules/deployment/pipeline.nix` row.
- `design/memory/agent-handoff.md` — gotchas (`podman-<name>` service naming, `mkDefault`/`mkForce`, `fsType="ext4"` stub-eval).

## What to build

### `modules/deployment/pipeline.nix`

A NixOS module emitting THREE concerns:

#### 1. Global dispatcher: `systemd.services.bnox-deploy-dispatcher`

- **The sole subscriber** to `host.deploy.>` (D-013). Long-running (the ONE legitimate idle process in the deploy path alongside the webhook receiver — D-013 explicitly blesses these two globals).
- Subscribes to the deploy namespace; on each message, parses the subject `host.deploy.<thing>.<event>` → extracts `<thing>` + `<event>`.
- **Routes:** on event `changed` → `systemctl start <thing>-sync.service`; on event `synced` → `systemctl start <thing>-build.service`. Other events (`built`/`deployed`/`failed`) are NOT routed (they're audit-only on the stream).
- **Guards:** if the target oneshot unit doesn't exist (thing not enabled on this host, or event for an unknown thing) → skip + log, do not crash. Validate the thing name against the regex `^[a-zA-Z0-9_-]+$` before invoking `systemctl` (no injection).
- **Language lean:** Python with `nats-py` (`python3Packages.nats`, in nixpkgs) as an async subscriber — robust subject parsing + consistent with the Job-09 receiver. **Alternative:** shell driving `nats sub host.deploy.> --exec <hook>` IF natscli cleanly exposes the subject to the exec'd command (verify; if not, use Python). State which + why.
- Runs as **root** (it starts other system services via `systemctl`). Apply a hardening bundle (mirror the Q9.7 / Job-05 pattern: `ProtectSystem=strict`, `ProtectHome=true`, `PrivateTmp=true`, `NoNewPrivileges=true`, `IPAddressDeny=any` + allow-list for NATS localhost + DNS, `ReadWritePaths` minimal). `nats` CLI or `nats-py` resolvable via the service.
- Gated by `lib.mkIf` on NATS enable (inert if NATS off — mirror Job 09's `natsReady`).

#### 2. Per-thing sync oneshot: `systemd.services."<name>-sync"`

For each enabled thing (iterate `enabledThingsList`):
- `Type=oneshot`. Runs as **the thing's user** (so `git reset --hard` preserves `/srv/<name>` ownership — root would chown files to root and break the thing's read access). `setuid` via `serviceConfig.User/Group = <thing>`.
- Script: `git -C /srv/<name> fetch origin && git -C /srv/<name> reset --hard origin/main` (D-011 §4; assume `main` — make the ref configurable later if needed, but hardcode `origin/main` for day-1 and note it). Assume `/srv/<name>` is already a checkout (initial clone is an operator/provisioning step — if absent, the unit fails loud; document).
- After successful sync: publish `host.deploy.<name>.synced` to NATS with the new SHA (`git -C /srv/<name> rev-parse HEAD`). On failure: publish `host.deploy.<name>.failed` with a reason. Use `nats pub` (CLI on the service path).
- Hardening: thing's user, `ProtectSystem=strict`, `ReadWritePaths=/srv/<name> /var/lib/<name>` (the checkout + thing home), `IPAddressDeny=any` + allow-list for the git remote (HTTPS/SSH egress — note this may need the `hardening.network.outboundHTTPS`-style override; lean: allow egress to `:443` and `:22` for fetch).

#### 3. Per-thing build oneshot: `systemd.services."<name>-build"`

For each enabled thing:
- `Type=oneshot`. Runs as **root** (Job 05's containers are rootful podman — service `podman-<name>-<comp>` runs as root by default — so `podman load` must target root's storage; root can also `systemctl restart`). State this rationale.
- Script (per D-011 §5/§7): for each enabled COMPONENT of the thing:
  - `nix build /srv/<name>#images.x86_64-linux.<component>` (the thing's flake exposes this; standard bnox-owned invocation).
  - Load the resulting image into podman and (re)tag as `<name>-<component>:current` (the image string the container runtime expects, Job 05). Use `dockerTools.streamLayeredImage` output piped to `podman load`, then `podman tag <loaded> <name>-<component>:current`. (The exact `nix build` output path → `podman load` piping is runtime-deferred; write the conventional invocation and note it needs runtime confirmation.)
  - `systemctl restart podman-<name>-<component>` (the service Job 05 generated).
  - Save the image tarball to `/var/lib/<name>/images/<git-sha>.tar` (D-011 §8; this job WRITES tarballs, Job 11 prunes). SHA from `git -C /srv/<name> rev-parse HEAD`.
  - Publish `host.deploy.<name>.built` after builds; `host.deploy.<name>.deployed` after restarts; `host.deploy.<name>.failed` on any failure (with reason).
- `nix` + `podman` + `nats` resolvable via the service path.
- Hardening: root, but still apply `NoNewPrivileges`, `ProtectSystem=strict` with `ReadWritePaths` covering `/srv/<name>`, `/var/lib/<name>`, the nix store paths needed, `/var/lib/containers` (podman storage) — note build/load needs broad-ish write access; document the tension (a fully-hardened build unit is hard; lean pragmatic). Keep `PrivateTmp`, `ProtectHome`.

### Wiring

- `modules/deployment/default.nix` — add `./pipeline.nix` to imports (alongside `webhook-receiver.nix` from Job 09).
- No change to `modules/default.nix` (deployment already imported in Job 09).

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT implement the webhook receiver (Job 09 — done) or rollback/prune (Job 11). This job writes tarballs; it does NOT prune or roll back.
- Do NOT touch `modules/things/*`, `modules/secrets/*`, `modules/platform/*` (except consuming nothing new), `modules/base/*`, `modules/profiles/*`, `modules/hardware/*`, `lib/*`, `home/*`, `flake.nix`, `modules/deployment/webhook-receiver.nix`. The ONLY existing file you may modify: `modules/deployment/default.nix` (add the pipeline import). New code goes in `modules/deployment/pipeline.nix`.
- Honor D-013: the dispatcher is the ONLY subscriber to `host.deploy.>`; sync + build are oneshots (`Type=oneshot`), NOT long-running. No per-thing subscriber daemons.
- No `bnox` CLI package (choice 3). Scripts inline or via `pkgs.writeText`/`writeShellScript`.
- Build unit as root is a documented LEAN (rootful podman consistency with Job 05) — state the rationale; the checker will assess.

## Validation to run before reporting done

- `nix flake check` (must pass); `nix flake show` (unchanged).
- **Throwaway `nixosSystem` eval** (x86_64-linux, `nixosModules.bnox` + stub fs/boot with `fsType="ext4"`), declare 1-2 enabled things (mock `.bnox/` not needed — this job consumes the schema, doesn't read `.bnox/`; but needs things enabled so per-thing units generate):
  - `systemd.services.bnox-deploy-dispatcher` exists; confirm it's gated on NATS enable.
  - For each enabled thing: `systemd.services."<name>-sync"` and `systemd.services."<name>-build"` exist; confirm `Type=oneshot"`, `User` (sync = thing's user, build = root), and the script references git/nix/podman/nats.
  - Confirm the dispatcher routes `.changed`→sync and `.synced`→build (read the dispatcher script; confirm subject parsing).
  - Confirm NO per-thing long-running subscriber services exist (D-013 — only the dispatcher subscribes).
  - Paste `nix eval` outputs.
- **`bnox-dev` regression:** existing demo thing config (container/vhost/fileSlot/loader) unchanged; NEW: `demo-sync` + `demo-build` oneshots + the global dispatcher present. Confirm `failedAssertions = []`.
- Comment scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → empty.
- Document in Worker notes: (a) dispatcher language choice + why; (b) the privilege model (sync=thing's user, build+dispatcher=root) + rationale; (c) the runtime-deferred mechanics (git/nix/podman/restart) and what assumptions need runtime confirmation; (d) the `:current` retag + tarball-write convention; (e) the dispatcher's handling of unknown things / missing units; (f) any egress/hardening tensions.

## Worker notes

**Built (Job 10, iteration 1, 2026-07-31).**

### Files created (1) / modified (1)

- `modules/deployment/pipeline.nix` (new, 234 lines) — the global dispatcher + per-thing `sync`/`build` oneshots.
- `modules/deployment/default.nix` (modified, +1 import) — added `./pipeline.nix` alongside `./webhook-receiver.nix` (no other change).

`modules/default.nix` NOT touched (deployment already imported in Job 09). No constrained path touched. No `bnox` CLI package introduced (choice 3 honored).

### Dispatcher language — Python with `nats-py`

**Chose: Python (`pkgs.python3.withPackages (ps: [ ps.nats-py ])`) driving an async `nats.subscribe(SUBJECT, cb=handle)` loop.**

Reasoning:
1. **Package-name correction.** The job spec wrote `python3Packages.nats`, but the actual nixpkgs-26.05 attr is **`python3Packages.nats-py`** (verified via `nix eval` against the pinned nixpkgs flake: `builtins.attrNames (lib.filterAttrs (n: _: builtins.substring 0 4 n == "nats") pkgs.python3Packages)` returns `[ "nats-py" "nats-python" "natsort" ]`; `nats-py` is the official async client from the NATS team, `nats-python` is the legacy sync client, `natsort` is unrelated). Used `nats-py`.
2. **Subject routing is the dispatcher's whole job** — Python's `msg.subject.split(".")` + `EVENT_SUFFIX` dict gives robust, branch-tested routing with clear error paths. The `nats sub ... --exec <hook>` shell alternative would have required parsing env vars (`NATS_SUBJECT`) per-message and re-exec'ing a shell per event — more fragile and equivalent in cost. Python's `asyncio` reconnect loop (5s backoff) also gives cleaner connection resilience than a shell `while true; do nats sub --exec ...; done` wrapper.
3. **Consistency with Job 09.** The receiver is Python (`http.server` + `hmac`); the dispatcher is Python (`asyncio` + `nats-py`). The deploy path's two globals share a language, simplifying the checker's review and the operator's mental model.

No `bnox` CLI introduced — the script is embedded inline via `pkgs.writeText "bnox-deploy-dispatcher.py" handlerSource` and invoked as `ExecStart = "${pythonWithNats}/bin/python3 ${dispatcherScript}"` (mirrors Job 09's receiver pattern exactly).

### Privilege model — sync=thing's user; build+dispatcher=root (load-bearing rationale)

| Unit | User | Why |
|---|---|---|
| `<name>-sync.service` | `<name>` (the thing's user) | `git reset --hard origin/main` writes files into `/srv/<name>`. If root ran this, every checked-out file would be chown'd to `root:root`, and the thing's container (which Job 05's `container.nix` runs as `User = <thing>`) would lose read/traverse access on its own checkout → container broken on next restart. Running as the thing's user preserves `/srv/<name>` ownership end-to-end. |
| `<name>-build.service` | `root` | Job 05's containers are **rootful podman** (per `modules/things/runtimes/container.nix:42` the service-hardening targets root; `virtualisation.podman.enable = true` with no `rootless` cfg means root storage at `/var/lib/containers`). `podman load` must target root's storage; `systemctl restart podman-<name>-<comp>` requires root. Running as anything else would force a rootless-podman rewrite + privilege escalation paths. |
| `bnox-deploy-dispatcher.service` | `root` | The dispatcher's only privileged action is `systemctl start <unit>` — starting a system unit requires root (or polkit). Root is the simplest correct choice. |

This privilege asymmetry (sync=thing user, build+dispatcher=root) is **not** a contradiction: it reflects that sync touches the THING's filesystem (preserved ownership) while build/dispatch touch the HOST's container+service graph (rootful podman + systemd).

### Dispatcher routing + guards

The dispatcher parses `host.deploy.<thing>.<event>` into 4 dot-separated parts (rejecting anything not matching `host.deploy.<thing>.<event>`). Then:

- **Routing table** (Python dict): `{"changed": "-sync.service", "synced": "-build.service"}`. Suffix is appended to the validated `<thing>` to form `systemctl start` target.
- **Other events** (`built`/`deployed`/`failed`): silently ignored — they are audit-only on the `host-deploy-logs` stream and need no action.
- **Thing-name regex**: `^[a-zA-Z0-9_-]+$` (Python `re.compile`) BEFORE `systemctl` invocation — blocks shell injection from a malformed subject.
- **Unknown things / missing units**: NOT pre-checked. `systemctl start <missing>.service` returns non-zero with an error message; the dispatcher logs `(stderr or "").strip()` to its own stderr (journald) and continues. Rationale: pre-checking `systemctl cat <unit>` would race with rebuilds; systemctl's own failure IS the existence check, and per the spec ("skip + log, do not crash") this is exactly the desired behavior. `subprocess.run(..., check=False, timeout=120)` ensures no exception escapes.
- **Concurrent events for same thing**: if a sync/build oneshot is already running, `systemctl start` of the same unit returns "Unit already running" (non-zero) — logged, no crash. Acceptable day-1; documented.

### Runtime-deferred mechanics (the gaps to confirm on a linux host)

These are structurally correct but untestable on darwin:

1. **`nix build --no-link --print-out-paths "/srv/<name>#images.x86_64-linux.<component>"`** — assumes the thing's flake exposes `images.x86_64-linux.<component>` as a `streamLayeredImage` (or `buildImage`/`buildLayeredImage`) per D-011 §7. The `--print-out-paths` flag prints the resulting store path on stdout; `--no-link` avoids leaving a `result` symlink in CWD.
2. **`nix build` output → `podman load` piping** — for `streamLayeredImage`, the store path is a single executable script that streams the OCI archive when invoked. The script handles BOTH cases via `[ -x "$imgpath" ]`:
   - **Streaming (streamLayeredImage):** `"$imgpath" | podman load` (execute the script, pipe stdout).
   - **Pre-built tarball (buildImage):** `podman load < "$imgpath"` (feed the file).
   - This dual-path is robust but runtime-deferred — needs confirmation against a real thing flake on linux.
3. **`podman load` output parsing**: `awk '/Loaded image/ {print $3}'` extracts the loaded image reference (e.g. `docker.io/library/<name>-<comp>:tag`) from podman's `Loaded image: <ref>` line. The format is conventional podman output; if a future podman revision changes the wording, this breaks. Runtime-deferred.
4. **`:current` retag**: `podman tag "$loaded" "<name>-<component>:current"` makes the image findable by the Job-05 container's `image = "<name>-<component>:current"` (per `container.nix:31`). Then `systemctl restart podman-<name>-<component>` restarts the Job-05-generated service.
5. **`podman save -o "$tarpath" <img1> <img2> ...`**: writes ONE tarball per (thing, sha) containing all the thing's component images — supports multi-component things (D-011 §5/§8). Job 11 prunes to last 3.
6. **`/srv/<name>` initial clone**: assumed to be a pre-existing operator-provisioned checkout. If absent, `git -C /srv/<name> fetch origin` fails loud → `.failed` published. Documented.

### The `:current` retag + tarball-write convention

- Each component's image is retagged `<thing>-<component>:current` immediately after `podman load`. The container runtime (`container.nix:31`) references this tag, so the next `systemctl restart` picks up the new image.
- The rollback tarball is written ONCE per build (after `.built`, before `.deployed`) to `/var/lib/<name>/images/<sha>.tar` — captures ALL the thing's component `:current` images in a single file. Rollback (Job 11) is `podman load /var/lib/<name>/images/<prior-sha>.tar` + restart.
- Phase ordering in the build script: **build+load+tag (per comp) → publish `.built` → save tarball → restart (per comp) → publish `.deployed`**. The tarball is captured between `.built` and `.deployed` so a rollback point exists BEFORE any container is restarted; if a restart fails, `.failed` is published with the build tarball already on disk.

### Egress / hardening tensions

- **Sync unit `IPAddressAllow = ":443 :22 :53"`**: the thing's git remote may be HTTPS (:443) or SSH (:22); DNS (:53) needed for hostname resolution. This is a wider egress surface than Job 05's containers (which gate on `outboundHTTPS` and use `:443` only), but `git fetch` is fundamentally an outbound network operation. Pragmatic day-1; a stricter policy would require per-thing remote-allowlisting (out of scope).
- **Build unit `ReadWritePaths = "/srv/<name> /var/lib/<name> /var/lib/containers /nix/var/nix"`**: this is broader than Job 05's hardening bundle, but unavoidable — `podman load` writes to root's storage (`/var/lib/containers`), `nix build` talks to the daemon socket at `/nix/var/nix/daemon-socket/socket`, and the tarball write goes to `/var/lib/<name>/images`. A fully-sandboxed build unit would require rootless podman or a build-daemon-side isolation model — both out of scope per the spec's pragmatic lean ("a fully-hardened build unit is hard; lean pragmatic"). `NoNewPrivileges`, `ProtectHome`, `PrivateTmp` still applied.
- **Dispatcher `RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ]`**: needs `AF_UNIX` for the D-Bus socket (`/run/dbus/system_bus_socket`) that `systemctl` uses to talk to systemd; `AF_INET/6` for NATS. The Job 09 receiver could restrict to `AF_INET/AF_INET6` only because it doesn't invoke systemctl — the dispatcher cannot.
- **Dispatcher `IPAddressAllow = "127.0.0.0/8 ::1"`**: NATS is on localhost (D-006 platform default). No external egress needed.

### D-013 fidelity

- **Sole subscriber**: `rg -n 'subscribe|nats sub' modules/deployment/` returns exactly ONE match — `pipeline.nix:76: await nc.subscribe(SUBJECT, cb=handle)` inside the dispatcher. No per-thing subscriber daemons.
- **Two global services**: `bnox-deploy-dispatcher` (Job 10) + `bnox-webhook-receiver` (Job 09) — both bnox-owned, both `Type=simple` long-running. Per-thing units (`<name>-sync`, `<name>-build`) are all `Type=oneshot`.
- **Event flow preserved**: `.changed` (Job 09 publishes) → dispatcher routes → `<name>-sync` runs → publishes `.synced` → dispatcher routes → `<name>-build` runs → publishes `.built`/`.deployed`/`.failed`. All events still on `host.deploy.>` → captured by `host-deploy-logs` stream.

### Validation output

- **Comment/description scan**: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → exit 1 (clean). `rg -n '#' modules/deployment/pipeline.nix` → exactly one match: `hashSep = "#";` (the `#` is preceded by `"`, which the formal regex excludes from `[^a-zA-Z0-9_"]`, so this does NOT match the formal scan). The `hashSep` indirection is required because the `nix build /srv/<name>#images.x86_64-linux.<comp>` invocation needs a literal `#` in the generated shell script; embedding it directly as `${name}#images...` would put a `}#` sequence in the Nix source (matches the formal regex). Defining `hashSep = "#"` once and interpolating `${hashSep}` avoids every other `#` in the file.

- **`nix flake check`**: passes — only the benign cross-system `x86_64-linux` omission warning + unchanged `unknown flake output 'profiles'/'hardware'` notes, identical to Jobs 01–09.

- **`nix flake show`**: unchanged — `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`.

**Throwaway two-thing eval** (x86_64-linux, mock `.bnox/` fixtures for `thing-a` (single component `web`) + `thing-b` (two components `api` + `worker`)):
```
bnoxDeployUnits = [ "bnox-deploy-dispatcher" "thing-a-build" "thing-a-sync" "thing-b-build" "thing-b-sync" ]
hasDispatcher = true                dispatcherType = "simple"   dispatcherUser = "root"
dispatcherAfter = [ "network.target" "nats.service" ]
dispatcherRequires = [ "nats.service" ]      dispatcherWantedBy = [ "multi-user.target" ]
hasThingASync = true   hasThingABuild = true   hasThingBSync = true   hasThingBBuild = true
thingASyncType = "oneshot"   thingASyncUser = "thing-a"   thingASyncRW = "/srv/thing-a /var/lib/thing-a"
thingABuildType = "oneshot"  thingABuildUser = "root"
thingABuildRW = "/srv/thing-a /var/lib/thing-a /var/lib/containers /nix/var/nix"
thingBBuildUser = "root"
hasBuiltSubscriberDaemon = false     (no per-thing long-running subscribers — D-013 honored)
```
NATS-off probe (services.nats.enable=false): `hasDispatcherWhenNatsOff = false` — `mkIf natsReady` gating confirmed.

Multi-component `thing-b-build` script verified: iterates `api` then `worker` (each: nix build → load → tag `<name>-<comp>:current`), publishes `.built`, saves BOTH images to one tarball via `podman save -o "$tarpath" thing-b-api:current thing-b-worker:current`, restarts both `podman-thing-b-api` + `podman-thing-b-worker`, publishes `.deployed`.

**bnox-dev regression**:
```
demo-sync   = { Type="oneshot"; User="demo"; Group="demo"; ProtectSystem="strict";
                ReadWritePaths="/srv/demo /var/lib/demo"; IPAddressAllow=":443 :22 :53"; ... }
demo-build  = { Type="oneshot"; User="root"; Group="root"; ProtectSystem="strict";
                ReadWritePaths="/srv/demo /var/lib/demo /var/lib/containers /nix/var/nix";
                IPAddressAllow="127.0.0.0/8 ::1"; path=[git nix podman natscli systemd gawk coreutils]; ... }
dispatcher  = { Type="simple"; User="root"; ExecStart="${python3-env}/bin/python3 ${bnox-deploy-dispatcher.py}";
                after=["network.target" "nats.service"]; requires=["nats.service"]; wantedBy=["multi-user.target"];
                ProtectSystem="strict"; IPAddressDeny="any"; IPAddressAllow="127.0.0.0/8 ::1";
                RestrictAddressFamilies=[AF_INET AF_INET6 AF_UNIX]; NoNewPrivileges; PrivateTmp; ProtectHome; ... }
demo container (Job 05) = UNCHANGED: { image="demo-web:current"; user="demo";
                environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]; ports=["127.0.0.1:8080:8080"]; }
demo Caddy (Job 05)     = UNCHANGED: "demo.local" → "reverse_proxy 127.0.0.1:8080"
podman-demo-web RW      = UNCHANGED: "/var/lib/demo /var/lib/bnox/secrets/demo"
failedAssertions        = 0   (out of 1527 total assertions — all bnox-specific + NixOS defaults pass)
```

### For the checker to focus on

1. **The `hashSep = "#"` indirection.** The only `#` in the file is at line 24, inside a Nix string literal where the `#` is preceded by `"`. The formal comment-scan regex `(^|[^a-zA-Z0-9_"])#` does NOT match this (the `"` is excluded from the negated class). This is REQUIRED — the `nix build /srv/<name>#images.x86_64-linux.<comp>` invocation is the D-011 §7 standard and needs a literal `#` in the generated shell text. Please confirm (a) the formal scan is clean (it is: exit 1), (b) `hashSep` is the SOLE `#` in the file, and (c) the resulting shell script contains the correct `/srv/<name>#images.x86_64-linux.<comp>` target (verified: the demo-build script resolves to `/srv/demo#images.x86_64-linux.web`).

2. **The privilege model asymmetry.** Sync runs as the THING's user; build + dispatcher run as ROOT. This is load-bearing (NOT a mistake): see the rationale table above. The key invariant — sync must NOT run as root or it chowns `/srv/<name>` to root and breaks the thing's container — is the kind of thing a casual reader might flag as "inconsistent." Please confirm the git-ownership argument holds.

3. **The dual-path `podman load` (`[ -x "$imgpath" ]` branch).** Handles both `streamLayeredImage` (executable script — run and pipe stdout) and `buildImage` (tarball — feed via stdin). Robust, but runtime-deferred — needs linux confirmation that the executable-detection heuristic correctly identifies the streamLayeredImage case for thing flakes authored to the D-011 §7 schema.

4. **The `podman save` writes ONE tarball per (thing, sha) containing all component images**, not one tarball per component. This matches D-011 §8's `/var/lib/<thing>/images/<git-sha>.tar` (singular path keyed on sha, no component in the filename). Job 11's prune operates on these files.

5. **Dispatcher's missing-unit handling is via systemctl's own failure**, not a pre-check. If `<name>-sync.service` doesn't exist (thing enabled on a different host, or event for an unknown thing), `systemctl start` returns non-zero → dispatcher logs to stderr → continues. No pre-check race; the spec's "skip + log, do not crash" is satisfied.

6. **Dispatcher is gated by `mkIf natsReady`** (`config.services.nats.enable && config.services.nats.jetstream`) — verified inert when NATS is off. The sync/build oneshots are NOT gated (always generated for enabled things) — they're only triggered by the dispatcher, so if NATS is off they never run; manual `systemctl start` would fail at `nats pub` and publish nothing (the `fail` helper tries `nats pub ...failed` but `|| true` swallow the secondary failure).

7. **Python source is comment-free and `#`-free.** The dispatcher source has no `#` characters anywhere (no shebang, no Python comments, no `#` in any regex or string). The shell scripts have no `#` characters either (no shebangs — NixOS wraps `script` in bash automatically; no shell comments; the only `#` is the runtime-resolved `${hashSep}` interpolation).

---

## Worker notes — iteration 2 (NEEDS-FIX remediation, 2026-07-31)

**Blocking issue addressed:** checker ruling on the build unit's `git rev-parse HEAD` running as root in `/srv/<name>` (owned by the thing's user). git 2.54.0 (nixpkgs 26.05) enforces the `safe.directory` ownership guard: when the invoking user (root) differs from the repository's owner (the thing's user), git refuses the operation with `fatal: detected dubious ownership in repository '/srv/<name>'`. This would have broken every `demo-build` (and every per-thing build) at runtime — the SHA extraction fails → `fail "rev-parse failed"` → `.failed` published → no image built.

### Fix applied (1 edit to `modules/deployment/pipeline.nix`, exactly per checker prescription)

**One-line change at `pipeline.nix:184`** — prepended `-c safe.directory=/srv/${name}` to the build unit's `git rev-parse` invocation:

Before:
```
sha=$(${pkgs.git}/bin/git -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
```
After:
```
sha=$(${pkgs.git}/bin/git -c safe.directory=/srv/${name} -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
```

The `-c safe.directory=<path>` flag is git's documented per-invocation escape hatch for the ownership guard (equivalent to adding the path to `safe.directory` in `~/.gitconfig`, but scoped to this single command — no global config mutation, no `git config --global` side effects on the host). The sync unit's `git fetch`/`git reset` are NOT touched — sync runs as the THING's user in its own repo, so git sees matching ownership and the guard never fires.

No other change. The fix introduces the literal string `safe.directory=` but adds no `#` and no comment — confirmed by re-scan below.

### Re-validation output

- **Comment/description scan:** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean). `rg -n '#' modules/deployment/pipeline.nix` → exactly one match, unchanged: `hashSep = "#";` (line 24). The `safe.directory=` addition introduces no new `#`.
- **`nix flake check`:** passes — only the benign cross-system `x86_64-linux` omission warning + unchanged `unknown flake output 'profiles'/'hardware'` notes, identical to iteration 1 + Jobs 01–09.
- **`nix flake show`:** unchanged (`nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`).

**`demo-build` script confirmed** (bnox-dev regression — relevant slice via `nix eval .#nixosConfigurations.bnox-dev.config.systemd.services.demo-build.script`):
```
sha=$(/nix/store/yfa34aybr5lyqs5c7v2pp5yw8z9f8yc3-git-2.54.0/bin/git -c safe.directory=/srv/demo -C /srv/demo rev-parse HEAD) || fail "rev-parse failed"
```
The flag appears between `git` and `-C`; the rest of the script is byte-identical to iteration 1.

**bnox-dev regression:**
```
failedAssertions = 0
demo container  = UNCHANGED: { image="demo-web:current"; user="demo";
                               environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]; ports=["127.0.0.1:8080:8080"]; }
demo Caddy      = UNCHANGED: "demo.local" → "reverse_proxy 127.0.0.1:8080"
```

All iteration-1 decisions stand unchanged. The only delta is the build-unit `safe.directory` flag.

## Checker notes

**Verdict: NEEDS-FIX** — one deterministic runtime bug (concern A, git `safe.directory` in the root build unit). All other checklist items PASS; structure, D-013 fidelity, privilege model, and validation all reproduce clean. Concern A is a one-line fix; until applied, every real build will fail at the `rev-parse HEAD` step on day-1 deployment.

### Per-checklist results

1. **Scope — PASS.** `git diff HEAD --stat -- modules/` = `modules/deployment/default.nix (+1)` + `modules/deployment/pipeline.nix (new, 234)`. No other module touched. `modules/default.nix`, `webhook-receiver.nix`, `modules/things/*`, `lib/*`, `flake.nix` all UNCHANGED. (`design/STATUS.md` is the worker's bookkeeping string, not a constrained path.)
2. **No comments / descriptions — PASS.** Formal scan `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean). `rg -n '#' modules/deployment/pipeline.nix` → exactly one match: line 24 `hashSep = "#";`. Embedded Python is comment-free, shebang-free, `#`-free; shell scripts have no shebangs (NixOS wraps) and no shell comments. See concern B for the `hashSep` rationale.
3. **D-013 fidelity — PASS (load-bearing).** (a) `rg -n 'subscribe|nats sub' modules/deployment/` → exactly ONE match: `pipeline.nix:76: await nc.subscribe(SUBJECT, cb=handle)` (in the dispatcher). Eval probe `scriptSubscribers`/`execSubscribers` both `[]` — no per-thing subscriber daemons. (b) Sync + build are `Type=oneshot` (verified on `thing-a-sync`/`thing-a-build`/`thing-b-build` via eval). (c) Two globals in the deploy path: `bnox-webhook-receiver` (Job 09) + `bnox-deploy-dispatcher` (Job 10); the stream-init oneshot is also global but oneshot/RemainAfterExit, not idle.
4. **Dispatcher correctness — PASS.** Python: subject parsed as exactly 4 dot-parts with `parts[0]=="host"` and `parts[1]=="deploy"` guards (pipeline.nix:45); thing regex `^[a-zA-Z0-9_-]+$` checked BEFORE systemctl (pipeline.nix:50); routing table `{changed: -sync.service, synced: -build.service}` (pipeline.nix:37-40); other events return silently (pipeline.nix:54); missing-unit handled via `check=False` + stderr log (pipeline.nix:58-69) — no exception escapes; `mkIf natsReady`-gated (pipeline.nix:203); reconnect loop on NATS error (pipeline.nix:73-80, `while True` + `asyncio.sleep(5)`). Verified NATS-off → `hasDispatcher = false`.
5. **Sync unit — PASS.** `Type=oneshot`, `User/Group=<thing>` (pipeline.nix:99-101); `git fetch origin && git reset --hard origin/main` (pipeline.nix:116-121); `rev-parse HEAD` + `nats pub .synced` with SHA (pipeline.nix:122-123); `fail()` publishes `.failed` (pipeline.nix:112-115). Hardening: `ProtectSystem=strict`, `ProtectHome`, `PrivateTmp`, `NoNewPrivileges`, `ReadWritePaths=/srv/<name> /var/lib/<name>`, `IPAddressDeny=any` + `IPAddressAllow=":443 :22 :53"`.
6. **Build unit — NEEDS-FIX (concern A).** Structure otherwise PASS: `Type=oneshot`, `User/Group=root` (pipeline.nix:167-169); per-comp `nix build /srv/<name>#images.x86_64-linux.<comp>` → dual-path `podman load` via `[ -x "$imgpath" ]` (pipeline.nix:139-144) → retag `<name>-<comp>:current` (pipeline.nix:145) → publish `.built` (pipeline.nix:188) → `podman save -o "$tarpath" ${imageRefs}` (pipeline.nix:190, single tarball per thing+sha) → `systemctl restart podman-<name>-<comp>` per comp (pipeline.nix:148-153) → publish `.deployed` (pipeline.nix:192). Phase ordering matches spec: build+load+tag → `.built` → tarball → restart → `.deployed` (rollback point exists before any container is restarted). The `.deployed` publish uses `|| true` (deployment already done); all critical steps use `|| fail`.
7. **Multi-component — PASS.** Eval on `thing-b` (components `api`+`worker`): ONE `thing-b-build` unit; buildLoop iterates both; `podman save -o "$tarpath" thing-b-api:current thing-b-worker:current` writes one tarball containing both images; restartLoop restarts both `podman-thing-b-api` + `podman-thing-b-worker`. Verified by regex match on the generated script.
8. **Validation reproduction — PASS (modulo concern A).**
   - `nix flake check` → passes (only the benign `x86_64-linux` omission + `unknown flake output 'profiles'/'hardware'` warnings, identical to Jobs 01–09).
   - `nix flake show` → unchanged (`nixosModules.{bnox,bnox-base}`, `nixosConfigurations.bnox-dev`, `profiles`, `hardware`, `lib`).
   - Throwaway two-thing + static-site eval: `bnoxDeployUnits = [ "bnox-deploy-dispatcher" "site-only-sync" "thing-a-build" "thing-a-sync" "thing-b-build" "thing-b-sync" ]`; dispatcher `{Type="simple", User="root", after=["network.target" "nats.service"], requires=["nats.service"], wantedBy=["multi-user.target"]}`; `thing-a-sync {Type="oneshot", User="thing-a", RW="/srv/thing-a /var/lib/thing-a", IPAllow=":443 :22 :53"}`; `thing-b-build {Type="oneshot", User="root", RW="/srv/thing-b /var/lib/thing-b /var/lib/containers /nix/var/nix"}`; NATS-off → `hasDispatcher=false`; `failedAssertions=[]`.
   - bnox-dev regression: `demo-sync {Type="oneshot", User="demo"}` + `demo-build {Type="oneshot", User="root"}` + dispatcher present; `demo-web` container `image="demo-web:current"` UNCHANGED; `failedAssertions=[]`.

### Concern rulings

**A. git `safe.directory` in the BUILD unit — NEEDS-FIX (deterministic runtime bug).** Confirmed real. The build unit runs as `User=root` (pipeline.nix:168) and invokes `${pkgs.git}/bin/git -C /srv/${name} rev-parse HEAD` (pipeline.nix:184). `/srv/<name>` is owned by the thing's user (the sync unit runs as `User=<thing>` and preserves that ownership via `git reset --hard`). nixpkgs-26.05 ships git 2.54.0 (verified in the eval store path), which has the safe.directory ownership guard introduced in git 2.35.2 (Apr 2022). Running git as eUID=0 in a repo whose directory is owned by another user errors with `fatal: detected dubious ownership in repository at '/srv/<name>'` and exits non-zero. This is not a "might-fail": it fails EVERY build, deterministically, at the very first `rev-parse HEAD` step, before any `nix build`/`podman load` runs. The sync unit does NOT hit this (same-user repo). The validation gap (darwin host, no real linux roundtrip) is why it slipped through — it is invisible to `nix flake check` and to the structural eval.

Minimal fix (scoped, certain): change pipeline.nix:184 from
```
sha=$(${pkgs.git}/bin/git -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
```
to
```
sha=$(${pkgs.git}/bin/git -c safe.directory=/srv/${name} -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
```
The `-c safe.directory=/srv/<name>` per-invocation override takes precedence over the global config and is the minimal scoped fix (no global config mutation; no `safe.directory=*` blast radius). If a follow-up runtime test reveals that `nix build /srv/<name>#...` ALSO trips git's guard via nix's internal git ops (possible but unverified here — nix uses libgit2 directly for flake resolution and may bypass), escalate to setting `GIT_CONFIG_GLOBAL` pointing at a file with `safe.directory=/srv/<name>` in the build unit's `environment`, but start with the one-line scoped fix above — it solves the certain failure. Recommend treating this as a Job-10 follow-up iteration before any real deployment; do NOT defer to Job 11.

**B. `hashSep = "#"` indirection — ACCEPTABLE (clean workaround).** Verified: (a) formal scan exits clean; (b) `hashSep = "#"` is the SOLE `#` in the file (line 24), and the `#` is preceded by `"` (excluded from the regex's negated class `[^a-zA-Z0-9_"]`), so it legitimately does not match; (c) the generated demo-build script resolves to `/srv/demo#images.x86_64-linux.web` (the correct D-011 §7 target — confirmed by regex match on the eval'd `thing-a-build` script: `/srv/thing-a#images.x86_64-linux.web`). The `${name}#images...` direct form would put `}#` in the Nix source (matches the regex's `}#` tail — `}` is not in the negated class), so the indirection is necessary. Not the comment-scan convention's fault; the convention is correct (it forbids inline `#` comments), and the worker's indirection is the right escape. Pattern noted: this is the SECOND job where a literal `#`/`*` token forced an indirection (Job 09's Caddy `/*` glob was the first, via `glob = "*" * "/"` style). Worth a one-line entry in `design/memory/agent-handoff.md` so future workers don't re-derive the workaround; not blocking.

**C. Static-site / non-container things: dispatcher noise — DOCUMENT (not NEEDS-FIX, day-1 acceptable).** Confirmed real. Eval with `site-only` (shape=static-site, runtime=container): `site-only-sync` IS generated (every enabled thing gets a sync unit), `site-only-build` is NOT (filtered out by `thingsWithBuildableComps` at pipeline.nix:13-22, which excludes `shape == "static-site"`). Event flow on a static-site push: webhook → `.changed` → dispatcher routes to `site-only-sync.service` (EXISTS, runs, updates `/srv/site-only`, Caddy serves fresh) → publishes `.synced` → dispatcher routes to `site-only-build.service` (DOES NOT EXIST) → `systemctl start site-only-build.service` returns non-zero → dispatcher logs `systemctl start site-only-build.service failed: Unit site-only-build.service could not be found.` to stderr (journald) on every static-site sync. Functionally fine (the files ARE updated and Caddy serves them); just one stderr line per static-site push. The spec explicitly allows "skip + log, do not crash" for missing units, and the worker's missing-unit handling is exactly the prescribed pattern. Day-1 call: ACCEPTABLE noise. RECOMMEND the worker add one sentence to the Worker notes under "Dispatcher routing + guards" documenting this so operators grepping journald don't file a bug. If the noise later proves operationally annoying, the cleanest mitigation is a no-op `site-only-build` oneshot synthesized by the dispatcher-side filter (or expanding `thingsWithBuildableComps` to all enabled things with a no-op script for things with zero buildable components) — but this is a Job-10-iteration-or-later call, not a Job-10 blocker. The current behavior is safe and matches the spec's letter.

**D. Privilege model asymmetry — SOUND.** Confirmed. Sync must run as `User=<thing>`: `git reset --hard origin/main` as root would chown every checked-out file to `root:root`, and the Job-05 container (which runs as `User=<thing>` per `container.nix:32`) needs to read `/srv/<name>` → would break on next restart. Build must run as `User=root`: Job-05 containers are rootful podman (`virtualisation.podman.enable = true` with no rootless cfg → root storage at `/var/lib/containers`), so `podman load` must target root's storage; `systemctl restart podman-<name>-<comp>` needs root. Dispatcher must run as `User=root`: `systemctl start` of a system unit requires root (or polkit). The asymmetry is not a contradiction — it reflects that sync touches the THING's filesystem (ownership preservation) while build/dispatch touch the HOST's container+service graph (rootful podman + systemd). Rationale holds.

### Reproduced validation output (command → result)

- `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean).
- `rg -n '#' modules/deployment/pipeline.nix` → `24:  hashSep = "#";` (only match).
- `rg -n 'subscribe|nats sub' modules/deployment/` → `modules/deployment/pipeline.nix:76: await nc.subscribe(SUBJECT, cb=handle)` (only match).
- `nix flake check` → passes (benign `x86_64-linux` omission + `unknown flake output 'profiles'/'hardware'` warnings, identical to prior jobs).
- `nix flake show` → `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib` (unchanged).
- Throwaway two-thing + static-site eval: `{ bnoxDeployUnits = [ "bnox-deploy-dispatcher" "site-only-sync" "thing-a-build" "thing-a-sync" "thing-b-build" "thing-b-sync" ]; hasDispatcher = true; siteOnlySyncPresent = true; siteOnlyBuildPresent = false; thingBBuildSavesBoth = true; thingBBuildRestartsBoth = true; demoBuildResolvesHash = true; scriptSubscribers = []; execSubscribers = []; failedAssertions = []; }`. NATS-off probe (`services.nats.enable = false`): `{ hasDispatcher = false; hasStreamInit = false; }` — `mkIf natsReady` gating confirmed.
- bnox-dev regression: `{ demoSyncPresent = true; demoSyncType = "oneshot"; demoSyncUser = "demo"; demoBuildPresent = true; demoBuildType = "oneshot"; demoBuildUser = "root"; dispatcherPresent = true; demoContainerImage = "demo-web:current"; failedAssertions = []; }`.

### Iteration 2 verdict — PASS

**Fix verified.** `git diff -- modules/deployment/pipeline.nix` (working tree vs iteration-1 staged blob) shows EXACTLY one line changed:

```
-          sha=$(${pkgs.git}/bin/git -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
+          sha=$(${pkgs.git}/bin/git -c safe.directory=/srv/${name} -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
```

At `pipeline.nix:184` (build unit only). The sync unit's `rev-parse` at `pipeline.nix:122` is UNTOUCHED (`git -C /srv/${name} rev-parse HEAD`, no `-c` flag) — correct, since the sync unit runs as `User=<thing>` in its own repo and does not hit the ownership guard. No other line changed between iterations 1 and 2.

**Reproduced validation (iteration 2):**
- `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean). The `safe.directory=` addition introduced no `#` (the `=` and alphanumerics don't trip the regex). `rg -n '#' modules/deployment/pipeline.nix` → still exactly one match: `24:  hashSep = "#";`. `rg -n 'safe.directory' modules/deployment/pipeline.nix` → single match at line 184 (build unit only — confirms sync unit was not also patched).
- `nix flake check` → passes (benign `x86_64-linux` omission + `unknown flake output 'profiles'/'hardware'` warnings, identical to prior jobs and to iteration 1).
- `nix flake show` → unchanged (`nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`); no new flake outputs (internal module edit only).
- bnox-dev `demo-build` script: `demoBuildHasSafeDir = true` (regex match on `git -c safe.directory=/srv/demo -C /srv/demo rev-parse HEAD`); `demoBuildType = "oneshot"`, `demoBuildUser = "root"`.
- bnox-dev `demo-sync` script: `demoSyncUntouched = true` (no `-c safe.directory` token present); `demoSyncType = "oneshot"`, `demoSyncUser = "demo"`.
- bnox-dev regression: `demoContainerImage = "demo-web:current"` (Job-05 container UNCHANGED); `failedAssertions = []`.

**Assessment.** The prescribed one-line scoped fix is applied verbatim, in the correct (sole) place, with no collateral changes. The deterministic runtime bug from iteration 1 (concern A) is closed: the build unit's `git rev-parse HEAD` as root in `/srv/<name>` (owned by the thing's user) now carries the per-invocation `-c safe.directory=/srv/<name>` override that takes precedence over git's ownership guard, so it will succeed on first real deployment. The scoped form (`=/srv/${name}`, not `=*`) keeps the trust surface to the single operator-owned checkout. Iteration-1 concerns B (hashSep), C (static-site dispatcher noise — documented lean), and D (privilege model) remain as previously ruled (B/D accepted, C documented); no new issues surfaced.

## Sign-off
PASS (iteration 2). Concern-A `safe.directory` fix applied as prescribed and verified; all validation reproduces clean. Ready for lead to mark Status=done. (Checker, 2026-07-31.)
