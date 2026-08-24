{ bnox, ... }:
{
  imports = [
    bnox.profiles.desktop
    ./hardware-configuration.nix
  ];

  networking.hostName = "macbook-pro-2014-15";
  networking.useDHCP = true;

  # Enable necessary services for a MacBook
  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable webcam
  hardware.camera.enable = true;

  # Enable touchpad
  hardware.trackpoint.enable = true;

  # Enable power management
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  # Configure network
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];

  # Enable sound
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;
}