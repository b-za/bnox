# D-019 §3 — inbound, the mirror of egress. Locked by default.
#   .bnox/<component>.nix  ingressPort = 8080; exposure = "tailnet";  (the most it accepts; default public)
#   host config            components.<c> = { domain = "…"; inbound = "public"; };  (default internal)
# Final level = the more restrictive of the two. internal: no vhost (reachable
# on the host's loopback only). tailnet: Caddy vhost that drops any client
# outside the tailnet. public: plain Caddy vhost. Works for every runtime;
# static sites serve files, everything else is reverse-proxied to
# 127.0.0.1:<ingressPort>. Login protection stays the app's job.
{ lib, config, ... }:
let
  rank = {
    internal = 0;
    tailnet = 1;
    public = 2;
  };
  lower = a: b: if rank.${a} <= rank.${b} then a else b;

  enabledThingsList = lib.mapAttrsToList (n: t: t // { name = n; }) (
    lib.filterAttrs (_: t: t.enable) config.bnox.things
  );

  components = lib.concatMap (
    t:
    lib.mapAttrsToList (c: comp: comp // {
      thing = t.name;
      component = c;
      inherit (t) source;
      level = lower comp.inbound comp.exposure;
    }) (lib.filterAttrs (_: comp: comp.enable) t.components)
  ) enabledThingsList;

  exposed = builtins.filter (c: c.level != "internal") components;
  id = c: "${c.thing}.${c.component}";

  # Tailscale CGNAT range + its IPv6 ULA prefix. ACME HTTP challenges are
  # answered by Caddy ahead of this handler chain.
  tailnetGuard = ''
    @outside_tailnet not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
    abort @outside_tailnet
  '';

  vhostBody =
    c:
    lib.optionalString (c.level == "tailnet") tailnetGuard
    + (
      if c.shape == "static-site" then
        ''
          root * ${c.source}/${c.component}
          file_server
        ''
      else
        ''
          reverse_proxy 127.0.0.1:${toString c.ingressPort}
        ''
    );
in
{
  config = {
    services.caddy.virtualHosts = builtins.listToAttrs (
      map (c: lib.nameValuePair c.domain { extraConfig = vhostBody c; }) (
        builtins.filter (c: c.domain != null && (c.shape == "static-site" || c.ingressPort != null)) exposed
      )
    );

    assertions =
      map (c: {
        assertion = c.domain != null;
        message = "bnox: ${id c} is exposed (${c.level}) but has no domain";
      }) exposed
      ++ map (c: {
        assertion = c.shape == "static-site" || c.ingressPort != null;
        message = "bnox: ${id c} is exposed (${c.level}) but its .bnox declares no ingressPort";
      }) exposed;

    warnings =
      map (c: "bnox: ${id c} has a domain but is not exposed (inbound ${c.inbound}, the thing accepts at most ${c.exposure}) — set components.${c.component}.inbound")
        (builtins.filter (c: c.domain != null && c.level == "internal") components);
  };
}
