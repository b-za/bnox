# D-019 §2 — egress, locked by default. A thing gets no outbound network
# unless the host grants it:
#   .bnox/thing.nix   egress = [ "googleapis.com" … ] | "any";   (what it needs)
#   host config       bnox.things.<n>.egress.grant = [ … ] | "any";  (ceiling)
# Final = the overlap. Both "any" → direct access. A domain list → a
# per-thing tinyproxy (one instance per thing, its own port, only its domains)
# and HTTPS_PROXY in the thing's environment. Nothing → loopback only.
# Mechanics from bnox-bg's agenthub proxy (tinyproxy, FilterDefaultDeny).
{ lib, config, pkgs, ... }:
let
  hardening = import ./hardening.nix { inherit lib; };
  cfg = config.bnox.egress;

  needType = lib.types.either (lib.types.enum [ "any" ]) (lib.types.listOf lib.types.str);

  enabledThingsList = lib.mapAttrsToList (n: t: t // { name = n; }) (
    lib.filterAttrs (_: t: t.enable) config.bnox.things
  );

  # a granted entry covers a domain and its subdomains
  grantCovers = h: d: d == h || lib.hasSuffix ".${h}" d;

  resolveThing =
    t:
    let
      needs = t.egress.needs;
      grant = t.egress.grant;
      domains =
        if needs == "any" && grant == "any" then
          [ ]
        else if needs == "any" then
          grant
        else if grant == "any" then
          needs
        else
          builtins.filter (d: lib.any (h: grantCovers h d) grant) needs;
      ungranted =
        if needs == "any" || grant == "any" then
          [ ]
        else
          builtins.filter (d: !(lib.any (h: grantCovers h d) grant)) needs;
      mode =
        if needs == "any" && grant == "any" then
          "direct"
        else if domains != [ ] then
          "proxy"
        else
          "none";
    in
    {
      inherit mode domains ungranted;
    };

  resolvedNoPort = builtins.listToAttrs (map (t: lib.nameValuePair t.name (resolveThing t)) enabledThingsList);
  proxied = builtins.sort builtins.lessThan (
    builtins.attrNames (lib.filterAttrs (_: r: r.mode == "proxy") resolvedNoPort)
  );
  portOf = name: cfg.basePort + lib.lists.findFirstIndex (n: n == name) 0 proxied;

  resolved = lib.mapAttrs (
    name: r: r // { port = if r.mode == "proxy" then portOf name else null; }
  ) resolvedNoPort;

  escapeRe = lib.replaceStrings [ "." ] [ "\\." ];
  filterFile =
    name: domains:
    pkgs.writeText "bnox-egress-${name}.filter" (
      lib.concatMapStrings (d: "(^|\\.)${escapeRe d}$\n") domains
    );
  proxyConf =
    name: r:
    pkgs.writeText "bnox-egress-${name}.conf" ''
      Listen 127.0.0.1
      Port ${toString r.port}
      Timeout 600
      MaxClients 50
      Allow 127.0.0.1
      ConnectPort 443
      Filter "${filterFile name r.domains}"
      FilterType ere
      FilterURLs Off
      FilterDefaultDeny Yes
      LogLevel Connect
    '';

  # users allowed out on 80/443 under hostLockdown
  directUsers = lib.filter (n: (resolved.${n}).mode == "direct") (
    map (t: t.name) (builtins.filter (t: lib.any (c: c.enable && c.runtime == "host-install") (builtins.attrValues t.components)) enabledThingsList)
  );
  lockdownUsers =
    lib.optional (proxied != [ ]) "bnox-egress"
    ++ lib.optional config.services.caddy.enable config.services.caddy.user
    ++ directUsers
    ++ cfg.hostLockdownAllowUsers;
  # Containers are not matched here: bridge traffic is forwarded (not output)
  # and slirp4netns runs as root; their per-unit IPAddressAllow scopes them.
  # rules are rendered at unit start with numeric uids (user names with "-"
  # are not valid bare nft identifiers; uids are assigned at activation)
  lockdownScript = pkgs.writeShellScript "bnox-egress-lockdown" ''
    set -euo pipefail
    allow=""
    for u in ${lib.escapeShellArgs lockdownUsers}; do
      uid=$(${pkgs.coreutils}/bin/id -u "$u")
      allow="$allow
        meta skuid $uid tcp dport { 80, 443 } accept
        meta skuid $uid udp dport 443 accept"
    done
    ${pkgs.nftables}/bin/nft delete table inet bnox_egress 2>/dev/null || true
    ${pkgs.nftables}/bin/nft -f - <<EOF
    table inet bnox_egress {
      chain output {
        type filter hook output priority filter; policy accept;
        oifname "lo" accept
        ct state established,related accept
        meta skuid 0 accept
        $allow
        tcp dport { 80, 443 } drop
        udp dport { 80, 443 } drop
      }
    }
    EOF
  '';

  egressModule = {
    options.egress = {
      needs = lib.mkOption {
        type = needType;
        default = [ ];
        description = "From .bnox `egress`: domains the thing needs, or \"any\".";
      };
      grant = lib.mkOption {
        type = needType;
        default = [ ];
        description = "Host: domains granted (a domain covers its subdomains), or \"any\". Nothing until granted.";
      };
    };
  };
