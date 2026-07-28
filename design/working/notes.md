# Working notes

Scratch space. Anything here may be rough, wrong, or speculative. Promote durable findings to the appropriate `process/` file when ready.

## 2026-07-27 — Initial discovery session

### Cross-system surprises

- uqbn and snowi-node ship **identical** `modules/neovim.nix` files (byte for byte). The nvim module is already a de-facto shared component.
- Both `home.nix` files have the same shell alias `btw = "echo i use nixos, btw"`. Same author voice.
- uqbn has the SSH pubkey not configured at all; snowi-node has the same `bh@bmac.local` RSA key — easy to standardize on.
- Neither system uses a real secrets manager — clear gap to fill in the base.
- snowi-node's `AGENTS.md` is excellent; that pattern becomes a base requirement (FR-10.2).
- Tailscale Funnel docs (`go_public.md`, `tailscale_port_grab_fix.md`) are duplicated in both repos. Clear candidate for shared base docs.

### Speculation (to verify later)

- The base could ship with a default `caddy` that has no vhosts, ready to be extended by service modules. Likely yes.
- Adding `nixos-hardware` as a flake input would handle MacBook quirks (broadcom wifi, cpu microcode, etc.) cleanly. Likely yes.
- `dockerTools.streamLayeredImage` works with both Docker and Podman — the image-build pattern is runtime-agnostic; only the load command differs (`docker load` vs `podman load`).
- snowi-node uses `nixos-24.11-small` (small channel = faster fetch, fewer packages). Whether the base should use `-small` is Q7.
- The user has `evolution` and `mealie` as separate Tailscale devices online — suggests they may already be running those workloads outside uqbn. Worth understanding before assuming uqbn is the only place Docker runs.

### Things to verify on the boxes themselves

- Actual wifi interface name on uqbn (run `ip link` on the box) — needed if we write a `hardware/macbook-broadcom-wifi.nix`.
- Whether Disko can re-partition uqbn without data loss (almost certainly not — Disko is for fresh installs; uqbn would need a reinstall).
- Whether nixos-anywhere can target a running MacBook over SSH (yes, in theory).
- Go version mismatch: snowi-node AGENTS.md says Go 1.22; newer NixOS would give a newer Go. Pin in packages if needed.
