{ lib, config, ... }:
let
  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  httpApiComponents = lib.concatMap (
    thing:
    lib.mapAttrsToList (
      compName: comp: {
        thing = thing.name;
        component = compName;
        inherit (comp) domain ingressPort;
      }
    ) (
      lib.filterAttrs (
        _: comp:
        comp.enable
        && comp.shape == "http-api"
        && comp.domain != null
        && comp.ingressPort != null
      ) thing.components
    )
  ) enabledThingsList;
in
{
  config.services.caddy.virtualHosts = builtins.listToAttrs (
    map (
      comp:
      lib.nameValuePair comp.domain {
        extraConfig = ''
          reverse_proxy 127.0.0.1:${toString comp.ingressPort}
        '';
      }
    ) httpApiComponents
  );
}
