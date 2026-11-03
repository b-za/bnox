{ lib, ... }:
{
  imports = [
    ./infra.nix
    ./backends/file.nix
    ./backends/nats-kv.nix
  ];

  options.bnox.secrets = {
    thingsBackend = lib.mkOption {
      type = lib.types.enum [
        "file"
        "nats-kv"
      ];
      default = "file";
    };

    fileSlots = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            owner = lib.mkOption {
              type = lib.types.str;
            };
            group = lib.mkOption {
              type = lib.types.str;
            };
            restartUnits = lib.mkOption {
              type = lib.types.listOf lib.types.str;
            };
          };
        }
      );
      default = { };
    };
  };
}
