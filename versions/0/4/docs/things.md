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
