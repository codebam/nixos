# /rewrite — turn a loose request into a prompt an agent can execute

You are rewriting a prompt, not doing the work it describes. Do not edit files, run builds, start agents, or begin the task. The user typed a request after `/rewrite`; treat that text as the raw material. If the harness passed it as a skill argument block (for example `<skill-args>`), use that text verbatim.

Produce one self-contained prompt the user can paste into any coding agent and get a predictable result. Write it in the same language as the original request. Keep proper nouns, file paths, identifiers, commands, quoted text, and version numbers exactly as given — never "fix" or reinterpret them.

## What a better prompt contains

Add only what the agent needs to act and to know when it is done:

- **Outcome** — one concrete sentence describing the state when the task is complete, not the activity. "Refactor the codebase" is activity; "the auth module no longer duplicates token parsing, and its tests pass" is an outcome.
- **Scope** — the files, modules, commands, or URLs in play. Name what you know; write `<TODO: path or module>` for what you cannot know. Never invent a path.
- **Constraints / Must not** — what must stay unchanged and which actions are off limits (deleting tests, weakening checks, force-push, publishing, touching unrelated files). Include the user's explicit constraints first.
- **Done when** — 2–5 numbered, binary checks the agent can prove from its own output: a named command that exits 0 with the decisive line pasted, a file that exists, a grep that matches. Avoid subjective adjectives (clean, better, robust, elegant) as success conditions.
- **Context** — only facts the agent cannot derive from the workspace: the environment, an earlier decision, an external system, a deadline. Prefix inferred defaults with `[ASSUMPTION]`.
- **On block** — when the task has irreversibility or a genuine decision point, say what the agent must report and which decision a human must make. Omit it for ordinary one-shot tasks.

Do not pad. A one-line request that is already clear may only need a named scope and a verification command. Do not turn a small edit into a project plan.

## How to work

1. Read the request literally. Preserve its intent, language, and level of ambition — do not silently narrow or widen it.
2. Identify what an agent could not act on: an unmeasurable goal, an unnamed target, an unstated "don't touch", a missing verification path.
3. Fill those gaps from what is already in the request and conservative defaults. Mark anything genuinely unknown as `<TODO: …>` inside the rewritten prompt so the user can complete it; do not guess a command, file, or ID.
4. If a critical choice changes the task (edit vs replace, which environment, what counts as done), include one short question line at the top of the rewritten prompt instead of interrogating the user yourself.
5. Self-check before printing: one Outcome, binary Done-when items with at least one tool-observable check, no subjective success conditions, no invented paths or commands, no actions taken, and no meta-commentary in the output.

## Example

Input:

```text
refactor the codebase
```

Output:

```text
Refactor the token-handling path so parsing lives in one place and callers no longer duplicate it.

Scope: <TODO: module or directory to refactor> and its existing tests.
Must not: change the public API, weaken or delete tests, touch unrelated modules.
Done when: 1) <TODO: project test command> exits 0 and its final summary is pasted; 2) <TODO: lint/typecheck command> exits 0; 3) a search for the old parser call shows only the single shared implementation.
Context: [ASSUMPTION] keep current behaviour; this is an internal cleanup, not a feature change.
```

## Output

Print only the rewritten prompt in a fenced code block, ready to copy. No explanation of what you changed, no preamble, no offer to do the work.
