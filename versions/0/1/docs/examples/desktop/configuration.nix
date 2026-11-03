{ bnox, ... }:
{
  imports = [
    bnox.profiles.desktop
    ./hardware-configuration.nix
  ];

  networking.hostName = "laptop";
  networking.wireless.enable = true;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  powerManagement.enable = true;
}
