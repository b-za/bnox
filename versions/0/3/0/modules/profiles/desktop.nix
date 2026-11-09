{ lib, pkgs, ... }:
{
  services.xserver = {
    enable = lib.mkDefault true;
    windowManager.qtile.enable = lib.mkDefault true;
  };

  services.displayManager.ly.enable = lib.mkDefault true;

  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  environment.systemPackages = with pkgs; [
    firefox
    alacritty
  ];
}
