# Open Questions

Things needing the user's input before we can finalize decisions. Ordered by blocking priority.

## Q1: Project name ✅ RESOLVED → D-001

**Resolved 2026-07-27:** name is **`bnox`**. See `process/05-decisions.md` D-001 for rationale. Other candidates that were considered and rejected: `baseos` (placeholder), `noxos` (collision with active NoxOS-org), `snowi-os` (too host-specific), `bhos`, `keystone`, `rootstockos`, `nyxos`.

---

## Q2: Container runtime ✅ RESOLVED → D-002

**Resolved 2026-07-27:** Podman is the base default, declared via `virtualisation.oci-containers` (not raw quadlets). All images must be built by Nix (`dockerTools.*`) — **Dockerfiles / `docker build` are forbidden** as a hard determinism requirement. uqbn's `docker/` content is treated as inspiration only, not migration baggage (no barrier to starting fresh). See `process/05-decisions.md` D-002 for full rationale and consequences.

---

## Q3: Secrets manager ✅ RESOLVED → D-007

**Resolved 2026-07-27:** **agenix** for the infra/bootstrap layer (host key, Caddy TLS, NATS auth, age key). Encrypted-in-git; decrypted at `nixos-rebuild` activation. SSH host key reused as age key — fits existing hardened-SSH setup. sops-nix rejected (extra features not needed; agenix's surface area is smaller). The original Q3 framing ("pick a tool") was reframed by Q11 into "pick an architecture" — the architecture decision (D-007, hybrid with file-on-host backend for things and agenix for infra) resolves which tool handles the push-at-deploy slice.

---

## Q4: NixOS version ✅ RESOLVED → D-010

**Resolved 2026-07-27:** Pin to **`nixos-26.05`** (current stable). Full channel (no `-small`). Original recommendation of 24.11 was stale — both source systems run EOL NixOS as of today (24.11 EOL'd 2025-06-30; 25.05 EOL'd 2025-12-31). bnox is a fresh start; no legacy to preserve. Bump cadence: every 6 months when new stable ships. See `process/05-decisions.md` D-010.

---

## Q5: Migration scope ✅ RESOLVED → D-012

**Resolved 2026-07-27:** Build bnox standalone first (Phase 1), deploy fresh somewhere to validate (Phase 2), then migrate uqbn per-thing (Phase 3 — MacBook wipe, selective keep/migrate/toss, Hermes first), snowi-node long-term/deferred (Phase 4). Migration is an operator activity, not bnox base functionality. See `process/05-decisions.md` D-012. **All blocking questions now resolved.**

---

## Q6: macOS build capability (non-blocking but design-relevant)

snowi-node explicitly says "Cannot run nixos-rebuild from macOS — must build on the VPS itself." This is partly because of the Go service image builds. The base could:
- **Option A:** Standardize on **remote build** (rsync + build on target) — matches snowi-node today.
- **Option B:** Standardize on **cross-build from macOS** (set up a remote builder for aarch64-darwin → x86_64-linux).
- **Option C:** Document both, pick per-host.

**Need from user:** preference. Recommendation: **A** for simplicity; revisit if/when build latency becomes painful.

---

## Q7: nixpkgs channel size ✅ RESOLVED → D-010

**Resolved 2026-07-27:** Full channel (`nixos-26.05`), **not** `-small`. `-small` excludes packages bnox might need (desktop profile, future things). Fetch time isn't a real bottleneck with binary caches. Folded into D-010.

---

## Q8: uqbn role trajectory (context only)

Not blocking, but worth noting: uqbn's role may evolve. If the user wants it headless eventually, the base's desktop profile becomes optional. If they want to keep it as a desktop, the desktop profile is load-bearing.

**Need from user:** confirm uqbn's role trajectory (stays desktop / goes headless / both at different times).

---

## Q9: Repo topology / OS-vs-app separation ✅ RESOLVED → D-006

**Resolved 2026-07-27:** See `process/05-decisions.md` D-006 for full rationale. Thing taxonomy (provenance × shape × dependencies), per-thing bnox-side declaration (plumbing config + secrets slot), platform/thing boundary (Caddy, NATS, Podman, static-site server = platform), NATS subject layout (`things.<name>.>` for things, `host.>` reserved), one JetStream stream per thing, self-declared upstream ports with bnox collision-check, dep-graph validation at rebuild, L0 enforcement with L1-ready `deps` schema.

**One residual sub-question remains open as Q9.5 below.**

---

## Q9.5: Location of per-thing declaration ✅ RESOLVED (with refinement)

**Resolved 2026-07-27 — option (c) hybrid.** bnox owns system-level config only (enable, source path, domain, secrets binding, per-component enable flags). All thing-intrinsic details (shape, deps, sub-services, ingress ports, sub-subject structure) live in the thing's own repo via a **`config.bnox/` directory convention** at the repo root.

**Refinement to D-006 (multi-component things):** D-006 specified `shape` as a single enum per thing. Real things (e.g. `ledger-king-ledger` in snowi-node) are **both** webapp **and** nats-api consumer. Refined model:

- A **thing** = one repo, one deploy unit.
- A thing has one or more **components**.
- Each component has its own shape (`static-site` / `webapp` / `http-api` / `nats-api`).
- Components live in subdirs of the thing's repo; each component has its own declaration in `config.bnox/<component>.nix`.
- bnox host config enables components per-host via `components.<name>.enable = true`.

This refines but does not break D-006 — shape taxonomy per component is unchanged. Will roll into a future superseding decision when more of the design settles.

**Secrets interface (independent of Q11 mechanism):**
- Thing's `config.bnox/thing.nix` declares **what secret slot names it needs** (e.g. `secrets = [ "xero_client_id" "xero_client_secret" ]`) — declarative, no values.
- bnox host config **binds those slots to actual sources** — host-specific.
- bnox's loader (per Q11/D-007) materialises secrets at the path the thing expects, before containers start.
- The slot contract is mechanism-agnostic — sops / agenix / pull-at-runtime all implement the same interface.

**Sketch — thing repo layout** (directory renamed to `.bnox/` per hidden-dir convention, like `.git/` / `.github/`):
```
ledger-king/                          # one thing = one repo
├── .bnox/
│   ├── thing.nix                     # thing-level: deps, natsSubject prefix, secret slot names
│   ├── webapp.nix                    # component: shape=webapp, ingressPort, image derivation ref
│   └── nats-api.nix                  # component: shape=nats-api, sub-services, image derivation refs
├── webapp/                           # webapp code + Nix derivation
└── nats-api/                         # nats-api code + per-sub-service Nix derivations
```

**Sketch — bnox host config** (host-specifics expressible at both thing-level and component-level; thing-level acts as default for all components, component-level overrides per-component):
```nix
bnox.things.ledger-king = {
  enable = true;
  source = "/srv/ledger-king";
  secrets = {                            # thing-level secret binding (default for all components)
    xero_client_id  = { source = ...; };
    xero_client_secret = { source = ...; };
  };
  components = {
    webapp = {
      enable = true;
      domain = "app.example.com";        # component-level host-specific
      secrets = { session_secret = { source = ...; }; };  # component-level secret binding
    };
    http-api = {
      enable = true;
      domain = "api.example.com";
    };
    nats-api = {
      enable = true;
      # no domain — internal only
    };
  };
};
```

**Symmetry rule:** the host-specific interface (enable / domain / secrets / source) is the same shape at thing-level and component-level. Thing-level values act as defaults; component-level values override. A component declares in `.bnox/<component>.nix` **what host-specific slots it needs** (e.g. "I need a domain"); bnox host config **binds those slots**.

### Q9.6: Per-thing user isolation (refinement to D-006, locked 2026-07-27)

**Locked:** every enabled thing gets a **dedicated system user**, auto-created by bnox when the thing is enabled. Applied uniformly to all things — not just third-party or daemon-shaped. This is the L0 security boundary (filesystem + process isolation); composes with future L1 (per-thing NATS users) for network-layer isolation.

- Default username = thing name (overridable).
- Each thing's home/state lives at `/var/lib/<thing-name>/`, owned by the thing's user.
- Each thing's systemd unit / container runs as its user (`User=`/`Group=`).
- Standard systemd hardening applied by default: `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths=/var/lib/<thing> /var/lib/bnox/secrets/<thing>`, `PrivateTmp=true`, `NoNewPrivileges=true`, `RestrictSUIDSGID=true`.
- Secrets (D-007 `file` backend) at `/var/lib/bnox/secrets/<thing>/<slot>` are chown'd to the thing's user. Cross-thing reads blocked by filesystem perms.
- Things communicate via NATS/HTTP (network), not shared files — per-user isolation reinforces the D-006 communication model.

**Cost analysis (confirmed effectively zero overhead):**
- Adding system users: automated, one entry per thing, negligible memory/disk.
- Runtime: zero — systemd `User=` is free.
- Debugging friction: mild (`sudo -u <thing>` to inspect state). Arguably a feature — forces explicit context-switching.
- File sharing between things: would need explicit setup, but is an anti-pattern under D-006 anyway (things communicate via NATS/HTTP, not shared files).
- Software assuming root: rare; containerized things already run non-root by Podman default.

**Justification for uniform application (vs. Hermes-only as user originally proposed):**
1. Cost is identical for 1 thing or 50 — the per-thing abstraction creates users automatically.
2. Defense in depth — first-party things can be compromised too; same cheap insurance applies.
3. Consistency — every thing looks the same to operator; no special cases.
4. Future-proofing — when next third-party thing arrives, isolation is already in place.
5. L1 NATS upgrade is free — per-thing Unix users are prerequisite for mapping NATS users to host identities.

**Will roll into D-006.1** (refined thing hosting architecture) when more of the design settles, alongside the multi-component refinement.

### Q9.7: Per-thing security model (refinement to D-006, locked 2026-07-27)

**Locked:** user isolation (Q9.6) is necessary but not sufficient. bnox applies a **standard hardening bundle** to every thing's systemd unit by default, with overrides available per thing for legitimate special needs (e.g. a daemon needing outbound HTTPS).

**What user isolation alone provides:**
- ✅ Filesystem boundary (strong, with proper ownership)
- ⚠️ Process boundary (can see other procs exist; can't `kill`/`ptrace` with default `Yama ptrace_scope`)
- ❌ Network boundary (any local user can connect to any local port)
- ❌ RAM/CPU/Disk limits (any user can exhaust host resources)
- ❌ Kernel exploit surface (kernel vuln = any user → root; true of any isolation short of separate hardware)

**Standard hardening bundle applied by bnox per thing (sane defaults; overridable):**

| Category | Directives |
|---|---|
| Filesystem | `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths=/var/lib/<thing> /var/lib/bnox/secrets/<thing>`, `PrivateTmp=true`, `PrivateDevices=true` |
| Privileges | `NoNewPrivileges=true`, `CapabilityBoundingSet=` (empty), `SystemCallFilter=@system-service`, `RestrictAddressFamilies=AF_INET AF_INET6` |
| Kernel surface | `ProtectKernelTunables=true`, `ProtectKernelModules=true`, `ProtectKernelLogs=true`, `ProtectControlGroups=true`, `ProtectClock=true`, `ProtectHostname=true` |
| Process visibility | `ProtectProc=invisible`, `ProcSubset=pid` |
| Resource caps | `MemoryMax=`, `CPUQuota=`, `TasksMax=` (defaults TBD per thing shape; overridable) |
| Network | `IPAddressDeny=any` + `IPAddressAllow=` for required destinations (e.g. resolver IPs, `:443` for daemons needing outbound HTTPS) |

**Honest threat model after applying the bundle:**

A compromised thing gets: its own state, its own secrets, its outbound network access (within allow-list, rate-limited), its CPU/RAM budget. It does NOT get: other things' files/secrets/processes, NATS access (unless explicitly granted), root, or unlimited resources.

**Residual risks (not isolated, by design or by physics):**
- **Kernel exploits** — any user → root via kernel vuln. Affects every isolation strategy short of separate hardware. Mitigation: kernel patch discipline; out of scope for bnox to solve.
- **Compromised thing attacking external services it legitimately reaches** (e.g. Hermes sending Discord messages, calling LLM APIs). Mitigation: scope API keys, rate limits, monitoring. Out of scope for bnox.
- **Side channels** (cache timing, Rowhammer) — theoretical; out of scope per Q14 "basics" guardrail.
- **Thing-internal sandbox backends that introduce their own kernel surface** (e.g. Hermes' Docker sandbox backend). Mitigation: configure things to disable risky backends (e.g. Hermes local sandbox only, no Docker/SSH backends).

**Per-thing overrides:** when a thing has a legitimate need not covered by the standard bundle (e.g. a daemon needs outbound HTTPS to arbitrary destinations), the override is declared in bnox host config: `bnox.things.<name>.hardening.network.outboundHTTPS = true;` or similar. The override is visible in the host config and recorded — not silently absorbed.

**Will roll into D-006.1** alongside Q9.6 when design settles more.

### Q9.8: New shape `daemon` (refinement to D-006, locked 2026-07-27 → D-009)

**Locked:** shape taxonomy (D-006) gets a fifth entry: **`daemon`** — long-running stateful process; no inbound HTTP/NATS interface required; initiates outbound connections; may have its own state directory and update mechanism. Examples: AI agents (Hermes), bots, polling integrations, scheduled job runners. Multi-component things can compose (e.g. `daemon` + `http-api` for a background agent with an HTTP control surface). First use: Hermes (D-009).

### Q9.9: New runtime option `host-install` (refinement to D-006, locked 2026-07-27 → D-009)

**Locked:** the thing-hosting abstraction (D-006 implied `oci-containers`) gets an orthogonal `runtime` field per component: `container` (default, Nix-built image per D-002) or `host-install` (thing manages its own installation in its user space; bnox provides only the user + systemd unit + secrets slot + Q9.7 hardening bundle). `host-install` is rare and requires a Q14 deviation per thing. First use: Hermes (D-009).

### Q9.1: Thing taxonomy (refined 2026-07-27)

A "thing" is a unit of application-layer deployment. Three orthogonal axes:

**Axis A — Provenance** (where the code comes from):

| Type | Source | Update trigger |
|---|---|---|
| `first-party` | repo the host owner builds & edits | git sync → rebuild |
| `third-party` | external upstream, owner doesn't edit | upstream release → pull new image |

**Axis B — Shape** (what interface it exposes):

| Shape | HTTP port? | NATS presence? | Multi-service? |
|---|---|---|---|
| `static-site` | served by shared web server | no | no |
| `webapp` | yes (UI) | maybe | no |
| `http-api` (REST or WebSocket) | yes (no UI) | maybe | no |
| `nats-api` | maybe | yes — shares a stream/subject tree | **yes — a batch of services acting as one logical thing** |

The `nats-api` shape bundles multiple services into one "thing" because they share a stream and only make sense together. This maps snowi-node's `ledger-king-*` (11 services) and `beertrader-*` (4 services) families each onto one repo / one thing / one rebuild unit.

**Axis C — Dependencies:** things declare what they depend on (other things, or platform services). Implemented via systemd `After=`/`Requires=`; bnox validates the graph at evaluation time and refuses to enable a thing whose declared deps are absent.

### Q9.2: Thing hosting abstraction

bnox owns a generic **"host a thing" mechanism**. Per-thing bnox-side declaration has **two pieces** (refined 2026-07-27):

1. **bnox-plumbing config** — everything bnox needs to wire the thing into platform services (Caddy vhost, NATS subject prefix, ingress port, deps). This is bnox-side integration, NOT the thing's own runtime config.
2. **secrets slot** — shape filled in by Q11; the slot exists regardless of which secrets architecture is chosen.

The thing's own config (env file structure, internal NATS sub-subjects below its mount point, internal storage paths) lives in **the thing's repo**, not in bnox.

Per-shape plumbing needs:

| Shape | Plumbing bnox needs |
|---|---|
| `static-site` | domain(s), source path on host (bnox serves files directly via Caddy `file_server` — static-site web server is platform, confirmed) |
| `webapp` | domain(s), upstream port (so Caddy can reverse-proxy) |
| `http-api` | domain/path, upstream port (or internal-only with no public exposure) |
| `nats-api` | NATS subject prefix (mount point); optionally HTTP ingress if the thing has one |

Conceptual sketch (not real Nix — for shape validation only):
```
bnox.things.<name> = {
  enable = true;
  shape = "nats-api" | "webapp" | "http-api" | "static-site";
  source = "/srv/<name>";              # git-synced checkout
  domain = "...";                      # if HTTP-exposed
  ingressPort = ...;                   # if HTTP-exposed
  natsSubject = "<name>.>";            # if shape = nats-api
  deps = [ ... ];                      # other things this depends on
  secrets = { ... };                   # shape tbd by Q11
};
```

### Q9.3: Platform vs thing boundary

**Platform** (bnox-owned, single instance per host, no per-thing config):
- **Caddy** — confirmed (every HTTP-exposed thing needs it).
- **NATS + JetStream** — confirmed (every nats-api thing needs it; one instance per host; **not** one per thing — "a waste to have multiple instances running").
- **Podman** — confirmed (D-002).
- **Static-site web server** — confirmed platform (bnox serves files via Caddy's `file_server`; no per-site container).

**Things** (instance-configured, dependency-declaring):
- EvolutionAPI, xero-auth, Forgejo, etc. — first-party or third-party things per Q9.1 provenance axis.

NATS subject mount: each thing gets a **subject prefix** (e.g. `ledger-king.>`); the thing owns everything beneath its prefix; its repo declares the sub-structure. **Stream separation falls out naturally** — one JetStream stream per nats-api thing, filtered on `thing-prefix.>`. Streams don't cross thing boundaries.

Q10 (shared infra classification) is fully absorbed here.

### Q9.4: Remaining narrow sub-questions

1. **Subject-prefix layout — LOCKED 2026-07-27.** Things live under `things.<name>.>`; top level reserved for host-level / ops / CQRS (`host.>`). The thing's repo owns everything beneath its prefix; bnox allocates the prefix and validates uniqueness.
2. **Who picks the upstream port for HTTP-exposed things?** Thing-repo-self-declares (bnox fails build on collision) **[lean]** vs bnox-allocates from a registry.
3. **JetStream stream per thing.** **LOCKED 2026-07-27:** one stream per thing, filtered on `things.<name>.>`. Streams do not cross thing boundaries.
4. **Dependency graph validation.** Per-thing `deps = [ … ]`; bnox's evaluation asserts every dep is enabled on this host, fails loud at rebuild. **[lean: yes]**
5. **Cross-thing stream access enforcement — LOCKED 2026-07-27.** **Start at L0** (convention only — bnox validates dep graph + systemd ordering; NATS itself open locally). **Design the `deps` field so an L1 upgrade (per-thing NATS users with explicit grants derived from `deps`) is additive and requires no schema change.** L1 is not built now. L2 (NATS accounts) is out of scope for the base.

---

## Q10: Shared infrastructure classification — ABSORBED INTO Q9.3

**Resolved by reframing 2026-07-27:** the first-party/third-party distinction in Q9.1 (provenance axis) plus the platform/thing distinction in Q9.3 covers this. EvolutionAPI = third-party thing; xero-auth = first-party http-api thing; NATS, Caddy, Podman = platform; Forgejo = third-party thing (if adopted). No separate classification needed. Kept here as a pointer for traceability.

---

## Q11: Secrets architecture ✅ RESOLVED → D-007

**Resolved 2026-07-27:** **Hybrid-1 with Hybrid-2-ready abstraction** (see `process/05-decisions.md` D-007).

- Infra layer (host key, Caddy TLS, NATS auth): **agenix** (push-at-deploy, encrypted-in-git).
- Things layer: **swappable backend, chosen at bnox config time per host.**
  - `file` (default, Hybrid-1): plaintext files under `/var/lib/bnox/secrets/<thing>/<slot>`, watched by systemd-path, restart on change. No host rebuild on secret update.
  - `nats-kv` (Hybrid-2, optional, **designed-for not built day-1**): secrets-service fetches from NATS KV using host key, decrypts, writes to local paths, restarts affected things. Central update, multi-host ready.
- Slot contract identical across backends (per Q9.5). Things and host configs unchanged when backend changes.
- Q3 resolved → agenix for infra layer.
- Q12 (host key home) still open.

---

## Q12: Host encryption key home ✅ RESOLVED → D-008

**Resolved 2026-07-27:** Host encryption key = **SSH host key** (`/etc/ssh/ssh_host_ed25519_key`). No separate bnox-managed key. agenix reads via `age.sshKeyPaths` (default pattern). Future `nats-kv` backend derives from same key via age. Provisioned via nixos-anywhere (matches snowi-node). **Recovery via second age recipient on every agenix secret** (held off-host, e.g. operator's workstation) — not via `/etc/ssh/` backup. TPM path documented as future hardware-host enhancement. See `process/05-decisions.md` D-008 for full rationale.

---

## Q13: App-layer deployment mechanism ✅ RESOLVED → D-011

**Resolved 2026-07-27:** Webhook + NATS event bus. Single bnox-owned `webhook-receiver.service` publishes to NATS subjects `host.deploy.<name>.{changed,synced,built,deployed,failed}`. Per-thing sync/build/container units subscribe and execute. JetStream stream `host-deploy-logs` for audit trail. Both build patterns supported day-1 (on-host default, off-host + registry optional, per-thing declaration in `.bnox/`). Build invocation is standard bnox-owned: thing's flake exposes `images.<system>.<component>`, bnox invokes uniformly. Rollback = last 3 tarballs at `/var/lib/<thing>/images/`, pruned daily. See `process/05-decisions.md` D-011 for full rationale.

---

## Q14: Over-engineering guardrail ✅ RESOLVED → D-009

**Resolved 2026-07-27:** Captured as NFR-6 in `process/03-requirements.md` (to be added):

> **NFR-6 — Deployment simplicity ceiling (default; deviations allowed with justification).** Default: application-layer deployment (per D-006) is implementable using only **Podman, systemd, git, and optionally Forgejo**. Per-thing overhead **≤ 3 systemd units** (container + git-sync + build-trigger). Rollback via `podman load` of prior image + `systemctl restart` — no separate rollback tooling. By default forbidden: Kubernetes, Nomad, Argo CD, Flux, Helm, any framework with its own control plane. **A specific thing may deviate** when it has a justified need; deviations are raised as an open question and logged as a decision (D-NNN) before adoption — not silent.

First use of the deviation clause: D-009 (Hermes).
