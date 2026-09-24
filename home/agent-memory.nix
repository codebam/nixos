# Shared values for the agent-memory knowledge-graph MCP server: the official
# `mcp-server-memory` run once behind mcp-proxy as a systemd *user* service
# (the unit lives in home/agents.nix), so every harness reads and writes ONE
# JSONL graph instead of spawning its own copy. The reference server rewrites
# the whole file per write and takes no cross-process lock, so a single shared
# writer is the point -- do not register it per-session over stdio. The store
# lives on a preserved path (modules/system/preservation.nix); the port is
# loopback only.
#
# Imported by home/agents.nix (the unit, the opencode/pi/dsh registrations,
# and their instruction files) and home/hermes.nix (its MCP row and
# system-prompt guidance), so the endpoint, server name, store path, and
# rendered guidance cannot drift between harnesses.
let
  name = "memory";
  port = 7979;
  # ExecStart expands %h (the requester's home) to the real path; the `-e`
  # passthrough is what tells the child stdio server where its graph lives.
  fileSpec = "%h/.local/share/agent-memory/memory.jsonl";

  # Rendered into each harness's standing instructions. opencode names the
  # tools `<server>_<tool>` and pi's adapter does the same with its default
  # `toolPrefix` ("server"); dsh and Hermes register the
  # `mcp__<server>__<tool>` form (Hermes sanitizes hyphens the same way),
  # which is the one substitution below.
  guidance = ''
    ## Agent memory (shared knowledge graph)

    A `memory` MCP server holds a persistent entity/relation/observation
    knowledge graph shared by every harness on this machine. Use it for durable
    facts the user asks you to keep, and to recall earlier decisions,
    preferences and project conventions.

    Tools (names as this host registers them):
    - `${name}_search_nodes { query }` — find entities by name, type, or observation text.
    - `${name}_open_nodes { names }` — open named entities with their relations.
    - `${name}_read_graph` — the whole graph; use sparingly, it can be large.
    - `${name}_create_entities { entities: [{ name, entityType, observations }] }`
    - `${name}_create_relations { relations: [{ from, to, relationType }] }`
    - `${name}_add_observations { observations: [{ entityName, contents }] }`
    - `${name}_delete_entities` / `${name}_delete_relations` / `${name}_delete_observations`

    Rules: store only durable, user-relevant facts — decisions, preferences,
    conventions — not transient chatter. Search before writing, and prefer
    `add_observations` on an existing entity over a near-duplicate one.
    `search_nodes` is substring matching, not semantic, so try distinctive
    terms and synonyms.

    On this machine the graph is *the* durable memory: Hermes runs with its
    native MEMORY.md store disabled and recalls graph entries into every turn
    by itself, so a fact worth keeping belongs here rather than in a
    harness-local file, and entries written by any one harness are read by the
    others.
  '';
in
{
  inherit
    name
    port
    fileSpec
    guidance
    ;

  # The loopback URL mcp-proxy serves statelessly; every harness registers it
  # as a remote server and talks to the one shared writer.
  url = "http://127.0.0.1:${toString port}/mcp";

  # The `mcp__<server>__<tool>` rendering (dsh and Hermes).
  guidanceMcp =
    builtins.replaceStrings
      [
        "${name}_search_nodes"
        "${name}_open_nodes"
        "${name}_read_graph"
        "${name}_create_entities"
        "${name}_create_relations"
        "${name}_add_observations"
        "${name}_delete_entities"
        "${name}_delete_relations"
        "${name}_delete_observations"
      ]
      [
        "mcp__${name}__search_nodes"
        "mcp__${name}__open_nodes"
        "mcp__${name}__read_graph"
        "mcp__${name}__create_entities"
        "mcp__${name}__create_relations"
        "mcp__${name}__add_observations"
        "mcp__${name}__delete_entities"
        "mcp__${name}__delete_relations"
        "mcp__${name}__delete_observations"
      ]
      guidance;
}
