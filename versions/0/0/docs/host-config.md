# Host config reference

A host config expresses **only divergence** from the bnox base. Everything else — SSH hardening, users, firewall defaults, platform services — is inherited. A typical host file is ~30 lines.

## Shape

```nix
{ bnox, ... }:
{
  imports = [
    bnox.profiles.server               # exactly one: .minimal / .server / .desktop
    ./hardware-configuration.nix       # kernel modules, bootloader, filesystems
    ./disk-config.nix                  # disko layout (fresh installs)
  ];

  networking.hostName = "myserver";
  networking.useDHCP = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  bnox.things.myapp = {                # zero or more things (see things.md)
    enable = true;
    source = "/srv/myapp";
  };
}
```

Note the `{ bnox, ... }:` head — `bnox` is passed as a specialArg by your host repo's flake and must be destructured.

## The three divergence axes

| Axis | Cardinality | What it controls |
|---|---|---|
| **Profile** | exactly one: `minimal` / `server` / `desktop` | GUI/software divergence. `minimal` trims to SSH + root + networking (bootstrap/first-boot); `server` is the headless floor; `desktop` adds X/qtile/ly/audio/browser |
| **Hardware** | zero or more `bnox.hardware.*` | kernel modules, firmware (e.g. broadcom wifi) — cloud hosts usually need none; the generated `hardware-configuration.nix` covers it |
| **Things** | zero or more `bnox.things.<name>` | which applications run here and their bindings ([things.md](./things.md)) |

`modules/base/` is the implicit floor every host inherits (SSH hardening, Tailscale, firewall on, base packages, home-manager; declare your own users — this version ships none). Profiles diverge from that floor; they don't replace it.

## Overriding bnox defaults

bnox sets defaults with `mkDefault` (platform services are `mkDefault true`; the `minimal` profile trims them with `mkForce false`). Your host config sets **plain values**, which beat `mkDefault`. That's the entire override mechanism:

```nix
services.tailscale.enable = false;     # beats the base's mkDefault true
```

The bnox base never special-cases hosts: no host names, no per-host conditions inside `modules/`. If you find yourself wanting one, that's a promotion candidate ([promotion.md](./promotion.md)).

## What belongs where

| In host config | In bnox (inherited) |
|---|---|
| hostname, network type (DHCP/static/wifi) | SSH hardening, users |
| profile + hardware selection | firewall defaults |
| thing enable + bindings | platform services (Caddy, NATS, Podman) |
| local `hardware-configuration.nix`, `disk-config.nix` | thing abstraction, hardening, deployment |
| host-specific firewall ports / extra packages | secrets backends |

## Bootloader notes

- UEFI hosts: `boot.loader.systemd-boot.enable = true;` in `hardware-configuration.nix` (see the bnox-test host in the bnox-test repo).
- BIOS-legacy hosts (common on cheap KVM VPSs): use GRUB. With a disko `EF02` BIOS-boot partition, disko sets `boot.loader.grub.devices` itself — the host only needs `boot.loader.grub.enable = true;` (see [examples/vps-server](./examples/vps-server/)).
