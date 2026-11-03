# Promotion

Host configs diverge freely — that's the design. But when a host-specific element turns out to be generally useful, it can be **promoted** into bnox. Promotion always happens in a **new version**; hosts pinned to older versions are unaffected until they bump.

## Two promotion modes

| Mode | What lands in bnox | When to use |
|---|---|---|
| **Opt-in** | A new option, `mkDefault`-gated, default off (or default-on-overridable) | Useful for some hosts but not all: a module (e.g. a backup service), a hardware quirk module, a profile tweak |
| **New default** | The behavior becomes the norm from that version on | The old way was actually wrong for everyone, or near-enough everyone that carrying both is noise |

Rule of thumb: opt-in when in doubt. A new default silently changes every host that bumps — that's a powerful tool, not a casual one.

## Process

1. The element proves itself in a host repo first (it works, it's wanted).
2. Raise it as a candidate (issue / conversation — in bnox's own design process this is an open question or decision entry).
3. Land it in a new version: patch (pure refactor/promotion, no behavior change for opted-out hosts) or minor (new capability → new series).
4. Hosts pick it up by bumping their pin — each at their own pace.
5. Once no host uses the old way, a later version may remove it (major bump if breaking).

## What must never be promoted

- Host names or per-host conditions (bnox never special-cases a host).
- Anything a host can express as a plain override already.
- Secrets, keys, or anything host-bound.
