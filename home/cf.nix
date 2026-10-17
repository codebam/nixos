# The Cloudflare CLI (`cf`, pkgs/cf.nix) guidance block, defined once the way
# email-mcp.nix owns the email policy: home/agents.nix interpolates the text
# into pi, dsh, and opencode's instruction files, and home/hermes.nix carries
# it in its system-prompt hints. The operational rules are distilled from the
# upstream agent guide (https://developers.cloudflare.com/cf/agents/) so every
# harness sees the same behavior the docs prescribe.
{
  guidance = ''
    ## Cloudflare CLI (cf)

    `cf` is on PATH from this flake (npm `cf`, open beta); do NOT `npm install
    -g` it. It covers the entire Cloudflare API (2,900+ generated commands)
    plus Workers projects, and it is built for agents: a real command prints
    JSON to stdout (parse it, or `jq`), messages and errors go to stderr, and
    a failure exits non-zero. Cloudflare work goes through `cf` unless the
    project has a `wrangler.jsonc`/`wrangler.toml`, which stays on Wrangler.

    - Find the command for a task: `cf cli search "<task in words>"` -- local
      search index, no credentials needed, up to five JSON matches, best
      first. Inspect one with `cf schema <command>` (operationId, method,
      path, params) and its own flags with `<command> --help`.
    - Preview with `--dry-run`: prints the would-be API request without
      sending it; also needs no credentials.
    - Destructive commands without `--force` in a non-interactive session
      print "Aborted." and exit 0 -- a zero exit does not prove the change
      happened, so review the command before adding `--force`.
    - Auth comes from `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID`, which
      this environment already exports; `cf auth login` is interactive and
      will not work here.
    - `cf dev`/`build`/`deploy` need a `cloudflare.config.ts` project
      (convert an existing Worker with `cf migrate`); never run them in a
      bare Wrangler project.
  '';
}
