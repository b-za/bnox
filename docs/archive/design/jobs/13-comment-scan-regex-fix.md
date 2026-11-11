# Job 13: comment-scan regex fix + `hashSep` workaround removal

**Status:** done
**Iteration:** 1
**Created:** 2026-07-31

## Scope

Fix the over-broad comment-scan regex that forced workarounds in Jobs 09 (Caddy `/*` glob → dedicated vhost) and 10 (literal `#` in `nix build /srv/<name>#images...` → `hashSep = "#"` indirection). Two parts:

1. **Canonize a corrected regex** in `design/jobs/README.md` (the verification reference workers/checkers consult). The current regex `(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =` false-positives on (a) `/*` path globs (e.g. Caddy `/bnox/webhook/*` — no closing `*/`) and (b) `#` after a Nix interpolation close-brace (e.g. `${name}#images` → `}#`). The corrected regex (verified by the lead against synthetic + real codebase) is:

   ```
   (^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =
   ```

   - `(^|[^a-zA-Z0-9_"}])#` — `#` line comment, adding `}` to the excluded prefix set so `}#` (Nix interpolation followed by `#`) doesn't match. (Real comments like `}; # foo` still match — the space before `#` is in the negated set.)
   - `/\*.*\*/` — paired block comment (requires a closing `*/`), so lone `/*` path globs don't match.
   - `description =` — unchanged.

   Lead has already verified (synthetic + full-tree scan) that the new regex: catches real `#` comments + paired `/* */` + `description =`; ignores `${x}#images` (`}#`) and `/path/*` (no `*/`); and scans the entire `modules/ hosts/ home/ lib/` tree clean (exit 1, no real comments were ever missed).

2. **Remove the now-unnecessary `hashSep` workaround** in `modules/deployment/pipeline.nix` (added in Job 10 purely because the old regex flagged `}#`). With the corrected regex, the literal `#` in `nix build "/srv/${name}#images.x86_64-linux.${comp}"` scans clean. Inline it directly and drop the `hashSep = "#"` let-binding.

