# Systems Inventory

What the user runs today.

## uqbn

- **Hardware:** Old MacBook, x86_64, Broadcom wifi (`broadcom-sta` / `wl` driver)
- **Role:** Personal desktop + Docker host
- **NixOS:** 25.05
- **Network:** WiFi via `networking.wireless` (wpa_supplicant, **hardcoded PSK in repo**), Tailscale
- **Disk:** Manual partitioning, plain ext4 root, no Disko, no encryption
- **Boot:** systemd-boot EFI
- **Containers:** Docker with `userland-proxy = false` and `checkReversePath = loose`
- **Reverse proxy:** None — uses Tailscale Funnel for public exposure
- **Desktop:** X server + qtile + ly display manager + alacritty + firefox + nerd-fonts
- **Home-manager:** Yes — qtile / nvim / ghostty / rofi configs as out-of-store symlinks to `~/dotfiles/config`
- **SSH:** Enabled but weak — password auth allowed, no SSH key configured for `bh`
- **Secrets:** Hardcoded wifi PSK in repo (security issue)
- **Modules:** Inline `configuration.nix`; single neovim home-manager module
- **Deploy:** Manual `nixos-rebuild switch`
- **Docs:** Sparse (2 markdown files in `docs/`)
- **Flake inputs:** nixpkgs-25.05, home-manager-25.05, portainer-flake
- **Services running:** Portainer (9443), Docker containers (evolution_api, mealie, test)
- **Repo:** `/Users/bh/code/systems/uqbn/`

## snowi-node (snowinode)

- **Hardware:** Cloud VPS at `160.119.248.187` (2GB RAM, x86_64, virtio)
- **Role:** Production application server
- **NixOS:** 24.11 (`nixos-24.11-small` channel)
- **Network:** Static IP (no DHCP, no WiFi), Tailscale
- **Disk:** **Disko** declarative disk layout (`disk-config.nix`); `/dev/sda` → boot (1G EFI) + swap (1G) + root (rest, ext4)
- **Boot:** systemd-boot EFI; virtio modules in initrd
- **Containers:** **Podman** with **quadlets** (`.container` files via `mkQuadlet` helper); images built with Nix `dockerTools.streamLayeredImage` (no Dockerfiles), loaded out-of-band via `deploy-app.sh`
- **Reverse proxy:** **Caddy** with auto-HTTPS (Let's Encrypt), multiple vhosts
- **Desktop:** None (headless)
- **Home-manager:** Yes — just nvim config + go / gcc / htop / tmux / ripgrep / fd
- **SSH:** Hardened — pubkey only, no root login, no password
- **Secrets:** `.env` files at `/var/lib/<service>/` (NOT in repo); templates committed as `.env*.template`
- **Modules:** Heavy factorization — one `.nix` per service; `lib/default.nix` exposes `mkQuadlet`, `mkEnvFile`
- **Custom packaging:** Yes — every Go service built via `buildGoModule` in `packages/`
- **Deploy:** 3-tier scripted (platform / app / content) in `scripts/`
- **Docs:** Comprehensive — 20 markdown docs + `AGENTS.md` + thorough `README.md`
- **Bootstrap:** `configuration-minimal.nix` for nixos-anywhere (root password, temp bh password, then swapped)
- **Flake inputs:** nixpkgs-24.11-small, home-manager-24.11, disko
- **Services running:** 20+ Go microservices (Ledger King, BeerTrader, WhatsApp tooling), Evolution API, NATS JetStream, PostgreSQL, Redis, Caddy, static sites
- **Repo:** `/Users/bh/code/systems/snowi-node/`

## Other systems in the user's world (context only)

From Tailscale status:
- **bmac** (`100.66.142.61`) — the macOS deploy machine (where this design work happens)
- **evolution** (`100.116.0.4`) — separate device running evolution (online)
- **mealie** (`100.99.80.101`) — separate device running mealie (online)
- **uqbn-container-test** (`100.65.218.21`) — experimental, offline

These suggest the user may have additional NixOS or non-NixOS boxes that could eventually consume the base.
