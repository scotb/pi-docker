# pi-personas

Persona switching for Pi — switch between lead, coder, reviewer, and architect mid-session.

Each persona defines WHO you are: your identity, reasoning style, communication approach, and boundaries. By default Pi is a **coder**. Switching personas rewrites the system prompt so the agent adopts that role's personality.

Tool restrictions reinforce those boundaries (e.g., reviewer can't edit files because a reviewer shouldn't modify code), but the persona itself — the instructions and identity — is what actually changes your behavior.

## Bundled

This extension is bundled with the `pi-portable` Docker image. It's copied into `~/.pi/agent/extensions/` automatically at container startup by the entrypoint script — no installation step required.

## Quick Start

### Built-in Personas

Four personas ship with the package out of the box:

| Persona | Model | Tools | Purpose |
|---------|-------|-------|---------|
| `lead` | llama-swap/lead | read, bash, grep, find, ls, edit, write | Orchestrator. Investigates with user, writes specs/docs, final review. |
| `coder` | llama-swap/coder | read, bash, edit, write | Implementation & bug fixes. Full file access. |
| `reviewer` | llama-swap/reviewer | read, bash, grep, find, ls | Code review. Read-only — never modifies files. |
| `architect` | llama-swap/architect | read, bash, grep, find, ls | System design & trade-off analysis. Read-only. |

### Usage

```bash
# Start as lead/orchestrator
pi --persona lead

# Switch mid-session
/persona coder

# Show selector UI
/persona

# Cycle through personas (Ctrl+Shift+U)
```

### Your Workflow

The personas map to a natural development pipeline:

1. **Lead** — investigate with you, plan the approach, write specs
2. **Coder** — implement based on the spec
3. **Reviewer** — check the code against the spec (loops back to coder if issues found)
4. **Lead** — final review and interactive discussion of results with you

## Configuration

Personas are configured in JSON files, merged in this order (later overrides earlier):

1. **Built-in defaults** (shipped with the extension)
2. **Global**: `~/.pi/agent/personas.json` — your personal persona definitions
3. **Project-local**: `<cwd>/.pi/personas.json` — project-specific personas that override global

### Example: ~/.pi/agent/personas.json

```json
{
  "lead": {
    "model": "llama-swap/lead",
    "thinkingLevel": "high",
    "tools": ["read", "bash", "grep", "find", "ls", "edit", "write"],
    "instructions": "You are the LEAD. Investigate with the user, plan solutions, write specs. Can write .md, .txt, config files (.json, .yaml, .yml, .toml, .ini, .env), shell scripts (.sh), Dockerfiles, CI/CD configs, and other documentation — but never source code."
  },
  "coder": {
    "model": "llama-swap/coder",
    "thinkingLevel": "high",
    "tools": ["read", "bash", "edit", "write"],
    "instructions": "You are a CODE WRITER. Implement features and fix bugs efficiently based on the spec."
  },
  "reviewer": {
    "model": "llama-swap/reviewer",
    "thinkingLevel": "high",
    "tools": ["read", "bash", "grep", "find", "ls"],
    "instructions": "You are a CODE REVIEWER. Analyze code quality against the spec. Do NOT modify files."
  },
  "architect": {
    "model": "llama-swap/architect",
    "thinkingLevel": "high",
    "tools": ["read", "bash", "grep", "find", "ls"],
    "instructions": "You are an ARCHITECT. Design system structure and evaluate trade-offs. Focus on big-picture decisions."
  }
}
```

### Persona Config Format

```json
{
  "<name>": {
    "model": "provider/model-id",
    "thinkingLevel": "high",
    "tools": ["read", "bash"],
    "instructions": "You are a ... Your job is to ..."
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `model` | string | Provider/model (e.g., `"llama-swap/lead"`). Looks up via model registry. |
| `thinkingLevel` | enum | `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max` |
| `tools` | string[] | Tools to enable. **Replaces** the default set — this is how personas restrict capabilities. |
| `instructions` | string | System prompt instructions appended before every LLM call. |

### Adding Custom Personas

Override built-ins or add new ones in your global config:

```json
{
  "my-custom": {
    "model": "llama-swap/lead",
    "thinkingLevel": "medium",
    "tools": ["read", "bash"],
    "instructions": "You are a CUSTOM persona. Do X, Y, Z."
  }
}
```

## How It Works

1. **Persona identity (primary)**: The `before_agent_start` event appends persona instructions to the system prompt before every LLM call. This is what actually changes who you are — your reasoning style, communication approach, and boundaries.
2. **Tool restrictions (secondary)**: `pi.setActiveTools([...])` replaces the full tool set to reinforce those boundaries (e.g., reviewer can't edit files).
3. **Model switching**: `pi.setModel()` swaps the active model via the registry lookup (`ctx.modelRegistry.find(provider, modelId)`). Different personas may use different models optimized for their role.
4. **Session persistence**: Active persona name is saved each turn via `pi.appendEntry("persona-state", ...)` and restored on session resume.
5. **Status bar**: Current persona shown in status bar via `ctx.ui.setStatus("persona", ...)`.