**Not in scope:** the Job 09 Caddy dedicated-vhost choice stays (it's a valid design, not purely a regex workaround — a path matcher is redundant on a dedicated vhost). Do NOT restore a `/bnox/webhook/*` matcher. The `shapes/daemon.nix`, schema, loader, and all other modules are untouched.

**Spec sources:**
- The lead's verification (above) — the corrected regex is final; the worker transcribes it verbatim.
- `modules/deployment/pipeline.nix` — the `hashSep` binding (line ~24) + its single use in `buildLoop`.

## Files to modify

1. **`design/jobs/README.md`** — add a **"## Verification conventions"** section (after the "## Workflow" section) containing:
   - The canonical comment-scan command (the corrected regex above), runnable as `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' <paths>`.
   - One line noting it enforces the "no comments in Nix files / no option `description` fields" rule, and that future job "Validation" sections should reference this command (not re-derive the regex).
   - **Also fix** the stale note in "## Workflow" step 4: it says "Lead dispatches the checker (`auditor` sub-agent)" — change to `general` sub-agent (the `auditor` agent type returns empty results in this environment; the established pattern since Job 01 is `general` as the independent checker — see `design/memory/agent-handoff.md`). This is a one-word accuracy fix while editing the file.
2. **`modules/deployment/pipeline.nix`** — drop the `hashSep = "#";` let-binding; replace its single `${hashSep}` use in the `nix build` target with a literal `#`. The resulting string must read `"/srv/${name}#images.x86_64-linux.${comp}"` (confirm the demo-build script resolves to `/srv/demo#images.x86_64-linux.web`). NO other change to the file.

## Constraints

- No comments in any Nix file (the new regex must scan `pipeline.nix` clean after the edit — it will, that's the point).
- Do NOT touch any file other than the two listed. Specifically: do NOT touch `webhook-receiver.nix` (the Caddy vhost stays), the schema/loader/shapes, or any other module.
- The corrected regex string is final (lead-verified); transcribe it verbatim — do not "improve" it.
- `nix flake check` must still pass after the `hashSep` removal (the generated shell script is functionally identical).

## Validation to run before reporting done

- Run the **new** regex across the whole tree: `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' modules/ hosts/ home/ lib/` → must exit 1 (clean).
- Confirm `hashSep` is GONE from `pipeline.nix` (`rg -n 'hashSep' modules/` → exit 1) and the `nix build` target now uses a literal `#`.
- `nix flake check` → pass. `nix flake show` → unchanged.
- Confirm (via `nix eval .#nixosConfigurations.bnox-dev.config.systemd.services.demo-build.script` or equivalent) the demo-build script still contains `/srv/demo#images.x86_64-linux.web`.
- Confirm `design/jobs/README.md` has the new "Verification conventions" section with the exact regex + the step-4 `general` fix.

## Worker notes

**Edits made:**

1. `design/jobs/README.md`:
   - Added "## Verification conventions" section after "## Workflow" with the canonical command `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' <paths>` and the one-line note (enforces the no-comments / no-`description` rule; future job Validation sections should reference it, not re-derive the regex).
   - Fixed "## Workflow" step 4: `auditor` → `general` sub-agent.
2. `modules/deployment/pipeline.nix`:
   - Removed the `hashSep = "#";` let-binding (was line 24).
   - Inlined the literal `#` in the `nix build` target: `"/srv/${name}#images.x86_64-linux.${comp}"`.

Regex transcribed verbatim (no modification). No other files touched; `webhook-receiver.nix` and all other modules untouched.

**Validation output:**

- `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' modules/ hosts/ home/ lib/` → exit 1 (clean, no matches).
- `rg -n 'hashSep' modules/` → exit 1 (gone).
- `nix flake check` → exit 0 (pass; warnings only for dirty git tree + incompatible systems + unknown `profiles`/`hardware` outputs, all pre-existing).
- `nix flake show` → unchanged structure (hardware, lib, nixosConfigurations.bnox-dev, nixosModules.{bnox,bnox-base}, profiles).
- `nix eval .#nixosConfigurations.bnox-dev.config.systemd.services.demo-build.script` → contains `nix build --no-link --print-out-paths "/srv/demo#images.x86_64-linux.web"` (literal `#` confirmed).

## Checker notes

**Verdict: PASS.**

Independent verification (2026-08-01):

1. **Scope.** `git diff HEAD --stat` shows ONLY `design/jobs/README.md` (+12/-1) and `modules/deployment/pipeline.nix` (+1/-3); the job file `design/jobs/13-comment-scan-regex-fix.md` is the only untracked file. No other module/host/flake/lib touched. `webhook-receiver.nix` UNTOUCHED (`git diff HEAD --stat -- modules/services/webhook-receiver.nix` empty).
2. **Regex verbatim.** README "## Verification conventions" contains exactly `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' <paths>` — `}` in the excluded set confirmed, paired `/\*.*\*/` confirmed. Notes that future job "Validation" sections should reference the command. Character-for-character match against the spec.
3. **README step-4 fix.** Workflow step 4 now reads `general` (was `auditor`). Confirmed via diff.
4. **hashSep removed.** `rg -n 'hashSep' modules/` → exit 1 (gone). `pipeline.nix:137` now reads `"/srv/${name}#images.x86_64-linux.${comp}"` (literal `#`, no `${hashSep}`). `git diff` shows only the binding removal (2 lines) + the one inlined `#` (1 line) — no other changes.
5. **Whole-tree scan clean.** `rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' modules/ hosts/ home/ lib/` → exit 1 (no matches).
6. **Independent regex-correctness reproduction** (synthetic `/tmp/regex-sanity.txt`, 7 lines): regex matched exactly the 4 intended lines — real `# comment` (line 1), paired `/* a real block comment */` (line 3), `description = "..."` (line 6), and trailing-space `#` comment (line 7). It correctly IGNORED the Caddy glob `/bnox/webhook/*` (line 4, no closing `*/`) and `${...}#images`-style `"#images` (line 5). Both former false-positives suppressed; all real comments caught.
7. **Functional equivalence.** `nix flake check` → exit 0 (warnings: dirty tree, incompatible systems x86_64-linux, unknown `profiles`/`hardware` outputs — all pre-existing). `nix flake show` → unchanged (hardware, lib, nixosConfigurations.bnox-dev, nixosModules.{bnox,bnox-base}, profiles). `nix eval .#nixosConfigurations.bnox-dev.config.systemd.services.demo-build.script` → contains `--print-out-paths "/srv/demo#images.x86_64-linux.web"` (literal `#` survived into generated shell).
8. **No comments introduced.** README diff adds only fenced-code-block content + prose (markdown, rule N/A); pipeline.nix diff adds no `#`/`/* */` comments. Covered by clean tree scan in item 5.

No NEEDS-FIX items.

## Sign-off

Checker approval: PASS — 2026-08-01. All eight checklist items reproduced independently; spec satisfied; no functional regression.
