{ pkgs, ... }:

{
  home.username = "bh";
  home.homeDirectory = "/home/bh";

  home.stateVersion = "26.05";

  programs.bash.enable = true;

  home.packages = with pkgs; [
    htop
    tmux
  ];
}
