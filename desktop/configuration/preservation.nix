_:

{
  preservation = {
    preserveAt."/persistent" = {
      users = {
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
