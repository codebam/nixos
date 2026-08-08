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
        # Just the journal cursor and the escalation cooldown stamp. Losing it
        # is not fatal, but a fresh cursor means the first scan after every
        # boot classifies nothing.
        {
          directory = "/var/lib/security-triage";
          mode = "0700";
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
            # This user's own HERMES_HOME (see desktop/makano-home.nix).
            # Holds their API login, sessions, memories, and skills, none of
            # which are reproducible from the flake.
            ".hermes"
            # `wrangler login` writes its OAuth token here. Without this the
            # login is undone by the next boot.
            ".config/.wrangler"
          ];
        };
      };
    };
  };
}
