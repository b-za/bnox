{ lib, config, ... }:
let
  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  staticSiteComponents = lib.concatMap (
    thing:
    lib.mapAttrsToList (
      compName: comp: {
        inherit (thing) name source;
        component = compName;
        inherit (comp) domain;
      }
    ) (lib.filterAttrs (_: comp: comp.enable && comp.shape == "static-site" && comp.domain != null) thing.components)
  ) enabledThingsList;
in
{
  config.bnox.platform.staticSites = builtins.listToAttrs (
    map (
      comp: lib.nameValuePair comp.domain "${comp.source}/${comp.component}"
    ) staticSiteComponents
  );
}
