# Shared values for the Google Calendar MCP server (the `google-calendar`
# tool namespace in Hermes): the stdio launcher and the server name, so the
# registration in home/hermes.nix and any future consumer cannot drift.
#
# The server is packaged in pkgs/google-calendar-mcp.nix; interactive
# authentication is a one-time `google-calendar-mcp auth` run whose tokens
# land in ~/.config/google-calendar-mcp/tokens.json, preserved across the
# root wipe with the rest of the home directory.
{ config, pkgs }:

let
  # Pre-activation fallback: the manual copy of the same Desktop-app client
  # JSON used to run `auth` before sops-nix mounted
  # /run/secrets/google-calendar-oauth. In steady state the secret wins and
  # this file is never read.
  fallbackCredentials = "${config.home.homeDirectory}/.config/google-calendar-mcp/gcp-oauth.keys.json";
in
{
  # The bin is self-contained (a makeWrapper script pinning the store's
  # node), so the launcher only has to point it at the credentials: the
  # `google-calendar-oauth` sops secret when mounted, otherwise the fallback
  # above. The file tests are runtime checks, not eval-time dependencies, so
  # a host before the activation that mounts the secret still starts.
  launcher = builtins.toString (
    pkgs.writeShellScript "google-calendar-mcp" ''
      if [ -r /run/secrets/google-calendar-oauth ]; then
        export GOOGLE_OAUTH_CREDENTIALS=/run/secrets/google-calendar-oauth
      elif [ -r ${fallbackCredentials} ]; then
        export GOOGLE_OAUTH_CREDENTIALS=${fallbackCredentials}
      fi
      exec ${pkgs.google-calendar-mcp}/bin/google-calendar-mcp "$@"
    ''
  );

  # The MCP server name is the tool namespace in Hermes:
  # mcp__google_calendar__*.
  name = "google-calendar";
}
