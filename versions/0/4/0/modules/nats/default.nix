# D-018 — NATS identity. The broker always requires logins (no anonymous
# user). Every identity gets an nkey generated on the host at runtime (never
# in a repo or the store); permissions are computed at evaluation from:
#   - things: full access to their own things.<name>.> + their own stream,
#     plus what the host grants them on other things (a role, or "offer")
#   - a thing's .bnox declares its offer (the most anyone else can get) and
#     named roles (subsets of the offer, checked here)
#   - bnox's own services (webhook receiver, dispatcher, per-thing pipeline)
#   - ops (full access, root only) and host-declared extra identities
# Runtime: bnox-nats-keygen (seeds + nats_seed slots) → bnox-nats-auth
# (auth.json from permissions + derived public keys, validated, nats restarted
# on change) → nats → bnox-nats-streams (one stream per NATS thing).
# Mechanics are agenthub's (bnox-bg), proven live; gotchas cited inline.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  hardening = import ../things/hardening.nix { inherit lib; };

  stateDir = "/var/lib/bnox/nats";
  seedPath = id: "${stateDir}/${id}.seed";
  streamName = thing: "things-${thing}";

  natscli = pkgs.natscli;
  nkeyPy = ./nkey.py;
  keygenPy = pkgs.python3.withPackages (ps: [ ps.cryptography ]);

  natsEnabled = config.services.nats.enable;

  enabledThingsList = lib.mapAttrsToList (n: t: t // { name = n; }) (
    lib.filterAttrs (_: t: t.enable) config.bnox.things
  );
  natsThings = builtins.filter (t: t.hardening.network.nats) enabledThingsList;
  natsThingByName = builtins.listToAttrs (map (t: lib.nameValuePair t.name t) natsThings);

  # ---- subject patterns -------------------------------------------------
  # covers b a: does pattern b match every subject pattern a matches?
  covers =
    b: a:
    let
      go =
        bs: as:
        if bs == [ ] then
          as == [ ]
        else
          let
            bh = builtins.head bs;
          in
          if bh == ">" then
            as != [ ]
          else if as == [ ] then
            false
          else
            let
              ah = builtins.head as;
            in
            if ah == ">" then
              false
            else if bh == "*" then
              go (builtins.tail bs) (builtins.tail as)
            else if ah == "*" then
              false
            else
              bh == ah && go (builtins.tail bs) (builtins.tail as);
    in
    go (lib.splitString "." b) (lib.splitString "." a);
  uncovered = pats: offers: builtins.filter (p: !(lib.any (o: covers o p) offers)) pats;

  resolveRole =
    dep: role:
    let
      d = natsThingByName.${dep};
    in
    if role == "offer" then d.nats.offer else d.nats.roles.${role};

  prefixed = dep: map (s: "things.${dep}.${s}");

  # ---- identities -------------------------------------------------------
  inbox = "_INBOX.>";

  thingIdentity =
    t:
    let
      s = streamName t.name;
      grants = lib.mapAttrsToList (dep: role: {
        inherit dep;
        r = resolveRole dep role;
      }) t.nats.grants;
    in
    {
      # host-install units read the seed file (natscli wants a path, G2)
      readers = t.name;
      publish = [
        "things.${t.name}.>"
        inbox
        # own stream: the durable pull-consumer surface (G5, verified)
        "$JS.API.INFO"
        "$JS.API.STREAM.INFO.${s}"
        "$JS.API.CONSUMER.CREATE.${s}"
        "$JS.API.CONSUMER.CREATE.${s}.>"
        "$JS.API.CONSUMER.DURABLE.CREATE.${s}.>"
        "$JS.API.CONSUMER.INFO.${s}.>"
        "$JS.API.CONSUMER.DELETE.${s}.>"
        "$JS.API.CONSUMER.MSG.NEXT.${s}.>"
        "$JS.ACK.${s}.>"
      ]
      ++ lib.concatMap (g: prefixed g.dep g.r.publish) grants
      ++ t.nats.extra.publish;
      subscribe = [
        "things.${t.name}.>"
        inbox
      ]
      ++ lib.concatMap (g: prefixed g.dep g.r.subscribe) grants
      ++ t.nats.extra.subscribe;
    };

  serviceIdentities = {
    ops = {
      readers = null;
      publish = [ ">" ];
      subscribe = [ ">" ];
    };
    bnox-webhook-receiver = {
      readers = "bnox-webhook-receiver";
      publish = [
        "host.deploy.*.changed"
        inbox
      ];
      subscribe = [ inbox ];
    };
    bnox-deploy-dispatcher = {
      readers = null;
      publish = [ inbox ];
      subscribe = [
        "host.deploy.>"
        inbox
      ];
    };
  }
  # per-thing pipeline identity: sync runs as the thing user, build as root
  // builtins.listToAttrs (
    map (
      t:
      lib.nameValuePair "bnox-deploy-${t.name}" {
        readers = t.name;
        publish = [
          "host.deploy.${t.name}.>"
          inbox
        ];
        subscribe = [ inbox ];
      }
    ) enabledThingsList
  );

  identities =
    serviceIdentities
    // builtins.listToAttrs (map (t: lib.nameValuePair t.name (thingIdentity t)) natsThings)
    // config.bnox.nats.identities;

  permissionsJson = pkgs.writeText "bnox-nats-permissions.json" (
    builtins.toJSON (lib.mapAttrs (_: i: { inherit (i) publish subscribe; }) identities)
  );

  # ---- evaluation checks -----------------------------------------------
  reserved = builtins.attrNames serviceIdentities;
  thingNames = map (t: t.name) natsThings;
  hostIdNames = builtins.attrNames config.bnox.nats.identities;

  errors =
    lib.concatMap (
      t:
      # grants on a non-NATS thing
      lib.optional (
        !t.hardening.network.nats && t.nats.grants != { }
      ) "bnox: thing \"${t.name}\" has nats.grants but does not use NATS (nats = true)"
    ) enabledThingsList
    ++ lib.concatMap (
      t:
      lib.optional (t.nats.roles ? offer)
        "bnox: thing \"${t.name}\" declares a role named \"offer\" (reserved: a grant of \"offer\" means the whole offer)"
      ++ lib.concatMap (
        role:
        let
          r = t.nats.roles.${role};
          badPub = uncovered r.publish t.nats.offer.publish;
          badSub = uncovered r.subscribe t.nats.offer.subscribe;
        in
        lib.optional (badPub != [ ] || badSub != [ ])
          "bnox: thing \"${t.name}\" role \"${role}\" goes beyond its offer (publish ${builtins.toJSON badPub}, subscribe ${builtins.toJSON badSub})"
      ) (builtins.attrNames t.nats.roles)
      ++ lib.concatMap (
        dep:
        let
          role = t.nats.grants.${dep};
        in
        if !(builtins.elem dep t.deps) then
          [ "bnox: thing \"${t.name}\" is granted NATS access to \"${dep}\", which is not in its deps" ]
        else if !(natsThingByName ? ${dep}) then
          [
            "bnox: thing \"${t.name}\" is granted NATS access to \"${dep}\", which is not an enabled NATS thing"
          ]
        else if role != "offer" && !(natsThingByName.${dep}.nats.roles ? ${role}) then
          [
            "bnox: thing \"${t.name}\" is granted role \"${role}\" on \"${dep}\", which declares no such role (roles: ${
              builtins.toJSON (builtins.attrNames natsThingByName.${dep}.nats.roles)
            })"
          ]
        else
          [ ]
      ) (builtins.attrNames t.nats.grants)
    ) natsThings
    ++ map (
      n: "bnox: NATS identity name \"${n}\" is reserved by bnox (thing or host identity collides)"
    ) (builtins.filter (n: builtins.elem n reserved) (thingNames ++ hostIdNames))
    ++ map (n: "bnox: host NATS identity \"${n}\" collides with a NATS thing of the same name") (
      builtins.filter (n: builtins.elem n thingNames) hostIdNames
    );

  # ---- streams ----------------------------------------------------------
  # complete and explicit (G8): natscli applies no defaults for absent fields
  streamConfig =
    t:
    pkgs.writeText "${streamName t.name}.json" (
      builtins.toJSON {
        name = streamName t.name;
        subjects = [ "things.${t.name}.>" ];
        retention = "limits";
        max_consumers = -1;
        max_msgs_per_subject = -1;
        max_msgs = -1;
        max_bytes = -1;
        max_age = config.bnox.nats.streamMaxAgeDays * 24 * 60 * 60 * 1000 * 1000 * 1000;
        max_msg_size = -1;
        storage = "file";
        discard = "old";
        num_replicas = 1;
        duplicate_window = 2 * 60 * 1000 * 1000 * 1000;
      }
    );

  # nats-server mangles absolute include paths (G12): the server config is a
  # runtime file in the state dir with relative includes only
  settingsFile = (pkgs.formats.json { }).generate "nats-settings.json" config.services.nats.settings;

  # ---- bnox-validate (D-020 §3) ----------------------------------------
  # Every allow pattern in the matrix becomes one concrete probe subject
  # (wildcards → the token _bnox_validate_). Every identity publishes every
  # probe; the broker must accept exactly where its own allows cover the
  # probe. Infrastructure subjects ($JS.*, _INBOX.*) are not probed.
  # Accepted probes land in the target thing's stream like any message —
  # things should ignore subjects carrying the _bnox_validate_ token.
  probeToken = "_bnox_validate_";
  concretize = p: lib.concatStringsSep "." (map (t: if t == "*" || t == ">" then probeToken else t) (lib.splitString "." p));
  isInfra = p: lib.hasPrefix "$JS" p || lib.hasPrefix "_INBOX" p;
  probes = lib.unique (
    map concretize (
      builtins.filter (p: !(isInfra p)) (
        lib.concatMap (i: i.publish) (builtins.attrValues identities)
      )
    )
  );
  checks = lib.concatLists (
    lib.mapAttrsToList (
      id: i:
      map (subject: {
        inherit id subject;
        expect = if lib.any (a: covers a subject) i.publish then "accept" else "reject";
      }) probes
    ) identities
  );
  validate = pkgs.writeShellApplication {
    name = "bnox-validate";
    runtimeInputs = [ natscli pkgs.coreutils ];
    text = ''
      if [ "$(id -u)" != 0 ]; then echo "bnox-validate: run as root (reads the NATS seeds)" >&2; exit 2; fi
      export NATS_URL=nats://127.0.0.1:4222
      pass=0; fail=0
      check() { # expect id subject
        if env NATS_NKEY="${stateDir}/$2.seed" nats pub "$3" "bnox-validate probe" >/dev/null 2>&1; then got=accept; else got=reject; fi
        if [ "$got" = "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $2 publish $3 — expected $1, got $got"; fi
      }
      echo "== anonymous connect must be rejected"
      if env -u NATS_NKEY nats pub "${probeToken}" x >/dev/null 2>&1; then echo "FAIL: anonymous publish accepted"; fail=$((fail+1)); else pass=$((pass+1)); fi
      echo "== ${toString (builtins.length checks)} permission checks (${toString (builtins.length (builtins.attrNames identities))} identities × ${toString (builtins.length probes)} probes)"
      ${lib.concatMapStringsSep "\n" (c: "check ${c.expect} ${lib.escapeShellArg c.id} ${lib.escapeShellArg c.subject}") checks}
      echo "bnox-validate: $pass passed, $fail failed"
      [ "$fail" = 0 ]
    '';
  };

  identityModule = {
    options = {
      publish = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      subscribe = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      readers = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Group allowed to read the seed file (0440 root:<group>); null = root only.";
      };
    };
  };

  subjectsModule = {
    options = {
      publish = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      subscribe = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
    };
  };
