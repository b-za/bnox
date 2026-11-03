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

  inputs.bnox.url = "github:b-za/bnox?dir=versions/0/0/1";

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
- To upgrade bnox: change the `?dir=` to a newer version (or series) and `nix flake update bnox`. Hosts never drift onto an untested mix.
- Local development before your host repo has a remote: `inputs.bnox.url = "git+file:../bnox?dir=versions/0/0/1";` (requires the bnox checkout to be committed).

## 2. Write the host

Copy an example from [examples/](./examples/) as a starting point. See [host-config.md](./host-config.md) for what goes in the divergence file.

## 3. Install with nixos-anywhere

From any machine with nix (flakes enabled), with the host repo committed:

```bash
nix run github:numtide/nixos-anywhere -- root@<ip> --flake .#myserver
```

This kexecs the target into a NixOS installer, wipes and repartitions the disks per `disk-config.nix` (disko), installs the system, and reboots into it. **Everything on the target disk is destroyed.**

After first boot:

- SSH in as your user (the bnox base ships the `bh` user with an authorized key, root login and password auth disabled).
- `sudo tailscale up` to join the tailnet (Tailscale ships enabled but unauthenticated).

## 4. Day-to-day changes

Clone the host repo onto the host (or push from your workstation) and:

```bash
sudo nixos-rebuild switch --flake .#myserver
```

Every rebuild is a boot menu entry — reboot into the previous generation to roll back an OS change. Application ("thing") updates do **not** need rebuilds; see [deployment.md](./deployment.md).
