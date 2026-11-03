{ lib, config, pkgs, ... }:
let
  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  imagesDirs = lib.concatStringsSep " " (
    map (thing: "/var/lib/${thing.name}/images") enabledThingsList
  );

  hasThings = enabledThingsList != [ ];
in
{
  config = lib.mkMerge [
    (lib.mkIf hasThings {
      systemd.services.bnox-deploy-prune = {
        path = [
          pkgs.findutils
          pkgs.coreutils
        ];
        serviceConfig = {
          Type = "oneshot";
          User = "root";
          Group = "root";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = imagesDirs;
        };
        script = ''
          for imgdir in ${imagesDirs}; do
            [ -d "$imgdir" ] || continue
            ${pkgs.findutils}/bin/find "$imgdir" -maxdepth 1 -type f -name '*.tar' -printf '%T@ %p\n' \
              | sort -rn \
              | tail -n +4 \
              | cut -d' ' -f2- \
              | while IFS= read -r p; do
                  rm -f -- "$p" || true
                done
          done
        '';
      };

      systemd.timers.bnox-deploy-prune = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "04:00";
          Persistent = true;
        };
      };
    })
  ];
}
