{ lib, config, ... }:
let
  hardening = import ../hardening.nix { inherit lib; };

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  hostInstallComponents = lib.concatMap (
    thing:
    lib.mapAttrsToList (
      compName: comp: {
        thing = thing.name;
        component = compName;
        serviceName = "${thing.name}-${compName}";
        user = thing.name;
        inherit (comp) execStart;
        nats = thing.hardening.network.nats;
        env = thing.env;
        egress = config.bnox.egress.resolved.${thing.name}; # D-019
        allSlots = thing.secrets ++ comp.secrets ++ lib.optional thing.hardening.network.nats "nats_seed";
      }
    ) (lib.filterAttrs (_: comp: comp.enable && comp.runtime == "host-install") thing.components)
  ) enabledThingsList;

  services = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.serviceName {
        wantedBy = [ "multi-user.target" ];
        after =
          [ "network.target" ]
          ++ lib.optional comp.nats "bnox-nats-keygen.service"
          ++ lib.optional (comp.egress.mode == "proxy") "bnox-egress-${comp.thing}.service";
        serviceConfig = {
          ExecStart = comp.execStart;
          User = comp.user;
          Group = comp.user;
          WorkingDirectory = "/var/lib/${comp.thing}";
          Restart = "on-failure";
          RestartSec = 5;
          Environment =
            [ "HOME=/var/lib/${comp.thing}" ]
            ++ lib.mapAttrsToList (k: v: "${k}=${v}") comp.env
            ++ lib.optionals (comp.egress.mode == "proxy") (
              let
                url = "http://127.0.0.1:${toString comp.egress.port}";
              in
              [
                "HTTPS_PROXY=${url}"
                "HTTP_PROXY=${url}"
                "https_proxy=${url}"
                "http_proxy=${url}"
                "NO_PROXY=127.0.0.1,localhost"
                "no_proxy=127.0.0.1,localhost"
              ]
            )
            ++ lib.optionals comp.nats [
            "NATS_URL=nats://127.0.0.1:4222"
            # D-018: natscli wants a seed *file* (G2); readable by the thing's group
            "NATS_NKEY=/var/lib/bnox/nats/${comp.thing}.seed"
          ];
          # D-017 §3 (G28): slots load as env files, as in the container
          # runtime. PID 1 reads them, so root-only 0600 slot files work.
          # nats_seed is required; other slots may land after first boot
          # ("-": start without, the slot's path unit restarts on arrival).
          EnvironmentFile = map (
            slot: (if slot == "nats_seed" then "" else "-") + "/var/lib/bnox/secrets/${comp.thing}/${slot}"
          ) comp.allSlots;
        } // (hardening.bundle {
          # D-017 §3: the secrets dir is no longer writable — a thing must not
          # be able to overwrite its own credentials
          writablePaths = [
            "/var/lib/${comp.thing}"
          ];
          # D-019: loopback only (broker, its egress proxy) unless granted "any"
          ipAddressAllow = if comp.egress.mode == "direct" then [ "any" ] else [ "127.0.0.0/8" "::1" ];
        });
      }
    ) hostInstallComponents
  );

  slotServicePairs = lib.concatMap (
    comp:
    map (
      slot: {
        slot = "${comp.thing}/${slot}";
        inherit (comp) thing serviceName;
      }
    ) comp.allSlots
  ) hostInstallComponents;

  slotGroups = lib.groupBy (p: p.slot) slotServicePairs;

  fileSlots = lib.mapAttrs (
    _key: pairs: {
      owner = (builtins.head pairs).thing;
      group = (builtins.head pairs).thing;
      restartUnits = lib.unique (map (p: p.serviceName) pairs);
    }
  ) slotGroups;
in
{
  config.systemd.services = services;

  config.bnox.secrets.fileSlots = fileSlots;

  config.assertions = map (
    comp: {
      assertion = comp.execStart != null;
      message = "bnox: host-install component \"${comp.thing}.${comp.component}\" requires execStart";
    }
  ) hostInstallComponents;
}
