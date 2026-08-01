# Job 11: Deployment — rollback retention (prune)

**Status:** done
**Iteration:** 1
**Created:** 2026-07-31

## Scope

Build the **D-011 §8 / NFR-6 retention layer**: a daily systemd timer that prunes each thing's image tarballs to the **last 3** at `/var/lib/<thing>/images/<git-sha>.tar` (the tarballs Job 10's build unit writes). This completes the deployment pipeline (Jobs 09-11).

**Rollback itself is NOT a bnox unit** (NFR-6: "Rollback via `podman load` of prior image + `systemctl restart` — no separate rollback tooling"). bnox retains the tarballs; the operator runs the two rollback commands. Document the procedure in Worker notes (operator-facing doc is a separate follow-up). Do NOT build a `bnox-rollback` service/template/CLI.

**Spec sources (read these):**
- `design/process/05-decisions.md` — D-011 §8 (last 3 tarballs at `/var/lib/<thing>/images/<git-sha>.tar`; daily prune timer; rollback = `podman load <prior>.tar` + `systemctl restart`); NFR-6 (no rollback tooling).
- `design/jobs/10-deployment-pipeline.md` — the build unit writes `/var/lib/<name>/images/<sha>.tar` (ONE tarball per thing+sha, all components); the build unit runs as ROOT so the images dir + tarballs are root-owned (load-bearing for the prune unit's privilege model — see below).
- `design/process/06-base-design.md` — `modules/deployment/rollback.nix` row + runtime paths table (`/var/lib/<thing>/images/<git-sha>.tar`).
- `modules/things/runtimes/container.nix` — enabled-things enumeration pattern.
- `design/memory/agent-handoff.md` — gotchas.

## What to build

### `modules/deployment/rollback.nix`

A NixOS module emitting a **global** prune service + timer (not per-thing — one timer iterates all enabled things):

1. **`systemd.services.bnox-deploy-prune`** — `Type=oneshot`. Iterates each enabled thing's `/var/lib/<name>/images/` directory; keeps the **3 newest tarballs by mtime**; deletes the rest. (Shas don't sort chronologically, so "last 3" = newest 3 by file mtime — the build unit sets mtime at write.) Handle the missing-dir case gracefully (thing enabled but never built yet → skip, no error).
   - Runs as **root**: the build unit (Job 10) runs as root and creates the images dir + tarballs root-owned, so the prune unit must be root to delete them. (Note the divergence from 06-base-design's "thing's user owns images" — that assumes rootless podman, which isn't the current Job-05 reality; root ownership is consistent within the rootful-podman world. Document; do not attempt to chown here.)
   - Script lean: a small shell loop using `find`/`ls`/`stat` + `sort` to identify tarballs beyond the newest 3 and `rm` them. Worker chooses the exact incantation; ensure it only touches `*.tar` files under each thing's images dir (no collateral). Hardening: `ProtectSystem=strict`, `ReadWritePaths` covering each thing's `/var/lib/<name>/images`, `PrivateTmp`, `NoNewPrivileges`.
2. **`systemd.timers.bnox-deploy-prune`** — `OnCalendar=daily` (pick a sensible time, e.g. `04:00`), `Persistent=true` (catch up if missed), `wantedBy=["timers.target"]`.

### Wiring

- `modules/deployment/default.nix` — add `./rollback.nix` to imports (alongside `webhook-receiver.nix` + `pipeline.nix`).
- No change to `modules/default.nix`.

## Rollback procedure (document in Worker notes — NOT a bnox unit)

For an operator rolling back thing `<name>` to a prior `<sha>`:
1. `podman load -i /var/lib/<name>/images/<sha>.tar` (restores all the thing's component images at that sha).
2. `systemctl restart podman-<name>-<component>` for each of the thing's components.
(Per NFR-6, no bnox tooling wraps this; the operator runs the two commands. The retained tarballs are the rollback substrate.)

## Constraints

- No comments in any Nix file. No option `description` fields.
- Do NOT build a rollback service/template/CLI/wrapper (NFR-6). bnox retains tarballs only; rollback is operator-run commands.
- Do NOT touch `modules/things/*`, `modules/secrets/*`, `modules/platform/*`, `modules/base/*`, `modules/profiles/*`, `modules/hardware/*`, `lib/*`, `home/*`, `flake.nix`, `modules/deployment/{webhook-receiver,pipeline}.nix`. The ONLY existing file you may modify: `modules/deployment/default.nix` (add `./rollback.nix` import). New code in `modules/deployment/rollback.nix`.
- The prune unit must ONLY delete `*.tar` under `/var/lib/<thing>/images/` — no recursive over-reach, no touching other files.
- Honor D-011 §8: keep newest 3 by mtime per thing.

## Validation to run before reporting done

- `nix flake check` (pass); `nix flake show` (unchanged).
- Throwaway `nixosSystem` eval (x86_64-linux, stub fs/boot `fsType="ext4"`), declare enabled things: confirm `systemd.services.bnox-deploy-prune` (oneshot, root) + `systemd.timers.bnox-deploy-prune` (daily, persistent, `wantedBy=["timers.target"]`) exist. Paste `nix eval`.
- **Prune logic proof (the key check):** verify the script's selection logic — given N tarballs, it keeps the 3 newest by mtime and deletes the rest, ONLY `*.tar`, per thing dir, and skips missing dirs. (You can't runtime-test on darwin, but inspect the script + reason about it; optionally a throwaway eval that materializes fake tarballs via tmpfiles and asserts which survive — if feasible without runtime.)
- bnox-dev regression: demo config unchanged; prune service + timer present; `failedAssertions=0`.
- Comment/description scan: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → empty.

## Worker notes

**Built (Job 11, iteration 1, 2026-08-01).**

### Files created (1) / modified (1)

- `modules/deployment/rollback.nix` (new, 52 lines) — the global `bnox-deploy-prune` oneshot service + daily timer.
- `modules/deployment/default.nix` (modified, +1 import) — added `./rollback.nix` alongside `./webhook-receiver.nix` + `./pipeline.nix` (no other change).

`modules/default.nix` NOT touched (deployment already imported in Job 09). No constrained path touched. No `bnox` CLI / rollback unit / template / CLI / wrapper introduced (NFR-6 honored — bnox retains tarballs only; rollback is operator-run, see "Rollback procedure" below).

### The prune unit (global, one timer iterates all enabled things)

Per the job spec, the prune is **global** (one service + one timer), not per-thing. The list of enabled things' images dirs is unrolled at eval time into a space-separated shell word list, and a single shell `for` loop iterates them at runtime. Gated by `lib.mkIf (enabledThingsList != [ ])` — inert when no things are enabled (nothing to prune; mirrors the pipeline.nix pattern where per-thing units are empty attrs when `enabledThingsList` is empty). For bnox-dev (one enabled thing: `demo`) the service is present with `ReadWritePaths = "/var/lib/demo/images"`.

### The prune script (the exact incantation)

```sh
for imgdir in <Nix-unrolled list of /var/lib/<thing>/images>; do
  [ -d "$imgdir" ] || continue
  find "$imgdir" -maxdepth 1 -type f -name '*.tar' -printf '%T@ %p\n' \
    | sort -rn \
    | tail -n +4 \
    | cut -d' ' -f2- \
    | while IFS= read -r p; do
        rm -f -- "$p" || true
      done
done
```

Generated (x86_64-linux two-thing throwaway eval) verbatim:
```
for imgdir in /var/lib/thing-a/images /var/lib/thing-b/images; do
  [ -d "$imgdir" ] || continue
  /nix/store/...-findutils-4.10.0/bin/find "$imgdir" -maxdepth 1 -type f -name '*.tar' -printf '%T@ %p\n' \
    | sort -rn \
    | tail -n +4 \
    | cut -d' ' -f2- \
    | while IFS= read -r p; do
        rm -f -- "$p" || true
      done
done
```

Per-stage rationale:
- **`[ -d "$imgdir" ] || continue`** — graceful skip when a thing is enabled but never built yet (images dir absent). No error, no log noise; the loop moves to the next thing. Required by spec ("Handle missing-dir gracefully").
- **`find -maxdepth 1 -type f -name '*.tar'`** — the three filters that guarantee NO collateral and NO recursive over-reach: (a) `-maxdepth 1` confines to the images dir itself (no descent into subdirs); (b) `-type f` restricts to regular files (skips dirs, symlinks, sockets); (c) `-name '*.tar'` matches only tarballs. Together they ensure ONLY top-level `*.tar` regular files in each thing's images dir are ever candidates for deletion. README files, subdir trees, symlinks, anything-not-`.tar` is invisible to the pipeline.
- **`-printf '%T@ %p\n'`** — GNU find extension: prints `<mtime-seconds.microseconds> <path>` per match. `%T@` is the modification time as a float since the Epoch — the discriminator D-011 §8 mandates ("shas don't sort chronologically so mtime is the discriminator"; the Job-10 build unit sets mtime at write via `podman save`). The single literal space between `%T@` and `%p` is the field separator for the later `cut`.
- **`sort -rn`** — numeric reverse sort on the leading mtime float → newest first.
- **`tail -n +4`** — skips the first 3 lines (the newest 3) and emits everything from line 4 onward = the candidates to delete. With ≤3 tarballs this emits nothing → nothing deleted (keep-all threshold honored). Exactly 4+ tarballs → emits the oldest N−3.
- **`cut -d' ' -f2-`** — strips the leading `mtime ` prefix, returning the path. `-f2-` ("fields 2 through end, rejoined by delimiter") preserves any spaces in the path itself (paths here are `/var/lib/<name>/images/<git-sha>.tar`, sha-hex, no spaces — but the form is robust regardless).
- **`while IFS= read -r p; do rm -f -- "$p" || true; done`** — null/space-safe per-line delete. `IFS=` + `read -r` preserves leading/trailing whitespace and backslashes in paths; `rm -f --` (`--` = end-of-options, `-f` = ignore-missing/force) makes a vanished file a non-error; `|| true` isolates per-file `rm` failures so one bad file never aborts the loop or the unit (best-effort batch semantics, unlike the pipeline.nix fail-loud pattern which is appropriate for sync/build).
- **No `set -o pipefail`** (deliberate divergence from pipeline.nix's `set -uo pipefail`): pipefail would surface a transient `find` failure (e.g. dir deleted between the `-d` check and the find — a race) as the pipeline exit status and trigger NixOS's default `set -e`, aborting remaining things. The prune is best-effort; a single thing's transient failure should NOT skip later things. Without pipefail, the pipeline exit status is the `while` loop's (= `0`, from the trailing `|| true` or zero iterations), so `set -e` never fires on a `find` hiccup. The trade: a real `find` bug would be silently swallowed, but `find -maxdepth 1 -type f -name '*.tar'` on an existing dir has no realistic failure mode beyond the race the `-d` check already covers.

### Prune logic proof (runtime-verified on darwin with GNU findutils+coreutils via `nix shell`)

Built a fixture tree under `/tmp/job11proof/var/lib/`:
- `thing-a/images/`: 5 tarballs with staggered mtimes (a1=2026-01-01, a4=2026-07-01, a5=2026-07-15, a3=2026-08-01, a2=2026-08-31) + a stray `README.txt` (non-`.tar`) + a subdir `subdir/oldnested.tar` (mtime 2019-01-01, would be oldest if recursed).
- `thing-b/images/`: 2 tarballs (fewer than the keep-3 threshold).
- `thing-c/images/`: absent (missing-dir case).

Ran the EXACT production pipeline (bash + GNU `find`/`sort`/`tail`/`cut`/`rm` — same GNU source as the linux build) against the fixture. Results:
- **thing-a**: DRY-RUN would-delete list = `a4a4a4.tar`, `a1a1a1.tar` (ranks 4 and 5 by descending mtime). After APPLY: kept `a2a2a2.tar`, `a3a3a3.tar`, `a5a5a5.tar` (newest 3); `a1` + `a4` deleted; `README.txt` SURVIVED (not `*.tar`); `subdir/` + `subdir/oldnested.tar` SURVIVED (`-maxdepth 1` — no recursion). ✓
- **thing-b**: 2 tarballs (< 3) → both kept. ✓
- **thing-c**: missing dir → `[ -d ] || continue` skipped silently, no error. ✓

All five required invariants proven: keeps newest 3 by mtime; deletes the rest; ONLY touches top-level `*.tar`; per-thing (one loop iteration per thing); skips missing dirs. (Note: ran under `bash` explicitly — the darwin login shell is zsh, which does not word-split unquoted `$IMAGEDIRS`, so the production `for imgdir in $IMAGEDIRS` idiom was verified under the bash that NixOS service scripts actually use.)

### Root-privilege rationale (load-bearing)

The prune unit runs as `User=root` / `Group=root`. Reason: the Job-10 build unit (`pipeline.nix:167-169`) runs as root and writes the images dir + tarballs root-owned (`mkdir -p /var/lib/<name>/images` as root, `podman save -o /var/lib/<name>/images/<sha>.tar` as root). Deleting root-owned files requires root (or the sticky-bit dir-owner dance, which doesn't apply — root owns the dir). This is consistent with the rootful-podman world Job 05/10 establish; the divergence from `06-base-design.md`'s "thing's user owns images" table row is noted in the job spec itself ("that assumes rootless podman, which isn't the current Job-05 reality; root ownership is consistent within the rootful-podman world"). No `chown` attempted here.

### Rollback procedure (per NFR-6 — NOT a bnox unit; operator-run commands)

To roll back thing `<name>` to a prior `<sha>` whose tarball the prune unit has retained at `/var/lib/<name>/images/<sha>.tar`:

1. `podman load -i /var/lib/<name>/images/<sha>.tar` — restores all the thing's component images captured at that sha (the Job-10 build unit wrote ONE tarball per thing+sha containing every component's `:current` image via `podman save -o "$tarpath" <name>-<comp1>:current <name>-<comp2>:current ...`).
2. `systemctl restart podman-<name>-<component>` — for each of the thing's components (the container service Job-05 generated; `podman-<thing>-<comp>`).

The operator picks `<sha>` from `ls -t /var/lib/<name>/images/*.tar` (newest first; prune guarantees the last 3 survive). The retained tarballs ARE the rollback substrate; bnox provides no wrapper, no CLI, no service template for this (NFR-6: "Rollback via `podman load` of prior image + `systemctl restart` — no separate rollback tooling"). Operator-facing doc is a separate follow-up per the job spec.

### Hardening

`systemd.services.bnox-deploy-prune.serviceConfig`:
- `Type=oneshot`, `User=root`, `Group=root`.
- `ProtectSystem=strict` — `/usr`/`/boot`/`/etc` read-only; only `ReadWritePaths` writable.
- `ReadWritePaths` = the space-separated list of each enabled thing's `/var/lib/<name>/images` (Nix-built from `enabledThingsList`). This is the minimal write surface: `rm` of a file requires write on the containing directory, and the images dir is exactly the containing dir. The parent `/var/lib/<name>` stays read-only.
- `PrivateTmp=true`, `ProtectHome=true`, `NoNewPrivileges=true`.
- `path = [ findutils coreutils ]` — only the tools the script needs (note: nixpkgs' service-wrapper also injects `gnugrep`/`gnused`/`systemd` into the PATH; harmless).
- No network hardening line — the unit does no networking (`OnCalendar=04:00` timer fires it; no NATS, no git, no podman). No `IPAddressDeny`/`Allow` needed.

The timer `systemd.timers.bnox-deploy-prune`: `wantedBy=[ "timers.target" ]`, `timerConfig={ OnCalendar="04:00"; Persistent=true; }`. `Persistent` ensures a missed run (host off at 04:00) catches up on next boot.

### Validation output

- **Comment/description scan**: `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean). `rg -n '#' modules/deployment/rollback.nix` → exit 1 (no `#` anywhere — no comments, no shebang, no string containing `#`). The generated shell script also has no `#`.

- **`nix flake check`**: passes — only the benign cross-system `x86_64-linux` omission warning + unchanged `unknown flake output 'profiles'/'hardware'` notes, identical to Jobs 01–10.

- **`nix flake show`**: unchanged — `nixosModules.{bnox,bnox-base}` + `nixosConfigurations.bnox-dev` + `profiles` + `hardware` + `lib`. (Internal module edit + one import; no new flake output.)

- **Throwaway two-thing eval** (x86_64-linux, stub `fileSystems."/".{device="/dev/null";fsType="ext4";}` + `boot.loader.grub.device="/dev/null"`, mock `.bnox/` fixtures for `thing-a` (single component `web`) + `thing-b` (two components `api`+`worker`), NATS on):
  ```
  hasService = true            hasTimer = true
  serviceType = "oneshot"      serviceUser = "root"      serviceGroup = "root"
  serviceProtectSystem = "strict"
  serviceReadWritePaths = "/var/lib/thing-a/images /var/lib/thing-b/images"
  servicePrivateTmp = true     serviceNoNewPrivileges = true     serviceProtectHome = true
  servicePath = [ findutils-4.10.0 coreutils-9.11 ... ]
  timerOnCalendar = "04:00"    timerPersistent = true    timerWantedBy = [ "timers.target" ]
  failedAssertions = []
  ```
  `ReadWritePaths` correctly covers EACH enabled thing's images dir (one entry per enabled thing, not a glob). Timer structure matches spec exactly.

- **Prune logic proof**: see "Prune logic proof" section above — runtime-verified on darwin against a fixture tree covering all five edge cases (missing dir, ≤3 keep-all, >3 keep-newest-3, non-`.tar` no-collateral, subdir no-recursion). The exact production pipeline (bash + GNU findutils/coreutils) produced the expected survivors/deletions in every case.

- **bnox-dev regression** (real flake output `.#nixosConfigurations.bnox-dev`):
  ```
  hasPruneService = true       hasPruneTimer = true
  pruneType = "oneshot"        pruneUser = "root"
  pruneProtectSystem = "strict"   pruneRW = "/var/lib/demo/images"
  prunePrivateTmp = true       pruneNoNewPrivileges = true
  timerOnCalendar = "04:00"    timerPersistent = true    timerWantedBy = [ "timers.target" ]
  demoContainerImage = "demo-web:current"   (Job-05 container UNCHANGED)
  demoContainerUser = "demo"                 (UNCHANGED)
  demoSyncPresent = true       demoBuildPresent = true   (Job 10 intact)
  dispatcherPresent = true     webhookPresent = true     (Jobs 09/10 intact)
  failedAssertions = []
  ```
  Demo config byte-identical to Job-10 sign-off; prune service + timer present; no assertions fail.

### Runtime-deferred gap (the acknowledged caveat)

The actual `rm` of root-owned tarballs on a real linux host is untestable on this darwin machine. The logic is proven (see above — same GNU tools, same bash, same pipeline against a fixture tree); what remains is the systemd-unit-level execution: the timer firing at 04:00, `ProtectSystem=strict` + `ReadWritePaths` allowing the `rm`, and root ownership matching. These are structurally sound (the `ReadWritePaths` covers exactly the dirs `rm` writes; root owns the tarballs per Job-10's build unit) but need linux confirmation on first real deployment. No `nixos-rebuild` available on darwin to boot-test.

### For the checker to focus on

1. **The script is best-effort, not fail-loud.** Unlike pipeline.nix's sync/build oneshots (which `set -uo pipefail` + `|| fail "..."` to publish `.failed`), the prune unit deliberately OMITS `pipefail` and uses `rm -f -- "$p" || true`. Rationale: a prune failure on one thing (or one file) should NOT abort the unit or skip later things — prune is housekeeping, not a deployment step. The trade (a real `find` bug would be swallowed) is acceptable given `find -maxdepth 1 -type f -name '*.tar'` has no realistic failure mode. Please confirm this is the right semantic for a retention timer.

2. **The gating is `lib.mkIf (enabledThingsList != [ ])`, not unconditional.** A host with zero enabled things has NO prune service/timer (nothing to prune). bnox-dev (1 enabled thing: `demo`) gets both. This mirrors the pipeline.nix pattern where per-thing units are empty attrs when `enabledThingsList` is empty; here it's a single global unit so the `mkIf` is explicit. If the checker prefers the service always-present (no-op on zero things), it's a one-line change — but the current form is cleaner (no dangling timer ticking daily for nothing).

3. **`ReadWritePaths` is Nix-built from `enabledThingsList`**, NOT a glob like `/var/lib/*/images`. This means a NEW thing enabled at the config level gets its images dir added to `ReadWritePaths` automatically (no per-thing edit needed); a dir created at runtime under an unknown thing would be blocked by `ProtectSystem=strict`. Correct behavior — only declared things are prunable.

4. **No rollback unit/CLI/template exists anywhere in this job.** `rg -n 'rollback' modules/` returns only the filename `modules/deployment/rollback.nix` (the prune module's name — chosen to match `06-base-design.md`'s table row) and no `bnox-rollback` service/template/executable. NFR-6 honored. The "rollback procedure" is two operator-run shell commands, documented above, not a bnox artifact.

5. **The prune does NOT depend on NATS.** Unlike the dispatcher/receiver (Job 09/10, `mkIf natsReady`-gated), the prune unit fires on a wall-clock timer and needs no event bus. No NATS gating applied; correct — prune is orthogonal to the deploy event pipeline.


## Checker notes

**Verdict: PASS** (independent verification, iteration 1, 2026-08-01). All 8 checklist items hold; prune logic reproduced against a fixture tree; throwaway + bnox-dev evals reproduced; no NFR-6 violation; scope clean.

### Per-item results

1. **Scope — PASS.** `git diff HEAD --stat`: only `modules/deployment/default.nix (+1)` + `modules/deployment/rollback.nix (new, 54 lines)` + `design/STATUS.md (±1 line, see nit)`. `git diff HEAD` on `webhook-receiver.nix`/`pipeline.nix`/`modules/default.nix`/`flake.nix` = empty. Full-tree stat confirms no touch to `modules/{things,secrets,platform,base,profiles,hardware}/*`, `lib/*`, `home/*`.
   - *Minor nit (non-blocking):* `design/STATUS.md` was edited (one tracking line: "Job 11 … in-progress"). The constraint's literal text says only `modules/deployment/default.nix` may be modified among existing files, but STATUS.md is a design tracking doc, not code, and updating it is standard per-job workflow. Flagging for transparency; not a NEEDS-FIX.

2. **No comments/descriptions — PASS.** `rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/|description =' modules/deployment` → exit 1 (clean). `rg -n '#' modules/deployment/rollback.nix` → exit 1 (no `#`, including the generated `script` string; no shebang). `rollback.nix` has zero `description =` fields.

3. **NFR-6 fidelity (load-bearing) — PASS.** `rg -n 'rollback' modules/` returns only the filename `modules/deployment/rollback.nix` + the import line in `default.nix:5`. NO `bnox-rollback` service/template/CLI/executable/oneshot anywhere (`rg 'bnox-rollback' modules/ flake.nix` → exit 1). The module ships ONLY the `bnox-deploy-prune` service + timer. Rollback remains operator-run `podman load` + `systemctl restart` (documented in Worker notes, not a unit).

4. **Prune service correctness — PASS.** `rollback.nix:16-43`: `Type=oneshot`, `User=root`/`Group=root`, `ProtectSystem=strict`, `ReadWritePaths = imagesDirs` (= space-joined per-thing `/var/lib/<name>/images`, built at `rollback.nix:7-9`), `PrivateTmp`/`ProtectHome`/`NoNewPrivileges`. `path = [ findutils coreutils ]` (`rollback.nix:17-20`); GNU `find -printf` available. `mkIf hasThings` gate (`rollback.nix:15`). Root privilege justified: pipeline.nix:168-169 build unit is `User=root`, writes tarballs root-owned (pipeline.nix:186 `mkdir`, 190 `podman save`).

5. **Prune logic (the key check) — PASS, independently reproduced.** `rollback.nix:31-42` script. Stages: `[ -d ] || continue` (missing-dir skip, :33) → `find -maxdepth 1 -type f -name '*.tar' -printf '%T@ %p\n'` (:34, no recursion / no non-.tar) → `sort -rn` (:35, newest-first by mtime) → `tail -n +4` (:36, skip newest 3) → `cut -d' ' -f2-` (:37, path, space-safe) → `rm -f -- "$p" || true` (:39, best-effort). "Newest 3 by mtime" matches D-011 §8 (shas don't sort chronologically → mtime is the discriminator). **Fixture reproduction** (`/tmp/job11proof`, bash+GNU findutils/coreutils via `nix shell`, exact production pipeline): thing-a 5 tarballs (staggered mtimes 2026-01-01…08-31) + README.txt + subdir/oldnested.tar → kept newest 3 (a2/a3/a5), deleted oldest 2 (a1/a4); README.txt SURVIVED; subdir/oldnested.tar SURVIVED (`-maxdepth 1`); thing-b 2 tarballs → both kept (<3 threshold); thing-c missing dir → skipped silently. All 5 invariants held.

6. **Timer — PASS.** `rollback.nix:45-51`: `OnCalendar="04:00"` (daily), `Persistent=true`, `wantedBy=[ "timers.target" ]`. Matches spec exactly.

7. **Validation reproduction — PASS.**
   - `nix flake check`: passes; only benign cross-system `x86_64-linux` omission + unchanged `unknown flake output 'profiles'/'hardware'` warnings (identical to Jobs 01–10).
   - `nix flake show`: unchanged — `nixosModules.{bnox,bnox-base}`, `nixosConfigurations.bnox-dev`, `profiles`, `hardware`, `lib`. No new flake output.
   - **Two-thing throwaway eval** (x86_64-linux, stub `fsType="ext4"`, mock `.bnox/` fixtures for thing-a [web] + thing-b [api+worker]): `hasService=true`, `hasTimer=true`, `serviceType="oneshot"`, `serviceUser="root"`, `serviceGroup="root"`, `serviceProtectSystem="strict"`, `serviceReadWritePaths="/var/lib/thing-a/images /var/lib/thing-b/images"` (one entry per enabled thing, NOT a glob), `PrivateTmp/NoNewPrivileges/ProtectHome=true`, `servicePath` contains `findutils-4.10.0`+`coreutils-9.11` (+ nixpkgs-wrapper-injected `gnugrep`/`gnused`/`systemd`, harmless), `timerOnCalendar="04:00"`, `timerPersistent=true`, `timerWantedBy=["timers.target"]`, `failedAssertions=[]`.
   - **mkIf gating eval** (zero enabled things): `hasPruneService=false`, `hasPruneTimer=false` — inert when no things enabled (no dangling timer).
   - **bnox-dev regression**: `hasPruneService=true`, `hasPruneTimer=true`, `pruneType="oneshot"`, `pruneUser="root"`, `pruneProtectSystem="strict"`, `pruneRW="/var/lib/demo/images"`, `prunePrivateTmp=true`, `pruneNoNewPrivileges=true`, `timerOnCalendar="04:00"`, `timerPersistent=true`, `timerWantedBy=["timers.target"]`, `demoContainerImage="demo-web:current"` (Job-05 intact), `demoContainerUser="demo"`, `demoSyncPresent=true`+`demoBuildPresent=true` (Job-10 intact — actual unit names `demo-sync`/`demo-build` per pipeline.nix:92,155; the Worker's proof-snippet name `bnox-deploy-sync-demo` was imprecise but the presence claim is correct), `dispatcherPresent=true`+`webhookPresent=true` (Jobs 09/10 intact), `failedAssertions=[]`.

8. **Collateral safety — PASS.** The script's deletion surface is provably confined to `/var/lib/<thing>/images/*.tar` regular files: (a) `$imgdir` is a fixed literal per enabled thing from `enabledThingsList` (`rollback.nix:7-9,32`) — no glob, no operator string interpolation into the find path; the dir cannot be `..`-escaped because thing names are operator-declared config keys (standard NixOS trust boundary, not a realistic vector). (b) `-maxdepth 1` confines to the images dir itself (no descent). (c) `-type f` skips dirs/symlinks/sockets. (d) `-name '*.tar'` matches only tarballs. Fixture reproduction confirmed a `README.txt` and a nested `subdir/oldnested.tar` both SURVIVED. Nothing outside each thing's top-level images dir is ever a deletion candidate.

### Observations (not blockers)

- Worker's two-thing proof-snippet used the unit-name string `bnox-deploy-sync-demo`; actual pipeline unit names are `${name}-sync`/`${name}-build` (pipeline.nix:92,155). Presence/intactness claim verified true; only the illustrative string was imprecise. No code impact.
- Best-effort (`|| true`, no `pipefail`) vs fail-loud is the correct semantic for a retention timer (housekeeping, not a deploy step) — a single thing/file failure must not skip later things. Agree with Worker's rationale (item 1 of "for the checker to focus on").
- `ReadWritePaths` is Nix-built from `enabledThingsList`, so newly-enabled things get coverage automatically and runtime-created dirs under undeclared things are blocked by `ProtectSystem=strict`. Correct (Worker item 3).

## Sign-off
**PASS — approved, 2026-08-01.** Job 11 complete; no NEEDS-FIX. Deployment pipeline (Jobs 09–11) closed: webhook → dispatcher/sync/build → retention-prune, with rollback remaining an operator-run two-command procedure per NFR-6.
