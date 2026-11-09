{ pkgs, ... }:

{
  home.stateVersion = "26.05";

  programs.bash.enable = true;

  home.packages = with pkgs; [
    htop
    tmux
  ];
}
