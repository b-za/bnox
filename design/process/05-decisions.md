# Decisions

Append-only log of decisions made during this design process. New decisions go at the bottom. Never edit a prior entry; supersede with a new entry that references the old one.

## Format

```
## D-NNN — <short title>
**Date:** YYYY-MM-DD
**Status:** proposed | accepted | superseded by D-NNN | rejected
**Context:** <why this is being decided>
**Decision:** <what we chose>
**Alternatives considered:** <what else was on the table>
**Consequences:** <what this implies>
```

## Pending decisions (awaiting user)

These map to the blocking open questions in `design/working/open-questions.md`:

(All blocking questions resolved as of D-012. D-013 is a non-blocking refinement to D-011 §4's dispatch topology. Q6, Q8 remain non-blocking.)
---

## D-001 — Project name
**Date:** 2026-07-27
**Status:** accepted
**Context:** Working name was `baseos`. Needed a real name before locking the directory and flake name (Q1). Wanted something short, OS-flavoured, personal, and collision-free.
**Decision:** **`bnox`** — bh + nox (nix + night). Short, ends in OS-adjacent sound, distinctive.
**Alternatives considered:** `baseos` (placeholder, generic), `noxos` (taken — active NoxOS-org on GitHub), `snowi-os` (too tied to one host), `bhos`, `keystone`, `rootstockos`, `nyxos`. Collision check ruled out `noxos`. `bnox` GitHub search returns only 8 weak results (file organizer, dormant crypto token, IMU sensor part number BNOx) — none in the OS / Nix space.
**Consequences:** Directory is `/Users/bh/code/systems/bnox/`. Future flake will publish as `github:<user>/bnox`. The string `bnox` should appear in flake description, README title, hostname convention docs, and commit prefixes once code lands.

---

## D-002 — Container runtime and image-build policy
**Date:** 2026-07-27
**Status:** accepted
**Context:** The base needs one container runtime and one image-build convention. Source systems diverge: snowi-node runs Podman + quadlets and builds images via Nix (`dockerTools.streamLayeredImage`, `packages/webapp.nix`); uqbn has Docker with three compose stacks under `docker/` that have never meaningfully been used. Discovery established that uqbn's `docker/` content is non-essential and carries **no migration barrier** — the base starts fresh. User also raised a hard constraint: image builds must be deterministic, which rules out `docker build` / Dockerfiles entirely.

**Decision:**

1. **Runtime: Podman** as the base default, via `virtualisation.podman.enable = true`.
2. **Container declaration idiom: `virtualisation.oci-containers.containers`** (the runtime-agnostic NixOS abstraction), **not** raw quadlet text. `oci-containers` works under Podman today and under Docker tomorrow if a host ever needs it — flips with one option, no module rewrite.
3. **Image-build policy: Nix only.** All container images must be produced by `pkgs.dockerTools.*` (`streamLayeredImage`, `buildImage`, `buildLayeredImage`). **Dockerfiles and `docker build` are forbidden in the base and in any host module.** This is a hard determinism requirement, not a preference.
4. **`mkQuadlet` / `mkEnvFile` from `snowi-node/lib/default.nix` are NOT carried over.** They generate raw unit text, which duplicates what `oci-containers` already does in a typed way. Revisit only if we hit a case `oci-containers` cannot express.
5. **No runtime switch in the base.** Podman is the default; a host that genuinely needs Docker declares `virtualisation.docker.enable = true` locally. The base does not pre-install or pre-configure Docker.

**Alternatives considered:**

- **Docker as base default** — rejected: daemon model is a worse fit for the systemd-native skeleton we're adopting from snowi-node; gives us nothing we need.
- **Raw `mkQuadlet` helper from snowi-node** — rejected: less type-checked than `oci-containers`, and snowi-node itself is inconsistent (`modules/evolution-api.nix:60` already uses `oci-containers` alongside it). One idiom only.
- **Base supports both runtimes via a switch** — rejected: premature. Optionality already exists because `oci-containers` is runtime-agnostic; formalising a switch adds abstraction cost now for a need that may never appear.
- **Allow Dockerfiles for "one-off" images** — rejected by user constraint: non-deterministic builds are not acceptable in any form.

**Consequences:**

- Base flake inputs do **not** need a Docker-specific flake (uqbn currently pulls `portainer-flake`; bnox will not).
- The `lib/default.nix` inherited from snowi-node is slimmed: `mkQuadlet` dropped, `mkEnvFile` retained only if a secrets-manager decision (D-003) wants env files as the delivery format.
- Any future host wanting Portainer or a Docker-only image must justify it per-host, not in the base.
- Documentation (`design/process/06-base-design.md` and per-service docs) must state the "Nix-only images" rule explicitly so contributors don't reach for a Dockerfile.
- Reversibility: if Podman turns out wrong for some host, switching that host to Docker is a local change because `oci-containers` is runtime-agnostic. The base itself does not need to change.

---

## D-006 — Thing hosting architecture
**Date:** 2026-07-27
**Status:** accepted
**Context:** snowi-node today bundles OS config + 17 NATS services + 2–4 webapps + 2 static sites + shared infra in a single repo. User requires the OS layer (bnox) to be deployable **independently of the application layer** — a change to a webapp, static site, or NATS processor batch must NOT trigger `nixos-rebuild`. Each "thing" lives in its own repo, git-synced to the host; things can depend on each other. Hard constraint from user: **"just basics, not hectic over-engineered."**

**Decision:**

1. **Thing taxonomy — three orthogonal axes:**
   - **Provenance:** `first-party` (host owner builds & edits; git sync → rebuild) or `third-party` (external upstream; image pull on release).
   - **Shape:** `static-site` (no backend; served by Caddy `file_server`) · `webapp` (HTTP with UI) · `http-api` (REST or WebSocket; no UI) · `nats-api` (a batch of NATS services sharing a stream/subject tree; multi-service; coined term).
   - **Dependencies:** declared per-thing; bnox validates the graph.

2. **Per-thing bnox-side declaration has two pieces:**
   - **bnox-plumbing config** — what bnox needs to wire the thing into platform services (domain, ingress port, NATS subject prefix, deps). This is bnox-side integration; NOT the thing's own runtime config.
   - **secrets slot** — shape filled in by future D-007 (Q11 secrets architecture); slot exists regardless.

3. **Platform vs thing boundary:**
   - **Platform** (bnox-owned, single instance per host, no per-thing config): **Caddy**, **NATS + JetStream**, **Podman** (per D-002), **static-site web server** (bnox serves files via Caddy `file_server`; no per-site container).
   - **Things** (instance-configured, dependency-declaring): everything else — EvolutionAPI, xero-auth, Forgejo (if adopted), all webapps, all nats-apis, all http-apis. Each is first-party or third-party per axis 1.

4. **NATS subject layout:**
   - Top level reserved for host/ops/CQRS: **`host.>`** is bnox-owned.
   - Things live under reserved namespace: **`things.<name>.>`**.
   - The thing's repo owns everything beneath its prefix; bnox allocates the prefix and validates uniqueness across enabled things.

5. **One JetStream stream per thing**, filtered on `things.<name>.>`. Streams do not cross thing boundaries. Each thing has its own retention policy.

6. **Per-thing HTTP upstream port:** self-declared by the thing's repo; bnox fails evaluation on collision across enabled things.

7. **Dependency graph validation at rebuild time.** Each thing's `deps = [ ... ]` is asserted against the set of enabled things; missing dep = loud rebuild failure. Same data translated to systemd `After=`/`Requires=` for runtime ordering.

8. **Cross-thing stream access — start at L0:**
   - **L0 (day 1, built):** bnox validates dep graph + systemd ordering; NATS itself is open locally (any local process can subscribe to anything).
   - **L1 (future, additive, NOT built now):** per-thing NATS users restricted to `things.<self>.>`; cross-thing access via explicit grant derived from existing `deps` declarations.
   - **L2 (out of scope for base):** NATS accounts.
   - **The `deps` schema is designed so the L1 upgrade requires no schema change** — bnox just emits per-thing NATS creds from existing dep declarations.

**Alternatives considered:**

- **One repo for everything (snowi-node status quo):** rejected per user requirement — OS must be deployable independently.
- **Kubernetes / Nomad / Argo / Flux:** rejected per user constraint ("just basics, not hectic over-engineered").
- **Multiple NATS instances per thing:** rejected — wasteful; one shared instance with subject-prefix isolation is sufficient.
- **NATS accounts (L2) day 1:** rejected — over-isolation for single-user base.
- **bnox-allocated HTTP ports:** rejected — ports are a thing-internal concern; bnox just needs to know what to point Caddy at. Self-declaration is simpler; collision check covers the failure mode.
- **Convention-only dependency declaration (no evaluation-time validation):** rejected — silent runtime failures are worse than loud rebuild failures.
- **Static-site web server as a per-site thing:** rejected — bnox serving files via Caddy `file_server` is simpler; one fewer container per site.

**Consequences:**

- bnox provides a generic **"host a thing" abstraction** (`bnox.things.<name> = { ... }`) — this is the load-bearing piece of the application-layer hosting model.
- Each thing lives in its own repo, git-synced to a per-thing directory on the host.
- The thing's repo contains: code, Nix derivation building its image, its internal NATS sub-subject tree beneath its allocated prefix, its internal env file structure, its own runtime config.
- bnox validates: subject-prefix uniqueness, port uniqueness, dependency graph closure.
- Static sites need no per-site container — files served directly by Caddy.
- Per-thing NATS user management is NOT implemented now, but the `deps` field design must support emitting creds later without schema change.
- Migration of existing snowi-node content onto this model is governed by Q5 (D-005 migration scope) — NOT part of this decision.
- The deployment mechanism (git sync → build → reload) is governed by Q13 — NOT part of this decision.

**Still open (NOT covered by this decision):**

- **Q9.5 (new):** Where does the per-thing bnox-side declaration live — all in bnox host config (option a), all in thing's repo (option b), or hybrid (thing repo declares shape+deps; bnox host flips enable, option c)?
- **Q11 / D-007:** Secrets architecture — determines the shape of the `secrets` slot in the per-thing declaration.
- **Q13 / D-008:** Deployment mechanism — the git-sync/build/reload flow this architecture presupposes.

---

## D-007 — Secrets architecture (Hybrid-1 default, Hybrid-2-ready abstraction)
**Date:** 2026-07-27
**Status:** accepted
**Context:** User requires that changing a thing's secrets must NOT trigger a host rebuild. This rules out pure push-at-deploy (agenix or sops-nix alone), which decrypt at `nixos-rebuild` activation. The chicken-and-egg constraint (some secrets — host key, Caddy TLS, NATS auth — must be available before any runtime service can run) means a pure pull-at-runtime design is impossible: infra secrets must be push-at-deploy. The Q9.5 slot contract (thing declares slot names, host binds sources) is mechanism-agnostic and supports swappable backends. bnox is intended as a reusable base — different users may legitimately want different backends, so the choice must be config-time, not code-time.

**Decision:**

1. **Two-layer secrets architecture.**
   - **Infra layer** (host key, Caddy TLS, NATS auth, age key): push-at-deploy via **agenix**. Encrypted-in-git, decrypted at `nixos-rebuild` activation. Changes require a host rebuild; these secrets change rarely.
   - **Things layer** (per-thing app secrets): swappable backend, chosen at bnox config time per host.

2. **Things-layer backend is a config-time choice.** bnox ships with two backend implementations; users adopt whichever fits their setup:
   - **`file` backend (Hybrid-1, default):** secrets are plaintext files under `/var/lib/bnox/secrets/<thing>/<slot>`. A systemd-path unit watches each file; on change, the thing's container restarts. Update flow: operator writes the new value (via SSH, scp, or a small CLI), saves, systemd-path fires. No host rebuild.
   - **`nats-kv` backend (Hybrid-2, optional):** secrets stored in NATS KV under `secrets/things/<thing>/<slot>`, encrypted with the host key. A secrets-service daemon fetches on demand and on watch, decrypts, writes to local paths, restarts affected things. Update flow: write to NATS KV from any authenticated client. No host rebuild, no SSH required. **Designed-for, not built day-1.**

3. **Slot contract is identical across backends** (per Q9.5). Things declare slot names in `.bnox/`; bnox host config binds slots. The slot name is the key; the backend decides where the value comes from. Things and host configs do not change when backend changes.

4. **agenix chosen for infra layer** (closes Q3). Reasoning: SSH host key reuse fits the existing hardened-SSH setup; one-file-per-secret matches the existing per-thing env-file pattern; smaller surface area than sops-nix; off-the-shelf.

5. **Default backend = `file` (Hybrid-1).** Rationale: day-1 single-host; "just basics" guardrail (Q14); familiar pattern (matches snowi-node today, formalized with auto-reload); smallest build cost. NATS-KV's advantages only materialize with multi-host or centralised update needs.

**Alternatives considered:**

- **Pure push-at-deploy (agenix only):** rejected — violates user requirement that secret changes not trigger host rebuild.
- **Pure pull-at-runtime (NATS-KV only):** rejected — chicken-and-egg; infra secrets have no NATS to fetch from.
- **Custom push-without-rebuild tooling:** rejected — non-standard agenix workflow, custom work for marginal benefit.
- **sops-nix for infra layer:** rejected — agenix's SSH-host-key reuse is a better fit; sops-nix's extra features (KMS, templating) not needed.
- **Building the `nats-kv` backend day-1:** rejected — Q14 over-engineering guardrail; day-1 single-host doesn't justify ~200 LOC custom service. Designed-for is enough.

**Consequences:**

- bnox flake inputs: **+1 (agenix)**.
- bnox module structure: `secrets/` directory containing `infra.nix` (agenix wiring), `backends/file.nix` (default), `backends/nats-kv.nix` (scaffolded interface, not implemented).
- Per-thing: each enabled thing gets one or more systemd-path units watching its declared secret slots (under the `file` backend).
- Host config: `bnox.secrets.thingsBackend = "file"` (default) or `"nats-kv"` (when implemented).
- **Q3 resolved → agenix** for the infra layer.
- **Q11 resolved.**
- **Q12 still open** (host encryption key home) — tightly coupled; needs resolution before D-007 is fully implementable.
- Future D-NNN will specify the `nats-kv` backend implementation when multi-host or central-update becomes a real need.
- Migration of existing snowi-node secrets (currently plaintext at `/var/lib/`) is trivial under the `file` backend — same pattern, plus auto-reload.

---

## D-008 — Host encryption key home
**Date:** 2026-07-27
**Status:** accepted
**Context:** D-007 requires a host-level key to decrypt secrets — both agenix (infra layer) and the future `nats-kv` backend (things layer option). The original Q12 recommendation (plain file at `/var/lib/bnox/host-key`) was framed before D-007 picked agenix. With agenix, the simpler answer is to reuse the existing SSH host key.

**Decision:**

1. **Host encryption key = SSH host key** (`/etc/ssh/ssh_host_ed25519_key` by default). No separate bnox-managed key.
2. **agenix reads it via `age.sshKeyPaths`** (agenix's documented default pattern).
3. **Future `nats-kv` backend** (D-007 Hybrid-2) derives its decryption key from the same SSH host key via age. No second key.
4. **Provisioning:** SSH host key generated on first boot OR injected via `nixos-anywhere` at provisioning — matches snowi-node's existing pattern.
5. **Recovery:** every agenix-encrypted secret carries a **second age recipient** (a recovery key held off-host, e.g. on the operator's workstation or in a password manager). Lose the host key → re-encrypt against the recovery key on a new host. **Backups of `/etc/ssh/` are NOT the recovery path** — the recovery recipient is.
6. **Rotation:** rotating the SSH host key requires re-encrypting every agenix secret. Standard agenix pain; rare operation; documented procedure (regenerate SSH host key, update `.age` recipient list, re-encrypt all secrets, commit, rebuild).
7. **TPM path:** documented as a future hardware-host enhancement (laptop/desktop profile). VPS hosts have no TPM; out of scope day-1.

**Alternatives considered:**

- **Separate age key at `/var/lib/bnox/host-key`:** rejected — adds a key to provision/back up/rotate for no real isolation benefit on a single-host threat model (root compromise exposes both keys regardless).
- **TPM-sealed key:** rejected for day-1 — VPS hosts have no TPM. Documented as future hardware-host path.
- **Derived from a provisioning-time injected seed:** rejected — adds reproducibility complexity; the recovery recipient already covers key loss without this.
- **Backups of `/etc/ssh/` as recovery:** rejected as primary path — the recovery recipient is cleaner (off-host, no dependence on filesystem backup integrity).

**Consequences:**

- No new bnox-managed key files; one less moving part.
- `.sops.yaml`-equivalent for agenix (the `secrets.nix` or `rules.nix` file) must list both the host SSH key and the recovery key as recipients for every secret.
- Operator must generate and securely store one recovery age key (workstation-side) before first bnox deployment. This is the bootstrap cost.
- Q12 resolved.
- D-007 + D-008 together fully specify the secrets architecture for implementation.

---

## D-009 — Hermes agent deviation (Q14 escape hatch used)
**Date:** 2026-07-27
**Status:** accepted
**Context:** User wants to host a Hermes agent (Nous Research, MIT, v0.19.0) on the bnox system. Hermes is a long-running AI agent that connects outward to messaging platforms (Telegram, Discord, Slack, etc.) and LLM APIs. Its distribution model is fundamentally imperative: `curl|bash` install script, manages its own Python (via uv) and Node.js, downloads Playwright/Chromium, and **self-updates via `hermes update`**. Forcing it into a Nix-built container image would: break the auto-update model; require repackaging on every upstream release; require vendoring all Python deps, Playwright, Node, Chromium; be a multi-week effort that recurs every release. This is exactly the case the Q14 deviation clause ("a specific thing may deviate when it has a justified need; deviations are raised as an open question and logged as a decision before adoption") exists for.

**Decision:**

1. **Hermes is hosted as a `daemon`-shape thing with `host-install` runtime** (both new — see Q9.8 and Q9.9 below). It runs on host (not in a container), under a dedicated `hermes` user, managed by a systemd service that invokes Hermes' gateway.

2. **Deviation scope is narrow and explicit.** This decision authorises **only** that D-002's "images must be Nix-built via `dockerTools.*`" rule does not apply to Hermes. Every other decision (D-006 thing architecture, D-007 secrets via `file` backend, Q9.6 user isolation, Q9.7 hardening bundle, Q14 default ceiling for all other things) applies to Hermes unchanged.

3. **bnox's role for Hermes:**
   - Creates the `hermes` user (Q9.6).
   - Provides `$HERMES_HOME` at `/var/lib/hermes/`, owned by `hermes`.
   - Runs the upstream install script once (manually, at provisioning) under the `hermes` user — NOT via Nix derivation.
   - Provides a systemd unit `hermes.service` that runs the gateway as `hermes`, with the standard Q9.7 hardening bundle plus network egress to required destinations (HTTPS outbound, DNS).
   - Provides secrets via D-007 `file` backend at `/var/lib/bnox/secrets/hermes/<slot>`, chown'd to `hermes`.
   - Does NOT manage Hermes updates — `hermes update` is run by the operator (or a cron job) as the `hermes` user. bnox treats Hermes as a self-managing black box.

4. **Hermes manages its own:**
   - Code (git checkout at `/var/lib/hermes/hermes-agent/`)
   - Python virtualenv (managed by uv)
   - Node.js (downloaded by install script)
   - Playwright/Chromium
   - State, sessions, memory, skills (`$HERMES_HOME`)
   - Updates (`hermes update`)

5. **Justification logged per Q14:** Hermes' upstream distribution and auto-update model is the load-bearing fact. Fighting it with Nix packaging is a recurring multi-week cost. The deviation is visible (this entry) and scoped (only Hermes; only the image-build rule).

**Alternatives considered:**

- **Nix-package Hermes properly:** rejected — recurring multi-week effort every release; breaks `hermes update`; Playwright packaging is notoriously painful.
- **Container with non-Nix image build (Option B):** rejected — corrupts D-002 more broadly (the entire image build is non-deterministic, vs. just an install path on host); still breaks `hermes update` inside immutable image.
- **Don't host Hermes on bnox:** rejected — doesn't meet user's stated goal.

**Consequences:**

- D-002 unchanged for all things except Hermes.
- Hermes appears in bnox host config as a `daemon`-shape thing with `runtime = "host-install"`.
- Hermes receives the standard Q9.6 user isolation + Q9.7 hardening bundle. Network egress restricted to required destinations (HTTPS, DNS) via systemd `IPAddressDeny=any` + `IPAddressAllow=`.
- Hermes' subagent sandbox backends (Docker, SSH, Singularity, Modal) are restricted to `local` only — no Docker socket exposure, no SSH backend. Configured in Hermes' config, enforced by absence of those capabilities in the systemd unit.
- Operator runs `sudo -u hermes hermes update` periodically (or schedules it via systemd timer). bnox does not manage Hermes version.
- The deviation is reviewed if Hermes' distribution model changes (e.g. they ship a Nix derivation or pre-built reproducible images).

**Supporting refinements (locked alongside this decision):**

### Q9.8 — New shape: `daemon` (refinement to D-006, locked)

Locked alongside D-009. The shape taxonomy (D-006) gets a fifth entry: **`daemon`** — long-running stateful process; no inbound HTTP/NATS interface required; initiates outbound connections; may have its own state directory and update mechanism. Examples: AI agents (Hermes), bots, polling integrations, scheduled job runners. A thing can still be multi-component, so e.g. `daemon` + `http-api` is valid (background agent + HTTP control surface).

### Q9.9 — New runtime option: `host-install` (refinement to D-006, locked)

Locked alongside D-009. The thing-hosting abstraction (D-006) implied `oci-containers`. Refinement: each component has an orthogonal `runtime` field — `container` (default, Nix-built image per D-002) or `host-install` (thing manages its own installation in its user space, bnox provides only the user + systemd unit + secrets slot + hardening). `host-install` is rare and requires a Q14 deviation per thing; Hermes is the first.

### Q14 — Over-engineering guardrail (resolved)

**Resolved 2026-07-27.** Captured as NFR-6 in `design/process/03-requirements.md` (to be added):

> **NFR-6 — Deployment simplicity ceiling (default; deviations allowed with justification).** Default: application-layer deployment (per D-006) is implementable using only **Podman, systemd, git, and optionally Forgejo**. Per-thing overhead **≤ 3 systemd units** (container + git-sync + build-trigger). Rollback via `podman load` of prior image + `systemctl restart` — no separate rollback tooling. By default forbidden: Kubernetes, Nomad, Argo CD, Flux, Helm, any framework with its own control plane. **A specific thing may deviate** when it has a justified need; deviations are raised as an open question and logged as a decision (D-NNN) before adoption — not silent.

D-009 (Hermes) is the first use of this deviation clause.

---

## D-010 — NixOS version pin and channel choice
**Date:** 2026-07-27
**Status:** accepted
**Context:** bnox needs a pinned nixpkgs input. The original Q4 analysis (recommending 24.11 for parity with snowi-node) was written when 24.11 was current; as of 2026-07-27, both source systems run EOL NixOS (24.11 EOL'd 2025-06-30, 25.05 EOL'd 2025-12-31, 25.11 just EOL'd 2026-06-30). The only currently-supported stable release is 26.05. User confirmed: latest stable is the right choice unless there's a specific reason to stay on an old release — and there isn't.

**Decision:**

1. **NixOS version pin: `nixos-26.05`** (current stable).
   ```nix
   inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
   ```
2. **Channel: full (no `-small`).** `nixos-26.05-small` exists for pure-headless scenarios where the excluded packages (desktop apps, some bigger GUI things) are never needed; bnox is a general-purpose base and should not pre-emptively exclude packages.
3. **Bump cadence:** every 6 months when a new stable ships (next: 26.11 in ~Nov 2026), update the pin and rebuild. Standard NixOS hygiene.

**Alternatives considered:**

- **24.11 (snowi-node's pin):** rejected — EOL 13 months. The "production parity" argument that originally supported this is moot; snowi-node itself needs upgrading.
- **25.05 (uqbn's pin):** rejected — EOL 7 months.
- **25.11:** rejected — just went EOL.
- **`nixos-unstable` (rolling):** rejected — bleeding edge; not appropriate for a base OS that should be predictable.
- **`-small` channel:** rejected — excludes packages that might be needed (desktop profile, future things); fetch time isn't a real bottleneck with binary caches.

**Consequences:**

- bnox flake input pinned to `nixos-26.05`.
- snowi-node migration (if/when undertaken, per Q5) requires jumping 24.11 → 26.05 — two major releases of catch-up (24.11 → 25.05 → 25.11 → 26.05). Non-trivial; weighs against Option B in Q5.
- uqbn migration (if/when undertaken) requires jumping 25.05 → 26.05 — one major release. Easier; supports Option C in Q5.
- All other decisions (D-002, D-006, D-007, D-008, D-009) are version-agnostic and unaffected.
- Q4 + Q7 both resolved.

---

## D-011 — App-layer deployment mechanism
**Date:** 2026-07-27
**Status:** accepted
**Context:** D-006 specifies what a "thing" is and how bnox hosts it; Q13 specifies the **dynamic** flow — how a thing's code changes propagate from a git push to a running container without an OS rebuild (per the user's hard constraint). NFR-6 (Q14) caps complexity at ≤ 3 systemd units per thing, no orchestration frameworks. NATS already exists as platform infra (D-006), making an event-driven pipeline natural. Hermes (D-009) is explicitly excluded — it self-manages via `hermes update`.

**Decision:**

1. **Trigger mechanism: webhook + NATS event bus.** A single bnox-owned `bnox-webhook-receiver.service` receives push events from GitHub/Forgejo (via Caddy vhost) and publishes to NATS. Per-thing sync/build/container units subscribe to NATS subjects and execute their step, publishing progress as they go.

2. **Event subjects under `host.deploy.<name>.*`** (host-level, per D-006's reserved `host.>` namespace):
   - `host.deploy.<name>.changed` — webhook received
   - `host.deploy.<name>.synced` — git pull done (with new SHA)
   - `host.deploy.<name>.built` — image built and loaded (with image hash)
   - `host.deploy.<name>.deployed` — container restarted
   - `host.deploy.<name>.failed` — failure at any step (with reason)

3. **JetStream persistence** via `host-deploy-logs` stream filtered on `host.deploy.>` — full audit trail of every deployment across every thing. Subscribe to `host.deploy.>` for real-time visibility.

4. **Pipeline shape per thing** (3 functional units, fits NFR-6):
   - `<name>-sync.service` — subscribes to `.changed`; runs `git fetch && git reset --hard origin/main`; publishes `.synced`.
   - `<name>-build.service` — subscribes to `.synced`; runs `nix build` for each component's image, pipes to `podman load`; publishes `.built`; restarts container(s) via `systemctl restart`; publishes `.deployed`.
   - `<name>-container.service` (or N container services for multi-component) — the `oci-containers` entry itself; plain systemd service, no NATS awareness needed.
   - Plus one global `bnox-webhook-receiver.service` (bnox-owned, not per-thing).

5. **Multi-component things:** one sync + one build per thing (the build rebuilds **all** components in one pass); one container service per component. A 3-component thing has 1 + 1 + 3 = 5 units. Acceptable Q14-noted variance: the ceiling is per-thing for single-component; multi-component naturally needs more container units.

6. **Build location: both patterns supported day-1, per-thing choice.**
   - **Pattern A — on-host (default):** `<name>-build.service` runs `nix build` locally and pipes to `podman load`. No extra infrastructure.
   - **Pattern B — off-host + registry:** an external builder (Forgejo Actions, separate machine) builds and pushes to a container registry; host runs `podman auto-update` on a timer or the build-unit subscribes to a "remote-built" event.
   - Thing declares its build pattern in `.bnox/`: `build = "on-host"` (default) or `"off-host"` or `"both"`.

7. **Build invocation: standard command, owned by bnox.** The thing's flake must expose `images.<system>.<component>` for each declared component (where `<component>` matches the names in `.bnox/<component>.nix`). bnox's build unit invokes `nix build /srv/<name>#images.x86_64-linux.<component>` uniformly across all things. Thing authors do Nix work in their own repo; bnox handles invocation. Non-standard builds require Q14 deviation.

8. **Rollback: last 3 image tarballs per thing.** Built tarballs retained at `/var/lib/<thing>/images/<git-sha>.tar`. Rollback = `podman load /var/lib/<thing>/images/<prior-sha>.tar` + `systemctl restart <thing>-container.service`. A daily systemd timer prunes to last 3.

**Alternatives considered:**

- **Polling instead of webhook:** rejected — slower feedback; NATS bus already available makes webhook trivially easy.
- **Webhook → directly invoke build (no NATS):** rejected — loses observability and decoupling; sync/build/restart can't be observed or intervened on independently.
- **Build on host only (no off-host option):** rejected — Pattern B is cheap to support day-1 (same units, different trigger) and the user explicitly wanted both available.
- **Custom build script per thing:** rejected — loses consistency; standard flake schema (`images.<system>.<component>`) is simple enough for any reasonable thing.
- **Rollback via separate tooling:** rejected per NFR-6 — `podman load` + `systemctl restart` is sufficient.

**Consequences:**

- bnox module `deployment/` contains: `webhook-receiver.nix` (global), `pipeline.nix` (per-thing sync + build units), `container.nix` (oci-containers wiring).
- bnox flake input: `nats-server` already covered (D-006 platform); no new inputs.
- Each thing's repo must expose the standard flake schema: `images.<system>.<component>` for each component.
- Caddy gets a `/bnox/webhook` vhost (or per-host webhook path) that proxies to the webhook receiver. Authentication via per-thing HMAC secrets (stored via D-007 `file` backend).
- Webhook receiver needs GitHub/Forgejo to know the host's webhook URL — either public Caddy vhost or Tailscale Funnel for non-public hosts. Documented per-host.
- Q13 resolved. Architecture track complete (Q9 → D-006, Q11 → D-007, Q12 → D-008, Q14 → NFR-6, Q4 → D-010, Q13 → D-011). Only Q5 (migration scope) remains blocking.

---

## D-012 — Migration scope
**Date:** 2026-07-27
**Status:** accepted
**Context:** Q5 asked whether bnox is for new systems only, retro-fits uqbn, or retro-fits snowi-node. User clarified: **bnox itself is the priority — finalize it as a standalone base first, without baggage from either source system.** Migration is a separate later phase, handled per-thing with a keep/migrate/toss decision for each. uqbn is the first migration target because the user wants to wipe the MacBook and replace uqbn with bnox, then selectively choose what to put on it (Hermes included; other uqbn content not critical and may be discarded). snowi-node migration is long-term, no urgency.

**Decision:**

1. **Phase 1 — Build bnox standalone.** Implement the base as specified by D-001 through D-011. No source-system-specific code, no migration shims, no compatibility layers. bnox stands on its own.

2. **Phase 2 — Initial deployment.** Deploy bnox fresh on a new host (VPS / VM / fresh hardware). Validate the base works as designed, including hosting at least one thing end-to-end (likely Hermes, per D-009). uqbn and snowi-node stay untouched during this phase.

3. **Phase 3 — uqbn migration (per-thing).** Wipe the MacBook, install bnox, then evaluate each piece of uqbn content individually:
   - **Keep + migrate:** selected things moved onto bnox via the standard `.bnox/` pattern (D-006).
   - **Discard:** anything not worth migrating gets thrown in the bin. User has signalled most uqbn content is non-critical.
   - Hermes (D-009) is the first thing to host on the post-wipe MacBook.

4. **Phase 4 — snowi-node migration (long-term).** Deferred indefinitely. Each snowi-node service evaluated per-thing when the time comes. No urgency; not part of bnox's design.

**Alternatives considered:**

- **Wholesale migration of either source system as a unit:** rejected per user — wants per-thing review, not bulk lift-and-shift.
- **snowi-node first:** rejected — production risk, two-major NixOS jump (D-010), no immediate motivation.
- **Build migration tooling into bnox itself:** rejected — bnox is the base; migration is an operator activity, not base functionality.

**Consequences:**

- **All blocking questions are now resolved.** Phase 4 (Decisions) of the bnox process is complete. Ready to enter Phase 5 (Base design).
- bnox design proceeds without further reference to uqbn/snowi-node specifics. The architecture (D-001 through D-011) is the spec.
- Migration of either source system is documented as a future operator activity, governed per-thing by the `.bnox/` pattern + Q9.5 host config binding.
- Q5 resolved. Q6 (macOS build capability) and Q8 (uqbn role trajectory) remain non-blocking and can be revisited when relevant.
- **Milestone:** with all blocking questions closed, work can begin on `design/process/06-base-design.md` (target flake + module layout) — translating the 12 decisions into concrete Nix code structure.

---

## D-013 — Deployment dispatch topology (central dispatcher)
**Date:** 2026-07-29
**Status:** accepted
**Context:** D-011 §4 described the per-thing pipeline units as subscribing to NATS subjects directly ("`<name>-sync.service` — subscribes to `.changed`"; "`<name>-build.service` — subscribes to `.synced`"). A literal reading means **2 long-running subscriber daemons per thing** (sync + build), each idle-waiting for events. On a host with N things that is 2N+1 always-running processes (plus containers). User explicitly rejected this: "I don't want to end up with many running processes that are just waiting, rather have a central one that wakes the right one up when it needs to wake up."

**Decision:**
1. **One global `bnox-deploy-dispatcher.service`** is the sole subscriber to the `host.deploy.>` event namespace. It parses the thing name + event type from the subject and triggers the corresponding per-thing oneshot (`<name>-sync.service` on `.changed`; `<name>-build.service` on `.synced`).
2. **Per-thing sync/build units become oneshots** (`Type=oneshot`), woken by the dispatcher — not long-running subscribers. They do their work (git sync; nix build + podman load + restart) and exit.
3. **All events still flow through NATS** (`host.deploy.<name>.{changed,synced,built,deployed,failed}`) and the `host-deploy-logs` JetStream stream still captures the full audit trail (D-011 §2/§3 observability intent preserved). The dispatcher is a router, not a replacement for the bus.
4. **Build invocation, rollback, subjects, and HMAC auth are unchanged from D-011** — only the dispatch topology changes.

**Alternatives considered:**
- **Per-thing subscriber daemons (D-011 §4 literal):** rejected by user — 2N+1 idle waiting processes; wasteful and noisy at rest.
- **Sync directly triggers build via `systemctl start` (no NATS hop between sync and build):** rejected — drops the `.synced` event from the bus, losing D-011's step-by-step audit trail and the ability to observe/intervene between sync and build.

**Consequences:**
- Two global services instead of one: `bnox-webhook-receiver.service` (publishes `.changed`) + `bnox-deploy-dispatcher.service` (routes `.changed`/`.synced` to oneshots). Both are bnox-owned, not per-thing.
- Per-thing unit count: sync(oneshot) + build(oneshot) + container(s). Single-component thing = 3 units (NFR-6 ceiling honored); multi-component adds container units only (as D-011 §5 already noted).
- Long-running process count is constant (2 globals) regardless of how many things run — scales cleanly. Trade: one more global service vs D-011 §4's literal one; accepted as worth it.
- `modules/deployment/` gains a dispatcher concern (lives in `pipeline.nix` or a sibling `dispatcher.nix` — implementation choice for the pipeline job). D-011 §4's unit descriptions are read as naming the *functional* units (sync, build, container), not mandating that each literally run a subscriber loop.

---

## D-014 — Host-repo split + versioned bnox product
**Date:** 2026-11-03
**Status:** accepted
**Context:** After Phase 2 implementation, operator deployment on a real host (the `agent` KVM VPS, committed as `hosts/agent` during this discussion) surfaced the coupling problem in Q-D2's in-bnox `hosts/` model: every host change is a bnox repo change, and hosts cannot sit on different bnox versions cleanly. User requirements: (1) per-host config lives in separate git repos importing public bnox at a specific pinned version; (2) bnox defaults with host overrides; (3) minimal host configs, bnox never special-cased per host; (4) a promotion path for host-specific elements that become generally useful (opt-in, or new default); (5) explicit versioning because multiple hosts may run different bnox versions.

**Decision:**

1. **bnox product repo contains no hosts.** `hosts/` auto-discovery (Q-D2) is removed from the bnox flake; host configs live in separate host repos. Supersedes Q-D2 (07-diversions) and D-012's implicit "hosts ship in bnox" stance. Product validation = throwaway evals; integration validation = host repos evaluating real hosts against pinned versions.

2. **Versioned copies at `versions/<major>/<minor>/<patch>/`** — each version dir is a complete product copy: `flake.nix` + `flake.lock` + `modules/` + `home/` + `lib/` + `secrets/` + `fixtures/` + `manifest`. Host repos pin via `github:b-za/bnox?dir=versions/<maj>/<min>/<patch>` (each dir has its own independent lock, so a version = frozen bnox + frozen nixpkgs). **Numbers are unpadded** (`0/0/1`, not `0/000/001`) — padding's only benefit is lexical sort order, cosmetic since paths are exact-pinned and copied, never globbed.

3. **Version workflow:** new version = copy the previous version dir, commit, then develop inside it. Manifest `status: done` = frozen forever; **no fixes are ever copied back** — wanting a fix means taking the new version. First version `0/0/1` = current tree minus `hosts/`.

4. **Series-level docs + examples:** each `versions/<major>/<minor>/` carries `docs/` (consumer-facing; `docs/examples/` = example host config skeletons). Docs are **amendable by patches within the series** (docs-only or alongside fixes); frozen when the next series starts. Docs live at series level, not per patch, so doc fixes never force a new patch version. `design/` remains the developer/AI-agent workspace at repo root; consumer docs never live there.

5. **Fixtures live inside each version copy** (`fixtures/`: `demo-thing`, `mock-daemon`), exposed as flake output. Reason: `?dir=` restricts a flake's source to the subtree, so anything consumable by host repos must be inside the version dir. `bnox-test` sources its demo things from the pinned bnox input; series docs reference them as the thing-author examples.

6. **Repo root = README + `design/` + `versions/` only.** No root `flake.nix`. Development happens inside the newest version dir.

7. **Manifest per version** (`versions/<p>/<m>/<patch>/manifest`): `status` (wip|done), date, nixpkgs rev, changes vs previous version. `done` is the freeze marker; consumers may only pin done versions.

8. **Host repos own host auto-discovery.** The hosts loop moves verbatim from bnox's flake into each host repo's root flake (`hosts/*/configuration.nix`, one `nixosSystem` per subdir, `specialArgs.bnox` = the pinned bnox input). One host repo may hold multiple hosts. Repos:

   | Repo | Path | Remote | Hosts |
   |---|---|---|---|
   | bnox-test | `/Users/bh/code/systems/bnox-test` | `git@github.com:b-za/bnox-test.git` | `bnox-test` (dev/test host; renamed `bnox-dev`; sources fixtures from pinned bnox) |
   | bnox-sn | `/Users/bh/code/systems/bnox-sn` | `git@github.com:b-za/bnox-sn.git` | `macbook-pro-2014-15`, future uqbn-migration MacBook (D-012 Phase 3) |
   | bnox-bg | `/Users/bh/code/systems/bnox-bg` | `git@github.com:b-za/bnox-bg.git` | `agenthub` (renamed `agent`; KVM VPS, BIOS-legacy, disko+GRUB) |

9. **Override semantics unchanged:** bnox sets `mkDefault`, hosts set plain values (profiles use `mkForce`); NixOS module merge does the rest. bnox modules never reference host names or host-specific conditions.

10. **Promotion process (formalized):** a host-specific element deemed generally useful is promoted into bnox in a new version, either **opt-in** (new `mkDefault`-gated option) or **new default** (norm from that version on; hosts pinned to older versions are unaffected until they bump — this is what versions buy).

11. **Numbering semantics:** major/minor/patch with semver meaning (major = breaking/philosophy, minor = feature batch/series, patch = fixes). No dots, no padding.

**Alternatives considered:**

- **Git tags instead of version dirs:** leaner (zero duplication, natural diffs) but rejected by user — in-tree copies are self-documenting, work naturally with `?dir=`, and give literal in-tree version identity.
- **Keep in-bnox `hosts/` (status quo):** rejected — couples host churn to the product repo; no version skew across hosts.
- **Zero-padded numbers (`0/000/001`):** rejected — no real problem with unpadded; padding's lexical-sort benefit is cosmetic for exact-pinned paths.
- **Docs at repo root tracking latest:** rejected — docs must match the pinned series; series-level docs solve doc-fix churn without per-patch duplication.
- **Docs/examples inside every patch version:** rejected — doc fixes would require new patch versions; series-level amendable docs chosen instead.
- **Per-host gitignored secrets example files:** rejected after agenix refresher — D-007 encrypted-in-git stands unchanged (option A); nothing in host repos is gitignored for secrets.

**Consequences:**

- bnox repo restructure: create `versions/0/0/1/` (current tree minus `hosts/`, plus fixtures moved in, plus manifest), create `versions/0/0/docs/` + `docs/examples/`, delete root `flake.nix` + `hosts/`. Version flake drops `nixosConfigurations` auto-discovery, keeps `nixosModules.*`, `profiles.*`, `hardware.*`, `lib`, adds a `fixtures` output.
- Three new host repos created with the pinned-input flake pattern; `bnox-dev` renamed `bnox-test` → bnox-test repo; `agent` renamed `agenthub` → bnox-bg; `macbook-pro-2014-15` → bnox-sn (its pre-existing eval breakage — `hardware.camera` etc. — is fixed or flagged during the move).
- Phase 2 remaining operator activity (runtime validation of the deployment roundtrip) now runs on `agenthub` via the bnox-bg repo.
- D-012 Phase 3 (uqbn migration) host lands in bnox-sn.
- README story changes: consumers create a host repo pinning a version dir; the "add a host dir to bnox" story is dead.
- 07-diversions Q-D2 superseded (discovery moves to host repos); Q-D1/Q-D3 unchanged; 06-base-design's `hosts/` layout superseded.

## D-015 — Passwordless wheel sudo + first-install fixes (series 0.2)
**Date:** 2026-11-08
**Status:** accepted
**Context:** The first real nixos-anywhere install of a bnox host (agenthub on a KVM VPS, built on 0/1/2) surfaced two structural problems. (1) Every 0/1 host had **no path to root by construction**: `bnox.users` creates key-only accounts with locked passwords (no password field set), sshd is hardened key-only with `PermitRootLogin = "no"` (0/1/2 closed the last PAM gap with `KbdInteractiveAuthentication = false`), but `security.sudo.wheelNeedsPassword` kept its NixOS default `true` — so sudo prompted for a password that can never be satisfied. Only the provider rescue console reached root. (2) `bnox-nats-stream-init` failed deterministically on every fresh boot (~16s, exit 1, boot degraded): the stream config JSON omitted `num_replicas`, and natscli's `--config` loader applies no defaults for absent fields, so every `stream add` was rejected with "must be >= 1 but found 0"; additionally `stream update` prompts for confirmation without a TTY and would have zeroed `-1` "unlimited" limits to `0`. Root cause verified empirically against the pinned nats-server 2.12.3 + natscli 0.3.0 (the job 09 design notes flagged the CLI invocations as runtime-deferred/untestable on darwin — that debt came due).

**Decision:**

1. **`security.sudo.wheelNeedsPassword = false`, hardcoded in the base** (`modules/base/users.nix`) with a rationale comment. Not a bnox option: `bnox.users` has no mechanism to set passwords, so passworded sudo is not an alternative policy within bnox — it is a lockout. An option whose other value is always-wrong is misconfiguration surface. Divergent hosts that set real passwords use the NixOS option directly.
2. **Accounts explicitly locked: `hashedPassword = mkDefault "!"`.** Was implicit (NixOS's null default also lands as locked); now self-documenting and immune to upstream default changes. Verified against nixpkgs at the pinned rev: `allowsLogin` treats `"!"` as first-class "password login disabled" (no invalid-hash warning), and a host's own `password`/`hashedPassword` wins by documented NixOS precedence (at most an informational multiple-passwords warning, no assertion).
3. **Stream-init config complete and explicit** (all limits spelled out as `-1`/`0`, `num_replicas = 1`, durations as nanosecond JSON numbers), `update` gains `--force` (no TTY), and an update failure no longer counts as success. The unit stays enabled under the existing `mkIf natsReady` — a unit that deterministically fails while its precondition holds is a bug, not a gating design. Retry loop and `after/requires nats.service` unchanged (the failure was never a race; it's a localhost connection).
4. **Series 0.2 (`versions/0/2/0`), not a patch:** (1) is a deliberate base-policy change (security posture of every host), which the "patch = fixes only" rule excludes. The series bump also carries the consumer docs (Ubuntu nixos-anywhere recipe, passwordless-sudo note) per D-014's series-docs model.

**Alternatives considered:**

- **`bnox.security.passwordlessSudo` option (default true):** rejected — no coherent `false` value exists within bnox; the NixOS option is the override point.
- **Gate stream-init (ConditionPathExists) / add network-online.target:** rejected — the stream is host-level deploy audit plumbing (D-011 §3), present per-host regardless of things; the mkIf on natsReady is the correct and existing gate; the connection is localhost and the retry loop already bounds JS init.
- **Initial root/wheel password + forced change:** rejected — puts a secret in the store and opens a one-boot window; key-only is the model.

**Consequences:**

- Fresh hosts get root via `sudo` out of the box; wheel membership remains the root grant, now actually usable.
- bnox-bg drops its temporary host-side `wheelNeedsPassword = false` divergence when it bumps the pin to 0/2/0 (promotion path D-014 §10, exercised in reverse: divergence removed as the base absorbs it).
- 0/1 hosts are frozen and unaffected; they carry the lockout unless their host repo sets the NixOS option itself.
- 0/2/0 verified on agenthub 2026-11-09 (bnox-bg repin, divergence dropped, rebuild + fresh boot: `running`, stream-init active, stream created) and frozen (`status: done`). Fresh nixos-anywhere installs of older hosts will confirm the same on their own schedule — the unit's behavior is boot-path identical.
- Found during verification (open follow-up): consumer repos' `nix flake update bnox` re-resolves bnox's transitive nixpkgs to the `nixos-26.05` branch tip rather than the version-frozen tarball — the "version freezes bnox and its nixpkgs" invariant needs an explicit `follows` in host repos (or an equivalent locking procedure) plus a series-docs note.

## D-016 — Container NATS reachability knob (series 0.3)
**Date:** 2026-11-09
**Status:** accepted
**Context:** agenthub's NATS agent platform (bnox-bg `docs/agenthub-nats-plan.md`, decision 14) needs worker containers to reach the host broker, which binds 127.0.0.1 only under nkey auth. bnox container things run rootful podman under the standard hardening bundle (IPAddressDeny=any). Empirical facts on agenthub (podman 5.8.2, systemd 260.2, nixpkgs 8623c4c — every one verified live, see the step-2 as-built notes in bnox-bg): (a) the netavark bridge cannot reach host-loopback services (10.88.0.1:4222 times out); (b) pasta is rootless-only on this podman; (c) slirp4netns works rootful but podman passes `--disable-host-loopback` by default, so the container must run `--network=slirp4netns:allow_host_loopback=true` to reach 127.0.0.1-bound services at the gateway 10.0.2.2; (d) under the bundle the cgroup-bpf filter sees two connects per broker session — the container's 10.0.2.2:4222 and slirp's host-side 127.0.0.1:4222 — so IPAddressAllow needs both addresses (10.0.2.2 alone = silent connect timeouts); (e) systemd 260 has no port-scoped IPAddressAllow (`:443` fails to parse: "Failed to parse IP address prefix"), which makes 0/2/0's outboundHTTPS/host-install allow lists load-invalid — a latent bug, never exercised because no such thing had ever started.

**Decision:**

1. **New thing-scoped option `hardening.network.nats`** (sibling of outboundHTTPS; self-declarable in `.bnox/thing.nix` as `nats = true`). For container things it implies: slirp4netns networking with allow_host_loopback, `IPAddressAllow = [10.0.2.2 127.0.0.1]`, `NATS_URL=nats://10.0.2.2:4222` in the container env, and an implied `nats_seed` slot. host-install things get the slot plus `NATS_URL=nats://127.0.0.1:4222` (host netns). The implied slot is the framework's first magic slot name, chosen (over step-3 thing-declared slots, the alternative bh was offered) so "declares NATS use", "gets a credential path" and "gets network reach" cannot drift apart. Slot contract: `/var/lib/bnox/secrets/<thing>/nats_seed` is an env file containing `NATS_SEED=<seed>`, host-written at runtime (agenthub's keygen does the write); rotation restarts the thing via the usual path unit. Seeds stay out of repos and the store (platform plan decision 3).
2. **slirp4netns lands in `virtualisation.podman.extraPackages`** automatically when any enabled container thing sets nats (the oci-containers units resolve podman's wrapped package, so the helper is on PATH exactly when needed).
3. **Container-thing units get a `runnerBundle`** (new in hardening.nix) instead of the thing bundle: rootful podman is a container runner, and the process-sandbox bundle is incompatible with it in six verified ways (ProtectHome EACCES on $HOME/.config/containers config lookup; empty caps → EPERM writing the pause process uid_map; storage locks under ProtectSystem=strict; /proc/sys masked by ProcSubset; container cgroup creation blocked by ProtectControlGroups; sethostname blocked by ProtectHostname — plus /dev/net/tun masked by PrivateDevices for slirp4netns and @system-service excluding syscalls crun's child needs). The runner bundle keeps the boundaries that still bind (strict fs with podman storage paths, ProtectHome=read-only, PrivateTmp, AF_UNIX/AF_INET/AF_INET6/AF_NETLINK, kernel modules/logs/clock, ProtectProc) and the load-bearing IPAddressDeny/Allow — verified to still scope container egress — and drops the process-level lockdown; podman is the payload's sandbox. Pipeline build units keep their own profile with the same ProtectHome=read-only fix (podman load needs no runner relaxations). No 0/2/0 container thing ever started, so the thing bundle stays as-is for host processes (keygen/assembler/echo prove it).
4. **Container payloads run as container root** (the `user = <thing>` oci-containers option is dropped): podman resolves `--user` names only against the image's /etc/passwd, and dockerTools images carry no per-thing users — the 0/2/0 setting failed every container with "unable to find user"; numeric uids are not an alternative (thing uids are assigned at activation, not eval). The container is the payload's boundary; the thing user stays the host-side boundary (state + secrets slots). Per-thing non-root payload users, if ever wanted, are baked into the thing's own image.
5. **Port-scoped IPAddressAllow is unrepresentable on the pinned systemd**: outboundHTTPS and host-install now allow `any` — honest degradation (an egress-allowing filter without port scoping is no filter), documented in the manifest and series docs; loopback-only units (hermes, platform step 4) pin per-unit allowlists in host config per the visible-override rule.
6. **Series 0/3** (feature ⇒ minor per D-014 §11); carries the parse fix, which could not have shipped as a 0/2 patch anyway (no fixes are copied back into frozen versions).

**Alternatives considered:**

- **pasta networking:** rejected — rootless-only on podman 5.8.2; bnox container units are rootful.
- **`--network=host`:** rejected — abandons netns isolation for a headless worker.
- **Broker on the bridge address:** rejected — the platform plan locks the broker to 127.0.0.1 (decision 1).
- **Thing-declared `nats_seed` slot (defer to the platform's step 3):** rejected as the default — flag/slot/network drift is exactly the silent inconsistency bnox exists to prevent.
- **Keep the `:443` entries until systemd grows port scoping:** rejected — they are load-invalid today; no 0/2/0 thing ever started with them.

**Consequences:**

- bnox-bg (agenthub) repins to 0/3/0; step-3 worker things declare `nats = true` in `.bnox/thing.nix` and get the full wiring; the host's keygen gains one env-file write per NATS thing.
- Hosts pinned to 0/2/0 with outboundHTTPS containers or host-install things were already broken (units fail to start on the first run); 0/3/0 is the fix path — versioning working as designed.
- The container→broker path exposes the host loopback to the container by design (that is what allow_host_loopback means); the broker's nkey auth is the enforcement layer. The knob stays opt-in per thing.

---

## D-017 — bnox-bg lessons, fix batch (series 0.3, patch 0/3/1)
**Date:** 2026-11-11
**Status:** accepted
**Context:** agenthub (bnox-bg) is the first real consumer of bnox 0/3/0. Its gotcha log (bnox-bg `docs/graph/*-G0xx.md`) and host config show bnox bugs worked around host-side: G20 (pure flake eval cannot read `/srv/<thing>/.bnox/`, so the documented `source = "/srv/<thing>"` can never load a manifest under `nixos-rebuild --flake`), G21/G22/G24/G25/G31 (the generated `<thing>-build` unit is too locked down to build: libgit2 safe.directory, unwritable fetcher cache, podman runtime paths, nix build-log dir, `podman save` refusing to overwrite a same-sha tar), G28 (host-install units get slot path units but no env files), missing slot files (podman refuses to start a container whose env file is absent; bnox-bg pre-creates them via tmpfiles). Reviewed one at a time with bh. Also: 0/3/0 was frozen after a single probe container round-trip — the deploy pipeline was never run against a real thing on the locked broker, and was broken (G23).

**Decision:**

1. **Thing manifest and thing code have separate sources.** `bnox.things.<name>.source` is where bnox reads `.bnox/` at evaluation — documented as a locked flake input of the host repo (a store path). The code is always built from the git checkout `/srv/<name>` by the deploy pipeline (already hardcoded in `pipeline.nix`). This keeps D-006's hard constraint (app deploys never trigger `nixos-rebuild`); the lock only needs bumping when `.bnox/` itself changes. Option A (flake input for both, deploy = lock bump + rebuild) was considered and rejected precisely because it violates D-006. The build unit **warns** when `/srv/<name>/.bnox/` differs from the evaluated manifest.
2. **Build unit fixes, taken over from bnox-bg as proven:** system `/etc/gitconfig` `safe.directory` for every thing checkout (covers nix's libgit2, not just the git CLI); `XDG_CACHE_HOME=/var/lib/<name>/.cache`; ReadWritePaths gain `/run/lock /run/libpod /run/containers /var/cache/containers /nix/var/log/nix`; the same-sha tar is removed before `podman save` (bnox-bg wiped the whole images dir, which would also destroy the rollback tarballs D-011 keeps — narrowed to the one file).
3. **Host-install runtime loads slots as env files** (`EnvironmentFile`), like the container runtime: `nats_seed` required, other slots `-`-prefixed. The host-install unit's secrets dir becomes read-only (it was writable — an app must not be able to overwrite its own credentials). Option B (files only, app reads by path) rejected for consistency; env inheritance by child processes changes little since the app user could read the files anyway.
4. **bnox creates every declared slot as an empty file, root:root 0600** (tmpfiles `f`, which never rewrites an existing file — G45). Supersedes the "slot owned by the thing's user" wording in the series docs: systemd reads env files as PID 1, so root-only is strictly safer.
5. **Pipeline publishes under NATS auth (G23) and the nats-py dispatcher's missing nkey support (G4) are NOT patched here** — they are solved by D-018 (NATS identity), not by another stopgap.
6. **Done rule (process):** a version may only be set `status: done` after, on a real host, (a) a real thing has completed the full deploy path git push → webhook → sync → build → restart, and (b) `bnox-validate` passes (once it exists, D-020; until then, the NATS round-trip checks the host already has).

**Alternatives considered:** listed inline above.

**Consequences:**

- bnox-bg can drop its G21/G22/G24/G25/G31 build-unit overrides, its slot-file tmpfiles and its hermes `EnvironmentFile` lines once it pins 0/3/1.
- Hosts using `source = "/srv/<thing>"` were already broken under flake eval; docs now show the flake-input form.
- Slot file ownership changes from thing user to root on upgrade only for newly-created files; existing files keep their mode (tmpfiles `f` does not touch them).

---

## D-018 — NATS identity: logins always, two-level permissions, roles (series 0.4)
**Date:** 2026-11-11
**Status:** accepted (implementation: 0/4/0)
**Context:** bnox's broker is open (D-006 L0); L1 (per-thing users) was designed-for. agenthub built its own lockdown: per-service nkeys generated on the host (`nkey.py`, keygen unit), per-service permission files, a runtime assembler writing the auth config (G12). bnox 0/3/0 ships an implied `nats_seed` slot that nothing in bnox fills, and its pipeline units break the moment the broker requires logins (G23, G4). agenthub also used its own subject layout (`agenthub.<worker>...`, one shared stream) — improvised, not reasoned against D-006.

**Decision:**

1. **NATS logins are always required.** No anonymous user. Not opt-in.
2. **Subject layout stays D-006:** `host.>` bnox-owned, `things.<name>.>` per thing, one JetStream stream per thing. Hosts fit custom structure beneath a thing's prefix (agenthub moves onto it).
3. **Two-level permissions; the final grant is what both levels allow (intersection):**
   - **Host level** decides who may talk to whom (from `deps` / explicit grants — e.g. che → gsheet), as a ceiling.
   - **Thing level** (`.bnox/`) declares what the thing offers to others (e.g. publish `command.>`, subscribe `event.>`) — so no host grant can let another identity publish fake events for it.
4. **Roles:** a thing's `.bnox/` may declare named roles (e.g. `user`, `admin`) as subsets of its offer; the host assigns a role per dependent. NATS enforces them (a non-admin cannot even publish an admin command).
5. **Keys are generated on the host at runtime** (agenthub's approach: never in git or the store; a rebuilt host makes new keys and permissions follow names, not keys). Supersedes D-007's placement of "NATS auth" in the agenix infra layer. **Recorded alternative:** agenix-encrypted keys, for a future case where a key must survive host rebuilds.
6. **Non-thing identities:** bnox ships fixed identities for its own services (webhook receiver, dispatcher, sync/build units — this fixes G23) scoped to `host.deploy.>`; an `ops` identity with full access, root-readable only; host config may declare extra identities with their own permissions (e.g. agenthub's echo canary). The dispatcher moves off nats-py (G4) — agenthub's Go `deploy-bridge` is the reference.
7. bnox fills the implied `nats_seed` slot itself (absorbs the keygen).

**Consequences:** supersedes D-006 §8 L0 (L1 becomes the floor) and D-007's NATS-auth line; bnox-bg retires its keygen/assembler/permission files in favour of bnox's and moves agenthub subjects under `things.<name>.>`; `bnox-validate` (D-020) is generated from the computed permission matrix.

---

## D-019 — Thing config and network exposure: `env`, egress, inbound (series 0.4)
**Date:** 2026-11-11
**Status:** accepted (implementation: 0/4/0)
**Context:** bnox has no plain (non-secret) config channel — agenthub passed `GSHEET_ADMINS` through a secret slot written by tmpfiles (value changes silently ignored, G45). Egress is per-unit address rules only (no domain filtering; with outbound HTTPS a thing reaches anywhere); agenthub added owner-based nftables rules + a tinyproxy domain allowlist (`egress.nix`, `proxy.nix`). Inbound is Caddy for container webapp/http-api only; host-install dashboards needed hand-written vhosts (`caddy.nix`), and the only exposure level is "public".

**Decision:**

1. **`env`** (attrset) at both levels: thing `.bnox/` for defaults, host config for host-specific values; host wins per key. Both runtimes. Changes take a rebuild (config, not secrets).
2. **Egress — locked by default:** no outbound unless granted. Thing `.bnox/` declares its needs (domain list, or `"any"`); host config grants a ceiling (domain list, or `"any"`); final = intersection; **nothing is allowed until the host grants** (explicit, like NATS deps). Domain lists go through a bnox-managed allowlisting proxy (`HTTPS_PROXY` injected); `"any"` on both sides means direct.
3. **Inbound — the mirror:** thing `.bnox/` declares its port and the maximum exposure it accepts; host grants a level `internal` / `tailnet` / `public` (and supplies domain + TLS); final = the more restrictive; default `internal`. Works for both runtimes (absorbs the host-install Caddy gap). Asymmetries accepted: the host supplies name/cert; outbound is a domain list, inbound a level; login protection stays the app's. An outbound `tailnet` level was raised, not adopted.

**Consequences:** bnox-bg's `egress.nix`/`proxy.nix`/`caddy.nix` and the `gsheet_admins` slot become declarations; every existing thing needs egress grants after upgrading to 0/4/0 (locked by default is a behaviour change — minor-version material).

---

## D-020 — Host-install switches, image helper, self-test (series 0.4)
**Date:** 2026-11-11
**Status:** accepted (implementation: 0/4/0)
**Context:** Hermes needed a login shell (bnox thing users get `nologin`; its terminal tool died — G33) and nix-ld with its variables in the unit (prebuilt glibc binaries — G26). gsheet's bare dockerTools image lacked `/etc/passwd`, `HOME` and a CA store (G18/G19/G30; the last only surfaced on the first live call). agenthub's `agenthub-validate` proves broker permissions by publishing as each identity.

**Decision:**

1. **Host-install switches in `.bnox/`:** `shell = true` (thing user gets bash) and `nixLd = true` (nix-ld enabled + `NIX_LD`/`NIX_LD_LIBRARY_PATH` set in the unit). Both default off; host-install only. These enable the thing to work — control stays in NATS/egress/inbound.
2. **`bnox.lib.mkImage`:** an image helper that always bakes a root `/etc/passwd`, `HOME`, and CA certificates; things use it instead of bare dockerTools.
3. **`bnox-validate`:** generated from the computed NATS permission matrix (D-018), tests every grant and every denial at the broker; later extended to egress/inbound. Part of the done rule (D-017 §6).
4. **Docs notes:** host repos pin bnox's nixpkgs explicitly (`follows`); `nixos-rebuild` may exit 4 when a NATS auth change restarts the broker mid-switch (G59) — check `systemctl is-active` after a few seconds.
