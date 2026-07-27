# Decisions

Append-only log of decisions made during this design process. New decisions go at the bottom. Never edit a prior entry; supersede with a new entry that references the old one.

## Format

```
## D-NNN — <short title>
**Date:** YYYY-MM-DD
**Status:** proposed | accepted | superseded by D-NNN | rejected
**Context:** <why this is being decided>
**Decision:** <what we chose>
**Alternatives considered:** <what else was on the table>
**Consequences:** <what this implies>
```

## Pending decisions (awaiting user)

These map to the blocking open questions in `working/open-questions.md`:

- **D-002** Container runtime (Q2)
- **D-003** Secrets manager (Q3)
- **D-004** NixOS version pin (Q4)
- **D-005** Migration scope (Q5)

---

## D-001 — Project name
**Date:** 2026-07-27
**Status:** accepted
**Context:** Working name was `baseos`. Needed a real name before locking the directory and flake name (Q1). Wanted something short, OS-flavoured, personal, and collision-free.
**Decision:** **`bnox`** — bh + nox (nix + night). Short, ends in OS-adjacent sound, distinctive.
**Alternatives considered:** `baseos` (placeholder, generic), `noxos` (taken — active NoxOS-org on GitHub), `snowi-os` (too tied to one host), `bhos`, `keystone`, `rootstockos`, `nyxos`. Collision check ruled out `noxos`. `bnox` GitHub search returns only 8 weak results (file organizer, dormant crypto token, IMU sensor part number BNOx) — none in the OS / Nix space.
**Consequences:** Directory is `/Users/bh/code/systems/bnox/`. Future flake will publish as `github:<user>/bnox`. The string `bnox` should appear in flake description, README title, hostname convention docs, and commit prefixes once code lands.
