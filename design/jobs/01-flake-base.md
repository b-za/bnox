# Job 01: Flake skeleton + lib + base modules

**Status:** done
**Iteration:** 1
**Created:** 2026-07-28

## Scope

Create the bnox flake foundation and the OS-skeleton modules (`modules/base/`). This is the floor every host inherits. Later jobs add platform/things/secrets/deployment/profiles — do NOT create those here.

**Spec sources (read these):**
- `design/process/06-base-design.md` — module breakdown table, flake inputs/outputs tables.
- `design/process/07-diversions.md` — flake host auto-discovery sketch (specialArgs `bnox = self`).
- `design/process/05-decisions.md` — D-010 (nixos-26.05), D-008 (SSH host key reuse context).
- `design/process/03-requirements.md` — FR-1.2, FR-2, FR-3, FR-7, FR-11 (the requirements this job implements).
- Reference (read-only, adapt patterns, do NOT copy wholesale): `/Users/bh/code/systems/snowi-node/flake.nix`, `configuration.nix`, `lib/default.nix`.

**Files to create:**

1. `flake.nix` — inputs: `nixpkgs` (`github:NixOS/nixpkgs/nixos-26.05`), `home-manager` (`release-26.05`, follows nixpkgs), `disko` (follows nixpkgs), `agenix` (follows nixpkgs), `nixos-hardware`. Outputs:
   - `nixosModules.bnox` — aggregate, imports `modules/default.nix`.
   - `nixosModules.bnox-base` — imports `modules/base/default.nix` only.
   - `nixosConfigurations` — auto-discover `hosts/*/` (one `nixosSystem` per subdir, `system = "x86_64-linux"`, `specialArgs = { bnox = self; }`, modules = `[ self.nixosModules.bnox ./hosts/<name>/configuration.nix ]`). **Must be robust to empty/missing `hosts/`** (guard `builtins.readDir` so the flake evaluates with no hosts yet — produce `{}`).
   - `lib` — expose `mkEnvFile` from `lib/default.nix`.
   - `packages.x86_64-linux` — empty attrset for now (placeholder).