in
{
  options.bnox.nats = {
    identities = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule identityModule);
      default = { };
      description = "Extra host-level NATS identities (absolute subjects). Seed at /var/lib/bnox/nats/<name>.seed.";
    };
    streamMaxAgeDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
    };
    computedPermissions = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      internal = true;
      description = "The final permission matrix (identity -> {publish, subscribe}); input to bnox-validate.";
    };
  };

  # thing-level NATS options (merged into the bnox.things submodule)
  options.bnox.things = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options.nats = {
          offer = lib.mkOption {
            type = lib.types.submodule subjectsModule;
            default = { };
            description = "From .bnox: what others may ever get, relative to things.<name>.";
          };
          roles = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule subjectsModule);
            default = { };
            description = "From .bnox: named subsets of the offer, relative to things.<name>.";
          };
          grants = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
            description = "Host: <dep> = <role name | \"offer\">. The dep must be in deps.";
          };
          extra = lib.mkOption {
            type = lib.types.submodule subjectsModule;
            default = { };
            description = "Host: extra absolute subjects for this thing's identity (visible escape hatch).";
          };
        };
      }
    );
  };

  config = lib.mkMerge [
    {
      bnox.nats.computedPermissions = lib.mapAttrs (_: i: { inherit (i) publish subscribe; }) identities;
    }
    (lib.mkIf natsEnabled {
      assertions = map (m: {
        assertion = false;
        message = m;
      }) errors;

      services.nats.settings.host = lib.mkDefault "127.0.0.1";

    environment.systemPackages = [ validate ];

      systemd.services = {
        nats = {
          after = [ "bnox-nats-auth.service" ];
          requires = [ "bnox-nats-auth.service" ];
          serviceConfig.ExecStart = lib.mkForce "${pkgs.nats-server}/bin/nats-server -c ${stateDir}/nats.conf";
        };

        bnox-nats-keygen = {
          description = "bnox: NATS nkey per identity (generated once, never regenerated) + nats_seed slots";
          wantedBy = [ "multi-user.target" ];
          after = [ "systemd-tmpfiles-setup.service" ];
          path = [
            keygenPy
            pkgs.coreutils
            pkgs.diffutils
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "bnox/nats";
          }
          // (hardening.bundle {
            writablePaths = [
              stateDir
              "/var/lib/bnox/secrets"
            ];
          })
          // {
            # chown seeds to reader groups; traverse thing-owned 0750 slot dirs
            CapabilityBoundingSet = "CAP_CHOWN CAP_DAC_OVERRIDE";
          };
          script = ''
            set -euo pipefail
            umask 077
            for id in ${lib.concatStringsSep " " (builtins.attrNames identities)}; do
              if [ ! -f "${stateDir}/$id.seed" ]; then
                python3 ${nkeyPy} | head -n1 > "${stateDir}/$id.seed.tmp"
                mv "${stateDir}/$id.seed.tmp" "${stateDir}/$id.seed"
                echo "generated nkey for $id"
              fi
              chown root:root "${stateDir}/$id.seed"
              chmod 0400 "${stateDir}/$id.seed"
            done
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (id: i: ''
                chown root:${i.readers} "${seedPath id}"
                chmod 0440 "${seedPath id}"
              '') (lib.filterAttrs (_: i: i.readers != null) identities)
            )}
            # the implied nats_seed slot (D-016): written only on change, so the
            # slot's path unit does not restart things on every boot
            ${lib.concatMapStringsSep "\n" (t: ''
              tmp=$(mktemp)
              printf 'NATS_SEED=%s\n' "$(cat ${seedPath t.name})" > "$tmp"
              if ! cmp -s "$tmp" /var/lib/bnox/secrets/${t.name}/nats_seed; then
                install -m 0600 -o root -g root "$tmp" /var/lib/bnox/secrets/${t.name}/nats_seed
                echo "wrote nats_seed slot for ${t.name}"
              fi
              rm -f "$tmp"
            '') natsThings}
          '';
        };

        bnox-nats-auth = {
          description = "bnox: assemble NATS authorization (computed permissions + runtime nkeys)";
          wantedBy = [ "multi-user.target" ];
          requires = [ "bnox-nats-keygen.service" ];
          after = [ "bnox-nats-keygen.service" ];
          restartTriggers = [
            permissionsJson
            settingsFile
          ];
          path = [
            keygenPy
            pkgs.jq
            pkgs.coreutils
            pkgs.systemd
          ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            StateDirectory = "bnox/nats";
          }
          // (hardening.bundle { writablePaths = [ stateDir ]; })
          // {
            # systemctl try-restart talks to pid 1 over a unix socket
            RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX";
            CapabilityBoundingSet = "CAP_CHOWN";
          };
          script = ''
            set -euo pipefail
            dir=${stateDir}
            jqargs=()
            for id in $(jq -r 'keys[]' ${permissionsJson}); do
              jqargs+=(--arg "$id" "$(python3 ${nkeyPy} "$dir/$id.seed")")
            done
            jq -n "''${jqargs[@]}" --slurpfile perms ${permissionsJson} '
              {authorization: {users: [ ($perms[0] | to_entries[])
                | {nkey: $ARGS.named[.key],
                   permissions: {publish: {allow: .value.publish},
                                 subscribe: {allow: .value.subscribe}}} ]}}
            ' > "$dir/auth.json.new"
            chown root:nats "$dir/auth.json.new"
            chmod 0640 "$dir/auth.json.new"

            ln -sfn "${settingsFile}" "$dir/settings.json"
            printf 'include "settings.json"\ninclude "auth.json"\n' > "$dir/nats.conf"
            chmod 0644 "$dir/nats.conf"

            # validate the full config with the new auth before it can reach a restart (G9)
            printf 'include "settings.json"\ninclude "auth.json.new"\n' > "$dir/nats.conf.check"
            ${pkgs.nats-server}/bin/nats-server -c "$dir/nats.conf.check" -t
            rm -f "$dir/nats.conf.check"
            mv "$dir/auth.json.new" "$dir/auth.json"

            # restart nats iff auth or settings changed since the last applied state
            # (a rebuild may report this restart as a failed unit — G59)
            newstate="settings=$(readlink "$dir/settings.json") auth=$(sha256sum "$dir/auth.json" | cut -d' ' -f1)"
            oldstate=$(cat "$dir/.applied" 2>/dev/null || true)
            if [ "$newstate" != "$oldstate" ]; then
              echo "auth state changed, restarting nats"
              systemctl try-restart nats.service
              printf '%s' "$newstate" > "$dir/.applied"
            fi
          '';
        };

        bnox-nats-streams = lib.mkIf (config.services.nats.jetstream && natsThings != [ ]) {
          description = "bnox: one JetStream stream per NATS thing (things-<name>)";
          wantedBy = [ "multi-user.target" ];
          after = [ "nats.service" ];
          requires = [ "nats.service" ];
          environment.NATS_NKEY = seedPath "ops";
          path = [ natscli ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          }
          // (hardening.bundle {
            writablePaths = [ ];
            ipAddressAllow = [ "127.0.0.1" ];
          });
          script = ''
            set -uo pipefail
            ensure() {
              for i in $(seq 1 15); do
                if nats stream info "$1" >/dev/null 2>&1; then
                  nats stream update "$1" --config "$2" --force >/dev/null 2>&1 && return 0
                elif nats stream add "$1" --config "$2" --defaults >/dev/null 2>&1; then
                  return 0
                fi
                sleep 1
              done
              echo "stream $1 could not be created/updated" >&2
              return 1
            }
            rc=0
            ${lib.concatMapStringsSep "\n" (
              t: "ensure ${streamName t.name} ${streamConfig t} || rc=1"
            ) natsThings}
            exit $rc
          '';
        };
      };
    })
  ];
}
