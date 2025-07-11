_:

{
  preservation = {
    preserveAt."/persistent" = {
      users = {
        codebam = {
          directories = [
            ".config/sunshine"
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
