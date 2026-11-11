{ lib, config, pkgs, ... }:
let
  hardening = import ../hardening.nix { inherit lib; };

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  containerBackend = config.virtualisation.oci-containers.backend;

  containerComponents = lib.concatMap (
    thing:
    lib.mapAttrsToList (
      compName: comp: {
        thing = thing.name;
        component = compName;
        containerName = "${thing.name}-${compName}";
        serviceName = "${containerBackend}-${thing.name}-${compName}";
        user = thing.name;
        inherit (comp) ingressPort;
        allSlots = thing.secrets ++ comp.secrets ++ lib.optional thing.hardening.network.nats "nats_seed";
        outboundHTTPS = thing.hardening.network.outboundHTTPS;
        nats = thing.hardening.network.nats;
      }
    ) (lib.filterAttrs (_: comp: comp.enable && comp.runtime == "container" && comp.shape != "static-site") thing.components)
  ) enabledThingsList;

  containers = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.containerName {
        image = "${comp.containerName}:current";
        environmentFiles = map (slot: "/var/lib/bnox/secrets/${comp.thing}/${slot}") comp.allSlots;
        environment = lib.optionalAttrs comp.nats { NATS_URL = "nats://10.0.2.2:4222"; };
        extraOptions = lib.optional comp.nats "--network=slirp4netns:allow_host_loopback=true";
        ports = lib.optional (comp.ingressPort != null) "127.0.0.1:${toString comp.ingressPort}:${toString comp.ingressPort}";
      }
    ) containerComponents
  );

  serviceHardening = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.serviceName {
        after = lib.optional comp.nats "bnox-nats-keygen.service";
        serviceConfig = hardening.runnerBundle {
          ipAddressAllow =
            lib.optional comp.outboundHTTPS "any"
            ++ lib.optionals comp.nats [
              "10.0.2.2"
              "127.0.0.1"
            ];
        };
      }
    ) containerComponents
  );

  slotServicePairs = lib.concatMap (
    comp:
    map (
      slot: {
        slot = "${comp.thing}/${slot}";
        inherit (comp) thing serviceName;
      }
    ) comp.allSlots
  ) containerComponents;

  slotGroups = lib.groupBy (p: p.slot) slotServicePairs;

  fileSlots = lib.mapAttrs (
    _key: pairs: {
      owner = (builtins.head pairs).thing;
      group = (builtins.head pairs).thing;
      restartUnits = lib.unique (map (p: p.serviceName) pairs);
    }
  ) slotGroups;

  natsContainerThings = lib.any (
    comp: comp.nats
  ) containerComponents;
in
{
  config.virtualisation.oci-containers.containers = containers;

  config.systemd.services = serviceHardening;

  config.bnox.secrets.fileSlots = fileSlots;

  config.virtualisation.podman.extraPackages = lib.mkIf (
    containerBackend == "podman" && natsContainerThings
  ) [ pkgs.slirp4netns ];
}
