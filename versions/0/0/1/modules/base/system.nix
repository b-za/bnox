{ pkgs, ... }:

{
  i18n.defaultLocale = "en_US.UTF-8";

  time.timeZone = "Africa/Johannesburg";

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
