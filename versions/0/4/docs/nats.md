# NATS (series 0.4)

The host broker (loopback only) **always requires a login** — there is no anonymous access (D-018). bnox gives every party its own identity (an nkey), computes what each may publish and subscribe to at rebuild, and writes that into the broker.

## Subjects and streams

- `host.>` belongs to bnox (deploy events: `host.deploy.<thing>.*`).
- `things.<name>.>` belongs to the thing `<name>`. Its repo decides everything beneath.
- Every NATS thing gets one JetStream stream, `things-<name>`, over `things.<name>.>` (retention: `bnox.nats.streamMaxAgeDays`, default 30).

## Who may do what — two levels

A thing always has full access to its own `things.<name>.>` and its own stream. Access to **another** thing is the overlap of two declarations:

**The thing offers** (its `.bnox/thing.nix`, subjects relative to `things.<name>.`):

```nix
nats = {
  offer.publish   = [ "command.>" ];   # the most anyone else can ever get
  offer.subscribe = [ "event.>" ];
  roles.user  = { publish = [ "command.*.read.>" ]; subscribe = [ "event.>" ]; };
  roles.admin = { publish = [ "command.>" ];        subscribe = [ "event.>" ]; };
};
```

`nats = true` still works (a NATS thing that offers nothing). Every role must fit inside the offer — bnox fails the rebuild otherwise.

**The host grants** (host config) — one role per dependency, or `"offer"` for the whole offer:

```nix
bnox.things.che.nats.grants.gsheet  = "user";
bnox.things.brix.nats.grants.gsheet = "admin";
```

A grant requires the dependency in the thing's `deps`. Nothing is granted by default.

**Escape hatch** (visible in host config): `bnox.things.<name>.nats.extra.{publish,subscribe}` adds absolute subjects to a thing's identity — e.g. a KV bucket outside the thing model.

## Identities

| Identity | Access | Seed readable by |
|---|---|---|
| `<thing>` | own prefix + stream + grants + extra | the thing's group |
| `ops` | everything | root only |
| `bnox-webhook-receiver` | publish `host.deploy.*.changed` | the receiver |
| `bnox-deploy-dispatcher` | subscribe `host.deploy.>` | root |
| `bnox-deploy-<thing>` | publish `host.deploy.<thing>.>` (sync + build) | the thing's group |
| host extras | `bnox.nats.identities.<name> = { publish; subscribe; readers; }` | `readers` group |

Seeds live at `/var/lib/bnox/nats/<identity>.seed`, generated once on the host and never regenerated or committed (`bnox-nats-keygen`). A thing receives its seed two ways: the `nats_seed` slot (`NATS_SEED=<seed>` as an env var) and, for host-install things, `NATS_NKEY=<seed file>` (what `nats` CLI expects). If a key must ever survive a host reinstall, the recorded alternative is agenix-encrypted seeds (D-018) — not built.

## By hand

```bash
sudo env NATS_NKEY=/var/lib/bnox/nats/ops.seed nats stream ls
```

A user-level `nats` context (`~/.config/nats/context/`) silently overrides the environment — check for one if logins fail unexpectedly.

## Runtime units

`bnox-nats-keygen` → `bnox-nats-auth` (assembles `/var/lib/bnox/nats/auth.json`, validates it with `nats-server -t`, restarts the broker only when it changed) → `nats` → `bnox-nats-streams`.

A rebuild that changes permissions restarts the broker; a client connecting at that instant fails once and restarts itself seconds later, but `nixos-rebuild` may already have reported it (exit 4). Check `systemctl is-active <unit>` a few seconds later.

## Checking it: `bnox-validate`

```bash
sudo bnox-validate
```

Generated from the computed permission matrix (D-020): every allow pattern becomes a concrete probe subject (wildcards replaced by the token `_bnox_validate_`), and every identity publishes every probe. The broker must accept exactly where that identity's permissions cover the probe, and reject everywhere else; an anonymous connection must be rejected. Infrastructure subjects (`$JS.*`, `_INBOX.*`) are not probed. Exit code 0 = all checks passed — part of the done rule for a bnox version.

Accepted probes are real messages: they land in the target thing's stream. Things should ignore subjects containing `_bnox_validate_` (the deploy dispatcher does).
