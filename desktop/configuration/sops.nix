{
  config,
  lib,
  ...
}:

{
  sops = {
    defaultSopsFile = ../../secrets/secrets.yaml;
    defaultSopsFormat = "yaml";
    age = {
      sshKeyPaths = [ "/persistent/etc/ssh/ssh_host_ed25519_key" ];
      keyFile = "/persistent/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
    secrets = {
      navidrome-lastfm = {
        owner = "navidrome";
        group = "navidrome";
      };
      # Gated on the module: it owns the `hermes` user, so leaving the
      # ownership here unconditional would hand sops-nix a chown against a
      # user that no longer exists once hermesAgent.enable is false.
      hermes-env = lib.mkIf config.hermesAgent.enable {
        owner = "hermes";
        group = "hermes";
      };
      # Same yaml key as hermes-env, mounted separately for codebam so the
      # opencode and pi wrappers can lift OPENROUTER_API_KEY out of it. One key
      # in secrets.yaml, one rotation point, and it stays mounted whether or
      # not the hermes module is enabled.
      opencode-env = {
        key = "hermes-env";
        owner = "codebam";
        group = "users";
      };
      # Same hermes-env key again, this time left root-owned: litellm runs
      # under a DynamicUser, and systemd reads EnvironmentFile as root before
      # the unit drops privileges, so no chown is needed and none is wanted.
      litellm-env = {
        key = "hermes-env";
      };
      searx-secret = { };
      "unredacted.org" = {
        sopsFile = ../../secrets/passwords.enc.yaml;
        owner = "codebam";
        group = "users";
      };
    };
  };
}
