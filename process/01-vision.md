# Vision

## Goal

A single, opinionated NixOS base flake + module set that serves as the foundation for all of the user's NixOS systems. Adding a new system means: clone the base, override a small number of host-specific keys (hostname, hardware, services), deploy. No more copy-pasting `configuration.nix` between boxes and watching them drift.

## Why

Today the user maintains two NixOS boxes that:
- Solve the same problems differently (Docker vs Podman; manual disk vs Disko; inline config vs factored modules)
- Duplicate effort (every new box re-derives SSH hardening, deploy scripts, secret patterns)
- Drift in NixOS versions and conventions
- Cannot easily inherit improvements from one another

`snowi-node` is significantly more mature operationally (Disko, modular, hardened SSH, deploy scripts, docs, `AGENTS.md`). `uqbn` is more desktop-aware (qtile, wifi, dotfiles). The base should take snowi-node's operational patterns as the starting point and add uqbn's desktop capabilities as an optional profile.

## In scope

- Base flake structure (inputs, outputs)
- Disk management (Disko)
- User + SSH defaults (hardened)
- Networking defaults (Tailscale, firewall)
- Container runtime + image build pattern (one runtime chosen)
- Reverse proxy (Caddy)
- Secrets pattern (one manager chosen)
- Home-manager base (nvim, git, shell, dotfile symlink idiom)
- Module-per-service pattern with shared lib helpers
- Deploy scripts
- `AGENTS.md` / `README.md` conventions
- A "minimal" bootstrap config for nixos-anywhere
- Profile system for diversions: `desktop.nix`, `server.nix`, hardware modules

## Out of scope

- The user's application code (Go services, etc.) — that stays in snowi-node
- Migrating existing systems forcibly — that's a follow-up decision (Q5)
- macOS / aarch64-darwin configs — base is x86_64-linux for now (the deploy machine is darwin but targets are linux)

## Success criteria

- A new NixOS box can be provisioned by: writing a ~30-line `hosts/<name>.nix`, running `nixos-anywhere`, done.
- Improvements made for one system (e.g. a better deploy script) automatically apply to all.
- A new agent reading `STATUS.md` + `memory/agent-handoff.md` can continue the work without context loss.
- Both existing systems (`uqbn`, `snowi-node`) **could** be expressed as the base + a small host-specific override file (whether they actually get migrated is a separate decision).
