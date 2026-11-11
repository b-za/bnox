{ lib }:
let
  readManifest =
    source:
    let p = "${source}/.bnox/thing.nix";
    in if builtins.pathExists p then import p else { };

  thingSubmodule =
    { name, config, ... }:
    let
      manifest = if config.enable then readManifest config.source else { };
    in
    {
      config = lib.mkIf config.enable {
        deps = lib.mkDefault (manifest.deps or [ ]);
        secrets = lib.mkDefault (manifest.secrets or [ ]);
        env = lib.mapAttrs (_: lib.mkDefault) (manifest.env or { });
        egress.needs = lib.mkDefault (manifest.egress or [ ]); # D-019
        shell = lib.mkDefault (manifest.shell or false); # D-020
        nixLd = lib.mkDefault (manifest.nixLd or false);
        branch = lib.mkDefault (manifest.branch or "main");
        # D-018: nats = true, or { offer = {publish, subscribe}; roles = { <r> = {…}; }; }
        hardening.network.nats = lib.mkDefault (
          let n = manifest.nats or false; in if builtins.isAttrs n then true else n
        );
        nats.offer = lib.mkDefault ((if builtins.isAttrs (manifest.nats or false) then manifest.nats else { }).offer or { });
        nats.roles = lib.mkDefault ((if builtins.isAttrs (manifest.nats or false) then manifest.nats else { }).roles or { });
      };
    };

  componentSubmodule =
    { name, thingSource, thingEnable, ... }:
    let
      manifest = if thingEnable then readManifest thingSource else { };
      manifestComponents = manifest.components or [ ];
      inManifest = builtins.elem name manifestComponents;
      compPath = "${thingSource}/.bnox/${name}.nix";
      hasFile = builtins.pathExists compPath;
      loadable = thingEnable && inManifest && hasFile;
      comp = if hasFile then import compPath else { };
    in
    {
      config = lib.mkIf loadable {
        shape = lib.mkDefault comp.shape;
        runtime = lib.mkDefault (comp.runtime or "container");
        ingressPort = lib.mkDefault (comp.ingressPort or null);
        natsSubject = lib.mkDefault (comp.natsSubject or null);
        secrets = lib.mkDefault (comp.secrets or [ ]);
        execStart = lib.mkDefault (comp.execStart or null);
        exposure = lib.mkDefault (comp.exposure or "public"); # D-019
      };
    };

  topLevel =
    { config, ... }:
    let
      enabledThings = lib.mapAttrsToList (n: v: { name = n; value = v; })
        (lib.filterAttrs (_: t: t.enable) config.bnox.things);

      messages = lib.concatMap (
        thing:
        let
          thingName = thing.name;
          source = thing.value.source;
          manifestPath = "${source}/.bnox/thing.nix";
          hasManifest = builtins.pathExists manifestPath;
          manifest = if hasManifest then import manifestPath else { };
          manifestComponents = manifest.components or [ ];
          hostComponents = builtins.attrNames thing.value.components;

          manifestMsg = lib.optional (!hasManifest)
            "bnox: thing \"${thingName}\" is enabled but has no .bnox/thing.nix at \"${source}/.bnox/\" (expected the thing-intrinsic manifest per Q9.5)";

          compMsgs = lib.concatMap (
            compName:
            if !builtins.elem compName manifestComponents then
              [ "bnox: host declares component \"${compName}\" on thing \"${thingName}\", but \"${compName}\" is not in the thing's .bnox manifest (${builtins.toJSON manifestComponents})" ]
            else if !builtins.pathExists "${source}/.bnox/${compName}.nix" then
              [ "bnox: thing \"${thingName}\" manifest lists component \"${compName}\" but \"${source}/.bnox/${compName}.nix\" is missing" ]
            else
              [ ]
          ) hostComponents;
        in
        manifestMsg ++ compMsgs
      ) enabledThings;
    in
    {
      config.assertions = map (msg: { assertion = false; message = msg; }) messages;
    };
in
{
  inherit topLevel thingSubmodule componentSubmodule;
}
