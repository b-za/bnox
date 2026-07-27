# Base Design

**Status:** Not started. Draft after decisions D-001 through D-005 are accepted in `05-decisions.md`.

## Will contain

- Target `flake.nix` structure (inputs, outputs, host enumeration)
- Module organization:
  - `modules/base/` — always-on defaults (user, SSH, Tailscale, firewall, time, packages)
  - `modules/profiles/` — `server.nix`, `desktop.nix`
  - `modules/hardware/` — host-specific kernel / wifi / disk modules
  - `modules/services/` — reusable service modules (caddy defaults, container helpers, etc.)
- `lib/` — shared Nix helpers (`mkQuadlet` / `mkEnvFile` or runtime-specific equivalents)
- `hosts/<name>/` — per-host directory with `default.nix` (the host override file)
- Default configuration values
- Step-by-step "adding a new host" recipe
