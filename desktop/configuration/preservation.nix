_:

{
  preservation = {
    preserveAt."/persistent" = {
      users = {
        codebam = {
          directories = [
            "Android"
            ".android"
            ".config/sunshine"
            ".config/bolt-launcher"
            # zvec-grep state: downloaded embedding models (~640M GGUF under
            # models/), the global config, and the MCP request key. Not
            # reproducible from the flake; re-downloading on every boot is
            # wasteful.
            ".zvec-grep"
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
