{ lib, config, ... }:
let
  enabledThings = lib.filterAttrs (_: thing: thing.enable) config.bnox.things;
in
{
  config.users.users = lib.mapAttrs' (
    name: _:
    lib.nameValuePair name {
      isSystemUser = true;
      home = "/var/lib/${name}";
      createHome = true;
      group = name;
    }
  ) enabledThings;

  config.users.groups = lib.mapAttrs' (
    name: _:
    lib.nameValuePair name { }
  ) enabledThings;
}
