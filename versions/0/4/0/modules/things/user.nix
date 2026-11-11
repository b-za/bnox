{ lib, config, pkgs, ... }:
let
  enabledThings = lib.filterAttrs (_: thing: thing.enable) config.bnox.things;
in
{
  config.users.users = lib.mapAttrs' (
    name: thing:
    lib.nameValuePair name ({
      isSystemUser = true;
      home = "/var/lib/${name}";
      createHome = true;
      group = name;
      # D-020: bnox thing users default to nologin; `shell = true` gives bash
    } // lib.optionalAttrs thing.shell { shell = pkgs.bashInteractive; })
  ) enabledThings;

  config.programs.nix-ld.enable = lib.mkIf (lib.any (t: t.nixLd) (builtins.attrValues enabledThings)) true;

  config.users.groups = lib.mapAttrs' (
    name: _:
    lib.nameValuePair name { }
  ) enabledThings;
}
