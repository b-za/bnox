{ lib, config, pkgs, ... }:
let
  natsCli = pkgs.natscli;

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

  # D-018: Go dispatcher (nats-py could not do nkey auth — G4)
  dispatcher = pkgs.buildGoModule {
    pname = "bnox-deploy-dispatcher";
    version = "0.4.0";
    src = ./dispatcher;
    vendorHash = "sha256-nA1CVJflkPFIj2eZY/wjmDP+AN0yqXJPM+zmQmw/BqM=";
  };

  pipelineSeed = name: "/var/lib/bnox/nats/bnox-deploy-${name}.seed";

  syncServices = builtins.listToAttrs (
    map (
      thing:
      let name = thing.name; in
      lib.nameValuePair "${name}-sync" {
        after = [ "network.target" "bnox-nats-keygen.service" ];
        # D-018: per-thing pipeline identity (publishes host.deploy.<name>.> only)
        environment.NATS_NKEY = pipelineSeed name;
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
          # systemd 260 IPAddressAllow is address-only (D-016 §5, G13): the 0/3/0
          # ":443 :22 :53" list was load-invalid; fetch needs the internet → any
          IPAddressAllow = "any";
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
            imgpath=$(${pkgs.nix}/bin/nix build --no-link --print-out-paths "/srv/${name}#images.${pkgs.stdenv.hostPlatform.system}.${comp}") || fail "nix build ${comp} failed"
            if [ -x "$imgpath" ]; then
              loaded=$("$imgpath" | ${pkgs.podman}/bin/podman load 2>/dev/null | awk '/Loaded image/ {print $3}') || fail "podman load ${comp} failed"
            else
              loaded=$(${pkgs.podman}/bin/podman load < "$imgpath" 2>/dev/null | awk '/Loaded image/ {print $3}') || fail "podman load ${comp} failed"
            fi
            ${pkgs.podman}/bin/podman tag "$loaded" "${name}-${comp}:current" || fail "podman tag ${comp} failed"
          ''
        ) comps;
        # D-017 §1: the manifest is evaluated from `source` (a locked flake
        # input); the code is built from /srv/<name>. Warn when they disagree —
        # the host repo's lock needs bumping and a rebuild for .bnox/ changes.
        manifestDir = "${thing.source}/.bnox";
        driftCheck = lib.optionalString (thing.source != "/srv/${name}") ''
          if ! diff -rq "${manifestDir}" "/srv/${name}/.bnox" >/dev/null 2>&1; then
            echo "bnox: WARNING ${name}: /srv/${name}/.bnox differs from the evaluated manifest (${manifestDir}); bump the host repo's lock for this thing and rebuild" >&2
          fi
        '';
        restartLoop = lib.concatMapStringsSep "\n" (
          comp:
          ''
            systemctl restart "podman-${name}-${comp}" || fail "restart podman-${name}-${comp} failed"
          ''
        ) comps;
      in
      lib.nameValuePair "${name}-build" {
        after = [ "network.target" "bnox-nats-keygen.service" ];
        path = [
          pkgs.git
          pkgs.nix
          pkgs.podman
          natsCli
          pkgs.systemd
          pkgs.gawk
          pkgs.coreutils
          pkgs.diffutils
        ];
        # G22: nix's fetcher cache under ProtectHome=read-only is unwritable
        environment = {
          XDG_CACHE_HOME = "/var/lib/${name}/.cache";
          NATS_NKEY = pipelineSeed name; # D-018
        };
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          # G24: podman's runtime locks + short-name alias cache; G31: nix build logs
          ReadWritePaths = "/srv/${name} /var/lib/${name} /var/lib/containers /nix/var/nix /nix/var/log/nix /run/lock /run/libpod /run/containers /var/cache/containers";
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
          ${driftCheck}
          ${buildLoop}
          ${natsCli}/bin/nats pub "host.deploy.${name}.built" "{\"thing\":\"${name}\",\"sha\":\"$sha\"}" >/dev/null 2>&1 || fail "nats publish built failed"
          tarpath="$imgdir/$sha.tar"
          # G25: podman save cannot overwrite an existing archive (same-sha rebuild);
          # remove only this sha's tar — older tars are the rollback set (D-011)
          rm -f "$tarpath"
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
    # G21: nix's libgit2 (and git) refuse /srv checkouts owned by another user
    # when the pipeline units run as root / the thing user; the git CLI gets
    # -c safe.directory, libgit2 only reads the system config
    (lib.mkIf (enabledThingsList != [ ]) {
      environment.etc."gitconfig".text = lib.concatMapStringsSep "\n" (
        thing: "[safe]\n\tdirectory = /srv/${thing.name}"
      ) enabledThingsList;
    })
    (lib.mkIf natsReady {
      systemd.services.bnox-deploy-dispatcher = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "nats.service" "bnox-nats-keygen.service" ];
        requires = [ "nats.service" ];
        environment = {
          NATS_URL = "nats://127.0.0.1:4222";
          NATS_NKEY = "/var/lib/bnox/nats/bnox-deploy-dispatcher.seed";
        };
        path = [ pkgs.systemd ];
        serviceConfig = {
          Type = "simple";
          User = "root";
          Group = "root";
          ExecStart = "${dispatcher}/bin/deploy-dispatcher";
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
