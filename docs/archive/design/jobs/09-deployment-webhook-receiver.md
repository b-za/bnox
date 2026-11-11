# Job 09: Deployment — webhook receiver

**Status:** done
**Iteration:** 2
**Created:** 2026-07-29

## Scope

Build the **first half of the D-011 deployment pipeline's entry point**: a single global `bnox-webhook-receiver` that receives push events from GitHub/Forgejo, verifies per-thing HMAC auth, and publishes `host.deploy.<name>.changed` to NATS. This is the trigger that the dispatcher (Job 10) will subscribe to and route to per-thing sync/build oneshots.

This job establishes the `modules/deployment/` directory and the `host.deploy.>` NATS namespace plumbing (including the `host-deploy-logs` JetStream audit stream). It publishes `.changed` only — it does NOT subscribe, does NOT sync, does NOT build, does NOT dispatch (all Job 10), and does NOT retain tarballs (Job 11).

**D-013 alignment (decided this session):** the user rejected long-running idle processes. The webhook receiver is the ONE global service legitimately in the event path. Lean toward **socket activation** (zero idle processes — systemd spawns the handler per incoming webhook) if it's clean in NixOS; fall back to a single localhost-listening daemon only if socket activation proves too fiddly. Do NOT create per-thing receiver processes (the receiver is global; per-thing routing happens in the URL path → thing name).

**Validation limit (acknowledged):** the service, Caddy vhost, fileSlot wiring, and NATS connection config all eval-clean. The actual webhook receipt, HMAC verification, and NATS publish roundtrip are **runtime-deferred** — they cannot be proven without a live webhook source + running NATS. Build the structure correctly; document the assumed webhook payload format; note the runtime gap.

**Spec sources (read these):**
- `design/process/05-decisions.md` — D-011 §1 (webhook + NATS bus), §2 (subjects `host.deploy.<name>.{changed,synced,built,deployed,failed}`), §3 (`host-deploy-logs` JetStream stream filtered on `host.deploy.>`), D-013 (central dispatcher topology — this job publishes `.changed`, Job 10 subscribes).
- `design/process/06-base-design.md` — choice 3 ("Webhook receiver wired as a shell/script inside its module; no `bnox` CLI") + the `modules/deployment/webhook-receiver.nix` table row.
- `design/jobs/03-secrets.md` — the `bnox.secrets.fileSlots` interface (this job populates it for webhook HMAC secrets).
- `design/jobs/08-bnox-loader.md` — how enabled things are enumerated (mirror the `enabledThingsList` pattern from `modules/things/default.nix` / `runtimes/container.nix`).
- `design/memory/agent-handoff.md` — gotchas (`mkDefault`/`mkForce`, `podman-<name>` naming, the `fsType="ext4"` stub-eval).

## What to build

### `modules/deployment/webhook-receiver.nix`

A NixOS module that emits:

