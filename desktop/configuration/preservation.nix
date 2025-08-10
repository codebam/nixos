_:

{
  preservation = {
    preserveAt."/persistent" = {
      users = {
        codebam = {
          directories = [
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
