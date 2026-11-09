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
      # Locked by declaration, not by omission: "!" is the documented
      # /etc/shadow "password login disabled" marker (nixpkgs' allowsLogin
      # treats it as first-class). mkDefault so a host that wants a real
      # hashedPassword/password for a user still wins by normal precedence.
      hashedPassword = lib.mkDefault "!";
      extraGroups = lib.optionals user.wheel [ "wheel" ];
      openssh.authorizedKeys.keys = user.keys;
    }) cfg;

    # Corollary of key-only users: bnox never sets a usable password, so a
    # sudo password prompt can never be satisfied. With the NixOS default
    # (wheelNeedsPassword = true) a fresh bnox host has no path to root at
    # all — sshd is key-only, root login is disabled, and wheel users have
    # locked passwords. Passwordless sudo for wheel is the only coherent
    # policy under key-only auth. Hardcoded, not an option: bnox.users has
    # no way to set passwords, so "passworded sudo" is not an alternative
    # policy but a lockout. A divergent host that sets real passwords can
    # re-enable the prompt via this same NixOS option.
    security.sudo.wheelNeedsPassword = false;

    home-manager.users = lib.mapAttrs (_: _: import ../../home/default.nix) (
      lib.filterAttrs (_: user: user.home) cfg
    );
  };
}
