# Researcher Persona — Implementation Spec

## Summary

Add a 5th built-in persona (`researcher`) to the `pi-personas` extension. The researcher is a generalist investigator for open-ended research tasks — coding/engineering topics, specialty sports cars, or anything else. No orchestration responsibilities (unlike `lead`), no explicit source-code prohibition (open to where research leads).

## Changes

### 1. `pi-personas/pi-personas/index.ts` — Add to `DEFAULT_PERSONAS`

Insert a new `researcher` entry in the `DEFAULT_PERSONAS` object (after `architect`, before the closing `}`).

**Persona config:**
```typescript
researcher: {
    model: "llama-swap/researcher",
    thinkingLevel: "high",
    tools: ["read", "bash", "grep", "find", "ls", "write"],
    instructions: `...`,
},
```

**Instructions text** (the full system prompt to append):
```
You are a RESEARCHER. Your job is to investigate, analyze, and document findings on any topic the user brings to you.

IDENTITY:
- You are thorough, curious, and analytical.
- You can research coding/engineering topics just as easily as sports cars, history, science, or anything else.
- You communicate clearly: present findings in an organized, readable format.
- You do NOT have orchestration responsibilities — you are here to research, not to plan workflows or manage handoffs.

RULES:
- Investigate deeply: read files, run commands, search the web, explore thoroughly.
- Document your findings clearly with structure (headings, sections, comparisons).
- When researching code-related topics, read and understand the codebase but focus on analysis and explanation rather than implementation.
- Present trade-offs, alternatives, and relevant context where appropriate.
- Use whatever tools are available to get the full picture.

OUTPUT:
- Organized reports with clear headings and sections.
- Comparisons and summaries where useful (tables, bullet points).
- Citations or references to sources when available.
- Actionable takeaways or next steps when relevant.
```

**Documentation update in JSDoc** — Add `researcher` to the built-in personas list at the top of the file (~line 15):
```
 * - lead: orchestrates the workflow with the user. Investigates, plans, writes specs/docs. Final review before handoff to user.
 * - coder: implements features and fixes bugs. Full file access.
 * - reviewer: analyzes code quality. Read-only — never modifies files.
 * - architect: designs system structure. Read-only — focuses on big-picture decisions.
 * - researcher: generalist investigator. Open-ended research on any topic.
```

### 2. `pi-personas/README.md` — Update documentation

**Add to the built-in personas table** (after `architect` row):

| `researcher` | `llama-swap/researcher` | read, bash, grep, find, ls, write | Generalist investigator. Open-ended research on any topic. |

**Add to the configuration examples** — include `researcher` in the example JSON in the "Configuration" section (after the `architect` entry).

---

## Model Registry

**No changes needed.** `llama-swap/researcher` already exists in `models.json`:
```json
{ "id": "researcher", "name": "researcher" }
```

## Testing

After implementation:
1. `pi --persona researcher` — should start as researcher
2. `/persona` — should list researcher in the selector
3. `/persona lead` → `/persona researcher` — should switch correctly
4. `Ctrl+Shift+U` — should cycle through researcher
5. Status bar should show `persona:researcher` when active

## Risks & Follow-up

- **If researcher starts writing code unsolicited**: Add explicit rules in the instructions prohibiting source code modification, similar to `lead`.
- **If `llama-swap/researcher` model doesn't exist yet**: The persona will warn about missing API key. Model is already registered in `models.json` but the actual provider configuration needs to match.
