# Job 07: Validation host (end-to-end eval)

**Status:** done
**Iteration:** 2
**Created:** 2026-07-29

## Scope

Create a real validation host under `hosts/` that the flake's auto-discovery (Job 01) picks up into `nixosConfigurations.<host>`, proving the entire bnox core composes end-to-end: base + platform + things + secrets + a profile → a fully evaluable NixOS system config. This is the capstone of D-012 Phase 1 (bnox standalone).

The flake already auto-discovers `hosts/*/` (one `nixosSystem` per subdir, injecting `self.nixosModules.bnox` + `specialArgs = { bnox = self; }`). So this job only needs to ADD a host directory with the right files — NO flake.nix edit.

**Deferred to Phase 2 (NOT this job):** the `.bnox/` loader (thing-intrinsic fields from a real thing repo), the deployment pipeline (webhook + NATS + rollback). The validation host declares its sample thing **inline** (host-config side), which is sufficient to prove the core composes. The `.bnox/` split is a Phase 2 concern (real thing hosting).

**Spec sources (read these):**
- `design/process/07-diversions.md` — host config shape (~30 lines, divergence-only), worked examples, provisioning flow.
- `design/jobs/01-flake-base.md` — the auto-discovery mechanism (specialArgs `bnox = self`, injects `self.nixosModules.bnox`).
- `design/jobs/04-things-core.md` + `05-things-shapes-runtimes.md` — the `bnox.things.*` schema (so the inline thing declaration is well-formed).

## Files to create

