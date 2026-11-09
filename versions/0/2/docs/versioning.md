# Versioning

bnox ships as **frozen complete copies** under `versions/`:

```
versions/
└── 0/                          ← major
    └── 0/                      ← minor (a "series" = feature batch)
        ├── docs/               ← consumer docs for the whole series (this page)
        │   └── examples/
        └── 1/                  ← patch: a complete product copy (flake.nix, flake.lock,
                                ←  modules/, home/, lib/, secrets/, fixtures/, manifest)
```

- Numbering: `major/minor/patch`, semver meaning, **no dots, no padding**. `0/0/1` is the first version.
- Each version directory is a full flake with its **own** `flake.lock`, so pinning a version freezes bnox *and* its nixpkgs together.
- Hosts pin a version directory: `github:b-za/bnox?dir=versions/0/2/0`. Different hosts may sit on different versions indefinitely.

## The manifest

Every version has a `manifest`:

```
status: done | wip
date: <cut date>
nixpkgs: <channel/rev>
changes: <what changed vs the previous version>
```

**`status: done` means frozen forever.** Consumers may only pin `done` versions.

## Workflow

1. To start a new version: copy the previous version directory, commit the copy, then develop inside it (`status: wip`).
2. When it's finished: set `status: done`. No changes after that — **not ever**.
3. **Fixes are never copied back.** Wanting a fix means taking the new version. This is the whole point of the model: a `done` version is a name you can trust for the life of the host.
4. Bump rules: patch = fixes only; minor = feature batch (new series); major = breaking/philosophy change.

## Series docs

`docs/` and `docs/examples/` live at the **series** level (`versions/<maj>/<min>/`), not per patch:

- Docs are **amendable by patches within the series** (docs-only fixes don't force a new patch version).
- When a new series starts, the previous series' docs freeze with it.

Fixtures (the reference thing repos) are the exception: they live *inside* each version copy, because a flake pinned with `?dir=` only sees the subtree — anything a host repo consumes must be inside the version itself.

## Development

The bnox repo root has no flake. Development happens inside the newest version directory; the root only holds `README.md`, `design/` (developer workspace) and `versions/`.
