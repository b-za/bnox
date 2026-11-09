# Things

A **thing** is an application hosted by bnox: a webapp, a static site, an HTTP API, a NATS service batch, or a daemon. Things live in their own repos; bnox hosts them without rebuilds.

## Declaring a thing on a host

```nix
bnox.things.myapp = {
  enable = true;
  source = "/srv/myapp";               # git checkout on host (deployment syncs it)
  branch = "main";                      # optional; default main, .bnox/ may declare it
  components.web.domain = "myapp.example.com";
};
```

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

Every enabled thing gets a dedicated system user and a standard systemd hardening bundle: filesystem lockdown, capability stripping, syscall filtering, cgroup resource caps, network egress allow-list. Overrides are per-host, visible in host config — never silent.

## Fixtures

This version ships two complete reference things as fixtures: `demo-thing` (container webapp) and `mock-daemon` (host-install daemon). Host repos consume them via `bnox.fixtures.demo-thing` / `bnox.fixtures.mock-daemon` (the bnox-test host uses both).

## Dependencies

`deps = [ "other-thing" ]` in `.bnox/thing.nix`. bnox validates the dependency graph at evaluation time (missing dep = loud failure) and derives systemd ordering.

## Updating a thing

See [deployment.md](./deployment.md) — git push to the thing repo triggers the pipeline; no host rebuild.
