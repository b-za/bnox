# Jobs

Implementation work is decomposed into jobs. The lead agent coordinates; sub-agents do the work and the checking. Each job is one file in this directory: `<NN>-<slug>.md`.

## Job file format

```markdown
# Job NN: <title>

**Status:** pending | in-progress | in-review | needs-fix | done
**Iteration:** 1
**Created:** YYYY-MM-DD

## Scope
<what to build, which files, which decisions to honor — quote design/process/06 or 07>

## Worker notes
<filled by worker sub-agent; what it did, decisions made>

## Checker notes
<filled by checker sub-agent; issues found, or sign-off>

## Sign-off
<checker final approval + date>
```

## Workflow

1. Lead creates a job file (status: `pending`).
2. Lead dispatches the **worker** (`general` sub-agent); status → `in-progress`.
3. Worker reports done; status → `in-review`.
4. Lead dispatches the **checker** (`general` sub-agent).
5. If issues: checker writes them to the file; status → `needs-fix`; lead resumes the worker (same `task_id`) to fix; loop back to step 3.
6. Checker approves; status → `done`.

The lead touches only job files and coordination, never the implementation.

## Verification conventions

The canonical comment-scan command (run from repo root) is:

```
rg -n '(^|[^a-zA-Z0-9_"}])#|/\*.*\*/|description =' <paths>
```

It enforces the "no comments in Nix files / no option `description` fields" rule. Future job "Validation" sections should reference this command rather than re-deriving the regex.
