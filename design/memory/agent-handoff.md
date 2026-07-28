# Agent Handoff

If you're a new agent picking up this project with no prior context, read this first.

## TL;DR

The user is designing a unified NixOS base called **`bnox`** that distills best practices from two existing systems: **uqbn** (old MacBook desktop + Docker host) and **snowi-node** (production VPS). The aim is one reusable foundation so that adding a new system means writing a small host-specific override file rather than copy-pasting a whole configuration.

**Repo layout:** the flake product lives at the repo root (`flake.nix` + `modules/`, once implemented). All design / planning / coordination material lives under `design/`. Nix ignores `design/`.

## Where to start

1. **Read `design/STATUS.md` first.** It tells you what phase we're in and what's blocked.
2. Then `design/process/01-vision.md` for the goal and scope.
3. Then `design/process/02-systems-inventory.md` for what exists today.
4. Then `design/working/open-questions.md` for what's blocking progress.

The two source repos (read-only — do not edit):
- `/Users/bh/code/systems/uqbn/`
- `/Users/bh/code/systems/snowi-node/`

## How to behave

- **Don't make decisions for the user.** Use `design/process/05-decisions.md` as the place to log decisions once the user makes them.
- **Don't edit a prior decision** — supersede it with a new entry that references the old one.
- **Update `design/STATUS.md` whenever the phase changes** or something becomes blocked/unblocked.
- **Update `design/memory/changelog.md` for any non-trivial change** to the workspace itself (new files, structural changes, completed phases).
- **Prefer concrete, evidence-grounded comparisons.** If you compare systems, cite actual files / line numbers.
- **Keep things concise.** These are working artifacts, not literature.
- **No comments in Nix files** unless the user asks (per user preference and existing repo style).

## Current state (snapshot)

(as of 2026-07-28)
- **All 6 design phases complete.** Phases 5 (base design) + 6 (diversions pattern) drafts landed: `design/process/06-base-design.md` and `design/process/07-diversions.md`. Both in user review.
- **All blocking questions resolved.** 9 decisions accepted (D-001 through D-012); Q9.5–Q9.9 refinements locked.
- **Repo reorganized:** product will live at repo root; all design material moved under `design/`. Implementation not yet started.
- **Next step: implementation**, coordinated by the lead agent via sub-agents (see `design/jobs/README.md`). The lead does **not** write implementation code directly — worker (`general` sub-agent) builds, checker (`auditor` sub-agent) verifies, loop until sign-off.
- Migration of uqbn / snowi-node is deferred (D-012) — not part of bnox itself.

## Key user communication preferences (observed)

- **Concise responses.** Prefer 1-3 sentences unless detail is requested. Tables OK.
- **Don't railroad decisions.** Present tradeoffs honestly; don't push a "lean" as if it were the answer. Positive mentions of an option by the user are NOT commitments — explore fully.
- **No comments in Nix files** (already in "How to behave" above; restated because it came up multiple times).
- **Don't make decisions for the user.** Log decisions in `design/process/05-decisions.md` only after the user makes them. Leans and recommendations OK; frame them as leans, not conclusions.
- **Update `design/STATUS.md` + `design/memory/changelog.md` whenever a decision lands or phase changes.** This is non-negotiable handoff hygiene.
- **No emojis** unless explicitly requested.

## What an agent should NOT do

- **Don't re-litigate settled decisions.** D-001 through D-012 are accepted; if you think one is wrong, raise it as a new open question rather than silently working around it.
- **Implementation is done by sub-agents coordinated by the lead** (see `design/jobs/README.md`). The lead creates job files, dispatches worker/checker sub-agents, and updates status — but does not write implementation code directly.
- **Don't migrate uqbn or snowi-node until the user explicitly asks** (D-012 — migration is deferred to a per-thing operator activity after bnox is built and validated).
- Don't edit uqbn's or snowi-node's actual repos — this repo is the bnox product + design workspace.
- Don't run `nixos-rebuild` against either source system without an explicit user request.
- Don't add comments to Nix files.

## Things to be aware of (implementation phase)

- **D-006 has pending refinements** (multi-component things, per-thing user isolation Q9.6, per-thing security model Q9.7, `daemon` shape Q9.8, `host-install` runtime Q9.9). These are locked in `design/working/open-questions.md` but will eventually be rolled into a superseding D-006.1. They're part of the design; treat them as accepted.
- The decision log uses non-sequential numbering (D-001, D-002, D-006, D-007, D-008, D-009, D-010, D-011, D-012). The gaps (D-003, D-004, D-005) were reserved for original questions that got reframed and resolved under different numbers. Don't be confused by this.
- `design/working/open-questions.md` is the authoritative source for all question state (resolved/locked/open). Read it before asking the user about anything.
- The user is **collaborative and decisive** — they like to make decisions when given clear options. Don't over-explore; present the menu, get the pick, move on.

## File map

| Path | Purpose |
|---|---|
| `README.md` | (repo root) Product overview, user-facing. |
| `design/README.md` | Design workspace navigation. |
| `design/STATUS.md` | Current phase, what's done, what's next, blockers. **Update often.** |
| `design/process/01-vision.md` | Goal, scope, success criteria. |
| `design/process/02-systems-inventory.md` | What uqbn and snowi-node are today. |
| `design/process/03-requirements.md` | What the base must do (FR + NFR). |
| `design/process/04-comparison.md` | Side-by-side evaluation per requirement. |
| `design/process/05-decisions.md` | Append-only decision log. |
| `design/process/06-base-design.md` | Target flake + module structure. |
| `design/process/07-diversions.md` | How per-host overrides work. |
| `design/working/notes.md` | Scratch. |
| `design/working/open-questions.md` | Things needing the user's input. |
| `design/memory/agent-handoff.md` | This file. |
| `design/memory/changelog.md` | Append-only log of workspace changes. |
| `design/jobs/` | Implementation job tracking (one file per job). |
