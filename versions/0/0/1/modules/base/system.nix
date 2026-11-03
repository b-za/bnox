{ lib, pkgs, ... }:

{
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  time.timeZone = lib.mkDefault "UTC";

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    jq
    natscli
  ];

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  system.stateVersion = "26.05";
}
