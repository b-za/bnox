# Requirements

What the unified base must provide. Each requirement is evaluated against both existing systems in `04-comparison.md`.

## FR-1: Provisioning
- **FR-1.1** Declarative disk layout (Disko-style) so a new box can be installed with `nixos-anywhere` and zero manual partitioning.
- **FR-1.2** A minimal bootstrap config (root password, SSH up, basic networking) for first-boot.
- **FR-1.3** Reproducible — same input revision → same system.

## FR-2: User & Access
- **FR-2.1** Standard user `bh` with `wheel` (sudo).
- **FR-2.2** SSH public keys declarative in the config.
- **FR-2.3** Hardened SSH defaults: no root login, no password auth, pubkey only.
- **FR-2.4** Tailscale enabled by default for private network access.

## FR-3: Networking
- **FR-3.1** Tailscale enabled.
- **FR-3.2** Firewall enabled with sensible defaults; per-host port openings.
- **FR-3.3** Hostname set per-host.
- **FR-3.4** Network config abstracted per-host (DHCP / static / WiFi).

## FR-4: Container runtime & images
- **FR-4.1** Single container runtime chosen and standardized.
- **FR-4.2** Image build pattern that's reproducible from Nix (no Dockerfiles in repos).
- **FR-4.3** Service-via-container pattern abstracted into a module helper.

## FR-5: Reverse proxy & TLS
- **FR-5.1** Reverse proxy with automatic HTTPS.
- **FR-5.2** Per-vhost config in service modules (not in the top-level configuration).

## FR-6: Secrets
- **FR-6.1** Secrets NOT hardcoded in the repo.
- **FR-6.2** Secrets encrypted-at-rest in the repo via a real secrets manager (sops-nix or agenix).
- **FR-6.3** Templates / examples committed for documentation.

## FR-7: Home-manager
- **FR-7.1** Standard home-manager user (`bh`).
- **FR-7.2** Shared dotfile symlink pattern (`~/dotfiles/config/<app>` via `mkOutOfStoreSymlink`).
- **FR-7.3** Standard nvim module (LSPs, lazy.nvim deps, telescope, etc.).

## FR-8: Module structure
- **FR-8.1** Each service/app is a self-contained NixOS module under `modules/`.
- **FR-8.2** Shared Nix helpers live in `lib/`.
- **FR-8.3** Top-level `configuration.nix` only imports modules + sets host-specific values (no large inline blocks).

## FR-9: Deployment
- **FR-9.1** Tiered deploy scripts: platform / app / content.
- **FR-9.2** Buildable from macOS (aarch64-darwin) → deployed to x86_64-linux targets.
- **FR-9.3** No requirement that `nixos-rebuild` runs only on the target (or a documented exception when it must).

## FR-10: Documentation
- **FR-10.1** `README.md` with: what runs on the box, directory structure, how to deploy, key gotchas, secrets layout.
- **FR-10.2** `AGENTS.md` orienting any agent on the repo.
- **FR-10.3** Per-service `docs/<service>.md` for anything non-trivial.

## FR-11: Standard tooling
- **FR-11.1** `experimental-features = [ "nix-command" "flakes" ]`.
- **FR-11.2** Standard system packages baseline: `vim wget git curl jq`.
- **FR-11.3** Time zone set per user (`Africa/Johannesburg`).

## FR-12: Profiles (the "diversion" pattern)
- **FR-12.1** A `server` profile (headless, no X).
- **FR-12.2** A `desktop` profile (X server + qtile + ly + terminal + browser).
- **FR-12.3** Profiles composable: a host picks one of (server, desktop) plus optional hardware add-ons (e.g. `hardware/macbook-broadcom-wifi.nix`).

## FR-13: Version & inputs
- **FR-13.1** Single pinned NixOS version across the base.
- **FR-13.2** Standard set of flake inputs (nixpkgs, home-manager, disko, + chosen secrets manager).

## Non-functional
- **NFR-1** Reproducibility — same flake lock → same system.
- **NFR-2** Security defaults conservative (deny by default).
- **NFR-3** Each existing system should be expressible as base + small host override.
- **NFR-4** No hard regression for `snowi-node` (the production box) when migrated.
- **NFR-5** Workflow is git-first (no out-of-band state that isn't documented).