in
{
  options.bnox.things = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule egressModule); };

  options.bnox.egress = {
    basePort = lib.mkOption {
      type = lib.types.port;
      default = 18100;
      description = "First port of the per-thing proxies (127.0.0.1, one port per proxied thing, sorted by name).";
    };
    hostLockdown = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Opt-in host-wide web egress lockdown (owner-based nftables output rules,
        from bnox-bg agenthub): only root, the egress proxies, Caddy, things
        granted direct "any", and hostLockdownAllowUsers may connect out on
        ports 80/443 (TCP, and UDP for QUIC). Catches what per-unit rules
        cannot: stray processes, interactive users, hand-written units.
        Fail-open by construction (policy accept + explicit drops); never
        touches input, loopback or other ports.
      '';
    };
    hostLockdownAllowUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra users allowed out on 80/443 under hostLockdown (e.g. your login user).";
    };
    resolved = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      readOnly = true;
      internal = true;
      description = "thing -> { mode = direct|proxy|none; domains; port; ungranted; } — read by the runtimes.";
    };
  };

  config = {
    bnox.egress.resolved = resolved;

    users.users.bnox-egress = lib.mkIf (proxied != [ ]) {
      isSystemUser = true;
      group = "bnox-egress";
    };
    users.groups.bnox-egress = lib.mkIf (proxied != [ ]) { };

    warnings = lib.concatLists (
      lib.mapAttrsToList (
        name: r:
        lib.optional (r.ungranted != [ ])
          "bnox: thing \"${name}\" needs egress to ${builtins.toJSON r.ungranted}, not granted by the host (blocked)"
      ) resolved
    );

    assertions = map (t: {
      assertion = !t.hardening.network.outboundHTTPS;
      message = "bnox: thing \"${t.name}\" sets hardening.network.outboundHTTPS — replaced in 0.4 by egress (.bnox `egress` + host `egress.grant`, D-019)";
    }) enabledThingsList;

    systemd.services = lib.optionalAttrs cfg.hostLockdown {
      bnox-egress-lockdown = {
        description = "bnox: host-wide web egress lockdown (owner-based nftables output rules)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        restartTriggers = [ lockdownScript ];
        serviceConfig =
          {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lockdownScript;
            ExecStop = "${pkgs.nftables}/bin/nft delete table inet bnox_egress";
          }
          // (hardening.bundle { writablePaths = [ ]; })
          // {
            # nft talks nfnetlink; loading rules needs CAP_NET_ADMIN
            RestrictAddressFamilies = "AF_NETLINK AF_UNIX";
            CapabilityBoundingSet = "CAP_NET_ADMIN";
          };
      };
    } // builtins.listToAttrs (
      map (
        name:
        let
          r = resolved.${name};
        in
        lib.nameValuePair "bnox-egress-${name}" {
          description = "bnox: egress proxy for ${name} (${lib.concatStringsSep ", " r.domains})";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig =
            {
              ExecStart = "${pkgs.tinyproxy}/bin/tinyproxy -d -c ${proxyConf name r}";
              # a static user: the hostLockdown rules match it by owner
              User = "bnox-egress";
              Group = "bnox-egress";
              Restart = "always";
              RestartSec = 2;
            }
            // (hardening.bundle {
              writablePaths = [ ];
              ipAddressAllow = [ "any" ];
            })
            // {
              # name resolution may go through a unix socket (nscd/resolved)
              RestrictAddressFamilies = "AF_INET AF_INET6 AF_UNIX";
            };
        }
      ) proxied
    );
  };
}
