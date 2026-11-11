# Deployment (thing updates)

OS changes go through `nixos-rebuild` in the host repo. **Thing changes never do.** A thing update flows through an event pipeline:

```
git push (thing repo)
   → webhook (GitHub/Forgejo → Caddy vhost → bnox-webhook-receiver, HMAC-verified per thing)
   → NATS  host.deploy.<thing>.changed
   → bnox-deploy-dispatcher  (the ONLY subscriber; a global router)
   → <thing>-sync.service    (oneshot, runs as the thing's user: git fetch + reset, publishes .synced)
   → <thing>-build.service   (oneshot, root: nix build → podman load → retag :current, publishes .built)
   → systemctl restart podman-<thing>-<component>
   → host.deploy.<thing>.deployed
```

Everything is on the `host.deploy.<name>.{changed,synced,built,deployed,failed}` subjects, persisted in the `host-deploy-logs` JetStream stream — a full audit trail of every deployment of every thing. Watch it live:

```bash
nats sub 'host.deploy.>'
```

## Constant footprint

Two global services (webhook receiver + dispatcher), regardless of how many things run. Per thing: 2 oneshots (sync, build) + its container(s). Nothing idles waiting per-thing.

## What a thing repo must provide

- `.bnox/` metadata ([things.md](./things.md)).
- For container runtime: a flake exposing `images.<system>.<component>` (built with `dockerTools.*`).
- Build pattern: on-host by default (`build = "on-host"` in `.bnox/`); off-host + registry supported.

## Webhook setup

- Set the host's webhook address if it differs from the default: `bnox.deployment.webhook.address = "https://deploy.example.com";` (default `http://bnox-webhook.local`, internal-only). The address is the Caddy vhost — a real domain gets automatic TLS.
- Register the webhook in GitHub/Forgejo pointing at that address + `/bnox/webhook/<thing>`, content-type JSON, push events.
- The per-thing HMAC secret lives at `/var/lib/bnox/deploy/<thing>/webhook_secret` (write it, done — no rebuild).

## Rollback

The build unit keeps the last 3 image tarballs per thing at `/var/lib/<thing>/images/<sha>.tar` (a daily timer prunes). Rollback is manual and boring by design:

```bash
podman load -i /var/lib/<thing>/images/<sha>.tar
systemctl restart podman-<thing>-<component>
```

OS-level rollback is NixOS generations (boot menu entry per rebuild).

## Exceptions

Hermes-style `host-install` things self-update (`hermes update`); the pipeline ignores them.

## Known limits (series 0.3)

- **The pipeline publishes to NATS without credentials.** On a broker that requires logins (agenthub), `host.deploy.*` publishes are rejected; the dispatcher (nats-py) cannot use nkeys either. Fixed properly in 0/4/0 (D-018: bnox service identities); until then hosts with a locked broker wire credentials host-side.
- **`nixos-rebuild` may exit 4 after a NATS auth change.** The broker restarts inside the switch; a unit connecting at that moment (e.g. `bnox-deploy-dispatcher`) fails once and auto-restarts seconds later, but the switch already reported it. Check `systemctl is-active <unit>` a few seconds later before chasing it.
