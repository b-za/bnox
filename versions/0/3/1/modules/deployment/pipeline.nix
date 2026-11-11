{ lib, config, pkgs, ... }:
let
  natsCli = pkgs.natscli;

  pythonWithNats = pkgs.python3.withPackages (ps: [ ps.nats-py ]);

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  natsReady = config.services.nats.enable && config.services.nats.jetstream;

  thingsWithBuildableComps = lib.concatMap (
    thing:
    let
      containerComps = lib.filterAttrs (
        _: comp: comp.enable && comp.runtime == "container" && comp.shape != "static-site"
      ) thing.components;
      compNames = builtins.attrNames containerComps;
    in
    lib.optional (compNames != [ ]) (thing // { inherit compNames; })
  ) enabledThingsList;

  dispatcherSource = ''
    import asyncio
    import os
    import re
    import subprocess
    import sys

    import nats

    SUBJECT = "host.deploy.>"
    THING_RE = re.compile(r"^[a-zA-Z0-9_-]+$")
    EVENT_SUFFIX = {
        "changed": "-sync.service",
        "synced": "-build.service",
    }

    async def handle(msg):
        subject = msg.subject
        parts = subject.split(".")
        if len(parts) != 4 or parts[0] != "host" or parts[1] != "deploy":
            sys.stderr.write("dispatcher: ignoring malformed subject " + subject + "\n")
            return
        thing = parts[2]
        event = parts[3]
        if not THING_RE.match(thing):
            sys.stderr.write("dispatcher: rejecting bad thing name in " + subject + "\n")
            return
        suffix = EVENT_SUFFIX.get(event)
        if suffix is None:
            return
        target = thing + suffix
        try:
            result = subprocess.run(
                ["systemctl", "start", target],
                check=False,
                timeout=120,
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                detail = (result.stderr or "").strip()
                sys.stderr.write("dispatcher: systemctl start " + target + " failed: " + detail + "\n")
        except (subprocess.SubprocessError, OSError) as exc:
            sys.stderr.write("dispatcher: error starting " + target + ": " + str(exc) + "\n")

    async def run():
        url = os.environ.get("BNOX_NATS_URL", "nats://127.0.0.1:4222")
        while True:
            try:
                nc = await nats.connect(url, name="bnox-deploy-dispatcher")
                await nc.subscribe(SUBJECT, cb=handle)
                await asyncio.Event().wait()
            except Exception as exc:
                sys.stderr.write("dispatcher: nats error: " + str(exc) + "; retrying in 5s\n")
                await asyncio.sleep(5)

    if __name__ == "__main__":
        asyncio.run(run())
  '';

  dispatcherScript = pkgs.writeText "bnox-deploy-dispatcher.py" dispatcherSource;

  syncServices = builtins.listToAttrs (
    map (
      thing:
      let name = thing.name; in
      lib.nameValuePair "${name}-sync" {
        after = [ "network.target" ];
        path = [
          pkgs.git
          natsCli
        ];
        serviceConfig = {
          Type = "oneshot";
          User = name;
          Group = name;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = "/srv/${name} /var/lib/${name}";
          IPAddressDeny = "any";
          IPAddressAllow = ":443 :22 :53";
        };
        script = ''
          set -uo pipefail
          fail() {
            ${natsCli}/bin/nats pub "host.deploy.${name}.failed" "{\"thing\":\"${name}\",\"reason\":\"$1\"}" >/dev/null 2>&1 || true
            exit 1
          }
          if ! ${pkgs.git}/bin/git -C /srv/${name} fetch origin; then
            fail "git fetch failed"
          fi
          if ! ${pkgs.git}/bin/git -C /srv/${name} reset --hard origin/${thing.branch}; then
            fail "git reset failed"
          fi
          sha=$(${pkgs.git}/bin/git -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
          ${natsCli}/bin/nats pub "host.deploy.${name}.synced" "{\"thing\":\"${name}\",\"sha\":\"$sha\"}" >/dev/null 2>&1 || fail "nats publish failed"
        '';
      }
    ) enabledThingsList
  );

  buildServices = builtins.listToAttrs (
    map (
      thing:
      let
        name = thing.name;
        comps = thing.compNames;
        imageRefs = lib.concatMapStringsSep " " (comp: "${name}-${comp}:current") comps;
        buildLoop = lib.concatMapStringsSep "\n" (
          comp:
          ''
            imgpath=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "/srv/${name}#images.${pkgs.system}.${comp}") || fail "nix build ${comp} failed"
            if [ -x "$imgpath" ]; then
              loaded=$("$imgpath" | ${pkgs.podman}/bin/podman load 2>/dev/null | awk '/Loaded image/ {print $3}') || fail "podman load ${comp} failed"
            else
              loaded=$(${pkgs.podman}/bin/podman load < "$imgpath" 2>/dev/null | awk '/Loaded image/ {print $3}') || fail "podman load ${comp} failed"
            fi
            ${pkgs.podman}/bin/podman tag "$loaded" "${name}-${comp}:current" || fail "podman tag ${comp} failed"
          ''
        ) comps;
        restartLoop = lib.concatMapStringsSep "\n" (
          comp:
          ''
            systemctl restart "podman-${name}-${comp}" || fail "restart podman-${name}-${comp} failed"
          ''
        ) comps;
      in
      lib.nameValuePair "${name}-build" {
        after = [ "network.target" ];
        path = [
          pkgs.git
          pkgs.nix
          pkgs.podman
          natsCli
          pkgs.systemd
          pkgs.gawk
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = "/srv/${name} /var/lib/${name} /var/lib/containers /nix/var/nix";
          IPAddressDeny = "any";
          IPAddressAllow = "127.0.0.0/8 ::1";
        };
        script = ''
          set -uo pipefail
          fail() {
            ${natsCli}/bin/nats pub "host.deploy.${name}.failed" "{\"thing\":\"${name}\",\"reason\":\"$1\"}" >/dev/null 2>&1 || true
            exit 1
          }
          sha=$(${pkgs.git}/bin/git -c safe.directory=/srv/${name} -C /srv/${name} rev-parse HEAD) || fail "rev-parse failed"
          imgdir=/var/lib/${name}/images
          mkdir -p "$imgdir" || fail "mkdir images failed"
          ${buildLoop}
          ${natsCli}/bin/nats pub "host.deploy.${name}.built" "{\"thing\":\"${name}\",\"sha\":\"$sha\"}" >/dev/null 2>&1 || fail "nats publish built failed"
          tarpath="$imgdir/$sha.tar"
          ${pkgs.podman}/bin/podman save -o "$tarpath" ${imageRefs} || fail "podman save failed"
          ${restartLoop}
          ${natsCli}/bin/nats pub "host.deploy.${name}.deployed" "{\"thing\":\"${name}\",\"sha\":\"$sha\"}" >/dev/null 2>&1 || true
        '';
      }
    ) thingsWithBuildableComps
  );
in
{
  config = lib.mkMerge [
    {
      systemd.services = syncServices // buildServices;
    }
    (lib.mkIf natsReady {
      systemd.services.bnox-deploy-dispatcher = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "nats.service" ];
        requires = [ "nats.service" ];
        environment = {
          BNOX_NATS_URL = "nats://127.0.0.1:4222";
        };
        path = [ pkgs.systemd ];
        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";
          ExecStart = "${pythonWithNats}/bin/python3 ${dispatcherScript}";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          IPAddressDeny = "any";
          IPAddressAllow = "127.0.0.0/8 ::1";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
          ];
        };
      };
    })
  ];
}
