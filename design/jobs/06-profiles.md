# Job 06: Profiles + flake profile outputs + secrets template

**Status:** done
**Iteration:** 1
**Created:** 2026-07-29

## Scope

Implement the profile diversion axis (FR-12, `07-diversions.md`): three profiles (`minimal`/`server`/`desktop`) exposed as flake outputs (`bnox.profiles.<name>`) that hosts import. Plus the agenix rules template (`secrets/secrets.nix.example`, choice 4a) and an empty `hardware` output placeholder.

Per `07-diversions.md`: profiles are **flake outputs imported separately by hosts** (a host does `imports = [ bnox.profiles.desktop ]`); they are NOT part of the auto-injected `nixosModules.bnox` aggregate. `modules/base/` is the implicit floor; profiles diverge from it.

**Spec sources (read these):**
- `design/process/07-diversions.md` — profile table (minimal/server/desktop content), flake output shape (`bnox.profiles.<name>`, `bnox.hardware.<name>`), the host-config sketch.
- `design/process/03-requirements.md` — FR-12 (profiles), FR-6.3 (secrets templates/examples).
- `design/process/05-decisions.md` — D-008 (agenix recovery recipient — second recipient on every secret; the template must show both host key + recovery key).
- `design/jobs/01-flake-base.md` — the flake output structure + `specialArgs = { bnox = self; }` (hosts reach `bnox.profiles.*` via this).

## Files to create / modify

1. `modules/profiles/minimal.nix` — the bootstrap/lightweight profile. **Pragmatic interpretation** (flag for review): disable the platform services that `modules/platform/` enables via `mkDefault` — i.e. `virtualisation.podman.enable = lib.mkForce false; services.caddy.enable = lib.mkForce false; services.nats.enable = lib.mkForce false;`. Keep base (SSH, user `bh`, Tailscale, firewall). No things. Rationale: `07-diversions.md` literally says minimal "disables Tailscale, defers user setup" but a useful minimal for bnox keeps the operator access (SSH+bh+Tailscale) and just turns off the heavy platform services; note this deviation in worker notes.
2. `modules/profiles/server.nix` — near-empty additive (base is already server-friendly; server is mostly the *absence* of desktop). Can be a minimal module (e.g. just `{ }` with a comment-free body, or set a couple of server-friendly defaults). State what (if anything) it sets.
3. `modules/profiles/desktop.nix` — the additive desktop profile (FR-12.2): X server (`services.xserver.enable`), window manager qtile, display manager ly (`services.displayManager.ly.enable` or the current NixOS 26.05 equivalent — verify the option path), a terminal (e.g. alacritty or kitty), a browser (firefox), audio (pipewire: `services.pipewire.enable`). Use `lib.mkDefault` where sensible so hosts can override.
4. **Modify `flake.nix`** — add outputs:
   - `profiles.minimal = ./modules/profiles/minimal.nix;` (and `.server`, `.desktop`) — these are module paths (hosts import them).
   - `hardware = { };` — empty attrset placeholder (hardware modules land in Phase 3 per D-012).
   - Do NOT add granular `nixosModules.bnox-platform/things/secrets` (deferred).
