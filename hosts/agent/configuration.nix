{ bnox, ... }:
{
  imports = [
    bnox.profiles.server
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "agent";
  networking.useDHCP = true;

  boot.loader.grub.enable = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
