_:

{
  preservation = {
    preserveAt."/persistent" = {
      users = {
        codebam = {
          directories = [
            {
              directory = ".cache/moonlight";
              user = "codebam";
              group = "users";
            }
          ];
        };
      };
    };
  };
}
