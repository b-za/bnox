# bnox

A unified, reusable NixOS base. Add a host by writing a small `hosts/<name>/configuration.nix` that diverges from this base.

## Status

In design / pre-implementation. The full design rationale, decision log (D-001 through D-012), and process live in [`design/`](./design/). Start at [`design/STATUS.md`](./design/STATUS.md) for current phase and blockers.

## Target structure

```
bnox/                              <- repo = the flake
├── flake.nix                      <- entry point
├── lib/                           <- bnox lib helpers
├── modules/                       <- NixOS modules: base, platform, things, secrets, deployment, profiles, hardware
├── home/                          <- home-manager dotfile modules
├── hosts/                         <- per-host configs (auto-discovered)
├── packages/                      <- bnox-owned packages (minimal)
├── secrets/                       <- agenix rules template
├── doc/                           <- user-facing docs
└── design/                        <- design workspace (not part of the flake)
```

Consumers reference this repo as a flake (`inputs.bnox.url = "github:<user>/bnox"`) or fork it and add host configs under `hosts/`. See [`design/process/06-base-design.md`](./design/process/06-base-design.md) and [`design/process/07-diversions.md`](./design/process/07-diversions.md) for the concrete layout and per-host extension pattern.
