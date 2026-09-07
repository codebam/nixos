_:

{
  imports = [
    # shell
    ./shell-common.nix
    ./terminal.nix
    # compositor
    ./sway.nix
    ./viewport.nix
    ./waybar.nix
    ./stylix.nix
    ./xdg.nix
    # user services (swayidle, gpg-agent, tmux, iamb-login)
    ./services.nix
    # apps / data
    ./home.nix
    ./programs.nix
    ./agents.nix
    ./mopidy.nix
    ./termsonic.nix
    ./voxtype.nix
  ];
}
