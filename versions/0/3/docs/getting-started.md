# Getting started

This walks through bringing up a new host from zero on a fresh Linux VPS (any distro works; it gets wiped).

## 1. Create a host repo

A host repo holds one or more hosts. One repo per system-group is typical, but any grouping works — every subdirectory of `hosts/` becomes a NixOS configuration.

```
my-hosts/
├── flake.nix
└── hosts/
    └── myserver/
        ├── configuration.nix           ← ~30 lines of divergence only
        ├── hardware-configuration.nix  ← kernel modules, bootloader
        └── disk-config.nix             ← disko layout (if installing fresh)
```

`flake.nix` — auto-discovers `hosts/*`, pins bnox, uses bnox's own nixpkgs:

```nix
{
  description = "my hosts on bnox";

  inputs.bnox.url = "github:b-za/bnox?dir=versions/0/2/0";

  outputs =
    {
      self,
      bnox,
    }:
    let
      nixpkgs = bnox.inputs.nixpkgs;
      hostsDir = ./hosts;
      hostEntries = if builtins.pathExists hostsDir then builtins.readDir hostsDir else { };
      hostNames = builtins.attrNames (nixpkgs.lib.filterAttrs (_: type: type == "directory") hostEntries);
    in
    {
      nixosConfigurations = builtins.listToAttrs (
        map (name: {
          inherit name;
          value = nixpkgs.lib.nixosSystem {
            system = "x86_64-linux";
            specialArgs = { bnox = bnox; };
            modules = [
              bnox.nixosModules.bnox
              ./hosts/${name}/configuration.nix
            ];
          };
        }) hostNames
      );
    };
}
```

Notes:

- Pinning happens twice: the `?dir=` selects the bnox version; the repo's `flake.lock` then freezes the exact commit. Because nixpkgs is taken from `bnox.inputs.nixpkgs`, a version pin freezes bnox **and** its nixpkgs together.
- To upgrade bnox: change the `?dir=` to a newer version (or series) and `nix flake update bnox`.
- **Pin nixpkgs explicitly.** Observed on agenthub: `nix flake update bnox` re-resolved bnox's nixpkgs to the `nixos-26.05` branch tip instead of the revision in the version's own `flake.lock`. Declare nixpkgs at the rev the bnox version locks and make bnox follow it:

  ```nix
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/8623c4c20aa4ca2f5fb81510d2944066c3fb0d96"; # = versions/0/3/<patch>/flake.lock
  inputs.bnox.url = "github:b-za/bnox?dir=versions/0/3/1";
  inputs.bnox.inputs.nixpkgs.follows = "nixpkgs";
  ```

  Update the rev whenever you move to a bnox version with a different lock.
- Local development before your host repo has a remote: `inputs.bnox.url = "git+file:../bnox?dir=versions/0/2/0";` (requires the bnox checkout to be committed).

## 2. Write the host

Copy an example from [examples/](./examples/) as a starting point. See [host-config.md](./host-config.md) for what goes in the divergence file.

## 3. Install with nixos-anywhere

If the provider only gives you root **password** auth (most VPSs), pre-seed your key first — nixos-anywhere makes several SSH round-trips and password-prompting mid-run fails:

```bash
ssh-copy-id root@<ip>
```

Then, from any machine with nix (flakes enabled), with the host repo committed:

```bash
nix run github:numtide/nixos-anywhere -- root@<ip> --flake .#myserver
```

This kexecs the target into a NixOS installer, wipes and repartitions the disks per `disk-config.nix` (disko), installs the system, and reboots into it. **Everything on the target disk is destroyed.**

<details>
<summary><strong>Ubuntu targets — quirks found on real installs (tested on 26.04)</strong></summary>

1. **The target needs `cpio` installed** (`apt-get install cpio`) or nixos-anywhere aborts during fact-gathering.
2. **Ubuntu 7.x kernels reject the unsigned NixOS kexec image** via `kexec_file_load` (`PEFILE: Unsigned PE binary` kernel log). Pass `--kexec-extra-flags '--kexec-syscall'` so kexec uses the legacy syscall, which skips signature verification:

   ```bash
   nix run github:numtide/nixos-anywhere -- root@<ip> --flake .#myserver \
     --kexec-extra-flags '--kexec-syscall'
   ```

3. **Run nixos-anywhere detached** (`nohup ... &`) — copying the closure to a remote VPS can outlive an interactive SSH session.

These are target quirks, not bnox behavior; other source distros don't need the workarounds.

</details>

After first boot:

- SSH in as your user — key-only, enforced on every axis: `PasswordAuthentication = false`, `KbdInteractiveAuthentication = false`, `PermitRootLogin = "no"` in the bnox base.
- `sudo` is passwordless for wheel users: bnox accounts have locked passwords by design, so NOPASSWD is the only path to root (since 0.2.0; on 0.1.x hosts nothing can satisfy the sudo prompt — fix via the provider rescue console or a host-side `security.sudo.wheelNeedsPassword = false`).
- `sudo tailscale up` to join the tailnet (Tailscale ships enabled but unauthenticated).

## 4. Day-to-day changes

Clone the host repo onto the host (or push from your workstation) and:

```bash
sudo nixos-rebuild switch --flake .#myserver
```

Every rebuild is a boot menu entry — reboot into the previous generation to roll back an OS change. Application ("thing") updates do **not** need rebuilds; see [deployment.md](./deployment.md).
