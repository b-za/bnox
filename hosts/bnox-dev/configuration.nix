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
    source = "/srv/demo";
    components.web = {
      shape = "webapp";
      runtime = "container";
      domain = "demo.local";
      ingressPort = 8080;
      secrets = [ "api_key" ];
    };
  };
}
