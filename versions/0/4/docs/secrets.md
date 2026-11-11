# Secrets

bnox has two secret layers. Don't mix them up.

| Layer | What lives here | Mechanism | Change requires |
|---|---|---|---|
| **Infra** (host-level) | tailscale auth keys, tokens the OS itself needs | **agenix** — encrypted in git, decrypted at activation | rebuild |
| **Things** (per-thing slots) | `api_key`, tokens, anything an app reads | **file backend** — plaintext at `/var/lib/bnox/secrets/<thing>/<slot>/`, watched by systemd-path | nothing — write file, service restarts |

## Infra layer — agenix

**Only ciphertext is ever committed.** A rules file maps each secret to its recipients:

```nix
# hosts/<name>/secrets/secrets.nix
let
  host = "ssh-ed25519 AAAA… <host pubkey>";
  recovery = "age1…";               # your off-host recovery key
in
{
  "tailscale.age".publicKeys = [ host recovery ];
}
```

- The secret itself is `tailscale.age`, encrypted to those keys. A repo leak is useless without a private key.
- On the host, the agenix module decrypts at activation using the SSH host key (`/etc/ssh/ssh_host_ed25519_key` — the host key *is* the decryption key). Plaintext appears only at `/run/agenix/<name>`: tmpfs, root-only, never on disk.
- **Every secret carries the recovery recipient** (held on your workstation / password manager). Host dies → clone repo on new hardware, re-add the new host key as recipient, re-encrypt — no backups of `/etc/ssh` needed.

Workflow:

```bash
# edit a secret (decrypts with your key, re-encrypts to all recipients on save)
agenix -e hosts/myserver/secrets/tailscale.age

# after adding a new host's key to the rules file, re-encrypt everything
agenix -r
```

New host bootstrap: install (first boot generates its SSH host key) → `ssh-keyscan <host>` → add pubkey to rules → `agenix -r` → rebuild.

A starter rules file ships at `secrets/secrets.nix.example` inside each bnox version.

## Things layer — file backend

Things declare slot names in `.bnox/`; the host binds them; values are plain files:

```
/var/lib/bnox/secrets/<thing>/<slot>
```

Each slot is a single file, an env file (`NAME=value` lines). bnox creates every declared slot as an **empty file, root-only (0600)**, so a thing can start before its values land; existing files are never touched (tmpfiles `f` writes only at creation — so don't use tmpfiles to *set* a value: a change is silently ignored). The slot directory belongs to the thing's user, but the files are root's: systemd reads them as PID 1 and loads them as environment variables into the thing — for both runtimes (container and host-install, from 0/3/1). Host-install things cannot write their secrets directory. Each slot is watched by a systemd-path unit: write a new value (SSH, scp, whatever) and the thing's service restarts — **no rebuild, no re-encryption**. This is deliberate: secrets an application reads change far more often than secrets the OS needs.

A `nats-kv` backend (pull from NATS KV, encrypted with the host key) is designed-for but not built; the slot contract is identical, so things and host configs won't change if it lands.

### The implied `nats_seed` slot

Things that declare `nats = true` ([things.md](./things.md)) get an extra `nats_seed` slot they did not list: bnox adds it automatically, so "declares NATS use", "gets a credential" and "gets network reach" cannot drift apart. The slot is an env file — one line, `NATS_SEED=<nkey seed>` — written by the host at runtime (keygen side; seeds never live in a repo or the store). Writing it works like any slot: the thing's service restarts.
