{ lib, config, pkgs, ... }:
let
  hardening = import ../hardening.nix { inherit lib; };

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  containerBackend = config.virtualisation.oci-containers.backend;

  slirp = comp: comp.nats || comp.egress.mode == "proxy";
  proxyEnv = url: {
    HTTPS_PROXY = url;
    HTTP_PROXY = url;
    https_proxy = url;
    http_proxy = url;
    NO_PROXY = "10.0.2.2,127.0.0.1,localhost";
    no_proxy = "10.0.2.2,127.0.0.1,localhost";
  };

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
        nats = thing.hardening.network.nats;
        egress = config.bnox.egress.resolved.${thing.name}; # D-019
        env = thing.env;
      }
    ) (lib.filterAttrs (_: comp: comp.enable && comp.runtime == "container" && comp.shape != "static-site") thing.components)
  ) enabledThingsList;

  containers = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.containerName {
        image = "${comp.containerName}:current";
        environmentFiles = map (slot: "/var/lib/bnox/secrets/${comp.thing}/${slot}") comp.allSlots;
        environment =
          comp.env
          // lib.optionalAttrs comp.nats { NATS_URL = "nats://10.0.2.2:4222"; }
          // lib.optionalAttrs (comp.egress.mode == "proxy") (proxyEnv "http://10.0.2.2:${toString comp.egress.port}");
        # the host loopback (broker, egress proxy) is only reachable via slirp (G14)
        extraOptions = lib.optional (slirp comp) "--network=slirp4netns:allow_host_loopback=true";
        ports = lib.optional (comp.ingressPort != null) "127.0.0.1:${toString comp.ingressPort}:${toString comp.ingressPort}";
      }
    ) containerComponents
  );

  serviceHardening = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.serviceName {
        after =
          lib.optional comp.nats "bnox-nats-keygen.service"
          ++ lib.optional (comp.egress.mode == "proxy") "bnox-egress-${comp.thing}.service";
        serviceConfig = hardening.runnerBundle {
          # D-019: nothing unless granted; both addresses for slirp (G15)
          ipAddressAllow =
            lib.optional (comp.egress.mode == "direct") "any"
            ++ lib.optionals (slirp comp) [
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

  natsContainerThings = lib.any slirp containerComponents;
in
{
  config.virtualisation.oci-containers.containers = containers;

  config.systemd.services = serviceHardening;

  config.bnox.secrets.fileSlots = fileSlots;

  config.virtualisation.podman.extraPackages = lib.mkIf (
    containerBackend == "podman" && natsContainerThings
  ) [ pkgs.slirp4netns ];
}
