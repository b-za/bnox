# Things

A **thing** is an application hosted by bnox: a webapp, a static site, an HTTP API, a NATS service batch, or a daemon. Things live in their own repos; bnox hosts them without rebuilds.

## Declaring a thing on a host

```nix
# host repo flake.nix: the thing repo is a flake input (inputs.myapp.url = "git+ssh://…/myapp.git")
bnox.things.myapp = {
  enable = true;
  source = "${myapp}";                  # where bnox reads .bnox/ — a locked flake input
  branch = "main";                      # optional; default main, .bnox/ may declare it
  components.web.domain = "myapp.example.com";
};
```

**Two copies, two jobs (from 0/3/1):**

- `source` is only where bnox reads the thing's `.bnox/` manifest at evaluation. It must be a store path — a flake input of the host repo. Flake evaluation is pure: a `/srv/...` path is invisible to it, so `source = "/srv/myapp"` can never load a manifest under `nixos-rebuild --flake`.
- The **code** is always built from the git checkout `/srv/<name>` by the deploy pipeline ([deployment.md](./deployment.md)). Pushing code never needs a rebuild.
- Bump the host repo's lock (`nix flake update myapp`) and rebuild **only when `.bnox/` changes**. The build unit logs a `WARNING` when `/srv/<name>/.bnox/` differs from the evaluated manifest.
- Static sites are served from `source`, so they update with the lock, not with the pipeline.

Host config carries only host-specific bindings (enable, source, domain, secrets). Thing-intrinsic facts (shape, runtime, ports, subjects, execStart, deps) are read from the thing's own repo — never duplicated in host config.

## The `.bnox/` convention

Each thing repo has a `.bnox/` directory at its root:

```
myapp/
├── .bnox/
│   ├── thing.nix          ← manifest: deps, thing-level secrets, nats = true for broker things
│   └── web.nix            ← per-component: shape, runtime, ingressPort, …
├── flake.nix              ← exposes images.<system>.<component> (container runtime)
└── …                      ← the app itself
```

bnox loads these at evaluation and merges them as defaults (`mkDefault`); host config can still override per host. A thing without `.bnox/` fails evaluation loudly.

## Plain config: `env` (from 0.4)

Non-secret settings go in `env`, never in a secret slot. The thing's `.bnox/thing.nix` gives defaults; host config wins per key. Every component of the thing gets them as environment variables (both runtimes). Changing a value takes a rebuild.

```nix
# .bnox/thing.nix
env = { LOG_LEVEL = "info"; };
# host config
bnox.things.gsheet.env.GSHEET_ADMINS = "brix";
```

## Outbound network: `egress` (from 0.4)

Locked by default: a thing reaches nothing beyond loopback until the host grants it (D-019).

```nix
# .bnox/thing.nix — what the thing needs
egress = [ "sheets.googleapis.com" ];   # or "any"
# host config — the ceiling (a domain also covers its subdomains)
bnox.things.gsheet.egress.grant = [ "googleapis.com" ];   # or "any"
```

| needs | grant | result |
|---|---|---|
| list | list | the needed domains the grant covers, via the thing's proxy |
| list | `"any"` | the needed domains, via the proxy |
| `"any"` | list | the granted domains, via the proxy |
| `"any"` | `"any"` | direct access |
| anything | nothing | none (needs not granted show up as rebuild warnings) |

Each thing with a domain list gets **its own** proxy (`bnox-egress-<thing>`, tinyproxy on `127.0.0.1`, ports from `bnox.egress.basePort` = 18100, one per thing) that allows exactly its domains, and `HTTPS_PROXY`/`HTTP_PROXY` in its environment. Containers reach it through slirp at `10.0.2.2`. Software that ignores `HTTPS_PROXY` simply cannot get out. `hardening.network.outboundHTTPS` is gone — use `egress`.

**Host-wide lockdown (opt-in).** The rules above bind bnox's own units. `bnox.egress.hostLockdown = true` also stops everything else — stray processes, interactive users, hand-written units — from connecting out on ports 80/443: an nftables output table (`bnox_egress`) where only root, the egress proxies, Caddy, host-install things granted direct `"any"`, and `bnox.egress.hostLockdownAllowUsers` may. Fail-open by construction (accept by default, explicit drops), never touches input, loopback or other ports. Meant for agent hosts; leave it off on a desktop, or add your user to `hostLockdownAllowUsers`.

## Inbound: `inbound` / `exposure` (from 0.4)

The mirror of `egress`. Locked by default: a component is reachable only on the host's loopback until the host exposes it (D-019).

```nix
# .bnox/<component>.nix — the port, and the most exposure the component accepts (default public)
ingressPort = 9191; exposure = "tailnet";
# host config — the level, plus the name (the host owns domains and certificates)
bnox.things.che.components.dashboard = { domain = "agent-che.example.com"; inbound = "public"; };
```

