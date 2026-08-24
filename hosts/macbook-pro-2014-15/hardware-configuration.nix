# This is a minimal hardware configuration for MacBook Pro 2014 15-inch
# It uses generic settings that should work with most MacBook hardware
{ config, lib, pkgs, ... }:

{
  # Bootloader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # File systems
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD_BOOT";
    fsType = "ext4";
  };

  # Enable swap
  swapDevices = [ { device = "/dev/disk/by-label/swap"; } ];

  # Enable SSH
  services.openssh.enable = true;

  # Enable power management
  powerManagement.enable = true;
  powerManagement.cpuFreqGovernor = "powersave";

  # Enable Bluetooth
  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;

  # Enable webcam
  hardware.camera.enable = true;

  # Enable trackpad
  hardware.trackpoint.enable = true;

  # Sound configuration
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.support32Bit = true;

  # Enable graphics drivers (Intel graphics typically used in MacBook Pros)
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
}