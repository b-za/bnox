# Agent Handoff

If you're a new agent picking up this project with no prior context, read this first.

## TL;DR

The user is designing a unified NixOS base called **`bnox`** that distills best practices from two existing systems: **uqbn** (old MacBook desktop + Docker host) and **snowi-node** (production VPS). The aim is one reusable foundation so that adding a new system means writing a small host-specific override file rather than copy-pasting a whole configuration.

## Where to start

1. **Read `STATUS.md` first.** It tells you what phase we're in and what's blocked.
2. Then `process/01-vision.md` for the goal and scope.
3. Then `process/02-systems-inventory.md` for what exists today.
4. Then `working/open-questions.md` for what's blocking progress.

The two source repos:
- `/Users/bh/code/systems/uqbn/`
- `/Users/bh/code/systems/snowi-node/`

## How to behave

- **Don't make decisions for the user.** Use `process/05-decisions.md` as the place to log decisions once the user makes them.
- **Don't edit a prior decision** — supersede it with a new entry that references the old one.
- **Update `STATUS.md` whenever the phase changes** or something becomes blocked/unblocked.
- **Update `memory/changelog.md` for any non-trivial change** to the workspace itself (new files, structural changes, completed phases).
- **Prefer concrete, evidence-grounded comparisons.** If you compare systems, cite actual files / line numbers.
- **Keep things concise.** These are working artifacts, not literature.
- **No comments in Nix files** unless the user asks (per user preference and existing repo style).

## Current state (snapshot)

(as of 2026-07-27)
- Phase: **Requirements synthesis** (phase 2 of 6).
- Discovery done for both source systems.
- Requirements list (FR-1 through FR-13) and comparison drafted; awaiting user review.
- 7 open questions (Q1 resolved → D-001 `bnox`); Q2–Q5 are blocking, Q6–Q8 are not.

## What an agent should NOT do

- Don't start writing flake.nix / modules until decisions D-001 through D-005 are accepted.
- Don't migrate uqbn or snowi-node until the user explicitly asks (Q5).
- Don't edit uqbn's or snowi-node's actual repos as part of this design workspace — this folder is design only.
- Don't add comments to Nix files (per user preference).
- Don't run `nixos-rebuild` against either source system without an explicit user request.

## File map

| Path | Purpose |
|---|---|
| `README.md` | Project overview, navigation. |
| `STATUS.md` | Current phase, what's done, what's next, blockers. **Update often.** |
| `process/01-vision.md` | Goal, scope, success criteria. |
| `process/02-systems-inventory.md` | What uqbn and snowi-node are today. |
| `process/03-requirements.md` | What the base must do (FR + NFR). |
| `process/04-comparison.md` | Side-by-side evaluation per requirement. |
| `process/05-decisions.md` | Append-only decision log. |
| `process/06-base-design.md` | (later) Target flake + module structure. |
| `process/07-diversions.md` | (later) How per-host overrides work. |
| `working/notes.md` | Scratch. |
| `working/open-questions.md` | Things needing user input. |
| `memory/agent-handoff.md` | This file. |
| `memory/changelog.md` | Append-only log of workspace changes. |
