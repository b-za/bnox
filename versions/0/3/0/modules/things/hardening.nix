{ lib }:
{
  bundle =
    { writablePaths, ipAddressAllow ? [ ] }:
    {
      ProtectSystem = "strict";
      ProtectHome = "true";
      ReadWritePaths = lib.concatStringsSep " " writablePaths;
      PrivateTmp = "true";
      PrivateDevices = "true";
      NoNewPrivileges = "true";
      CapabilityBoundingSet = "";
      SystemCallFilter = "@system-service";
      RestrictAddressFamilies = "AF_INET AF_INET6";
      ProtectKernelTunables = "true";
      ProtectKernelModules = "true";
      ProtectKernelLogs = "true";
      ProtectControlGroups = "true";
      ProtectClock = "true";
      ProtectHostname = "true";
      ProtectProc = "invisible";
      ProcSubset = "pid";
      IPAddressDeny = "any";
      IPAddressAllow = lib.concatStringsSep " " ipAddressAllow;
    };

  runnerBundle =
    { ipAddressAllow ? [ ] }:
    {
      ProtectSystem = "strict";
      ProtectHome = "read-only";
      ReadWritePaths = "/var/lib/containers /var/cache/containers";
      PrivateTmp = "true";
      RestrictAddressFamilies = "AF_UNIX AF_INET AF_INET6 AF_NETLINK";
      ProtectKernelModules = "true";
      ProtectKernelLogs = "true";
      ProtectClock = "true";
      ProtectProc = "invisible";
      IPAddressDeny = "any";
      IPAddressAllow = lib.concatStringsSep " " ipAddressAllow;
    };

  overrideModule =
    { name, ... }:
    {
      options.hardening = lib.mkOption {
        type = lib.types.submodule {
          options.network = lib.mkOption {
            type = lib.types.submodule {
              options = {
                outboundHTTPS = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
                nats = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
            };
            default = { };
          };
        };
        default = { };
      };
    };
}
