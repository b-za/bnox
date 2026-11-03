{ lib, ... }:
{
  virtualisation.podman.enable = lib.mkForce false;
  services.caddy.enable = lib.mkForce false;
  services.nats.enable = lib.mkForce false;
  services.xserver.enable = lib.mkDefault false;
}