1. `hosts/<name>/configuration.nix` — the validation host. Pick a short hostname (e.g. `bnox-dev`, dir `hosts/bnox-dev/`). Per 07-diversions shape:
   - `imports = [ bnox.profiles.server ./hardware-configuration.nix ];` (the aggregate `self.nixosModules.bnox` is auto-injected by the flake — do NOT import it here; the host only imports the profile + local files).
   - `networking.hostName = "<name>";`
   - a network setting (e.g. `networking.useDHCP = true;` — simple, no static IP needed for a validation host)
   - `networking.firewall.allowedTCPPorts = [ 80 443 ];` (so Caddy is reachable)
   - one inline sample thing: a webapp, e.g.:
     ```
     bnox.things.demo = {
       enable = true;
       source = "/srv/demo";
       components.web = {
         shape = "webapp";
         runtime = "container";
         domain = "demo.local";
         ingressPort = 8080;
         secrets = [ "api_key" ];
       };
     };
     ```
   - Keep it ~30 lines (the vision's target).
2. `hosts/<name>/hardware-configuration.nix` — a stub that lets the system evaluate (NOT a real machine). Include a fake root `fileSystems` entry with `fsType = "ext4"` (the Job 04 checker found NixOS 26.05's ZFS module accesses `.fsType` during eval, so a stub needs `fsType`), `boot.loader.systemd-boot.enable = true`, and `system.stateVersion = "26.05"` (or rely on base for stateVersion — but hardware-configuration traditionally carries it; pick one place, don't duplicate with conflict). The goal: `nixosConfigurations.<name>` evaluates without a real machine.

NO `disk-config.nix` needed for a validation host (disko is for real provisioning; the stub hardware-configuration is enough to evaluate). NO flake.nix edit (auto-discovery handles it).

## Constraints

- No comments in any `.nix` file.
- Do NOT edit `flake.nix` (auto-discovery picks up the new host dir automatically).
- Do NOT modify any module files.
- Do NOT implement the `.bnox/` loader or deployment pipeline.
- The host imports ONLY the profile + local hardware-configuration (the aggregate is auto-injected; importing `bnox.nixosModules.bnox` here would double-inject).

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — confirm `nixosConfigurations.<name>` NOW APPEARS (it was empty before; the new host makes it non-empty).
- `nix eval .#nixosConfigurations.<name>.config.networking.hostName` — returns the hostname.
- Deeper eval proving composition: `nix eval .#nixosConfigurations.<name>.config.virtualisation.oci-containers.containers` (the demo webapp container "demo-web" present), `...config.services.caddy.virtualHosts` (the "demo.local" vhost present), `...config.bnox.things.demo.enable` (true), `...config.users.users.demo` (the thing's user exists). Paste results.
- Confirm the full system config is evaluable up to a reasonable depth (e.g. `nix eval .#nixosConfigurations.<name>.config.system.build.toplevel.drvPath` exists — proves it would build, without actually building).

## Worker notes

**Built (Job 07, iteration 1, 2026-07-29):**

**Hostname / dir:** `bnox-dev` → `hosts/bnox-dev/`.

**Files created (2), both comment-free** (`rg -n '(^|[^a-zA-Z0-9_"])#|/\*|\*/' hosts/bnox-dev/` → exit 1):
- `hosts/bnox-dev/configuration.nix` (23 lines):
  ```
  { bnox, ... }:
  {
    imports = [
      bnox.profiles.server
      ./hardware-configuration.nix
    ];

    networking.hostName = "bnox-dev";
    networking.useDHCP = true;

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];

    bnox.things.demo = {
      enable = true;
      source = "/srv/demo";
      components.web = {
        shape = "webapp";
        runtime = "container";
        domain = "demo.local";
        ingressPort = 8080;
        secrets = [ "api_key" ];
      };
    };
  }
  ```
- `hosts/bnox-dev/hardware-configuration.nix` (9 lines):
  ```
  { ... }:
  {
    fileSystems."/" = {
      device = "/dev/disk/by-label/root";
      fsType = "ext4";
    };

    boot.loader.systemd-boot.enable = true;
  }
  ```

**Key decisions:**
1. **Module arg `{ bnox, ... }:`** in configuration.nix. `bnox` is a specialArg (not a global); it must be destructured to reference `bnox.profiles.server`. The 07-diversions worked examples write `{ ... }: { imports = [ bnox.profiles.server ]; }` — that would be an unbound-variable error; `{ bnox, ... }:` is the working form.
2. **`system.stateVersion` omitted from hardware-configuration.nix** — base already sets it (`modules/base/system.nix:22 = "26.05"`). Spec said "pick one place, don't duplicate"; base is the single source. Verified `stateVersion = "26.05"` resolves through the host.
3. **`fsType = "ext4"` on the stub root** (not zfs) per the Job-04 checker note: NixOS 26.05's ZFS module accesses `fileSystems."/".fsType` during eval, so the stub needs an explicit non-zfs fsType or eval explodes. `boot.loader.systemd-boot.enable = true` satisfies the boot-loader requirement without a real disk.
4. **No `disk-config.nix`, no `secrets/secrets.nix`.** Both are optional in the 07-diversions shape; neither is needed to evaluate, and the spec said no disk-config for a validation host. The demo thing's `secrets = ["api_key"]` slot still resolves (Job 05 wires it to `bnox.secrets.fileSlots."demo/api_key"` and the container's environmentFiles) without a local agenix rules file.
5. **Files staged (`git add`) — NOT committed.** Flakes only see git-tracked/staged files; unstaged `hosts/bnox-dev/` is invisible to `builtins.readDir ./hosts`, so `nixosConfigurations` stayed empty until staged. Staging is required for any flake eval of the host; left staged for the principal/next step to commit.

**RESOLVED — pre-existing latent bug in `flake.nix:68`, authorized fix applied (iteration 1 follow-up, 2026-07-29):**

The spec's `nix eval .#nixosConfigurations.bnox-dev.config.*` (validation steps 3–5) was initially blocked by a one-line path-interpolation footgun in `flake.nix:68`. The original line:
```
hostsDir/${name}/configuration.nix
```
In Nix path-interpolation syntax, leading identifier-like text is a **literal path component relative to the current file**, NOT the `hostsDir` variable. So this evaluated to `<flake-source>/hostsDir/<name>/configuration.nix` (a literal dir named `hostsDir`), not `<flake-source>/hosts/<name>/configuration.nix`; the `let hostsDir = ./hosts;` binding was silently shadowed.

**Proof of the bug** (`/tmp/pathtest.nix`, Nix 2.28.4):
```
{ hostsDirVal = "/tmp/bnox-test-hosts";          # the variable resolves correctly
  v1 = "/tmp/hostsDir/bnox-dev/configuration.nix"; # but hostsDir/${name} uses a LITERAL "hostsDir" dir
  v1type = "path"; }
```
Original live failure:
```
error: path '/nix/store/w7r9kw6jyzlqq0ixp3yy4421ic5iznka-source/hostsDir/bnox-dev/configuration.nix' does not exist
```
The bug had been latent since Job 01: `nix flake check`/`show` passed (lazy — they didn't force the module path), and Jobs 01–06 checkers proved composition via *throwaway* `nixosSystem` evals that built their own `modules` list, never forcing the flake's `hostsDir/${name}` path. It only triggered once `hosts/` was non-empty AND `.config` was forced (this job).

**Authorization:** the coordinator authorized a one-line `flake.nix` edit (normally out of Job 07 scope) as required for Job 07 to verify.

**Syntactic note on the authorized form:** the coordinator specified `${hostsDir}/${name}/configuration.nix`, but that form is a **lexer syntax error** — Nix path-interpolation forbids a path *starting* with `${` (a literal path prefix is required before the first interpolation):
```
error: syntax error, unexpected DOLLAR_CURLY
       at .../flake.nix:68:15
```
The semantically-identical, valid, idiomatic form is `./hosts/${name}/configuration.nix`: the `./hosts/` literal prefix anchors the path (and `hostsDir` is defined as exactly `./hosts`), with only `${name}` interpolated. `hostsDir` stays defined (still used by the `pathExists`/`readDir` guard above); only line 68 changed. Applied fix:
```
              ./hosts/${name}/configuration.nix
```
(no comment added; the only `flake.nix` delta in this job).

**All spec'd evals now pass via the REAL `.#nixosConfigurations.bnox-dev` output** — no longer throwaway. See "Validation output" below. The throwaway-eval proof from the first pass (which established the host deliverable was correct independent of the bug) remains valid and is consistent with the real-output results (same `toplevel.drvPath` hash `sy04hxwc…`).

**Validation output:**

- `rg` comment scan on `hosts/bnox-dev/` → exit 1 (no comments). ✓
- `nix flake check` → all outputs OK. **New (post-fix): `checking NixOS configuration 'nixosConfigurations.bnox-dev'...`** — flake check now actually deep-evaluates the host (it couldn't before the fix). Only benign warnings (`x86_64-linux` cross-system + informational "unknown flake output 'profiles'/'hardware'", identical to Job 06):
  ```
  checking flake output 'lib'...
  checking flake output 'nixosModules'...
  checking NixOS module 'nixosModules.bnox'...
  checking NixOS module 'nixosModules.bnox-base'...
  checking flake output 'nixosConfigurations'...
  checking NixOS configuration 'nixosConfigurations.bnox-dev'...
  checking flake output 'profiles'...   (warning: unknown flake output 'profiles')
  checking flake output 'hardware'...   (warning: unknown flake output 'hardware')
  checking flake output 'packages'...
  warning: The check omitted these incompatible systems: x86_64-linux
  ```
- `nix flake show` → `nixosConfigurations.bnox-dev` present:
  ```
  ├───nixosConfigurations
  │   └───bnox-dev: NixOS configuration
  ```
- **Spec'd evals — ALL PASS via the real `.#nixosConfigurations.bnox-dev` output (previously blocked; now green):**
  - `nix eval .#nixosConfigurations.bnox-dev.config.networking.hostName` → `"bnox-dev"` ✓
  - `nix eval .#nixosConfigurations.bnox-dev.config.virtualisation.oci-containers.containers` (attrNames) → `[ "demo-web" ]` ✓
  - `nix eval .#nixosConfigurations.bnox-dev.config.services.caddy.virtualHosts` (attrNames) → `[ "demo.local" ]` ✓
  - `nix eval .#nixosConfigurations.bnox-dev.config.bnox.things.demo.enable` → `true` ✓
  - `nix eval .#nixosConfigurations.bnox-dev.config.users.users` (`? demo`) → `true` ✓
  - `nix eval .#nixosConfigurations.bnox-dev.config.system.build.toplevel.drvPath` → `"/nix/store/sy04hxwczrnagzc2924w2jk6rmi0fszx-nixos-system-bnox-dev-26.05.20260726.8623c4c.drv"` ✓ (real derivation; hash matches the throwaway-eval proof, confirming consistency)

**Self-assessment:**

My two deliverables (`configuration.nix`, `hardware-configuration.nix`) are complete, comment-free, minimal (~30-line target met: 23 + 9 lines), and proven to compose the entire bnox core end-to-end via the **real** `nixosConfigurations.bnox-dev` flake output (base + platform + things + the server profile → a fully evaluable NixOS system with a building `toplevel` derivation). The capstone intent of D-012 Phase 1 is met: the inline thing flows through the full stack (user/group, container, Caddy vhost, secret slot, hardening, validators), and the auto-discovery picks up the host into `nixosConfigurations.<host>` with no per-host flake registration.

The authorized one-line `flake.nix:68` fix (Job-01 latent path-interpolation bug) was applied in the minimal valid form (`./hosts/${name}/configuration.nix`) after discovering the coordinator-specified `${hostsDir}/...` form is a lexer syntax error. This was the only edit outside my original file set, explicitly authorized, and it unblocks every future host (not just this one). I verified the `flake.nix` diff is exactly one line, no comment added.

**Focus areas for the checker:**

1. **The authorized `flake.nix:68` fix.** Confirm the one-line delta (`hostsDir/${name}/…` → `./hosts/${name}/…`) and the syntactic deviation from the coordinator's literal `${hostsDir}/…` form (which is a lexer error — path interpolation can't start with `${`). Note this is a Job-01 defect fixed here under authorization; a back-reference in Job 01's checker notes is optional. With it applied, `nix flake check` now deep-checks `nixosConfigurations.bnox-dev` and all six spec'd evals pass verbatim via the real flake output.
2. **`{ bnox, ... }:` module arg** vs the 07-diversions worked-example shape (`{ ... }:`). I used the destructured form because it's the only one that compiles. If the checker prefers the docs to be the source of truth, the 07-diversions examples should be amended to `{ bnox, ... }:` in a doc-only follow-up (out of my scope here).
3. **No local `secrets/secrets.nix`** for the demo thing. The thing declares `secrets = ["api_key"]` and Job 05 wires it to `fileSlots."demo/api_key"` + the container's environmentFiles automatically — no per-host agenix rule is required to *evaluate*. A real deployment would add the actual secret file + agenix rule, but that's deployment (Phase 2), not this eval-capstone. Confirm this reading.
4. **DHCP + stateVersion delegation** are intentional lean choices per the spec's own guidance; no surprises expected.

## Checker notes

**VERDICT: PASS** — independent re-run, 2026-07-29. All 7 checklist items green. The D-012 Phase 1 capstone is met: the bnox core (base + platform + things + secrets + the server profile) composes into a fully evaluable NixOS system via the real `.#nixosConfigurations.bnox-dev` flake output, with a real `toplevel` derivation.

**Per-item results:**

1. **Scope — OK.** `git status`: new staged files `hosts/bnox-dev/{configuration,hardware-configuration}.nix`; `flake.nix` modified (unstaged); untracked `design/jobs/07-validation-host.md`. `git diff --numstat flake.nix` = `1 1` (exactly one line). No module files touched. No `.bnox/` loader, no deployment pipeline, no `disk-config.nix`. `hosts/bnox-dev/` contains exactly the 2 expected files.
2. **No comments — OK.** `rg -n '(^|[^a-zA-Z0-9"])#|/\*' hosts/bnox-dev flake.nix` → exit 1 (no matches) in both the new files and `flake.nix`.
3. **configuration.nix shape — OK.** `imports = [ bnox.profiles.server ./hardware-configuration.nix ]` ONLY (no double-import of `bnox.nixosModules.bnox`). `{ bnox, ... }:` arg form is correct — `bnox` is a specialArg (flake.nix:63-65), so destructuring is required; the 07-diversions doc's `{ ... }:` examples are a doc-side inconsistency, not a code defect. hostname, DHCP, `firewall.allowedTCPPorts = [80 443]`, and the inline `demo` webapp thing all present. ~27 lines (meets the ~30-line target; the worker's self-reported "23 lines" is a minor miscount — the actual file is 27, immaterial).
4. **hardware-configuration.nix — OK.** 9-line stub: fake root `fileSystems."/"` with `fsType = "ext4"`, `boot.loader.systemd-boot.enable = true`. Evaluates cleanly without a real machine (all evals below pass).
5. **flake.nix fix — OK, sole delta, correct.** Line 68 is now `./hosts/${name}/configuration.nix` (diff: `hostsDir/${name}/configuration.nix` → `./hosts/${name}/configuration.nix`, exactly one line). `hostsDir` still defined (flake.nix:32) and still used by the guard (`pathExists` flake.nix:34 + `readDir` flake.nix:35). Independently reproduced both worker claims: `${hostsDir}/foo/bar.nix` → `error: syntax error, unexpected DOLLAR_CURLY` (so the coordinator's literal `${hostsDir}/...` form genuinely does not parse), and `hostsDir/foo/bar.nix` resolves to the literal path `<src>/hostsDir/foo/bar.nix` (confirming the latent Job-01 bug). `./hosts/${name}/configuration.nix` is the canonical valid idiom and is semantically identical to the intended `${hostsDir}/${name}/...` (since `hostsDir = ./hosts`). Deviation from the literal authorized form is justified.
6. **End-to-end composition — OK.** Pasted output below.
7. **D-012 Phase 1 capstone — OK.** The inline thing flows through the full stack and forces the entire real flake output path: `users.users.demo` (thing user), container `demo-web`, Caddy vhost `demo.local`, secret slot wired (Job 05), server profile applied, base floor inherited. `toplevel.drvPath` is a real store derivation → would build. Capstone intent met.

**Pasted verification output:**

```
$ nix flake check
warning: Git tree '...' is dirty
checking flake output 'lib'...
checking flake output 'nixosModules'...
checking NixOS module 'nixosModules.bnox'...
checking NixOS module 'nixosModules.bnox-base'...
checking flake output 'nixosConfigurations'...
checking NixOS configuration 'nixosConfigurations.bnox-dev'...
checking flake output 'profiles'...   (warning: unknown flake output 'profiles')
checking flake output 'hardware'...   (warning: unknown flake output 'hardware')
checking flake output 'packages'...
warning: The check omitted these incompatible systems: x86_64-linux
exit=0
```
(Deep-checks `nixosConfigurations.bnox-dev`; the only warnings are the cross-system `x86_64-linux` omission on this darwin host and the benign unknown-output notices for `profiles`/`hardware` — both consistent with prior jobs.)

```
$ nix flake show
├───hardware: unknown
├───lib: unknown
├───nixosConfigurations
│   └───bnox-dev: NixOS configuration
├───nixosModules
│   ├───bnox: NixOS module
│   └───bnox-base: NixOS module
└───profiles: unknown
```

```
$ nix eval .#nixosConfigurations.bnox-dev.config.networking.hostName
"bnox-dev"

$ nix eval .#nixosConfigurations.bnox-dev.config.virtualisation.oci-containers.containers --apply 'builtins.attrNames'
[ "demo-web" ]

$ nix eval .#nixosConfigurations.bnox-dev.config.services.caddy.virtualHosts --apply 'builtins.attrNames'
[ "demo.local" ]

$ nix eval .#nixosConfigurations.bnox-dev.config.bnox.things.demo.enable
true

$ nix eval .#nixosConfigurations.bnox-dev.config.users.users --apply 'builtins.attrNames'
[ "bh" "caddy" "demo" "dhcpcd" "messagebus" "nats" "nixbld1" ... "nixbld32" "nobody" "nscd" "root" "sshd" "systemd-coredump" "systemd-network" "systemd-oom" "systemd-resolve" "systemd-timesync" ]
(demo present — the thing's user)

$ nix eval .#nixosConfigurations.bnox-dev.config.system.build.toplevel.drvPath
"/nix/store/sy04hxwczrnagzc2924w2jk6rmi0fszx-nixos-system-bnox-dev-26.05.20260726.8623c4c.drv"
```
All six spec'd evals pass verbatim via the real flake output; `drvPath` hash `sy04hxwcz…` matches the worker's report.

**flake.nix sole delta confirmation:** `git diff --numstat flake.nix` = `1 1` — one line changed (line 68), no comment added, `hostsDir` binding + guard untouched. Fix is correct and minimal. The authorized Job-01 latent path-interpolation bug is resolved (worth a back-reference in Job 01's checker notes at principal's discretion — out of scope here).

No issues found. No fixes requested.

## Sign-off

Checker APPROVED — VERDICT: PASS. 2026-07-29.
