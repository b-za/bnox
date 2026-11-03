{ lib, ... }:
{
  virtualisation.podman.enable = lib.mkDefault true;
}
