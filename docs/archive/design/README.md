# bnox

A unified NixOS base configuration that distills the best practices from two existing systems (`uqbn` and `snowi-node`) into a reusable foundation. Per-host customizations become small diversions from this base.

## Why this exists

The user maintains two NixOS systems with overlapping but inconsistent patterns:

- **uqbn** — an old MacBook repurposed as a desktop + Docker host
- **snowi-node** — a cloud VPS running production Go microservices

Both share concepts (flakes, home-manager, Tailscale, neovim) but differ in important ways (container runtime, disk management, secret handling, module structure, SSH hardening, deploy tooling). This folder is the **design workspace** where we decide what the unified base should look like before any code is written.

## How to navigate

| Read this | When |
|---|---|
| `STATUS.md` | First. Always. Tells you where we are. |
| `process/01-vision.md` | To understand the goal and scope. |
| `process/02-systems-inventory.md` | To see what we have today. |
| `process/03-requirements.md` | To see what the base must do. |
| `process/04-comparison.md` | To see how uqbn and snowi-node stack up. |
| `process/05-decisions.md` | Append-only decision log. |
| `process/06-base-design.md` | Target flake + module structure. |
| `process/07-diversions.md` | How per-host overrides work. |
| `working/open-questions.md` | Things needing the user's input. |
| `memory/agent-handoff.md` | If you're an agent picking this up cold. |

## Process

1. Discovery — understand both existing systems
2. Requirements — list what the base must enable
3. Compare — how does each existing system meet each requirement
4. Decide — pick winners and hybrids
5. Design — the actual flake + module structure
6. Document — so any agent can continue

## Source repos (do not edit as part of design)

- `/Users/bh/code/systems/uqbn/`
- `/Users/bh/code/systems/snowi-node/`
