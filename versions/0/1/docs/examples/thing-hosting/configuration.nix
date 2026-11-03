{ bnox, ... }:
{
  imports = [
    bnox.profiles.server
    ./hardware-configuration.nix
  ];

  networking.hostName = "apphost";
  networking.useDHCP = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  bnox.things.mywebapp = {
    enable = true;
    source = "/srv/mywebapp";
    components.web.domain = "mywebapp.example.com";
  };

  bnox.things.mysite = {
    enable = true;
    source = "/srv/mysite";
    components.www.domain = "mysite.example.com";
  };

  bnox.things.mydaemon = {
    enable = true;
    source = "/srv/mydaemon";
    components.main = { };
  };
}
