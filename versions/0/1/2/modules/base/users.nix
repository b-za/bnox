{ config, lib, ... }:
let
  cfg = config.bnox.users;
in
{
  options.bnox.users = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          wheel = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          home = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
        };
      }
    );
    default = { };
  };

  config = {
    users.users = lib.mapAttrs (name: user: {
      isNormalUser = true;
      extraGroups = lib.optionals user.wheel [ "wheel" ];
      openssh.authorizedKeys.keys = user.keys;
    }) cfg;

    home-manager.users = lib.mapAttrs (_: _: import ../../home/default.nix) (
      lib.filterAttrs (_: user: user.home) cfg
    );
  };
}
