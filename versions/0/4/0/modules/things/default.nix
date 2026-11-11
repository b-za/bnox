{ lib, config, ... }:
let
  hardening = import ./hardening.nix { inherit lib; };
  loader = import ./loader.nix { inherit lib; };

  componentSubmodule =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        shape = lib.mkOption {
          type = lib.types.enum [
            "static-site"
            "webapp"
            "http-api"
            "nats-api"
            "daemon"
          ];
        };
        runtime = lib.mkOption {
          type = lib.types.enum [
            "container"
            "host-install"
          ];
          default = "container";
        };
        domain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        # D-019 §3: host grants the inbound level; the thing caps it
        inbound = lib.mkOption {
          type = lib.types.enum [ "internal" "tailnet" "public" ];
          default = "internal";
        };
        exposure = lib.mkOption {
          type = lib.types.enum [ "internal" "tailnet" "public" ];
          default = "public";
          description = "From .bnox: the most exposure this component accepts.";
        };
        ingressPort = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
        };
        natsSubject = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        secrets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        execStart = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    };

  thingOptionsModule =
    { name, config, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
        };
        source = lib.mkOption {
          type = lib.types.str;
        };
        branch = lib.mkOption {
          type = lib.types.str;
          default = "main";
        };
        deps = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        secrets = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
        };
        # D-019: plain (non-secret) config for every component of the thing.
        # .bnox/thing.nix `env` gives defaults; host config wins per key.
        env = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
        components = lib.mkOption {
          type = lib.types.attrsOf (lib.types.submoduleWith {
            modules = [ componentSubmodule loader.componentSubmodule ];
            specialArgs = {
              thingSource = config.source;
              thingName = name;
              thingEnable = config.enable;
            };
          });
          default = { };
        };
      };
    };

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  enabledThingNames = map (thing: thing.name) enabledThingsList;

  enabledComponents = lib.concatMap (
    thing:
    lib.mapAttrsToList (
      compName: comp: comp // {
        thing = thing.name;
        component = compName;
      }
    ) (lib.filterAttrs (_: comp: comp.enable) thing.components)
  ) enabledThingsList;

  depErrors = lib.concatMap (
    thing:
    lib.concatMap (
      dep:
      lib.optional (!builtins.elem dep enabledThingNames)
        "bnox: thing \"${thing.name}\" declares dependency \"${dep}\", but no enabled thing named \"${dep}\" exists"
    ) thing.deps
  ) enabledThingsList;

  portUsers = builtins.filter (comp: comp.ingressPort != null) enabledComponents;
  portGroups = lib.groupBy (comp: toString comp.ingressPort) portUsers;
  portCollisions = lib.concatMap (
    port:
    let users = portGroups.${port}; in
    lib.optional (builtins.length users > 1)
      (
        "bnox: ingressPort ${port} declared by multiple enabled components: "
        + lib.concatMapStringsSep ", " (u: "${u.thing}.${u.component}") users
      )
  ) (builtins.attrNames portGroups);

  subjectUsers = builtins.filter (comp: comp.natsSubject != null) enabledComponents;
  subjectGroups = lib.groupBy (comp: comp.natsSubject) subjectUsers;
  subjectCollisions = lib.concatMap (
    subject:
    let users = subjectGroups.${subject}; in
    lib.optional (builtins.length users > 1)
      (
        "bnox: natsSubject \"${subject}\" declared by multiple enabled components: "
        + lib.concatMapStringsSep ", " (u: "${u.thing}.${u.component}") users
      )
  ) (builtins.attrNames subjectGroups);
in
{
  imports = [
    ./user.nix
    ./shapes/default.nix
    ./runtimes/default.nix
    ./egress.nix
    ./inbound.nix
    loader.topLevel
  ];

  options.bnox.things = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule [
        thingOptionsModule
        hardening.overrideModule
        loader.thingSubmodule
      ]
    );
    default = { };
  };

  config.assertions = map (
    msg: {
      assertion = false;
      message = msg;
    }
  ) (depErrors ++ portCollisions ++ subjectCollisions);
}
