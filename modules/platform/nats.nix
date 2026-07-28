{ lib, ... }:
{
  services.nats = {
    enable = lib.mkDefault true;
    jetstream = true;
    settings.max_payload = 8388608;
  };
}
