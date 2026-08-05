_:

{
  preservation = {
    preserveAt."/persistent" = {
      directories = [
        # HERMES_HOME lives at /var/lib/hermes/.hermes: agents, skills,
        # memories, kanban.db, state.db, auth.json. Tree is 2770 hermes:hermes.
        {
          directory = "/var/lib/hermes";
          user = "hermes";
          group = "hermes";
          mode = "2770";
        }
      ];
      users = {
        codebam = {
          directories = [
            "Android"
            ".android"
            ".config/sunshine"
            ".config/bolt-launcher"
          ];
        };
        makano = {
          commonMountOptions = [
            "x-gvfs-hide"
          ];
          directories = [
            "persist"
          ];
        };
      };
    };
  };
}
