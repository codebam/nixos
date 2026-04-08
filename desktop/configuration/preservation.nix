_:

{
  preservation = {
    preserveAt."/persistent" = {
      directories = [
        "/var/lib/meilisearch-master-key"
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
