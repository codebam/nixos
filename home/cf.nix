# The Cloudflare CLI (`cf`, pkgs/cf.nix) guidance block, defined once the way
# email-mcp.nix owns the email policy: home/agents.nix interpolates the
# host-tier text into pi's instruction file and the sandbox-tier text into the
# dsh and opencode files, and home/hermes.nix carries the host-tier text in
# its system-prompt hints. The operational rules are distilled from the
# upstream agent guide (https://developers.cloudflare.com/cf/agents/) so every
# harness sees the same behavior the docs prescribe.
{
  # Host-tier sessions (pi) and tiers whose environment carries the API token
  # (Hermes' terminal backend).
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

  # The dsh default world and opencode2's sandbox shell: cf is on PATH, but
  # no Cloudflare credentials are forwarded into the container, so only the
  # credential-free subcommands work there.
  guidanceSandbox = ''
    ## Cloudflare CLI (cf) — credential-free subcommands only in this sandbox

    `cf` is on PATH in this tier, but nothing here carries the Cloudflare API
    token, so commands that talk to the API cannot authenticate. The local
    parts still work and are useful for planning: `cf cli search "<task in
    words>"` (local index, up to five JSON matches, best first), `cf schema
    <command>`, and `--dry-run` (prints the would-be API request without
    sending it). For actual Cloudflare work, say plainly that it needs a
    credentialed session -- the human's shell, a reviewed `dsh-host-access`
    launch, or an `OPENCODE2_NO_SANDBOX=1` relaunch -- and do not attempt
    `cf auth login` or another workaround.
  '';
}
