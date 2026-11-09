# bnox docs — series 0.2

Consumer documentation for bnox versions 0.2.x. Start with [getting-started.md](./getting-started.md).

| Page | What it covers |
|---|---|
| [getting-started.md](./getting-started.md) | Create a host repo, pin a bnox version, add a host, install it |
| [host-config.md](./host-config.md) | The per-host divergence file: profiles, hardware, things, firewall |
| [things.md](./things.md) | Hosting a "thing": shapes, runtimes, the `.bnox/` convention, fixtures |
| [secrets.md](./secrets.md) | The two secret layers: agenix (infra) and the file backend (things) |
| [deployment.md](./deployment.md) | How thing updates flow: webhook → NATS → sync/build → restart |
| [versioning.md](./versioning.md) | The `versions/<maj>/<min>/<patch>/` model, manifests, freeze rules |
| [promotion.md](./promotion.md) | Promoting a host-specific element into bnox (opt-in or new default) |
| [examples/](./examples/) | Example host configs: VPS server, desktop, thing-hosting |

bnox is a unified, reusable NixOS base. You never install bnox onto a running system; you build NixOS hosts that consume it as a flake input. Each host lives in your own git repo, pins a specific bnox version directory, and overrides only what diverges from the base.