Final level = the more restrictive of `inbound` (default `internal`) and `exposure`:

| Level | Result |
|---|---|
| `internal` | no vhost; loopback only |
| `tailnet` | Caddy vhost that drops every client outside the tailnet (`100.64.0.0/10`, `fd7a:115c:a1e0::/48`) |
| `public` | plain Caddy vhost (automatic HTTPS) |

Works for every shape and runtime: static sites serve their files, everything else is proxied to `127.0.0.1:<ingressPort>`. Login protection is the app's own job. A domain without an exposing level is reported as a rebuild warning.

## Host-install switches (from 0.4)

Two `.bnox/thing.nix` switches for host-install things that need them to work at all (D-020). Both default off; your control over the thing stays in NATS, `egress` and `inbound`.

- `shell = true` — the thing's user gets bash instead of `nologin` (agents whose job is running commands).
- `nixLd = true` — enables nix-ld and sets `NIX_LD`/`NIX_LD_LIBRARY_PATH` in the thing's units, so downloaded prebuilt Linux programs (managed Python, Node, …) can start on NixOS.

## Container images: `bnox.lib.mkImage` (from 0.4)

Build container images with bnox's helper instead of bare `dockerTools` — it always includes `/etc/passwd` + `/etc/group`, `HOME=/root`, a CA store (`/etc/ssl/certs/ca-certificates.crt`, `SSL_CERT_FILE`) and `/tmp`, each of which a bare image lacks:

```nix
# thing repo flake.nix (inputs.bnox.url = "github:b-za/bnox?dir=versions/0/4/0")
images.x86_64-linux.main = bnox.lib.mkImage {
  inherit pkgs; name = "myapp-main";
  contents = [ myapp ]; entrypoint = [ "/bin/myapp" ];
};
```

## Shapes

| Shape | Meaning | bnox provides |
|---|---|---|
| `static-site` | files only | Caddy `file_server` vhost (no container) |
| `webapp` | HTTP with UI | Caddy reverse_proxy vhost + container |
| `http-api` | REST/WS, no UI | reverse_proxy (or internal-only if `domain = null`) + container |
| `nats-api` | batch of NATS services sharing a stream | subject prefix `things.<name>.>`, one JetStream stream |
| `daemon` | long-running stateful process, outbound only | systemd unit, no inbound wiring |

## Runtimes

| Runtime | Meaning |
|---|---|
| `container` (default) | Nix-built image (`pkgs.dockerTools.*` — Dockerfiles are forbidden), run under Podman with the full hardening bundle |
| `host-install` | thing installs/updates itself on the host; bnox provides only user, systemd unit, hardening, secrets (rare; requires a logged deviation — see Hermes) |

### The `nats` knob

A thing that talks to the host NATS broker declares `nats = true` in `.bnox/thing.nix` (or `bnox.things.<name>.hardening.network.nats` in host config). Container things then get:

- slirp4netns networking with the host loopback reachable at the fixed gateway `10.0.2.2`; the broker address is injected as `NATS_URL=nats://10.0.2.2:4222`
- an egress allow-list of exactly `10.0.2.2` + `127.0.0.1` under the standard deny-any filter (both required: the slirp relay's host-side connect targets loopback)
- an implied `nats_seed` slot (see [secrets.md](./secrets.md)) holding the nkey seed

host-install things get the same slot and `NATS_URL=nats://127.0.0.1:4222` (they share the host netns).

Notes: `IPAddressAllow` on the pinned systemd (260) has no port scoping, so the allows are address-wide — the broker's own auth (nkeys) is the real door. Combining `nats` with `ingressPort` is untested; workers are headless.

## Isolation

Every enabled thing gets a dedicated system user — the host-side boundary: owner of its `/var/lib/<thing>` state and its secrets slots. Unit hardening depends on the runtime: host-process things get the standard bundle (filesystem lockdown, capability stripping, syscall filtering, process visibility, network egress allow-list); container things get the runner profile (podman is the payload's sandbox — the unit keeps the filesystem layout, the address families and the egress allow-list, and drops the process-level lockdown that rootful podman cannot run under). Container payloads run as container root — the container is their isolation boundary; a thing wanting a non-root payload user bakes one into its own image. Overrides are per-host, visible in host config — never silent.

## Fixtures

This version ships two complete reference things as fixtures: `demo-thing` (container webapp) and `mock-daemon` (host-install daemon). Host repos consume them via `bnox.fixtures.demo-thing` / `bnox.fixtures.mock-daemon` (the bnox-test host uses both).

## Dependencies

`deps = [ "other-thing" ]` in `.bnox/thing.nix`. bnox validates the dependency graph at evaluation time (missing dep = loud failure) and derives systemd ordering.

## Updating a thing

See [deployment.md](./deployment.md) — git push to the thing repo triggers the pipeline; no host rebuild.
