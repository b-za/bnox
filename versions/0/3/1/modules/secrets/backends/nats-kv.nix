{ config, lib, ... }:
{
  config = lib.mkIf (config.bnox.secrets.thingsBackend == "nats-kv") {
    assertions = [
      {
        assertion = false;
        message = "nats-kv secrets backend not implemented yet (D-007 Hybrid-2)";
      }
    ];
  };
}
