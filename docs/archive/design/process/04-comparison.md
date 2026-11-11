# Comparison

For each requirement area: how does each existing system address it, and what's the better starting point for the base?

Legend: ⭐ strong choice · ✅ adequate · ⚠️ weak / risk · ❌ absent.

## Provisioning (FR-1)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-1.1 Declarative disk (Disko) | ❌ manual `hardware-configuration.nix` | ⭐ `disk-config.nix` (Disko) | **snowi-node** |
| FR-1.2 Minimal bootstrap | ❌ none | ⭐ `configuration-minimal.nix` for nixos-anywhere | **snowi-node** |
| FR-1.3 Reproducible | ⚠️ flake lock but lots of imperative state | ⭐ fully reproducible | **snowi-node** |

## User & Access (FR-2)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-2.1 User `bh` + wheel | ✅ | ✅ | tie |
| FR-2.2 SSH pubkey in config | ❌ not set | ⭐ in `users.users.bh.openssh.authorizedKeys.keys` | **snowi-node** |
| FR-2.3 Hardened SSH | ⚠️ password auth allowed | ⭐ `PermitRootLogin=no`, `PasswordAuthentication=false` | **snowi-node** |
| FR-2.4 Tailscale | ✅ | ✅ | tie |

## Networking (FR-3)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-3.1 Tailscale | ✅ | ✅ | tie |
| FR-3.2 Firewall | ⚠️ disabled | ✅ ports 80/443, `checkReversePath=loose` | **snowi-node** (needs default-on firewall with per-host openings) |
| FR-3.3 Hostname | ✅ | ✅ | tie |
| FR-3.4 Network abstraction | ⚠️ wifi block hardcoded inline | ✅ static IP block (no abstraction needed) | needs **new abstraction** for both WiFi and static |

## Container runtime & images (FR-4)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-4.1 Runtime | Docker | Podman + quadlets | **OPEN Q2** — leaning snowi-node |
| FR-4.2 Image build pattern | ❌ pulls pre-built images | ⭐ `dockerTools.streamLayeredImage` from Nix | **snowi-node** |
| FR-4.3 Service-via-container helper | ❌ | ⭐ `mkQuadlet` + `mkEnvFile` in `lib/` | **snowi-node** |

Note: Docker is more familiar and Portainer is already in use on uqbn. Podman is more Nix-idiomatic, daemonless, and integrates with systemd via quadlets. The `dockerTools.streamLayeredImage` pattern works with **either** runtime (image is a tarball both can load). See Q2.

## Reverse proxy & TLS (FR-5)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-5.1 Auto-HTTPS reverse proxy | ❌ Tailscale Funnel only (no LAN TLS) | ⭐ Caddy + Let's Encrypt | **snowi-node** |
| FR-5.2 Per-vhost config in modules | ❌ | ⭐ modules contribute `services.caddy.virtualHosts` | **snowi-node** |

## Secrets (FR-6)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-6.1 Not hardcoded | ⚠️ wifi PSK hardcoded | ✅ env files outside repo | **snowi-node** (with caveats) |
| FR-6.2 Encrypted-at-rest | ❌ | ❌ | **NEW** — neither uses sops-nix/agenix; base adds one (Q3) |
| FR-6.3 Templates committed | ❌ | ⭐ `.env*.template` files | **snowi-node** |

Recommendation: adopt snowi-node's template-file pattern **plus** add **sops-nix** (or agenix) as a net-new improvement.

## Home-manager (FR-7)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-7.1 User `bh` | ✅ | ✅ | tie |
| FR-7.2 Dotfile symlink pattern | ⭐ qtile + nvim + ghostty + rofi | ✅ nvim only | **uqbn** (richer set; same `mkOutOfStoreSymlink` idiom) |
| FR-7.3 Standard nvim module | ✅ identical file | ✅ identical file | tie (literally same code) |

## Module structure (FR-8)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-8.1 Module per service | ❌ inline | ⭐ one `.nix` per service | **snowi-node** |
| FR-8.2 Shared lib helpers | ❌ | ⭐ `lib/default.nix` | **snowi-node** |
| FR-8.3 Slim top-level config | ❌ mostly inline | ✅ imports + enables | **snowi-node** |

## Deployment (FR-9)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-9.1 Tiered deploy | ❌ none | ⭐ platform / app / content scripts | **snowi-node** |
| FR-9.2 Buildable from macOS | ✅ (builds on target) | ⚠️ builds on target (rsync then rebuild on VPS) | needs work — see Q6 |
| FR-9.3 No target-only build | ✅ | ⚠️ README explicitly says cannot build from macOS | needs work — see Q6 |

## Documentation (FR-10)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-10.1 README | ❌ stub | ⭐ comprehensive | **snowi-node** |
| FR-10.2 AGENTS.md | ❌ none | ⭐ comprehensive | **snowi-node** |
| FR-10.3 Per-service docs | ⚠️ 2 generic docs | ⭐ 20 docs | **snowi-node** |

## Standard tooling (FR-11)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-11.1 experimental-features | ✅ | ✅ | tie |
| FR-11.2 Standard packages | ✅ vim wget git + alacritty | ✅ vim wget git curl jq natscli | **merge**: `vim wget git curl jq` baseline |
| FR-11.3 Time zone | ✅ | ✅ | tie |

## Profiles (FR-12)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-12.1 Server profile | ❌ | ⭐ (it is one) | extract from snowi-node |
| FR-12.2 Desktop profile | ⭐ (qtile + ly + alacritty + firefox + fonts) | ❌ | extract from uqbn |
| FR-12.3 Composable hardware add-ons | ❌ wifi hardcoded inline | ❌ static IP hardcoded inline | **new abstraction** needed |

## Version & inputs (FR-13)

| Requirement | uqbn | snowi-node | Recommendation |
|---|---|---|---|
| FR-13.1 Pinned NixOS | 25.05 | 24.11 | **OPEN Q4** — leaning 24.11 for production parity |
| FR-13.2 Standard flake inputs | nixpkgs, home-manager, portainer-flake | nixpkgs, home-manager, disko | merge + add secrets manager + maybe nixos-hardware |

## Summary

| Area | Stronger system |
|---|---|
| Provisioning | snowi-node |
| User & Access | snowi-node |
| Networking | snowi-node |
| Containers | snowi-node (pending Q2) |
| Reverse proxy | snowi-node |
| Secrets | snowi-node (but neither uses a real secrets manager — net-new via Q3) |
| Home-manager dotfiles | **uqbn** (richer) |
| Module structure | snowi-node |
| Deployment | snowi-node (macOS-build is a gap, Q6) |
| Documentation | snowi-node |
| Server profile | snowi-node |
| Desktop profile | **uqbn** |
| WiFi / desktop hardware | **uqbn** |

**Headline:** snowi-node is the right **skeleton**; uqbn contributes the **desktop profile** and richer **dotfiles**; both are missing a real **secrets manager** and a clean **profile abstraction**. Two open questions dominate: **container runtime** (Q2) and **NixOS version** (Q4).