5. `secrets/secrets.nix.example` — agenix rules template. Show the canonical agenix `secrets.nix` shape: a function returning an attrset mapping secret names → `{ file = ./.<name>.age; owners = [ "host-ssh-key" "recovery-key" ]; }` (or the `age` recipient list form agenix uses). Include BOTH recipients per D-008 (the host SSH key + a recovery key) with placeholders + a short note (this is an example file, comments are fine here since it's not a Nix module — but keep minimal).

## Constraints

- No comments in the profile `.nix` files or `flake.nix`. (The `secrets.nix.example` is documentation — minimal clarifying comments OK there.)
- No option `description` fields.
- Profiles are flake outputs, NOT imported into `modules/default.nix` (the aggregate). Do NOT modify `modules/default.nix`.
- Do NOT touch base/platform/things/secrets/lib/home beyond the `flake.nix` edit.
- Verify the NixOS 26.05 option paths for ly display manager and pipewire (they may have moved from older NixOS).

## Validation to run before reporting done

- `nix flake check` — must pass.
- `nix flake show` — confirm `profiles` output appears (with minimal/server/desktop) and `hardware`.
- Throwaway `nixosSystem` evals (x86_64-linux, stub fs/boot `fsType="ext4"`):
  - **desktop**: `nixosSystem` with modules `[ self.nixosModules.bnox self.profiles.desktop ]` → confirm `config.services.xserver.enable` true, pipewire enabled, qtile present, ly enabled, firefox/terminal in system packages.
  - **minimal**: modules `[ self.nixosModules.bnox self.profiles.minimal ]` → confirm `config.virtualisation.podman.enable == false`, `services.caddy.enable == false`, `services.nats.enable == false` (mkForce overrode the platform mkDefault), while `services.openssh.enable == true` (base retained).
  - **server**: modules `[ self.nixosModules.bnox self.profiles.server ]` → confirm it evaluates (near-empty); platform services still default-on (server doesn't trim them).
- Paste all results.

## Worker notes

**Files created/modified:**
- Created `modules/profiles/minimal.nix`, `modules/profiles/server.nix`, `modules/profiles/desktop.nix`.
- Created `secrets/secrets.nix.example`.
- Modified `flake.nix`: added `profiles.{minimal,server,desktop}` + `hardware = { }`.
- Did NOT touch `modules/default.nix`, base/platform/things/secrets/lib/home.

**NixOS 26.05 option paths (verified against pinned nixpkgs in the Nix store):**
- **ly**: `services.displayManager.ly.enable`. Source: `nixos/modules/services/display-managers/ly.nix` (moved out of `services.xserver.displayManager` in modern NixOS; the old path does NOT exist in 26.05).
- **pipewire**: `services.pipewire.enable` (+ `.alsa.enable`, `.pulse.enable`). Source: `nixos/modules/services/desktops/pipewire/pipewire.nix`. Note `audio.enable` auto-derives to `alsa.enable || jack.enable || pulse.enable`, so enabling alsa+pulse is sufficient — no need to set `audio.enable` explicitly.
- **qtile**: `services.xserver.windowManager.qtile.enable` (unchanged from older NixOS). Source: `nixos/modules/services/x11/window-managers/qtile.nix`.

**What `server.nix` sets:** nothing. It is an intentional no-op (`{ ... }: { }`). Rationale: base IS the server floor — SSH/bh/Tailscale/firewall + platform services are already server-appropriate, and base does not enable any GUI. "server" is the *absence* of desktop, and since base adds no desktop, the server profile is a marker/placeholder hosts import for semantic clarity (and a future extension point). Flagged for checker: if you'd prefer it to set something explicit (e.g. `services.xserver.enable = mkDefault false;` as a defensive guard), that's a one-line addition.

**Key decision / deviation — minimal profile interpretation:**
- `07-diversions.md` literally says minimal "Trims: disables Tailscale, defers user setup… Just SSH + root + basic networking."
- **Pragmatic deviation (per the job spec's own guidance):** bnox's minimal keeps the operator-access floor from base (SSH hardened, user `bh`, Tailscale, firewall) and instead trims the heavy *platform* services — podman/caddy/nats — via `mkForce false`. These override the platform modules' `mkDefault true`.
- Rationale: a minimal bnox box that loses SSH+bh+Tailscale on first boot is operationally useless for this single-operator setup; the platform services are the real weight. The original "disable Tailscale/defer user" framing was a copy of snowi-node's `configuration-minimal.nix` concept that doesn't translate cleanly to bnox's "base is the floor" model. This deviation is explicitly authorized by the job spec (point 1) and flagged here for review. If the checker prefers the literal 07 interpretation, the file is a 2-line change.

**`secrets.nix.example`:** canonical agenix `publicKeys` form (a let-bound key list, attrset of `"<name>.age".publicKeys = all`). Shows BOTH recipients per D-008 (host SSH ed25519 key + age-format recovery key) with placeholders. Minimal clarifying comments (allowed since this is documentation, not a module).

**Validation results:**
- `nix flake check`: passes (warnings only — "unknown flake output 'profiles'/'hardware'" expected for custom outputs; "incompatible systems: x86_64-linux" expected evaluating linux-only config on darwin; "Git tree dirty" expected mid-work).
- `nix flake show`: `profiles` (unknown type — module paths) and `hardware` both appear alongside existing outputs.
- Throwaway evals (all passed, no assertion failures):
  - desktop: xserver/qtile/ly/pipewire(+alsa+pulse) all `true`; firefox + alacritty present in system packages.
  - minimal: podman/caddy/nats all `false` (mkForce overrode platform mkDefault); openssh `true` (base retained).
  - server: evaluates; podman/caddy/nats/openssh all default-on (`true`); xserver `false` (no GUI).

## Checker notes

**VERDICT: PASS** — verified independently against spec, nixpkgs source, and live `nixosSystem` evals.

Checklist results:
1. **Scope — OK.** `git status` shows only `flake.nix` modified + `modules/profiles/` and `secrets/` untracked. `git diff flake.nix` is the 8-line `profiles`/`hardware` addition only. `modules/default.nix` unchanged (still 8 lines, no profile import). No base/platform/things/secrets/lib/home edits. No granular `nixosModules.*` added.
2. **No comments / no descriptions — OK.** `rg '(^|[^a-zA-Z0-9"])#|/\*|description =' modules/profiles flake.nix` returns only the pre-existing `flake.nix:2: description = "bnox — unified NixOS base";` (the flake's top-level metadata string, NOT a NixOS option description, and NOT introduced by this job). The three profile `.nix` files are comment- and description-free. `secrets.nix.example` carries only the two minimal clarifying comments allowed by spec.
3. **flake outputs — OK.** `profiles.{minimal,server,desktop}` point at the three module paths; `hardware = { };` is the empty placeholder. Both verifiable via `nix eval .#profiles --json` (returns the three paths) and `nix eval .#hardware --json` (returns `{}`). `modules/default.nix` is unchanged.
4. **NixOS 26.05 option paths — OK (independently verified against pinned nixpkgs at `/nix/store/mfvg1blms6k3rfkgxr3q17cyswv9p3z3-source`, rev `aaff8c16…`):**
   - `services.displayManager.ly.enable` — declared at `nixos/modules/services/display-managers/ly.nix:57-58` (`options.services.displayManager.ly.enable = mkEnableOption "ly as the display manager";`). The old `services.xserver.displayManager.ly` path does NOT exist in 26.05.
   - `services.pipewire.enable` (+ `.alsa.enable`, `.pulse.enable`) — declared at `nixos/modules/services/desktops/pipewire/pipewire.nix:93,116,133`. `audio.enable` auto-derives to `alsa.enable || jack.enable || pulse.enable` (line 109), so enabling alsa+pulse is sufficient (worker's note is correct).
   - `services.xserver.windowManager.qtile.enable` — declared at `nixos/modules/services/x11/window-managers/qtile.nix:25-26`. (Only `backend` was removed via `mkRemovedOptionModule`; `enable` path unchanged.)
5. **minimal deviation — ACCEPTED (spec-authorized).** `minimal.nix` uses `mkForce false` on podman/caddy/nats (overriding platform `mkDefault true`) while leaving base (SSH/bh/Tailscale/firewall) intact. This is exactly what Job spec point 1 authorized ("Pragmatic interpretation … Keep base (SSH, user bh, Tailscale, firewall) … note this deviation in worker notes"). Worker notes document the deviation clearly. Operationally sound for a single-operator base where losing SSH+bh+Tailscale on first boot would brick the box. Deviates from 07-diversions.md's literal "disables Tailscale, defers user setup" framing but the job spec explicitly supersedes that with the pragmatic interpretation. Confirmed by eval: podman/caddy/nats all `false`, openssh `true`.
6. **server no-op — ACCEPTED (with minor non-blocking recommendation).** `server.nix` is `{ ... }: { }`. Eval confirms platform services stay default-on (podman/caddy/nats/openssh `true`) and no GUI (`xserver`/`ly` `false`). Matches 07-diversions.md's "near-empty additive … server is mostly the *absence* of desktop" — and base adds no GUI, so a no-op is correct today. **Minor recommendation (NOT a blocker, deferred to a future hardening pass):** defensively add `services.xserver.enable = lib.mkDefault false;` so a future base module that enables X doesn't silently flip every server host to a GUI. Acceptable to defer.
7. **desktop.nix — OK.** X + qtile + ly + pipewire(+alsa+pulse) all enabled with `mkDefault`; firefox + alacritty in `environment.systemPackages`. Eval confirms all `true` and both packages present.
8. **secrets.nix.example — OK.** Canonical agenix `publicKeys` form (let-bound `all = [hostKey recoveryKey]`; attrset of `"<name>.age".publicKeys = all`). BOTH recipients per D-008 (host SSH ed25519 + age recovery key). Placeholder values. Two minimal clarifying comments (allowed in an example file). Shape matches D-008 §5 + D-008 Consequences.

**Independent validation output:**

`nix flake check`:
```
warning: Git tree '/Users/bh/code/systems/bnox' is dirty
evaluating flake...
checking flake output 'lib'...
checking flake output 'nixosModules'...
checking NixOS module 'nixosModules.bnox'...
checking NixOS module 'nixosModules.bnox-base'...
checking flake output 'nixosConfigurations'...
checking flake output 'profiles'...
warning: unknown flake output 'profiles'        # EXPECTED — custom output
checking flake output 'hardware'...
warning: unknown flake output 'hardware'        # EXPECTED — custom output
checking flake output 'packages'...
warning: The check omitted these incompatible systems: x86_64-linux   # EXPECTED — darwin host
```
No errors. Only the three benign warnings the spec said to expect.

`nix flake show`:
```
git+file:///Users/bh/code/systems/bnox
├───hardware: unknown
├───lib: unknown
├───nixosModules
│   ├───bnox: NixOS module
│   └───bnox-base: NixOS module
└───profiles: unknown
```
Both `profiles` and `hardware` present. (`profiles` shows as `unknown` because each value is a path, not a derivable type; `nix eval .#profiles --json` confirms `{desktop,minimal,server}` all resolve to the three module paths.)

Throwaway `nixosSystem` evals (x86_64-linux, stub `fsType="ext4"` + grub device, `system.stateVersion="26.05"`, `specialArgs={bnox=self;}`, modules `[ self.nixosModules.bnox <profile> ]`):
```
{
  "desktop": {
    "caddy": true, "ly": true, "nats": true, "pipewire": true,
    "pipewire-alsa": true, "pipewire-pulse": true,
    "pkgs-has-alacritty": true, "pkgs-has-firefox": true,
    "podman": true, "qtile": true, "ssh": true, "xserver": true
  },
  "minimal": {
    "caddy": false, "ly": false, "nats": false, "pipewire": false,
    "pipewire-alsa": false, "pipewire-pulse": false,
    "pkgs-has-alacritty": false, "pkgs-has-firefox": false,
    "podman": false, "qtile": false, "ssh": true, "xserver": false
  },
  "server": {
    "caddy": true, "ly": false, "nats": true, "pipewire": false,
    "pipewire-alsa": false, "pipewire-pulse": false,
    "pkgs-has-alacritty": false, "pkgs-has-firefox": false,
    "podman": true, "qtile": false, "ssh": true, "xserver": false
  }
}
```
Per-spec assertions: desktop → xserver/qtile/ly/pipewire all true, firefox+alacritty present ✓; minimal → podman/caddy/nats all false (mkForce won), openssh true ✓; server → evaluates, platform services default-on, no GUI ✓.

## Sign-off

**PASS — 2026-07-29.** All checklist items OK or accepted-with-non-blocking-recommendation (item 6, deferred). Spec deviation on minimal profile (item 5) is explicitly authorized by the job spec and documented in worker notes; server no-op (item 6) is correct per 07-diversions.md with a minor future-hardening note recorded. No fixes required to merge.
