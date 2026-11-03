# bnox

A unified, reusable NixOS base. You don't install bnox — you build NixOS hosts that consume it as a flake input at a pinned version, overriding only what diverges.

## Structure

```
bnox/
├── README.md              ← you are here
├── design/                ← developer / AI-agent workspace (process, decisions, jobs)
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

The design rationale, decision log (D-001 through D-014), and implementation history live in [`design/`](./design/). Start at [`design/STATUS.md`](./design/STATUS.md) for the current phase.
