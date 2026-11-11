# bnox

A unified, reusable NixOS base. You don't install bnox — you build NixOS hosts that consume it as a flake input at a pinned version, overriding only what diverges.

## Structure

```
bnox/
├── README.md              ← you are here
├── AGENTS.md              ← agent boot prompt (sebig); CLAUDE.md points here
├── docs/graph/            ← developer / AI-agent corpus: decisions, sessions, jobs (sebig)
├── docs/archive/design/   ← the former design workspace (D-001..D-021, history)
├── tools/                 ← sebig hows, checks, scripts (links into .sebig/)
└── versions/
    └── 0/0/               ← series (feature batch)
        ├── docs/          ← consumer docs + examples for the series
        └── 1/             ← version: complete frozen product copy (flake + modules + fixtures + manifest)
```

- No hosts live in this repo. Each host (or group of hosts) lives in its own git repo that pins a version directory: `inputs.bnox.url = "github:b-za/bnox?dir=versions/0/0/1";`
- A version with `status: done` in its manifest is frozen forever. Fixes land in a new version — you take the new version, or you stay pinned.
- Development happens inside the newest version directory; the repo root has no flake.

## Start here

Read [`versions/0/0/docs/getting-started.md`](./versions/0/0/docs/getting-started.md) — it walks through creating a host repo, pinning bnox, writing a host config, and installing with nixos-anywhere.

Working on bnox itself: start at [`AGENTS.md`](./AGENTS.md) (sebig). Decisions from now on are notes in [`docs/graph/`](./docs/graph/); the earlier design rationale and decision log (D-001 through D-021) are archived in [`docs/archive/design/`](./docs/archive/design/).
