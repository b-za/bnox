{ bnox, ... }:
{
  imports = [
    bnox.profiles.server
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "vps";
  networking.useDHCP = true;

  boot.loader.grub.enable = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
