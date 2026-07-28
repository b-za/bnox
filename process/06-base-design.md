# Base design

**Phase 5 deliverable.** Translates the accepted decisions (D-001 through D-012, plus the locked Q9.5–Q9.9 refinements) into a concrete flake + module layout. This is the structural spec for implementation; it does not yet contain Nix code. Per-host extension/profile patterns are elaborated in `07-diversions.md` (Phase 6).

## Resolved structural choices (this session)

| # | Choice | Resolution |
|---|---|---|
| 1 | `oci-containers` entry location | Declared by the thing (`modules/things/runtimes/container.nix`); `deployment/` owns only the sync/build/reload pipeline. D-011's `deployment/container.nix` is read as the same concern described from the deployment angle — collapsed into things. |
| 2 | `hosts/` inclusion | Ship in bnox. Convention: `hosts/<hostname>/`. Starts with one hand-written validation host (D-012 Phase 2); grows over time. uqbn/snowi-node successors get fresh hostnames (not those names). Host configs are intentionally non-reusable — reusability lives in `modules/`. |
| 3 | `packages/` scope | Minimal day-1. Webhook receiver wired as a shell/script inside its module; no `bnox` CLI (document SSH/scp for file-backend secret writes). Revisit when a real package need appears. |
| 4a | agenix secrets location | **Option A.** bnox ships `secrets/secrets.nix.example` template only (documents rules format + recipient setup); real `.age` files + rules live per-host under `hosts/<name>/secrets/`. Base ships zero secrets. |
| 4b | `nixos-hardware` input | Added now. `modules/hardware/` ships empty; real hardware profiles (e.g. MacBook broadcom wifi) land in Phase 3 once tested on 26.05. |
| 5 | home-manager dotfiles | `modules/base/home.nix` (invocation) + `home/` subdir for dotfile modules (mirrors snowi-node's `dotfiles/`). |

## Flake inputs

| Input | Pin / ref | Follows | Source |
|---|---|---|---|
| `nixpkgs` | `github:NixOS/nixpkgs/nixos-26.05` | — | D-010 |
| `home-manager` | `github:nix-community/home-manager/release-26.05` | `nixpkgs` | inherited (snowi-node pattern) |
| `disko` | `github:nix-community/disko` | `nixpkgs` | inherited (FR-1.1) |
| `agenix` | `github:ryantm/agenix` | `nixpkgs` | D-007, D-008 |
| `nixos-hardware` | `github:NixOS/nixos-hardware` | — | choice 4b above |

Explicitly **not** inputs: `portainer-flake` (D-002), `nats-server` (in nixpkgs; D-011). Thing flakes are referenced by path per-host, never as flake inputs (things own their own flakes per D-011).

## Flake outputs

| Output | Purpose |
|---|---|
| `nixosModules.bnox` | Aggregate module — imports all of `modules/`. Default import for consumers. |
| `nixosModules.bnox-base` | Base OS skeleton only (for partial adoption / custom hosts that skip the thing abstraction). |
| `nixosModules.bnox-things` | The thing-hosting abstraction in isolation. |
| `nixosModules.bnox-secrets` | Secrets layer in isolation. |
| `nixosModules.bnox-platform` | Platform services (Podman/Caddy/NATS) in isolation. |
| `nixosConfigurations.<host>` | One per entry under `hosts/`. |
| `packages.${system}.*` | Minimal day-1 (see choice 3). |
| `lib.<helper>` | `mkEnvFile` + thing validators, exposed for thing authors. |
| `overlays.default` | None — bnox does not override nixpkgs. |

## Top-level layout

```
bnox/
├── flake.nix
├── lib/
│   └── default.nix              # mkEnvFile (mkQuadlet dropped per D-002); thing validators
├── modules/
│   ├── default.nix              # aggregate → nixosModules.bnox
│   ├── base/                    # OS skeleton (systemd-native, from snowi-node)
│   ├── platform/                # D-006 platform services (single instance per host)
│   ├── things/                  # D-006 thing-hosting abstraction (load-bearing)
│   ├── secrets/                 # D-007 / D-008
│   ├── deployment/              # D-011 webhook + NATS pipeline
│   ├── profiles/                # server / desktop profiles (FR-12; elaborated in 07-diversions.md)
│   └── hardware/                # hardware profiles (empty day-1; Phase 3)
├── home/                        # home-manager dotfile modules (FR-7.2, FR-7.3)
├── packages/
│   └── default.nix              # minimal (see choice 3)
├── hosts/                       # host configs (D-012 Phase 2 validation onwards)
│   └── <hostname>/
│       ├── configuration.nix
│       ├── hardware-configuration.nix
│       └── disk-config.nix
├── secrets/
│   └── secrets.nix.example      # agenix rules template (choice 4a)
└── doc/                         # bnox-side documentation (README, AGENTS, per-area docs)
```

## Module breakdown

### `modules/base/` — OS skeleton

Adopts snowi-node's systemd-native base. Implements FR-1.2, FR-2, FR-3, FR-7, FR-11.

| File | Owns |
|---|---|
| `system.nix` | locale, timezone (`Africa/Johannesburg` per FR-11.3), base packages (`vim wget git curl jq`), `experimental-features = [ "nix-command" "flakes" ]`, NixOS version state-version |
| `ssh.nix` | Hardened SSH (FR-2.3): no root login, no password auth, pubkey only. Host key reuse point for D-008 (`age.sshKeyPaths` reads `/etc/ssh/ssh_host_ed25519_key`). |
| `users.nix` | Operator user `bh` with `wheel` (FR-2.1); SSH pubkeys declarative (FR-2.2). |
| `networking.nix` | Firewall enabled with sensible defaults (FR-3.2); hostname placeholder (set per-host, FR-3.3); Tailscale enabled (FR-2.4, FR-3.1). |
| `home.nix` | home-manager invocation (`useGlobalPkgs`, `useUserPackages`, `users.bh`); imports `home/` dotfile modules. |

### `modules/platform/` — D-006 platform services

Single instance per host, no per-thing config. Things depend on these, never the reverse.

| File | Owns | Decision |
|---|---|---|
| `podman.nix` | `virtualisation.podman.enable = true`; no Docker pre-installed. | D-002 |
| `caddy.nix` | Base Caddy with no vhosts, ready to be extended by thing shape handlers. Automatic HTTPS. | D-006, FR-5 |
| `nats.nix` | NATS + JetStream. Reserves `host.>` and `things.>` subject namespaces. Creates `host-deploy-logs` stream (filtered on `host.deploy.>`). | D-006, D-011 |
| `static-site.nix` | Caddy `file_server` helper invoked by static-site components (no per-site container). | D-006 |

### `modules/things/` — thing-hosting abstraction (load-bearing)

Implements D-006 + Q9.5 multi-component + Q9.6 user isolation + Q9.7 hardening + Q9.8 daemon shape + Q9.9 host-install runtime.

| File | Owns |
|---|---|
| `default.nix` | `bnox.things.<name>` option schema (below); the `.bnox/` loader (reads each enabled thing's source dir); evaluation-time validators (dep-graph closure, ingress-port uniqueness, NATS subject-prefix uniqueness). Missing dep or collision = loud rebuild failure (D-006 §6/§7). |
| `user.nix` | Per-thing dedicated system user auto-created on enable (Q9.6). Default username = thing name. Owns `/var/lib/<thing>/`. systemd units/containers run as this user. |
| `hardening.nix` | Standard systemd hardening bundle applied per thing (Q9.7): `ProtectSystem=strict`, `ProtectHome=true`, `ReadWritePaths` scoped to thing paths, `PrivateTmp`, `NoNewPrivileges`, `CapabilityBoundingSet=` empty, `SystemCallFilter=@system-service`, `ProtectKernel*`, `ProtectProc=invisible`, resource caps, `IPAddressDeny=any` + allow-list. Overridable per thing via `bnox.things.<name>.hardening`. |
| `shapes/static-site.nix` | Plumbing for static-site components: registers Caddy `file_server` route for the bound domain. No container. |
| `shapes/webapp.nix` | Plumbing for webapp components: Caddy reverse-proxy vhost → declared `ingressPort`. |
| `shapes/http-api.nix` | Plumbing for http-api components: Caddy reverse-proxy (or internal-only). |
| `shapes/nats-api.nix` | Plumbing for nats-api components: allocates `things.<name>.<component>.>` subject prefix; creates one JetStream stream filtered on that prefix (D-006 §5). |
| `shapes/daemon.nix` | Plumbing for daemon components (Q9.8): long-running stateful process, no inbound interface required. First use: Hermes (D-009). |
| `runtimes/container.nix` | Default runtime. Emits `virtualisation.oci-containers.containers.<name>` entry from component spec. Image sourced from thing's flake via the deployment pipeline (D-011 §7). |
| `runtimes/host-install.nix` | `host-install` runtime (Q9.9): bnox provides user + systemd unit + secrets slot + hardening only; thing manages its own install in its user space. Requires Q14 deviation per thing. Hermes is the first (D-009). |

**Host config schema** (refined from Q9.5 sketch — system-level bindings only; thing-intrinsic detail lives in `.bnox/`):

```nix
bnox.things.<name> = {
  enable = true;
  source = "/srv/<name>";                       # git-synced checkout (D-011)

  secrets = {                                   # thing-level binding (default for all components)
    <slot> = { source = ...; };                 # source shape per chosen backend (D-007)
  };

  hardening = {                                 # Q9.7 overrides (optional)
    network.outboundHTTPS = true;               # e.g. for a daemon needing egress
  };

  components.<component> = {
    enable = true;
    domain = "...";                             # host-specific, if HTTP-exposed
    ingressPort = ...;                          # validated unique across enabled things (D-006 §6)
    secrets = { <slot> = { source = ...; }; };  # component-level binding overrides thing-level
  };
};
```

**Thing repo layout** (the `.bnox/` convention, Q9.5 — thing-intrinsic, not host-set):

```
<thing>/                         # one thing = one repo = one deploy unit
├── .bnox/
│   ├── thing.nix                # deps, natsSubject prefix, secret slot names, component list
│   └── <component>.nix          # per component: shape, runtime, ingressPort, image derivation ref
├── <component>/                 # component code + Nix derivation
└── flake.nix                    # exposes images.<system>.<component> (D-011 §7)
```

The loader in `things/default.nix` reads `.bnox/` from each enabled thing's `source` path, merges it with host-level bindings, and validates consistency. Shape taxonomy, deps, ports, and subject prefixes come from `.bnox/`; enable/domain/secrets-binding come from host config (Q9.5 symmetry rule).

### `modules/secrets/` — D-007 / D-008

| File | Owns |
|---|---|
| `default.nix` | `bnox.secrets.thingsBackend = "file" \| "nats-kv"` selector; dispatches to chosen backend. |
| `infra.nix` | agenix wiring: `age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ]` (D-008); every secret carries a second recipient entry for the off-host recovery key. |
| `backends/file.nix` | **Hybrid-1 default.** Secrets as plaintext files at `/var/lib/bnox/secrets/<thing>/<slot>`, chown'd to the thing's user (Q9.6). One `systemd-path` unit per slot; on change, restarts the thing's container/unit. Update flow: operator writes new value via SSH/scp, path unit fires, no host rebuild. |
| `backends/nats-kv.nix` | **Hybrid-2 scaffold** — interface only, not implemented day-1 (D-007, Q14 guardrail). Fetches from NATS KV, decrypts with host key, writes local paths, restarts affected things. Built when multi-host or central-update becomes a real need. |

### `modules/deployment/` — D-011 webhook + NATS pipeline

| File | Owns |
|---|---|
| `webhook-receiver.nix` | Global `bnox-webhook-receiver.service` (one per host, not per thing). Receives push events from GitHub/Forgejo via a Caddy vhost; publishes `host.deploy.<name>.changed` to NATS. Per-thing HMAC auth via D-007 `file` backend. |
| `pipeline.nix` | Per-thing `<name>-sync.service` (subscribes `.changed` → `git fetch && git reset --hard origin/main` → publishes `.synced`) and `<name>-build.service` (subscribes `.synced` → `nix build /srv/<name>#images.<system>.<component>` for each component → `podman load` → `systemctl restart` → publishes `.built`/`.deployed`). On-host default; off-host + registry pattern supported per thing's `.bnox/` declaration. |
| `rollback.nix` | Retains last 3 image tarballs per thing at `/var/lib/<thing>/images/<git-sha>.tar`. Daily systemd timer prunes to 3. Rollback = `podman load <prior>.tar` + `systemctl restart`. Fits NFR-6. |

Hermes excluded — self-manages via `hermes update` (D-009).

### `modules/profiles/` — FR-12 (elaborated in `07-diversions.md`)

Day-1 structure: `server.nix` (headless, no X) and `desktop.nix` (X + qtile + ly + terminal + browser). Composable with hardware add-ons from `modules/hardware/`. A host picks one profile plus optional hardware modules. Full per-host extension pattern is Phase 6.

### `modules/hardware/` — empty day-1 (Phase 3)

Ships empty. Real hardware profiles (e.g. `macbook-broadcom-wifi.nix`, per FR-12.3) are added during D-012 Phase 3, built on `nixos-hardware` and tested on 26.05 before adoption.

## Runtime paths

| Path | Owner | Purpose | Decision |
|---|---|---|---|
| `/etc/ssh/ssh_host_ed25519_key` | NixOS | SSH host key; reused as agenix decryption key | D-008 |
| `/srv/<thing>/` | thing's user | git-synced checkout of the thing's repo | D-011, Q9.5 |
| `/var/lib/<thing>/` | thing's user | thing home + state | Q9.6 |
| `/var/lib/bnox/secrets/<thing>/<slot>` | thing's user | per-thing secret files (file backend) | D-007, Q9.6 |
| `/var/lib/<thing>/images/<git-sha>.tar` | thing's user | retained image tarballs for rollback | D-011 §8 |
| `/var/lib/hermes/` | `hermes` user | Hermes home, venv, state | D-009 |

## Deferral boundaries (what is NOT in bnox)

Per D-012, bnox ships standalone. None of the following are part of bnox itself:

- **Thing repos** — each thing (Hermes, future webapps, etc.) lives in its own repo with its own flake exposing `images.<system>.<component>`. bnox hosts them; bnox is not them.
- **Migration shims** — no uqbn or snowi-node compatibility layers. Migration is a per-thing operator activity (D-012 Phase 3/4).
- **The `nats-kv` secrets backend** — designed-for, scaffolded, not implemented (D-007, Q14).
- **L1/L2 NATS isolation** — L0 convention only day-1; per-thing NATS users (L1) and accounts (L2) are future additive upgrades (D-006 §8).
- **Hardware profiles** — empty until Phase 3.
- **Provisioning helper script** — a bnox wrapper around `nixos-generate-config` + `nixos-anywhere` that emits a `hosts/<name>/` skeleton is a Phase 2 deliverable, not Phase 5.

## Phase 3 risk note (hardware validation on the MacBook)

D-012 Phase 3 wipes the MacBook and installs bnox. uqbn's hardware config (broadcom wifi in particular) was hard-won; the risk is that a fresh install with a re-derived hardware config on NixOS 26.05 breaks networking, and recovery means typing on the physical MacBook.

Mitigations (to be elaborated in Phase 3 planning; recorded here so they are not lost):

1. **Post-install deploys are safe via NixOS generations.** Each `nixos-rebuild` creates a boot-menu entry; a bad deploy → reboot → pick previous generation → recovered. No config typing, no SSH required. This is the built-in safety net for everything *after* first boot.
2. **First install is the genuinely risky moment** — no previous generation exists. Mitigation: validate the candidate bnox + hardware config from a **live USB before wiping uqbn** (boot USB, confirm wifi/trackpad/etc. work, *then* wipe). Standard pre-install validation.
3. **Conservative hardware profile.** Start from `nixos-hardware`'s maintained MacBook profile + what `nixos-generate-config` detects; avoid hand-rolled broadcom quirks unless nixos-hardware proves insufficient on 26.05.
4. **Keep uqbn recoverable** until bnox is proven end-to-end on the MacBook (e.g. via the live-USB validation above, or dual-boot if extra caution is warranted).

This is a Phase 3 execution concern, not a Phase 5 design change. bnox provides the *infrastructure* for hardware profiles (now in place); the testing procedure is Phase 3.

## Open items carried to Phase 6

- The full per-host extension / profile / diversion pattern (how `hosts/<name>/configuration.nix` composes with `modules/profiles/` + `modules/hardware/` + thing bindings) is the subject of `07-diversions.md`.
- Q6 (macOS build capability) and Q8 (uqbn role trajectory) remain non-blocking; revisit when Phase 3 planning begins.
