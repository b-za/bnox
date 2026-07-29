{ lib, config, ... }:
{
  options.bnox.platform.staticSites = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
  };

  config.services.caddy.virtualHosts = lib.mapAttrs (
    domain: root: {
      extraConfig = ''
        root * ${root}
        file_server
      '';
    }
  ) config.bnox.platform.staticSites;
}
