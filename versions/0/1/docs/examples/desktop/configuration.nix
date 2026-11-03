{ bnox, ... }:
{
  imports = [
    bnox.profiles.desktop
    ./hardware-configuration.nix
  ];

  bnox.users.<name> = {
    keys = [ "ssh-ed25519 AAAA your-key-here" ];
  };

  networking.hostName = "laptop";
  networking.wireless.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  powerManagement.enable = true;
}
