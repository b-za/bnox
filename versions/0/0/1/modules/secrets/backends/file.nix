{ config, lib, ... }:
let
  cfg = config.bnox.secrets;
  secretsRoot = "/var/lib/bnox/secrets";
  slotUnitName = key: "bnox-secret-" + builtins.replaceStrings [ "/" ] [ "-" ] key;
in
{
  config = lib.mkIf (cfg.thingsBackend == "file") (
    lib.mkMerge [
      {
        systemd.paths = lib.mapAttrs' (
          key: _slot:
          lib.nameValuePair (slotUnitName key) {
            wantedBy = [ "multi-user.target" ];
            pathConfig.PathChanged = "${secretsRoot}/${key}";
          }
        ) cfg.fileSlots;

        systemd.services = lib.mapAttrs' (
          key: slot:
          lib.nameValuePair (slotUnitName key) {
            serviceConfig.Type = "oneshot";
            serviceConfig.User = "root";
            script = lib.concatMapStringsSep "\n" (unit: "systemctl restart ${unit}") slot.restartUnits;
          }
        ) cfg.fileSlots;
      }
      (lib.mkIf (cfg.fileSlots != { }) {
        systemd.tmpfiles.rules =
          [ "d ${secretsRoot} 0755 root root -" ]
          ++ lib.unique (
            lib.flatten (
              lib.mapAttrsToList (
                key: slot:
                let
                  parentDir = builtins.dirOf "${secretsRoot}/${key}";
                in
                lib.optional (parentDir != secretsRoot)
                  "d ${parentDir} 0750 ${slot.owner} ${slot.group} -"
              ) cfg.fileSlots
            )
          );
      })
    ]
  );
}
