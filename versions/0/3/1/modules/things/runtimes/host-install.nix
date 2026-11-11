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
        allSlots = thing.secrets ++ comp.secrets ++ lib.optional thing.hardening.network.nats "nats_seed";
      }
    ) (lib.filterAttrs (_: comp: comp.enable && comp.runtime == "host-install") thing.components)
  ) enabledThingsList;

  services = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.serviceName {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = comp.execStart;
          User = comp.user;
          Group = comp.user;
          WorkingDirectory = "/var/lib/${comp.thing}";
          Restart = "on-failure";
          RestartSec = 5;
          Environment = [ "HOME=/var/lib/${comp.thing}" ] ++ lib.optional comp.nats "NATS_URL=nats://127.0.0.1:4222";
        } // (hardening.bundle {
          writablePaths = [
            "/var/lib/${comp.thing}"
            "/var/lib/bnox/secrets/${comp.thing}"
          ];
          ipAddressAllow = [ "any" ];
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
