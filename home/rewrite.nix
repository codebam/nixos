# One /rewrite prompt-improver for every harness on this machine.
#
# Qwen Code, dsh, Hermes and Claude Code read a user skill bundle as `/<name>`;
# Pi exposes its prompt templates directly as `/<name>` but skills only as
# `/skill:<name>`; OpenCode needs a command file. The instruction body is one
# file so the five spellings cannot drift -- only the frontmatter and the way
# the original request reaches the model differ.
_:

let
  body = builtins.readFile ./skills/rewrite/body.md;
  description = "Rewrite a loose request into a specific, verifiable prompt an agent can execute. Use when the user types /rewrite with a prompt to improve";

  skill = ''
    ---
    name: rewrite
    description: ${description}
    ---

    ${body}
  '';

  # Pi templates and OpenCode commands get the request as a template variable;
  # skill bundles receive it from the harness as a skill argument instead.
  commandFrontmatter = "---\ndescription: ${description}\n";
  openCodeCommand = commandFrontmatter + "---\n\n${body}\nOriginal request: $ARGUMENTS\n";
  piTemplate =
    commandFrontmatter
    + "argument-hint: \"[request to improve]\"\n---\n\n${body}\nOriginal request: $@\n";
in
{
  home.file = {
    ".qwen/skills/rewrite/SKILL.md".text = skill;
    ".dsh/skills/rewrite/SKILL.md".text = skill;
    ".hermes/skills/rewrite/SKILL.md".text = skill;
    ".claude/skills/rewrite/SKILL.md".text = skill;
    ".agents/skills/rewrite/SKILL.md".text = skill;

    ".pi/agent/prompts/rewrite.md".text = piTemplate;
  };

  xdg.configFile = {
    # OpenCode scans `commands/` for global slash commands; the legacy
    # singular `command/` is discovered too but is not the current path.
    "opencode/commands/rewrite.md".text = openCodeCommand;
  };
}
