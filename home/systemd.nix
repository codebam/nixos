{ pkgs, config, ... }:
{
  systemd = {
    user = {
      services = {
        tmux = {
          Unit = {
            Description = "Tmux server";
            After = [ "graphical-session.target" ];
          };
          Service = {
            Type = "forking";
            ExecStart = "${pkgs.tmux}/bin/tmux -S /run/user/%U/tmux-%U/default new-session -d -s default";
            ExecStop = "${pkgs.tmux}/bin/tmux -S /run/user/%U/tmux-%U/default kill-session -t default";
            Restart = "always";
          };
          Install = {
            WantedBy = [ "default.target" ];
          };
        };
      };
    };
  };
}
