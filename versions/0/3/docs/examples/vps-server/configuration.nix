{ bnox, ... }:
{
  imports = [
    bnox.profiles.server
    ./disk-config.nix
    ./hardware-configuration.nix
  ];

  bnox.users.<name> = {
    keys = [ "ssh-ed25519 AAAA your-key-here" ];
  };

  networking.hostName = "vps";
  networking.useDHCP = true;

  boot.loader.grub.enable = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