2. `lib/default.nix` — `{ lib }: { mkEnvFile = ...; }` porting the one-liner from snowi-node `lib/default.nix` (line 45). Do NOT port `mkQuadlet` (dropped per D-002).
3. `modules/default.nix` — aggregate; for now imports only `modules/base/default.nix` (later jobs extend it).
4. `modules/base/default.nix` — imports `system.nix`, `ssh.nix`, `users.nix`, `networking.nix`, `home.nix`.
5. `modules/base/system.nix` — locale (`en_US.UTF-8` default is fine), `time.timeZone = "Africa/Johannesburg"` (FR-11.3), base packages (`vim wget git curl jq natscli`), `nix.settings.experimental-features = [ "nix-command" "flakes" ]`, `system.stateVersion = "26.05"`.
6. `modules/base/ssh.nix` — `services.openssh.enable = true`; `settings.PermitRootLogin = "no"`; `settings.PasswordAuthentication = false` (FR-2.3).
7. `modules/base/users.nix` — `users.users.bh`: `isNormalUser = true`, `extraGroups = [ "wheel" ]`, `openssh.authorizedKeys.keys` set to the `bh@bmac.local` RSA key (copy exact value from `/Users/bh/code/systems/snowi-node/configuration.nix` line 73).
8. `modules/base/networking.nix` — `networking.firewall.enable = true`; `services.tailscale.enable = true` (FR-2.4/FR-3.1). Leave `networking.hostName` unset (per-host).
9. `modules/base/home.nix` — register home-manager: import the home-manager NixOS module is NOT done here (it's injected by the host/flake); instead set the `home-manager` config block: `useGlobalPkgs = true`, `useUserPackages = true`, `users.bh = import ../../home/default.nix;`, `backupFileExtension = "backup"`. (Mirror snowi-node `flake.nix` lines 51-59 pattern.)
10. `home/default.nix` — minimal home-manager config for `bh` (a few base packages + shell). Full dotfiles are a later job; keep this minimal.

**Constraints:**
- **No comments in any Nix file** (hard rule, user preference).
- Pin `nixos-26.05` (D-010).
- Honor the requirements cited above.
- Do not create: `modules/platform/`, `modules/things/`, `modules/secrets/`, `modules/deployment/`, `modules/profiles/`, `modules/hardware/`, `hosts/`, `packages/*` content, `secrets/` — those are later jobs.
- Do not generate `flake.lock` unless `nix flake lock` succeeds (it's fine if it does; fine if network-blocked).

**Validation to run before reporting done:**
- `nix flake lock` (best effort).
- `nix flake show` and/or `nix flake check` — confirm the flake evaluates and exposes `nixosModules.bnox`, `nixosModules.bnox-base`, `lib`.

## Worker notes

**Built (Job 01, iteration 1, 2026-07-28):**

Files created (10 total):
- `flake.nix` — 5 inputs (nixos-26.05, home-manager release-26.05, disko, agenix, nixos-hardware), outputs `nixosModules.{bnox,bnox-base}`, `nixosConfigurations` (auto-discovery), `lib`, `packages.x86_64-linux` (empty placeholder).
- `lib/default.nix` — `mkEnvFile` only (mkQuadlet dropped per D-002).
- `modules/default.nix` — aggregate importing `./base/default.nix`.
- `modules/base/default.nix` — imports system/ssh/users/networking/home.
- `modules/base/system.nix` — locale `en_US.UTF-8`, TZ `Africa/Johannesburg`, base packages (vim wget git curl jq natscli), experimental-features, stateVersion `26.05`.
- `modules/base/ssh.nix` — openssh enabled, `PermitRootLogin="no"`, `PasswordAuthentication=false`.
- `modules/base/users.nix` — `bh` (normal user, wheel), single RSA pubkey `bh@bmac.local` copied verbatim from snowi-node configuration.nix.
- `modules/base/networking.nix` — firewall enabled, tailscale enabled. `networking.hostName` deliberately unset (per-host).
- `modules/base/home.nix` — home-manager config block only (useGlobalPkgs, useUserPackages, backupFileExtension="backup", `users.bh = import ../../home/default.nix`).
- `home/default.nix` — minimal (username, homeDirectory, stateVersion 26.05, bash, htop+tmux).

**Key decisions beyond the literal spec:**

1. **Home-manager NixOS module injection point.** Spec said the HM NixOS module is "injected by the host/flake" and *not* in `modules/base/home.nix` (which only sets the HM config block). I inject `home-manager.nixosModules.home-manager` inside `nixosModules.bnox` and `nixosModules.bnox-base` in `flake.nix` (each module's `imports` list). This keeps `modules/` free of flake-input references (so `modules/` could in principle be vendored), and keeps host configs divergence-only — a host importing `bnox.nixosModules.bnox` automatically gets the HM module. Both `bnox` and `bnox-base` carry the injection so a partial-adopt consumer of `bnox-base` also sees the `home-manager.*` options that `modules/base/home.nix` sets. Confirmed end-to-end via a full `nixosSystem` eval (see validation).
2. **`flake.lock` was committed by `nix flake lock`.** The spec said "fine if it does; fine if network-blocked" — lock succeeded, so `flake.lock` exists at repo root (pinned to nixos-26.05 commit `8623c4c...`).
3. **`nix flake check` cross-system warning is benign.** We're on aarch64-darwin; `packages.x86_64-linux = {}` triggers "check omitted these incompatible systems: x86_64-linux". The empty attrset has nothing to actually check, and the warning is standard cross-system noise, not a failure.
4. **Auto-discovery filters to directories only** via `lib.filterAttrs (_: type: type == "directory")`, so stray files in `hosts/` (e.g. a README) won't be treated as hosts. Robust to missing `hosts/` via `builtins.pathExists` guard (returns `{}` → empty `nixosConfigurations`).
5. **`packages.${system} = {}`** uses the let-bound `system = "x86_64-linux"` for one-line consistency with the rest of the outputs.

**Validation output:**

- `nix flake lock` → succeeded. Resolved: nixpkgs `8623c4c...` (nixos-26.05), home-manager `d4fd246...` (release-26.05), disko `ff8702b...`, agenix `b027ee2...`, nixos-hardware `a017f5b...`. `flake.lock` written.
- `nix flake show` →
  ```
  git+file:///Users/bh/code/systems/bnox
  ├───lib: unknown
  └───nixosModules
      ├───bnox: NixOS module
      └───bnox-base: NixOS module
  ```
  (`packages` and `nixosConfigurations` are empty attrsets → not rendered, as expected.)
- `nix flake check` → all outputs OK:
  ```
  checking flake output 'lib'...
  checking flake output 'nixosModules'...
  checking NixOS module 'nixosModules.bnox'...
  checking NixOS module 'nixosModules.bnox-base'...
  checking flake output 'nixosConfigurations'...
  checking flake output 'packages'...
  warning: The check omitted these incompatible systems: x86_64-linux  (benign — see decision 3)
  ```
- **Deeper eval** (beyond spec; proves the HM injection is sound end-to-end by building a real `nixosSystem` from `bnox-base` on x86_64-linux):
  ```
  nix eval --impure --expr '(nixosSystem with bnox-base){...}'
  => { stateVersion = "26.05"; timeZone = "Africa/Johannesburg";
       sshEnabled = true; permitRoot = "no"; tailscale = true; fw = true;
       hmUser = "bh"; bhUid = true; bhKey = 1; pkgsPresent = 131; }
  ```
  All FR-2/FR-3/FR-7/FR-11 requirements satisfied; home-manager user resolves (`hmUser="bh"`).
- `mkEnvFile [ "FOO=bar" "BAZ=qux" ]` → `"FOO=bar\nBAZ=qux\n"` ✓.
- Comment scan: zero `#` or `/* */` comments across all 10 Nix files (hard constraint met).

## Checker notes

**VERDICT: PASS** — 2026-07-28 (independent checker, iteration 1).

All 12 checklist items OK. Summary (one line each):

1. **Scope — OK.** Exactly 11 files staged (the 10 spec'd + `flake.lock`, which the spec explicitly permits). No out-of-scope dirs: no `modules/{platform,things,secrets,deployment,profiles,hardware}/`, no `hosts/`, no `packages/*` content.
2. **No comments — OK.** `rg -n '(^|[^a-zA-Z0-9"])#|/\*' --glob '*.nix' .` returns no matches (exit 1) across all 10 `.nix` files.
3. **Flake inputs — OK.** `nixpkgs = github:NixOS/nixpkgs/nixos-26.05` (flake.nix:5); `home-manager` `release-26.05` w/ `follows = "nixpkgs"` (flake.nix:6-9); `disko` (flake.nix:10-13) and `agenix` (flake.nix:14-17) both follow nixpkgs; `nixos-hardware` present (flake.nix:18). Cross-checked against `flake.lock`: root binds nixpkgs→`nixpkgs_2` (rev 8623c4c, nixos-26.05), home-manager→`home-manager_2` (rev d4fd246, release-26.05, follows root nixpkgs).
4. **Flake outputs — OK.** `nixosModules.bnox` aggregate (flake.nix:42-47), `nixosModules.bnox-base` (flake.nix:49-54), `lib` exposing `mkEnvFile` (flake.nix:72 + lib/default.nix:4), `packages.x86_64-linux` empty placeholder (flake.nix:74), `nixosConfigurations` auto-discovery (flake.nix:56-70).
5. **Auto-discovery robustness — OK.** Guarded by `builtins.pathExists hostsDir` (flake.nix:33); directory-only filter (flake.nix:37-39); `specialArgs = { bnox = self; }` (flake.nix:61-63); `system = "x86_64-linux"` (flake.nix:60); modules = `[ self.nixosModules.bnox ./hosts/<name>/configuration.nix ]` (flake.nix:64-67). Verified live: `hosts/` is currently missing and the flake evaluates cleanly with `nixosConfigurations = {}`.
6. **base/system.nix — OK.** `time.timeZone = "Africa/Johannesburg"` (system.nix:6); packages `vim wget git curl jq natscli` (system.nix:8-15); `experimental-features = ["nix-command" "flakes"]` (system.nix:17-20); `system.stateVersion = "26.05"` (system.nix:22). Locale `en_US.UTF-8` set (system.nix:4).
7. **base/ssh.nix — OK.** `services.openssh.enable = true` (ssh.nix:3); `PermitRootLogin = "no"` (ssh.nix:5); `PasswordAuthentication = false` (ssh.nix:6).
8. **base/users.nix — OK.** `users.users.bh` with `isNormalUser` (users.nix:3), `extraGroups = ["wheel"]` (users.nix:4), `bh@bmac.local` RSA key present (users.nix:6). `diff` of the key string against `/Users/bh/code/systems/snowi-node/configuration.nix:73` → byte-identical ("KEYS IDENTICAL").
9. **base/networking.nix — OK.** `networking.firewall.enable = true` (networking.nix:2); `services.tailscale.enable = true` (networking.nix:4); `networking.hostName` deliberately absent (file has only 2 settings).
10. **base/home.nix — OK.** `useGlobalPkgs = true`, `useUserPackages = true`, `backupFileExtension = "backup"`, `users.bh = import ../../home/default.nix` (home.nix:3-6).
11. **lib/default.nix — OK.** `mkEnvFile` present and correct (lib/default.nix:4); `mkQuadlet` absent (D-002 honored). `nix eval` of `mkEnvFile [ "FOO=bar" "BAZ=qux" ]` → `"FOO=bar\nBAZ=qux\n"` ✓.
12. **HM-injection interpretation — OK (sound).** See assessment below.

**Reproduced command output:**

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───lib: unknown
└───nixosModules
    ├───bnox: NixOS module
    └───bnox-base: NixOS module
```
(`packages` and `nixosConfigurations` are empty attrsets → not rendered, as expected; matches worker claim.)

`nix flake check`:
```
checking flake output 'lib'...
checking flake output 'nixosModules'...
checking NixOS module 'nixosModules.bnox'...
checking NixOS module 'nixosModules.bnox-base'...
checking flake output 'nixosConfigurations'...
checking flake output 'packages'...
warning: The check omitted these incompatible systems: x86_64-linux
```
(cross-system warning is benign — empty `packages.x86_64-linux` attrset on an aarch64-darwin host; nothing to check. Matches worker decision note 3.)

**Real `nixosSystem` composition eval** (independent reproduction — built a throwaway `nixosSystem` from `f.nixosModules.bnox` on x86_64-linux with a stub filesystem, proving all base options and home-manager options resolve end-to-end):
```
{ basePkgsCount = 131; bhIsNormal = true; bhKeys = 1; bhWheel = [ "wheel" ];
  hmUserBh = "bh"; }   ← second pass (fileSystems stub)
{ fw = true; hmBackup = "backup"; hmUseGlobal = true; hmUseUserPkgs = true;
  hostNameUnset = "checkhost"; nixFeats = [ "nix-command" "flakes" ];
  passwordAuth = false; permitRoot = "no"; sshEnabled = true;
  stateVersion = "26.05"; tailscale = true; timeZone = "Africa/Johannesburg"; }
```
All FR-2/FR-3/FR-7/FR-11 requirements satisfied; `home-manager.*` options resolve (proves HM NixOS module was injected); `home-manager.users.bh` resolves to username "bh" (proves `home/default.nix` loads). `basePkgsCount = 131` matches the worker's claim exactly.

**Assessment of worker's HM-injection interpretation (item 12):**

The worker injected `home-manager.nixosModules.home-manager` inside BOTH `nixosModules.bnox` and `nixosModules.bnox-base` (flake.nix:44, 51), rather than at host level or inside `modules/base/home.nix`. This is sound and arguably the cleanest reading of the spec:

- Spec line 33 explicitly says the HM NixOS module is "injected by the host/flake" and *not* in `modules/base/home.nix`. The worker chose "flake"; this is a valid branch of the spec's own "host/flake" phrasing.
- (a) **`modules/` is free of flake-input references** — confirmed by reading all 7 files under `modules/`; only `flake.nix` references the `home-manager` input. `modules/base/home.nix` sets only the `home-manager.*` config block and does not import the module. This keeps `modules/` vendorable.
- (b) **Consistent with `07-diversions.md`.** That doc's auto-discovery sketch injects only `self.nixosModules.bnox` (line 89) and states host files stay divergence-only / the base is "injected by the flake". Because `bnox` now carries the HM module, a host is NOT forced to import HM manually — the worked examples in 07-diversions.md (which import only profiles/hardware/thing bindings) work as written. No flag.
- Injecting into `bnox-base` as well as `bnox` is necessary (not redundant): `modules/base/home.nix` sets `home-manager.*` options, so any consumer of `bnox-base` must also have the HM module in scope. NixOS module imports are dedup-safe, so the double declaration is harmless.

No issues found. Approved.

## Sign-off
Approved 2026-07-28 — independent checker, iteration 1, verdict PASS (all 12 items OK, `nix flake check` reproduced, HM-injection interpretation confirmed sound).
