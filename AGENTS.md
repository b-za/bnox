# bnox — Agent Boot Prompt

## Current State

**Active Project:** `261111224500-P001` (bnox) — `docs/graph/261111224500-P001.md`
**Latest Session:** `261111224600-S001` — `docs/graph/261111224600-S001.md` (its handover is the order of attack)

**Boot Set (Read in Order):**

1. tools/meta/260831200000-EGOA.md — Agent Boot Guide (bnox copy)
2. tools/meta/260825144541-DFTS.md — Spec Authoring Guide (bnox copy)
3. tools/meta/260829153015-EFGV.md — Boot Set (bnox copy)
4. tools/meta/260831210001-EGOC.md — Hows System
5. tools/meta/260904120700-GOVN.md — Corpus Change Governance
6. tools/meta/261111224800-H001.md — bnox local hows
7. docs/graph/261111224500-P001.md — bnox project
8. docs/graph/261111224600-S001.md — latest session and its handover

---

## Quick Commands

1. Validate — bash tools/scripts/spec-validate
2. Check links — bash tools/scripts/link-check
3. Regenerate project index — python3 tools/scripts/project-index --project 261111224500-P001 --write
4. Regenerate hows index — python3 tools/scripts/hows-index --write
5. Start session — python3 tools/scripts/session-start --session-id <id> --write
6. End session — python3 tools/scripts/session-end --session-id <id> --write

---

## Hows Index

<!-- GENERATED:START:hows-index -->
- [[tools/meta/260831200000-EGOA|260831200000-EGOA]] — `protocol`
- [[tools/meta/260829153015-EFGV|260829153015-EFGV]] — `policy`
- [[tools/meta/260904120700-GOVN|Corpus Change Governance]] — `policy`
- [[tools/meta/260825144541-DFTS|260825144541-DFTS]] — `standard`
- [[tools/meta/260831210001-EGOC|Hows System]] — `standard`
- [[tools/meta/261111224800-H001|261111224800-H001]] — `standard`
<!-- GENERATED:END:hows-index -->

---

## Key Principles

1. Read the boot set first — before doing any work
2. Every decision gets a note — see the Spec Authoring Guide (bnox copy) for what counts and how
3. Run validations before commit
4. No corpus or hows change without an explicit decision by bh — see governance guide
5. tools/ is symlinked to the immutable .sebig/ base — never edit through the symlink
6. The product is `versions/<maj>/<min>/<patch>/`; a `status: done` version is frozen forever
7. The former design workspace is archived in docs/archive/design/ and referenced by path
