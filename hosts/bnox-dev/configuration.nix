{ bnox, ... }:
{
  imports = [
    bnox.profiles.server
    ./hardware-configuration.nix
  ];

  networking.hostName = "bnox-dev";
  networking.useDHCP = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  bnox.things.demo = {
    enable = true;
    source = toString ./demo-thing;
    components.web.domain = "demo.local";
  };

  bnox.things.mock-daemon = {
    enable = true;
    source = toString ./mock-daemon;
    components.main = { };
  };
}