1. **The receiver service.** `systemd.services.bnox-webhook-receiver` — the HTTP endpoint that receives webhooks. Leans:
   - **Socket activation (preferred):** a `systemd.sockets.bnox-webhook-receiver` listening on a unix socket at `/run/bnox/webhook.sock` (or a localhost port), with `bnox-webhook-receiver.service` set `ListenStream`-activated (`systemd.services."bnox-webhook-receiver".socketConfig` / the socket unit's wiring). The service is `Type=oneshot` per-connection OR a short-lived handler invoked by systemd-socket-activate. Zero idle processes.
   - **Fallback:** a single `bnox-webhook-receiver.service` daemon (`Type=simple`) listening on `127.0.0.1:<pick-a-port>`. One idle process. Use only if socket activation is impractical.
   - State which you chose and why.

2. **The handler script.** The script invoked by the service. It must:
   - Parse the incoming webhook (HTTP request — via the socket-activated stdin, or the daemon's request body).
   - Extract the thing name from the URL path (convention: `/bnox/webhook/<thing>`).
   - Read that thing's HMAC secret from `/var/lib/bnox/secrets/<thing>/webhook_secret` (the file backend path, D-007).
   - Verify the request signature (GitHub/Forgejo use `X-Hub-Signature-256` / `X-Forgejo-Signature` HMAC-SHA256 of the body). On mismatch → 401, no publish.
   - On match → publish `host.deploy.<thing>.changed` to NATS (via `nats pub`), respond 200.
   - **Language lean:** shell (`nats pub` + `jq` + `openssl dgst -sha256`/`openssl HMAC`) per choice 3's "shell/script". Fall back to Python (`pkgs.python3` with stdlib `hmac`/`json` + `nats` CLI shelling out for the publish) only if robust HMAC+HTTP parsing in shell proves too fragile. State which and why. The script lives inline in the module (a `script` or `serviceConfig.ExecStart`/`ExecStartPre` string) or as a derivation in `lib/`/`packages/` if substantial — prefer inline unless reuse demands otherwise.
   - Document the assumed webhook payload format (GitHub `push` events to `refs/heads/main`; note Forgejo equivalence).

3. **Caddy vhost.** A `services.caddy.virtualHosts` entry reverse-proxying `/bnox/webhook/*` (or a dedicated webhook subdomain — pick the simpler one and state it) to the receiver's socket/port. Use the existing platform Caddy (do not spawn a second web server). If the host has no public domain yet (e.g. `bnox-dev`), the vhost still evals (Caddy accepts arbitrary hostnames); document that real deployment needs a reachable URL or Tailscale Funnel (D-011 consequence).

4. **Per-thing HMAC secret slot wiring.** For each enabled thing, auto-wire `bnox.secrets.fileSlots."<thing>/webhook_secret"` with `owner`/`group` = `bnox-webhook-receiver` (or root — state which; the receiver must read it) and `restartUnits` = `[ "bnox-webhook-receiver.service" ]` (so a secret rotation restarts the receiver) OR empty if the script reads per-request (state which strategy). Rationale: the webhook secret is bnox-side plumbing (between GitHub/Forgejo and bnox), NOT thing-intrinsic — so bnox's deployment layer provisions it, the thing repo is unaware. Mirror `modules/things/runtimes/container.nix`'s `enabledThingsList` iteration pattern.

5. **Dedicated receiver user.** Create a `bnox-webhook-receiver` system user/group (the service runs as this user; the HMAC secret files are owned by it). Mirror `modules/things/user.nix`'s pattern but for this one global service user (not per-thing).

6. **`host-deploy-logs` JetStream stream.** The audit stream for the whole `host.deploy.>` namespace (D-011 §3). **Investigate whether NixOS's `services.nats` supports declarative JetStream stream creation** (check `services.nats.jetstream.*` options in nixpkgs 26.05). If yes → declare it in `modules/platform/nats.nix` (filtered on `host.deploy.>`). If no → emit a boot-time oneshot `systemd.services.bnox-nats-stream-init.service` (runs `nats stream add`/equivalent idempotently on startup, `after nats.service`). State which path you took and cite the nixpkgs option/source.

### `modules/deployment/default.nix` (new)

Imports `./webhook-receiver.nix` (pipeline.nix + rollback.nix added in Jobs 10/11).

### `modules/default.nix` (modify)

Add `./deployment/default.nix` to the existing `imports` list. No other changes.

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT implement the dispatcher, per-thing sync/build units, or rollback (Jobs 10/11). This job publishes `.changed` only.
- Do NOT touch `modules/things/*` (the loader/schema/shapes/runtimes), `modules/secrets/*` (except consuming `bnox.secrets.fileSlots`), `modules/base/*`, `modules/profiles/*`, `modules/hardware/*`, `lib/*`, `home/*`, `flake.nix`. The only existing files you may modify: `modules/default.nix` (one import), `modules/platform/nats.nix` (the stream, IF declarative is supported — otherwise leave it alone and use the oneshot). New files only under `modules/deployment/`.
- No per-thing receiver processes. The receiver is ONE global service (D-011 §1, D-013).
- Honor choice 3: no `bnox` CLI package. The handler is a script wired into the service, not a user-facing tool.
- The `nats` CLI must be resolvable by the service at runtime (add to the service's `path` or reference the package) — but do NOT add it to `environment.systemPackages` globally unless conventional.
- If you add the receiver user, mirror the existing `modules/things/user.nix` style (no description fields).

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — outputs unchanged.
- **Throwaway `nixosSystem` eval** (x86_64-linux, `nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"` — the Job-04/08 trick) declaring one or two enabled things, confirm:
  - `systemd.services.bnox-webhook-receiver` exists (and `systemd.sockets.bnox-webhook-receiver` if socket-activated).
  - A Caddy virtualHost reverse-proxies to the receiver's socket/port.
  - `bnox.secrets.fileSlots."<thing>/webhook_secret"` exists for each enabled thing, with the expected owner/group/restartUnits.
  - The `bnox-webhook-receiver` user/group exists.
  - The `host-deploy-logs` stream is declared (if declarative) OR the init oneshot exists.
  - Paste the `nix eval` outputs.
- **`bnox-dev` regression:** `nix eval .#nixosConfigurations.bnox-dev.config.<path>` — the existing demo thing still works (container, vhost, fileSlot for `api_key` unchanged), AND now additionally has a `demo/webhook_secret` fileSlot + the global webhook-receiver service + Caddy vhost. Confirm the loader (Job 08) still produces identical intrinsic fields.
- Comment scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → no matches. (If you modify `nats.nix`, scan it too.)
- Document explicitly in Worker notes: (a) socket-vs-daemon choice + why; (b) shell-vs-Python choice + why; (c) whether declarative JetStream streams are supported in nixpkgs 26.05 (cite the option/source) and which path you took; (d) the assumed webhook payload format; (e) the HMAC read strategy (per-request vs startup-load) and the corresponding restartUnits choice.

## Worker notes

**Built (Job 09, iteration 1, 2026-07-29):**

Files created (2) / modified (1):
- `modules/deployment/webhook-receiver.nix` (new) — the global receiver service + Python handler + Caddy vhost + per-thing `webhook_secret` fileSlots + `bnox-webhook-receiver` user/group + the `host-deploy-logs` JetStream init oneshot.
- `modules/deployment/default.nix` (new) — `imports = [ ./webhook-receiver.nix ];` (pipeline.nix + rollback.nix added in Jobs 10/11).
- `modules/default.nix` (modified) — added `./deployment/default.nix` to the existing `imports` list (one line; no other change).

`modules/platform/nats.nix` was NOT modified (declarative JetStream streams are unsupported in nixpkgs 26.05 — see stream path below).

### Receiver design — socket vs daemon

**Chose: single `Type=simple` localhost-listening daemon (the spec's documented fallback).** NOT socket activation.

Reasoning: socket activation (`Accept=yes`, inetd-style) was the preferred lean, but its fd-wiring has an irreducible uncertainty I could not resolve on the darwin eval host — specifically whether `StandardOutput=socket` (needed to route the handler's HTTP response back through the accepted socket fd) is honored by NixOS 26.05's `serviceConfig` enum and by systemd 260 for the `bnox-webhook-receiver@.service` template that `Accept=yes` requires. The alternative (writing the response via `os.write(0, ...)` to the bidirectional socket fd) is non-obvious and equally untestable here. The spec's escape clause explicitly permits a single localhost-listening daemon ("only if socket activation proves too fiddly"), and D-013 explicitly blesses the receiver as the ONE global service legitimately in the event path — so one idle Python process is consistent with D-013's intent (the "2N+1 idle processes" rejection was about PER-THING subscribers, not the one global receiver). The daemon is the canonical, certain NixOS HTTP-service pattern; the full webhook→HMAC→publish roundtrip is runtime-deferred regardless, so shipping the certain approach is the responsible call. The daemon is hardenable (`Type=simple` + `Restart=on-failure` + a FS/proc hardening set that preserves NATS egress).

### Receiver design — shell vs Python

**Chose: Python (`pkgs.python3` stdlib `http.server` + `hmac`/`hashlib`/`json` + shelling out to `nats pub`).**

Reasoning: choice 3 prefers a shell/script, with the explicit fallback "only if robust HMAC+HTTP parsing in shell proves too fragile." It does. Robustly parsing an HTTP/1.1 request off a socket in shell — CRLF header termination, case-insensitive header lookup (`X-Hub-Signature-256` vs `x-hub-signature-256`), Content-Length-driven body reads, hex HMAC comparison (`openssl dgst -sha256 -mac HMAC`) — is genuinely fragile (the GitHub header is `sha256=<hex>`; Forgejo's `X-Forgejo-Signature` is bare `<hex>`; both must normalize). Python's `http.server.BaseHTTPRequestHandler` does all HTTP parsing in stdlib; `hmac.compare_digest` gives constant-time comparison; `json` normalizes the push payload into a small envelope for the dispatcher. The `nats` CLI publish is a single `subprocess.run(["nats","pub",...])` — same shell-out cost either way. The handler is ~90 lines, embedded inline via `pkgs.writeText` (no separate derivation per the "prefer inline" lean), invoked as `ExecStart = "${pkgs.python3}/bin/python3 ${handlerScript}"`. No `bnox` CLI package is introduced (choice 3 honored).

### HMAC read strategy

**Chose: per-request read (handler opens `/var/lib/bnox/secrets/<thing>/webhook_secret` on every incoming webhook).** Therefore `restartUnits = []` on every `webhook_secret` fileSlot.

Reasoning: per-request read means a secret rotation takes effect on the NEXT webhook with no service restart — strictly better than startup-load (which would need `restartUnits = [ "bnox-webhook-receiver.service" ]` and would miss rotations until the next restart). The file open is cheap (one syscall per webhook; webhook volume is a handful per hour at most). This also keeps the fileSlot's restart list empty, which is exactly the case the spec anticipated ("OR empty if the script reads per-request").

### `host-deploy-logs` JetStream stream — declarative vs oneshot

**Investigated → declarative is NOT supported in nixpkgs 26.05. Chose: boot-time idempotent oneshot `systemd.services.bnox-nats-stream-init`.**

nixpkgs source checked: the `services.nats` module at the flake-locked nixpkgs rev `3497aa5c9457a9d88d71fa93a4a8368816fbeeba` is `nixos/modules/services/networking/nats.nix`. Its option surface is exactly: `enable`, `user`, `group`, `serverName`, `jetstream` (boolean `mkEnableOption`), `port`, `dataDir`, and `settings` (a freeform `pkgs.formats.json {}` that becomes the NATS server config file). There is NO option for declarative JetStream stream contents — `settings.jetstream` only takes `store_dir` (and optionally `max_mem`/`max_file`); stream/consumer creation is a runtime NATS API operation requiring the server to be running. So a declarative stream in `modules/platform/nats.nix` is impossible (and `modules/platform/nats.nix` was therefore left untouched).

The oneshot: `Type=oneshot`, `RemainAfterExit=true`, `wantedBy=["multi-user.target"]`, `after=["nats.service"]`, `requires=["nats.service"]`. It writes a stream config to the store via `pkgs.writeText "host-deploy-logs.json" (builtins.toJSON { name="host-deploy-logs"; subjects=["host.deploy.>"]; retention="limits"; storage="file"; })` and runs an idempotent shell loop (up to 15s with 1s sleeps to let JetStream initialize after `nats.service` starts): `nats stream info host-deploy-logs` → if exists, `nats stream update --config <json>`; else `nats stream add --config <json> --defaults`. The `nats` CLI is `pkgs.natscli` (provides `bin/nats`; `mainProgram = "nats"`), resolvable via the service's `path = [ pkgs.natscli ]` (NOT added to `environment.systemPackages`). Gated by `lib.mkIf (config.services.nats.enable && config.services.nats.jetstream)` so it's inert if NATS is off. The actual stream creation is runtime-deferred (needs a running NATS).

### Assumed webhook payload format

**GitHub `push` events to `refs/heads/main` (Forgejo-equivalent).** The handler:
- Reads the thing name from the URL path `/bnox/webhook/<thing>` (POST; the dedicated Caddy vhost `http://bnox-webhook.local` proxies all traffic to the daemon, which validates the path and 404s anything else).
- Verifies the HMAC-SHA256 of the raw request body against the `X-Hub-Signature-256: sha256=<hex>` header (GitHub) OR `X-Forgejo-Signature: <hex>` (Forgejo) — both normalize to the bare hex for comparison via `hmac.compare_digest`.
- On match, parses the body as JSON and publishes a NORMALIZED envelope to `host.deploy.<thing>.changed` (NOT the raw GitHub payload, so the dispatcher in Job 10 doesn't need to speak GitHub's schema): `{"thing": <name>, "ref": <e.g. "refs/heads/main">, "before": <sha>, "after": <sha>, "repo": <full_name>, "head_commit": <id>}`. Fields are `null` if absent in the payload (so non-push or malformed bodies still publish with nulls — the dispatcher decides policy like ref filtering).
- Responses: 200 on success, 401 on missing/bad signature or no secret file, 404 on bad path/thing name, 502 if `nats pub` fails. All JSON. `Connection: close` per response (HTTP/1.1, no keep-alive).

Thing-name validation: `^[a-zA-Z0-9_-]+$` regex rejects path traversal (`..`, slashes) before any filesystem access.

### CRITICAL DEVIATION — `webhook_secret` fileSlot owner/group

The spec suggested `owner`/`group` = `bnox-webhook-receiver` (or root). **I set `owner = <thing>; group = <thing>;` instead** (the thing's own user, NOT the receiver). This is forced by a tmpfiles collision the spec did not anticipate:

Job 03's `modules/secrets/backends/file.nix` emits one tmpfiles rule per slot's parent dir, deduped by EXACT string match (`lib.unique`). A thing's existing secret slot (`<thing>/api_key`, owner `<thing>`) and the new `<thing>/webhook_secret` slot BOTH produce a rule for `/var/lib/bnox/secrets/<thing>/`. If the two slots have DIFFERENT owners, the two rule strings differ → `lib.unique` keeps BOTH → systemd-tmpfiles applies both with last-wins → the dir ends up owned by whichever owner sorts last alphabetically (the receiver, since `bnox-webhook-receiver` > thing names… actually it's per-key-sorted: `<thing>/webhook_secret` sorts after `<thing>/api_key`, so the receiver-owned rule wins), BREAKING the thing's own container (it can no longer traverse its secrets dir to read `api_key`).

Setting `owner = group = <thing>` makes both slots produce the IDENTICAL rule string → `lib.unique` dedupes to ONE rule → no collision, the thing's dir stays owned by `<thing>:<thing>`. Verified empirically: bnox-dev's tmpfiles rules contain exactly ONE `d /var/lib/bnox/secrets/demo 0750 demo demo -` (from both `demo/api_key` and `demo/webhook_secret`); the two-thing throwaway likewise has one rule per thing dir.

The receiver still reads the secret: it's added to each enabled thing's group via `users.users.bnox-webhook-receiver.extraGroups = thingNames;`, so it can traverse the `0750 <thing>:<thing>` parent dir via group `x`, and read the `webhook_secret` file if the operator created it group-readable (0640 `<thing>:<thing>` or 0644). The operator workflow is documented above; the file's perms are an operator concern (Job 03's "slot file itself is NOT created by bnox"). This satisfies the spec's actual intent ("the receiver must read it") via a different, collision-free mechanism. I could not modify `modules/secrets/backends/file.nix` (forbidden — only consume `fileSlots`), so consistent ownership from the consumer side is the only fix.

### Caddy vhost note

The spec offered `/bnox/webhook/*` (path matcher) or a dedicated subdomain. I used a dedicated vhost `http://bnox-webhook.local` that proxies ALL traffic to the daemon (no path matcher on the Caddy side). Two reasons: (1) the vhost is dedicated to the receiver anyway, so a path matcher is redundant — the handler validates the URL path and 404s non-matching paths; (2) the literal Caddy glob `/*` in `/bnox/webhook/*` triggers a false-positive match on the spec's comment-scan regex `/\*` (it's a Caddy path wildcard, not a C comment), and a dedicated vhost with no path matcher avoids it cleanly. The `http://` prefix (not HTTPS) avoids Caddy attempting Let's Encrypt provisioning against the placeholder `.local` domain at runtime; production overrides with a real HTTPS domain (documented per-host; Tailscale Funnel is the non-public-host path per D-011). The vhost evaluates clean on bnox-dev (Caddy accepts arbitrary addresses).

### Validation output

- **Comment/description scan:** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → exit 1 (no matches; hard constraint met). Also `rg -n '#' modules/deployment/webhook-receiver.nix` → exit 1 (no `#` anywhere, including inside the embedded Python and shell strings).
- **`nix flake check`:** passes — only the benign cross-system warning (`x86_64-linux` omitted on aarch64-darwin) + the unchanged `unknown flake output 'profiles'/'hardware'` notes, identical to Jobs 01–08.
- **`nix flake show`:** outputs unchanged — `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`.

**Throwaway `nixosSystem` eval (x86_64-linux, `bnox.nixosModules.bnox` + stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`, TWO enabled things `thing-a` + `thing-b` with mock `.bnox/` fixtures):**
- `bnox.secrets.fileSlots` = `{ "thing-a/api_key" = {owner="thing-a";group="thing-a";restartUnits=["podman-thing-a-web"];}; "thing-a/webhook_secret" = {owner="thing-a";group="thing-a";restartUnits=[];}; "thing-b/webhook_secret" = {owner="thing-b";group="thing-b";restartUnits=[];}; }` — per-thing iteration confirmed.
- `users.users.bnox-webhook-receiver.extraGroups` = `[ "thing-a" "thing-b" ]` — receiver joins BOTH thing groups.
- tmpfiles secrets rules = `[ "d /var/lib/bnox/secrets 0755 root root -" "d /var/lib/bnox/secrets/thing-a 0750 thing-a thing-a -" "d /var/lib/bnox/secrets/thing-b 0750 thing-b thing-b -" ]` — ONE rule per thing dir, no collision (thing-a has two slots yet one rule).
- `builtins.hasAttr "bnox-webhook-receiver" systemd.services` = `true`; `builtins.hasAttr "bnox-nats-stream-init" systemd.services` = `true`.
- `services.caddy.virtualHosts."http://bnox-webhook.local".extraConfig` = `"reverse_proxy 127.0.0.1:8842\n"`.
- `failedAssertions` = 0.

**`bnox-dev` regression (full stack via `nix eval .#nixosConfigurations.bnox-dev.config.*`):**
- Receiver service: `Type="simple"`, `User="bnox-webhook-receiver"`, `Group="bnox-webhook-receiver"`, `Restart="on-failure"`, `NoNewPrivileges=true`, `ProtectSystem="strict"`, `RestrictAddressFamilies=["AF_INET","AF_INET6"]`, `ReadWritePaths="/var/lib/bnox-webhook-receiver"`, `wantedBy=["multi-user.target"]`, `after=["network.target"]`, `path` includes `natscli-0.4.0`, `environment={BNOX_WEBHOOK_HOST="127.0.0.1"; BNOX_WEBHOOK_PORT="8842";}`, `ExecStart="${python3}/bin/python3 ${bnox-webhook-receiver.py}"`.
- Stream-init oneshot: `wantedBy=["multi-user.target"]`, `after=["nats.service"]`, `requires=["nats.service"]`, `Type="oneshot"`, `RemainAfterExit=true`, script resolves `natscli` + the `host-deploy-logs.json` store path.
- Caddy webhook vhost `"http://bnox-webhook.local".extraConfig` = `"reverse_proxy 127.0.0.1:8842\n"`.
- fileSlots = `{ "demo/api_key" = {owner="demo";group="demo";restartUnits=["podman-demo-web"];}; "demo/webhook_secret" = {owner="demo";group="demo";restartUnits=[];}; }` — `demo/api_key` UNCHANGED, `demo/webhook_secret` ADDED.
- Receiver user: `isSystemUser=true`, `group="bnox-webhook-receiver"`, `home="/var/lib/bnox-webhook-receiver"`, `createHome=true`, `extraGroups=["demo"]`. Receiver group exists.
- Demo regression byte-identical to Job 08 sign-off: container `demo-web` `{image="demo-web:current";user="demo";environmentFiles=["/var/lib/bnox/secrets/demo/api_key"];ports=["127.0.0.1:8080:8080"];}`; caddy `demo.local.extraConfig="reverse_proxy 127.0.0.1:8080\n"`; `podman-demo-web.serviceConfig.ReadWritePaths="/var/lib/demo /var/lib/bnox/secrets/demo"`, `ProtectSystem="strict"`; loader output `demo.components.web={domain="demo.local";enable=true;ingressPort=8080;natsSubject=null;runtime="container";secrets=["api_key"];shape="webapp"}`; tmpfiles has ONE `demo` dir rule; `failedAssertions=0`.

### For the checker to focus on

1. **The `webhook_secret` owner/group deviation (the load-bearing one).** owner/group = the THING's user (not `bnox-webhook-receiver`), with the receiver added to each thing's group via `extraGroups`. This is FORCED by the tmpfiles parent-dir collision (two different owners for the same `<thing>/` dir → two non-dedupable tmpfiles rules → last-wins ownership → breaks the thing's own container). The only alternative would be modifying `modules/secrets/backends/file.nix` to dedupe by path-without-owner, which is forbidden. Please confirm (a) the collision is real (reproduced via the dedup logic in `backends/file.nix:30-43`), (b) the consistent-owner fix eliminates it (verified: one rule per thing dir), and (c) the receiver can actually read the secret via group traversal (`0750 <thing>:<thing>` + receiver in group `<thing>` + operator-created file at 0640/0644).
2. **Daemon over socket activation.** The spec preferred socket activation; I used the daemon fallback due to fd-wiring uncertainty I couldn't runtime-verify on darwin (`StandardOutput=socket` for the `@.service` template). Please confirm the daemon choice is acceptable per the spec's escape clause + D-013's "ONE global service legitimately in the event path" blessing. If the checker wants socket activation pursued, that's a runtime-verification follow-up (needs a linux host), not an eval-fixable item here.
3. **Python over shell.** HTTP/HMAC robustness. The handler is inline via `pkgs.writeText` (no `bnox` package). Confirm no `bnox` CLI was introduced (choice 3) and `nats` CLI is on the service `path` only (not `environment.systemPackages`).
4. **The Caddy vhost proxies ALL traffic** (no `/bnox/webhook/*` path matcher) to avoid the `/*` comment-scan false positive. The handler does path validation. Confirm this is semantically equivalent for a dedicated vhost.
5. **Stream-init oneshot correctness** — the idempotent check-then-add/update loop + the `nats stream add --config <json> --defaults` / `nats stream update --config <json>` invocations are runtime-deferred (can't test `nats` CLI behavior on darwin); please sanity-check the `nats` CLI flags against the `natscli` docs if concerned. The stream config JSON and the `after/requires nats.service` wiring are eval-verified.

---

## Worker notes — iteration 2 (NEEDS-FIX remediation, 2026-07-31)

**Blocking issue addressed:** deviation 1 (checker ruling lines 193-222). The iter-1 `webhook_secret` scheme (`fileSlots."<thing>/webhook_secret"` with `owner=group=<thing>` + `users.users.bnox-webhook-receiver.extraGroups = thingNames`) was rejected on isolation grounds: it joined the most internet-exposed service into every thing's primary group, granting group-read on each thing's HOME + secrets dir (including `api_key` whenever the operator creates secrets group-readable, which the scheme itself required for `webhook_secret`). Adopted the checker's prescribed separate-deploy-namespace fix verbatim.

### Fix applied (5 edits to `modules/deployment/webhook-receiver.nix`, exactly per checker lines 208-218)

1. **Dropped** `webhookFileSlots` (the `builtins.listToAttrs` block), `thingNames`, and `config.bnox.secrets.fileSlots = webhookFileSlots;`. The module no longer consumes `fileSlots` at all.
2. **Dropped** `extraGroups = thingNames;` from the receiver user. The receiver joins NO thing group.
3. **Added** the webhook module's OWN tmpfiles for a separate `/var/lib/bnox/deploy/` namespace (in the first `mkMerge` attrset): top-level `d /var/lib/bnox/deploy 0755 root root -` (only when ≥1 enabled thing) + per-thing `d /var/lib/bnox/deploy/<thing> 0750 bnox-webhook-receiver bnox-webhook-receiver -`.
4. **Changed** `SECRETS_ROOT` in the Python handler from `/var/lib/bnox/secrets` to `/var/lib/bnox/deploy`. Per-thing secret path is now `/var/lib/bnox/deploy/<thing>/webhook_secret`.
5. **No change** to `ReadWritePaths` (`/var/lib/bnox-webhook-receiver`) — confirmed reads work under `ProtectSystem=strict` (strict blocks writes, not reads); the receiver owns the deploy dirs and reads as owner.

`enabledThingsList` kept (drives the tmpfiles iteration); `thingNames` dropped (was only used by `extraGroups`).

### Before / after (the relevant config)

**Before (iter 1):**
```nix
users.users.${receiverUser} = { ...; extraGroups = thingNames; };
bnox.secrets.fileSlots = webhookFileSlots;          # "<thing>/webhook_secret" owner=<thing>
# SECRETS_ROOT = "/var/lib/bnox/secrets"
```
**After (iter 2):**
```nix
users.users.${receiverUser} = { ...; };             # no extraGroups
systemd.tmpfiles.rules =
  lib.optional (enabledThingsList != [ ]) "d /var/lib/bnox/deploy 0755 root root -"
  ++ map (thing: "d /var/lib/bnox/deploy/${thing.name} 0750 ${receiverUser} ${receiverGroup} -") enabledThingsList;
# SECRETS_ROOT = "/var/lib/bnox/deploy"
```

Net: webhook secrets live in a deploy-layer namespace the webhook module owns outright; the receiver no longer touches the secrets backend, joins no thing group, and cannot reach any thing's `api_key` or HOME files. Operator drops the secret at `/var/lib/bnox/deploy/<thing>/webhook_secret` at any mode ≥ 0400 owner-readable (the receiver is the owner; no group-readable requirement, no chmod caveat). Strictly simpler than iter 1 (dropped `extraGroups` wiring + the operator-must-chmod-group-readable footnote).

### Re-validation output

- **Comment/description scan:** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → exit 1 (clean).
- **`nix flake check`:** passes (only the benign cross-system `x86_64-linux` warning + unchanged `unknown flake output 'profiles'/'hardware'` notes, identical to iter 1 + Jobs 01–08).
- **`nix flake show`:** outputs unchanged (`nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`).

**Throwaway two-thing eval** (thing-a with `api_key`; thing-b with no secrets; mock `.bnox/` fixtures):
```
fileSlots = { thing-a/api_key {owner,group=thing-a; restartUnits=[podman-thing-a-web];} }   # NO webhook_secret anywhere
receiverExtraGroups = [ ]                                                                      # joins NO thing group
deployTmpfiles = [ "d /var/lib/bnox/deploy 0755 root root -",
                   "d /var/lib/bnox/deploy/thing-a 0750 bnox-webhook-receiver bnox-webhook-receiver -",
                   "d /var/lib/bnox/deploy/thing-b 0750 bnox-webhook-receiver bnox-webhook-receiver -" ]
secretsTmpfiles = [ "d /var/lib/bnox/secrets 0755 root root -",
                    "d /var/lib/bnox/secrets/thing-a 0750 thing-a thing-a -" ]                 # thing-b has no secrets-namespace slot
failedAssertions = 0
```
No collision possible (deploy + secrets are disjoint parent paths); receiver owns ONLY deploy dirs.

**bnox-dev regression:**
```
fileSlots = { demo/api_key {owner,group=demo; restartUnits=[podman-demo-web];} }              # REVERTED to Job 08 (demo/webhook_secret GONE)
receiverExtraGroups = [ ]                                                                      # empty
tmpfiles includes: "d /var/lib/bnox/deploy 0755 root root -"
                   "d /var/lib/bnox/deploy/demo 0750 bnox-webhook-receiver bnox-webhook-receiver -"   # NEW, owned by receiver
                   "d /var/lib/bnox/secrets 0755 root root -"                                           # unchanged
                   "d /var/lib/bnox/secrets/demo 0750 demo demo -"                                      # unchanged, ONE rule
demoContainer = {image="demo-web:current"; user="demo"; environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]; ports=["127.0.0.1:8080:8080"];}  # UNCHANGED
demoCaddy."demo.local".extraConfig = "reverse_proxy 127.0.0.1:8080\n"                                  # UNCHANGED
webhookCaddy."http://bnox-webhook.local".extraConfig = "reverse_proxy 127.0.0.1:8842\n"               # present
demo.components.web = {domain="demo.local"; enable; ingressPort=8080; natsSubject=null; runtime="container"; secrets=["api_key"]; shape="webapp";}  # byte-identical to Job 08
receiverService = {User,Group="bnox-webhook-receiver"; ProtectSystem="strict"; ReadWritePaths="/var/lib/bnox-webhook-receiver"; ...}  # UNCHANGED
streamInit = {Type="oneshot"; RemainAfterExit=true; after,requires=["nats.service"];}                  # present
failedAssertions = 0
```

All other iter-1 decisions stand unchanged (daemon over socket activation; Python over shell; per-request HMAC read → no restart needed; host-deploy-logs via oneshot — declarative unsupported in nixpkgs 26.05; Caddy dedicated vhost proxying all traffic). The only delta from iter 1 is the webhook-secret namespace move.

## Checker notes

**Verdict: NEEDS-FIX** (one issue — deviation 1; everything else PASS). Independent checker, iteration 1, 2026-07-31. The tmpfiles collision the worker identified is REAL and severe (reproduced below — the spec's literal `owner=bnox-webhook-receiver` emits two conflicting dir rules and BREAKS the thing's own container). The worker's consistent-owner fix eliminates the collision correctly. **However**, the chosen remediation (owner = the thing's user + receiver joined to EVERY thing's primary group via `extraGroups`) is a systemic privilege widening for the single most internet-exposed service, contradicts the spec's own framing ("the webhook secret is bnox-side plumbing, NOT thing-intrinsic"), and has a cleaner in-scope fix the worker did not consider. Ruling: adopt the separate-deploy-namespace fix (prescribed in detail below). Deviation 2 (Caddy no-matcher) is acceptable. All other checklist items PASS with reproduced validation.

### Checklist results

1. **Scope — PASS.** `git diff HEAD --stat -- modules/` = exactly 3 files: `modules/default.nix` (+1 import), `modules/deployment/default.nix` (new, 5 lines), `modules/deployment/webhook-receiver.nix` (new, 204 lines). `modules/platform/nats.nix`, `modules/things/*`, `modules/secrets/*`, `modules/base/*`, `modules/profiles/*`, `modules/hardware/*`, `lib/*`, `home/*`, `flake.nix` UNTOUCHED. (A `design/STATUS.md` one-line status bump is a design doc, not a constrained file — fine.)
2. **No comments / no descriptions — PASS.** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → exit 1 (no matches). Independently confirmed no stray `#` anywhere in the handler source (including embedded Python + shell strings): `rg -n '#' modules/deployment/webhook-receiver.nix` → exit 1.
3. **D-011/D-013 fidelity — PASS.** (a) ONE global `bnox-webhook-receiver` service — no per-thing receivers (`webhook-receiver.nix:141`). (b) Publishes ONLY `host.deploy.<thing>.changed` (`webhook-receiver.nix:73`) — no subscribe/sync/build/dispatch. (c) No rollback. (d) Choice 3 honored: no `bnox` CLI; handler inline via `pkgs.writeText` (`webhook-receiver.nix:97,153`); `nats` CLI on service `path = [ natsCli ]` only (`webhook-receiver.nix:148`) — the worker added it ONLY to the service path. (`natscli` does appear in `environment.systemPackages` but that is PRE-EXISTING from `modules/base/system.nix:14` — not introduced by this job; not a regression.)
4. **fileSlots wiring — structurally correct (owner is the deviation, see below).** Per-thing `webhook_secret` slot emitted via `enabledThingsList` mirror of `container.nix:5-7` (`webhook-receiver.nix:110-125`); `restartUnits = []` matches per-request read (`webhook-receiver.nix:122`).
5. **Receiver user — created; extraGroups is the deviation.** `bnox-webhook-receiver` system user + group present (`webhook-receiver.nix:132-139`); `extraGroups = thingNames` (`webhook-receiver.nix:137`) is deviation 1.
6. **Stream-init oneshot — PASS.** `mkIf (config.services.nats.enable && config.services.nats.jetstream)` gated (`webhook-receiver.nix:127,175`); `after/requires nats.service` (`:178-179`); idempotent check-then-add/update loop (`:186-199`); `nats` CLI resolvable via `path = [ natsCli ]` + `natscli.meta.mainProgram = "nats"` (confirmed). **Declarative-stream-impossibility claim VERIFIED:** fetched the pinned-rev nixpkgs nats module (`3497aa5c9457…/nixos/modules/services/networking/nats.nix`); its option surface is exactly `enable/user/group/serverName/jetstream/port/dataDir/settings/validateConfig`; `settings` is a freeform JSON blob that becomes the server config and `jetstream` only sets `store_dir` — there is NO option for declarative JetStream stream contents. Oneshot is the only path; `modules/platform/nats.nix` correctly left untouched. (The `nats stream add --config <json> --defaults` / `nats stream update --config <json>` flags are runtime-deferred — untestable on darwin — but match natscli conventions.)
7. **Caddy vhost — PASS (deviation 2, see ruling).** Reverse-proxies to `127.0.0.1:8842` (`webhook-receiver.nix:168-170`); confirmed `reverse_proxy 127.0.0.1:8842\n` on bnox-dev.
8. **Handler correctness — PASS.** Read the Python end-to-end. Thing regex `^[a-zA-Z0-9_-]+$` (`:19`, applied `:38`) blocks traversal. Header lookup is case-insensitive via `BaseHTTPRequestHandler`'s `HTTPMessage` (`:43`). Signature normalization `signature.split("=",1)[-1]` (`:53`) handles BOTH `sha256=<hex>` (GitHub `X-Hub-Signature-256`) and bare `<hex>` (Forgejo `X-Forgejo-Signature`). `hmac.compare_digest` constant-time (`:55`). `nats pub` via `subprocess.run(check=True, timeout=15)` → 502 on failure (`:72-81`). Response codes 200/401/404/502 all correct (`:35,39,45,51,56,80,82`); normalized envelope `{thing,ref,before,after,repo,head_commit}` with null defaults (`:63-70`); `Connection: close` + `Content-Length` per response (`:28-29`). **Robustness gaps (acceptable day-1, non-blocking):** single-threaded `HTTPServer` (`:90`) queues concurrent webhooks (volume is a handful/hour — fine; swap to `ThreadingHTTPServer` later if needed); `log_message` suppressed (`:84-85`) means failed-auth (401) leaves no local trace (audit for successes still flows to `host-deploy-logs`); no explicit max-body cap (bounded by Content-Length; Caddy fronts it).
9. **Receiver hardening — PASS on the unit, FAIL on the privilege posture (deviation 1).** Unit hardening is solid: `ProtectSystem=strict` + `ProtectHome=true` + `PrivateTmp=true` + `NoNewPrivileges=true` + `ReadWritePaths=/var/lib/bnox-webhook-receiver` + `RestrictAddressFamilies=[AF_INET,AF_INET6]` (`webhook-receiver.nix:156-164`). Reads ARE allowed under `ProtectSystem=strict` (strict blocks writes, not reads) — which is exactly why deviation 1's group-traversal grants real read access (cross-reference below).
10. **Validation reproduction — PASS** (outputs pasted below; `nix flake check`, `nix flake show`, throwaway two-thing eval, bnox-dev regression all reproduced; collision-probe reproduced both the bug and the fix).

### Deviation 1 — DETAILED RULING: NEEDS-FIX

**(a) Collision is REAL and severe (reproduced).** `modules/secrets/backends/file.nix:31-42` dedupes tmpfiles rules via exact-string `lib.unique` on the FULL rule string. A thing with both `<thing>/api_key` (owner `<thing>`) and `<thing>/webhook_secret` produces two rules for `/var/lib/bnox/secrets/<thing>/`. **Counterfactual probe** (forced `demo/webhook_secret` owner to `bnox-webhook-receiver`) emitted:
```
"d /var/lib/bnox/secrets/demo 0750 demo demo -"
"d /var/lib/bnox/secrets/demo 0750 bnox-webhook-receiver bnox-webhook-receiver -"
```
Two non-dedupable rules for the SAME dir → systemd-tmpfiles applies both, last-wins → dir ends up owned by the receiver → demo's container (runs as `demo`) **cannot traverse its own secrets dir** → `api_key` read fails → container broken. The worker's consistent-owner fix (`owner=group=<thing>`) makes both slots emit the identical string → `lib.unique` dedupes to ONE rule (verified: bnox-dev + throwaway both show exactly one `d …/demo 0750 demo demo -`). **Diagnosis correct; the spec's literal `owner=bnox-webhook-receiver` is unviable as-is.**

**(b) Security consequence of the chosen fix — NOT acceptable.** `users.users.bnox-webhook-receiver.extraGroups = thingNames` (`webhook-receiver.nix:137`) puts the receiver into EVERY enabled thing's primary group. What that grants: traversal (`x`) + group-read of group-readable files under `/var/lib/<thing>/` (thing HOME, `0750 <thing>:<thing>` per `user.nix:11`) AND `/var/lib/bnox/secrets/<thing>/` (`0750 <thing>:<thing>` per `file.nix:39`). That includes the thing's OWN secrets (e.g. `api_key`) whenever the operator creates them group-readable (0640/0644) — and the receiver scheme ITSELF requires `webhook_secret` to be group-readable (0640+), else the receiver can't read it and every webhook 401s. The receiver is the single most internet-exposed service in bnox (accepts webhooks, parses untrusted JSON in Python `http.server`); an RCE there = read of all group-readable thing secrets across ALL things. This directly works against the Q9.6/Q9.7 isolation intent and the spec's own line 46: *"the webhook secret is bnox-side plumbing … NOT thing-intrinsic."* Putting deploy plumbing inside the thing secrets dir + joining thing groups is architecturally misaligned with that framing.

**(c) Ruling: NEEDS-FIX — adopt the separate-deploy-namespace fix.** The worker's reasoning ("I could not modify `backends/file.nix`, so consistent ownership from the consumer side is the only fix") is **incomplete**: it conflates "can't touch the secrets backend" with "must use `fileSlots` at all." Neither is required. The webhook secret is deploy-layer plumbing, so it belongs in a deploy-layer namespace the webhook module owns. This is within Job 09 scope (the webhook module may emit its own `systemd.tmpfiles.rules` + read its own paths), is ~10 lines, and is strictly SIMPLER than the current scheme (drops the `extraGroups` wiring and the operator-must-chmod-group-readable caveat — aligning with the "just basics" guardrail rather than fighting it).

**Prescribed fix (execute in iteration 2):**

In `modules/deployment/webhook-receiver.nix`:
1. **Drop** `webhookFileSlots` (`:116-125`), `thingNames` (`:114`), and `bnox.secrets.fileSlots = webhookFileSlots;` (`:172`). The module no longer consumes `fileSlots`.
2. **Drop** `extraGroups = thingNames;` from the receiver user (`:137`). Receiver joins NO thing group.
3. **Add** the webhook module's OWN tmpfiles for a separate namespace (in the first `mkMerge` attrset):
   ```nix
   systemd.tmpfiles.rules =
     lib.optional (enabledThingsList != [ ]) "d /var/lib/bnox/deploy 0755 root root -"
     ++ map (thing: "d /var/lib/bnox/deploy/${thing.name} 0750 ${receiverUser} ${receiverGroup} -") enabledThingsList;
   ```
4. **Change** `SECRETS_ROOT` in the handler (`:17`) from `/var/lib/bnox/secrets` to `/var/lib/bnox/deploy`. Per-thing path becomes `/var/lib/bnox/deploy/<thing>/webhook_secret`.
5. No change to `ReadWritePaths` (`:160`): reads are allowed under `ProtectSystem=strict`; the receiver owns the deploy dirs and reads as owner.

Result: no tmpfiles collision (different parent path entirely); receiver reads ONLY its own webhook secrets (cannot reach `api_key` or thing HOME files); no group cross-membership; operator drops the file at any mode ≥ 0400 owner-readable. This also removes the only path by which the most-exposed service touches thing-isolation boundaries.

(Alternative, lesser fix if the namespace move is rejected: keep `fileSlots` but re-key to `deploy/<thing>` so the parent dir is `/var/lib/bnox/secrets/deploy/<thing>` owned by the receiver — still no collision, still no group widening, but pollutes the secrets namespace conceptually. The separate `/var/lib/bnox/deploy/` namespace is preferred.)

### Deviation 2 — RULING: ACCEPTABLE (PASS)

Dedicated vhost `http://bnox-webhook.local` proxying ALL traffic to the daemon (`webhook-receiver.nix:168-170`) is semantically equivalent to a `/bnox/webhook/*` matcher for a dedicated vhost: the handler validates the path (`:34-40`) and 404s non-matching paths, so behavior is identical. The `http://` (not HTTPS) scheme is the right placeholder for `bnox-dev` (a `.local` hostname would make Caddy attempt LE provisioning at runtime; real deployment overrides with a real domain or Tailscale Funnel per D-011). The `/*` comment-scan false-positive argument is valid but secondary. No change required.

### Reproduced validation output

`nix flake check`:
```
checking NixOS module 'nixosModules.bnox'...
checking NOS module 'nixosModules.bnox-base'...
checking NixOS configuration 'nixosConfigurations.bnox-dev'...
warning: unknown flake output 'profiles' / 'hardware'
warning: The check omitted these incompatible systems: x86_64-linux
```
(passes — identical warnings to Jobs 01–08.)

`nix flake show`: `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib` — unchanged.

**Collision probe** (counterfactual — see deviation 1a):
```
workerFix_ownerIsDemo:       [ "d /var/lib/bnox/secrets 0755 root root -", "d /var/lib/bnox/secrets/demo 0750 demo demo -" ]
specLiteral_ownerIsReceiver: [ "d /var/lib/bnox/secrets 0755 root root -", "d /var/lib/bnox/secrets/demo 0750 demo demo -", "d /var/lib/bnox/secrets/demo 0750 bnox-webhook-receiver bnox-webhook-receiver -" ]
```

**Throwaway two-thing eval** (thing-a with `api_key`+`webhook_secret`; thing-b with `webhook_secret` only):
```
fileSlots = { thing-a/api_key {owner,group=thing-a; restartUnits=[podman-thing-a-web];},
              thing-a/webhook_secret {owner,group=thing-a; restartUnits=[];},
              thing-b/webhook_secret {owner,group=thing-b; restartUnits=[];} }
receiverExtraGroups = [ "thing-a" "thing-b" ]
tmpfilesSecretsRules = [ "d /var/lib/bnox/secrets 0755 root root -",
                         "d /var/lib/bnox/secrets/thing-a 0750 thing-a thing-a -",   # ONE rule despite 2 slots
                         "d /var/lib/bnox/secrets/thing-b 0750 thing-b thing-b -" ]
hasReceiverService=true  hasStreamInit=true  hasCaddyVhost=true  failedAssertions=[]
```

**bnox-dev regression**:
```
fileSlots = { demo/api_key {owner,group=demo; restartUnits=[podman-demo-web];}     # UNCHANGED
              demo/webhook_secret {owner,group=demo; restartUnits=[];} }            # ADDED
tmpfilesSecretsRules = [ "…secrets 0755 root root -", "d …/secrets/demo 0750 demo demo -" ]  # ONE rule
demoComponent = {domain="demo.local"; enable; ingressPort=8080; natsSubject=null; runtime="container"; secrets=["api_key"]; shape="webapp";}  # byte-identical to Job 08
demoContainer = {image="demo-web:current"; user="demo"; environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]; ports=["127.0.0.1:8080:8080"];}  # UNCHANGED
receiverServiceConfig = {Type="simple"; User,Group="bnox-webhook-receiver"; ProtectSystem="strict"; ReadWritePaths="/var/lib/bnox-webhook-receiver"; RestrictAddressFamilies=[AF_INET,AF_INET6]; NoNewPrivileges; PrivateTmp; ProtectHome; Restart="on-failure";}
receiverExecStart = "${python3-3.13.14}/bin/python3 ${bnox-webhook-receiver.py}"
receiverPath includes natscli-0.4.0  (NOT added to environment.systemPackages by this job — pre-existing in base/system.nix)
receiverUser = {isSystemUser; group="bnox-webhook-receiver"; home="/var/lib/bnox-webhook-receiver"; extraGroups=["demo"]}
caddyVhost."http://bnox-webhook.local".extraConfig = "reverse_proxy 127.0.0.1:8842\n"
failedAssertions = []
```

## Sign-off
NEEDS-FIX — iteration 1, 2026-07-31. Single blocking issue: deviation 1 (receiver joined to every thing's primary group) — adopt the prescribed separate `/var/lib/bnox/deploy/<thing>/webhook_secret` namespace (webhook module's own tmpfiles, owner=receiver, drop `fileSlots` + `extraGroups`). All other items PASS; deviation 2 acceptable. Re-review after iteration 2.

---

## Checker notes — iteration 2 (NEEDS-FIX remediation review, 2026-07-31)

**Verdict: PASS.** Independent checker, iteration 2, 2026-07-31. The worker executed the prescribed separate-deploy-namespace fix verbatim (all 5 edits applied exactly, no deviation from the prescription). The receiver no longer touches the secrets backend, joins no thing group, and cannot reach any thing's secrets or HOME. All iteration-1 PASS items remain PASS (handler, hardening, Caddy vhost, stream-init, D-011/D-013 fidelity, choice 3). Reproduced `nix flake check`, `nix flake show`, comment scan, two-thing throwaway, and the bnox-dev regression independently. No new issues found. Security goal of the fix confirmed (below).

### Prescribed-fix re-check (webhook-receiver.nix, current source)

1. **`webhookFileSlots` / `thingNames` / `bnox.secrets.fileSlots = …` GONE — PASS.** No `fileSlots` reference anywhere in the module (let-binding now only `enabledThingsList` `:110-112` + `natsReady` `:114`). Both evals report `fileSlotsHasWebhook = false`.
2. **`extraGroups = thingNames;` GONE — PASS.** Receiver user (`:119-124`) has no `extraGroups`. Both evals report `receiverExtraGroups = []`.
3. **OWN `systemd.tmpfiles.rules` for `/var/lib/bnox/deploy/` — PASS.** `:127-129`: top-level `d /var/lib/bnox/deploy 0755 root root -` guarded by `lib.optional (enabledThingsList != [ ])` + per-thing `d /var/lib/bnox/deploy/<thing> 0750 ${receiverUser} ${receiverGroup} -`.
4. **`SECRETS_ROOT = /var/lib/bnox/deploy` — PASS.** `:17` (handler reads `/var/lib/bnox/deploy/<thing>/webhook_secret`).
5. **`ReadWritePaths` unchanged — PASS.** `/var/lib/${receiverUser}` (`:150`).
6. **No dangling references — PASS.** `enabledThingsList` consumed by the tmpfiles map; `thingNames` removed entirely.

### Re-validation (independently reproduced)

- **Comment/description scan:** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment modules/default.nix` → exit 1 (clean).
- **Scope:** `git diff HEAD --stat -- modules/` = exactly 3 files (`modules/default.nix` +1, `modules/deployment/default.nix` new, `modules/deployment/webhook-receiver.nix` 192 lines, down from iter-1's 204 — consistent with the dropped bindings). No constrained path touched.
- **`nix flake check`:** passes (only benign `x86_64-linux` omission + `unknown flake output 'profiles'/'hardware'`, identical to Jobs 01–08).
- **`nix flake show`:** unchanged (`nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`).

**Two-thing throwaway eval** (thing-a w/ `api_key`; thing-b w/ none):
```
fileSlots          = { thing-a/api_key {owner,group=thing-a; restartUnits=[podman-thing-a-web];} }   # NO webhook_secret anywhere
fileSlotsHasWebhook = false
receiverExtraGroups = []                                                                              # joins NO thing group
deployTmpfiles = [ "d /var/lib/bnox/deploy 0755 root root -",
                   "d /var/lib/bnox/deploy/thing-a 0750 bnox-webhook-receiver bnox-webhook-receiver -",
                   "d /var/lib/bnox/deploy/thing-b 0750 bnox-webhook-receiver bnox-webhook-receiver -" ]
secretsTmpfiles = [ "d /var/lib/bnox/secrets 0755 root root -",
                    "d /var/lib/bnox/secrets/thing-a 0750 thing-a thing-a -" ]                        # thing-b has no secrets-namespace slot
namespacesDisjoint = true   hasReceiverService=true  hasStreamInit=true  hasCaddyVhost=true  failedAssertions=[]
```

**bnox-dev regression (load-bearing):**
```
fileSlots          = { demo/api_key {owner,group=demo; restartUnits=[podman-demo-web];} }             # REVERTED to Job 08; demo/webhook_secret GONE
fileSlotsHasWebhook = false
receiverExtraGroups = []                                                                              # empty
deployTmpfiles  = [ "d /var/lib/bnox/deploy 0755 root root -",
                    "d /var/lib/bnox/deploy/demo 0750 bnox-webhook-receiver bnox-webhook-receiver -" ]  # NEW, owned by receiver
secretsTmpfiles = [ "d /var/lib/bnox/secrets 0755 root root -",
                    "d /var/lib/bnox/secrets/demo 0750 demo demo -" ]                                  # ONE rule, no collision
namespacesDisjoint = true
demoContainer   = {image="demo-web:current"; user="demo"; environmentFiles=["/var/lib/bnox/secrets/demo/api_key"]; ports=["127.0.0.1:8080:8080"];}  # UNCHANGED Job 08
demoCaddyVhost  = "reverse_proxy 127.0.0.1:8080\n"                                                    # UNCHANGED
demoSvcReadWritePaths = "/var/lib/demo /var/lib/bnox/secrets/demo"  demoSvcProtectSystem = "strict"   # UNCHANGED
demoComponent   = {domain="demo.local"; enable; ingressPort=8080; natsSubject=null; runtime="container"; secrets=["api_key"]; shape="webapp";}  # byte-identical to Job 08
receiverService = {Type="simple"; User,Group="bnox-webhook-receiver"; ProtectSystem="strict"; ReadWritePaths="/var/lib/bnox-webhook-receiver"; RestrictAddressFamilies=[AF_INET,AF_INET6];}  # UNCHANGED
receiverExecStart = "${python3-3.13.14}/bin/python3 ${bnox-webhook-receiver.py}"   # store hash changed vs iter 1 (SECRETS_ROOT edit) — expected
hasStreamInit=true  hasCaddyWebhookVhost=true ("reverse_proxy 127.0.0.1:8842\n")  hasReceiverGroup=true  failedAssertions=[]
```

### Security confirmation (the point of the fix)

The receiver's reachable read surface is now scoped to ONLY its own deploy namespace:
- Owns `/var/lib/bnox/deploy/<thing>/` dirs (`0750 bnox-webhook-receiver:bnox-webhook-receiver`) → can read its own `webhook_secret` as owner. Intended.
- `extraGroups = []` → NOT a member of any thing's primary group.
- `/var/lib/bnox/secrets/<thing>/` is `0750 <thing>:<thing>` (`file.nix:39`); receiver is neither owner nor in group, dirs are not world-traversable (no `x` for other) → **CANNOT traverse or read** thing secrets (incl. `api_key`). Filesystem ACL denies access regardless of `ProtectSystem=strict` allowing reads in principle.
- `/var/lib/<thing>/` (thing HOME, `0750 <thing>:<thing>` per `user.nix:11`) → same denial; receiver cannot traverse or read thing HOME files.

**Conclusion: an RCE in the receiver no longer grants read of thing secrets or thing HOME files.** Blast radius is now limited to the webhook secrets in the receiver's own namespace. The iteration-1 privilege widening (receiver in every thing group) is fully eliminated. The tmpfiles collision that forced the iter-1 workaround cannot arise — deploy and secrets are disjoint parent paths (`namespacesDisjoint = true` in both evals).

### Iteration-1 standing items (unchanged, re-confirmed PASS)

Deviation 2 (Caddy dedicated vhost, no matcher, `http://` placeholder) — ACCEPTABLE. Daemon-over-socket (D-013 escape clause), Python-over-shell (choice 3 fallback), per-request HMAC read, stream-init oneshot (declarative JetStream impossible in nixpkgs 26.05 — re-verified last iteration), no `bnox` CLI, `nats` CLI on service `path` only — all stand. The handler store-path hash changed only because `SECRETS_ROOT` is embedded in the source string; behaviorally identical.

## Sign-off
PASS — iteration 2, 2026-07-31. Deviation 1 fixed exactly as prescribed (separate `/var/lib/bnox/deploy/` namespace, receiver owns it, `fileSlots` + `extraGroups` dropped); receiver can no longer reach thing secrets or HOME; tmpfiles collision structurally impossible (disjoint namespaces). All validation reproduced independently; zero failed assertions; bnox-dev demo regression byte-identical to Job 08. Ready for the lead to set Status = done. (Status field left unchanged per instruction.)
