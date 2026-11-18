# The Assisted-by commit trailer rule, defined once for every harness:
# home/agents.nix interpolates `guidance` into the dsh, pi and opencode
# global AGENTS.md files, and home/hermes.nix into its always-on
# environment_hint / coding_instructions. The hand-written ~/.claude/CLAUDE.md
# and ~/.gemini/GEMINI.md carry the same rule by hand (they stay hand-written
# so each tool's own /memory-style editing keeps working). Qwen's
# ~/.qwen/QWEN.md is flake-managed (home/agents.nix) and carries only the
# zvec-grep block so far, not this one.
#
# Instruction-based on purpose: a git hook cannot know which model is
# committing, and a global hook would also tag Sean's own commits.
{
  guidance = ''
    ## Git commits: Assisted-by trailer

    Every git commit you create must carry an `Assisted-by:` trailer naming the
    model that did the work — your own model name, not the harness or product
    name (e.g. `Assisted-by: Claude Opus 4.5`). Use the model you are actually
    running as, including when you are a subagent.

    - Trailer position: the last paragraph of the commit message, after a blank
      line; one `Assisted-by: <model name>` line per assisting model.
    - `Assisted-by:` is the only trailer this rule adds. Never add
      `Co-authored-by` or any other trailer, and never copy trailers from
      exemplar commits in the log.
    - Applies to every commit you author or rewrite: new commits, `--amend`,
      and merge/rebase/cherry-pick messages you write. Never add it to commits
      the user writes themselves.
    - On rewrites, keep trailers the commit already carries (`Signed-off-by`,
      `Co-authored-by`, …) intact; do not duplicate an `Assisted-by` line that
      already names your model.
    - Safe append: `git interpret-trailers --trailer "Assisted-by: <model name>"`.
  '';
}
