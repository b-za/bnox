{ lib, ... }:
{
  services.caddy.enable = lib.mkDefault true;
}
