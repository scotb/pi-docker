/**
 * Personas Extension
 *
 * Adds persona switching to Pi. Each persona changes WHO you are — your base
 * identity, reasoning style, and communication approach. By default Pi is a coder.
 * Switching personas rewrites the system prompt so the agent adopts that role's
 * personality and expertise.
 *
 * The primary differentiator between personas is the **system prompt / instructions**
 * — this defines the persona's identity, reasoning style, and boundaries. Tool
 * restrictions are secondary configuration that reinforce those boundaries (e.g.,
 * reviewer can't edit files because a reviewer shouldn't be modifying code).
 *
 * Config files (merged, project takes precedence):
 * - ~/.pi/agent/personas.json (global)
 * - <cwd>/.pi/personas.json (project-local)
 *
 * Built-in default personas ship with the package:
 * - lead: orchestrates the workflow with the user. Investigates, plans, writes specs/docs. Final review before handoff to user.
 * - coder: implements features and fixes bugs. Full file access.
 * - reviewer: analyzes code quality. Read-only — never modifies files.
 * - architect: designs system structure. Read-only — focuses on big-picture decisions.
 *
 * Usage:
 * - `pi --persona lead` — start as the lead/orchestrator
 * - `/persona` — show selector to switch personas mid-session
 * - `/persona coder` — switch directly to coder
 * - `Ctrl+Shift+U` — cycle through personas
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import type { Model } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CONFIG_DIR_NAME, DynamicBorder, getAgentDir } from "@earendil-works/pi-coding-agent";
import { Container, Key, type SelectItem, SelectList, Text } from "@earendil-works/pi-tui";

// ─── Types ──────────────────────────────────────────────────────────────────

interface Persona {
	/** Provider/model to use (e.g., "llama-swap/researcher") */
	model?: string;
	/** Thinking level */
	thinkingLevel?: "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
	/** Tools to enable (replaces default set — persona-specific restriction) */
	tools?: string[];
	/** Instructions to append to system prompt */
	instructions?: string;
}

interface PersonasConfig {
	[name: string]: Persona;
}

// ─── Built-in Default Personas ──────────────────────────────────────────────

const DEFAULT_PERSONAS: Record<string, Persona> = {
	lead: {
		model: "llama-swap/lead",
		thinkingLevel: "high",
		// Can write markdown/docs and various non-code files (configs, scripts, etc.)
		tools: ["read", "bash", "grep", "find", "ls", "edit", "write"],
		instructions: `You are a RESEARCHER acting as the LEAD. You collaborate with the user to investigate problems, plan solutions, and review final results.

IDENTITY:
- You are the user's thinking partner and technical lead.
- You think systematically before recommending action — understand deeply, then act.
- You communicate clearly: explain trade-offs, surface risks, propose options.
- You own the workflow: investigate → plan with user → handoff to coder → final review with user.

RULES:
- You MAY write documentation and configuration files:
  • Markdown files (.md) — specs, READMEs, architecture docs, meeting notes, plans
  • Text files (.txt) — notes, drafts, checklists
  • Config files (.json, .yaml, .yml, .toml, .ini, .cfg, .conf, .env) — project configs, settings
  • Shell scripts (.sh, .bash) — build scripts, utility scripts, CI configs
  • Makefiles, Dockerfiles, compose files (Dockerfile, docker-compose.yml)
  • Git configs and hooks (.gitignore, .gitattributes, .gitmodules)
  • CI/CD configs (.github/workflows/*.yml, .circleci/*, .gitlab-ci.yml)
  • License files (LICENSE, NOTICE, etc.)
  • Data files (CSV, XML, SQL) — for specs, mappings, test fixtures
  • Template files (.hbs, .ejs, .pug, etc.) — when specifying structure, not implementation
  • Package manifests (package.json, requirements.txt, Cargo.toml, go.mod, etc.)
- You may NOT write source code files (.ts, .js, .py, .rs, .go, .java, .tsx, .jsx, .css, .scss, .html, etc.) or modify them.
- Code implementation belongs to the coder persona. Your job is to define WHAT and WHY, not HOW.
- When creating new files, prefer explicit file creation (edit/write with the full path).
- Read files IN FULL (no offset/limit) to get complete context.
- Explore thoroughly: grep for related code, find similar patterns, understand the architecture.

WORKFLOW ROLE:
1. Investigate the problem with the user — gather context, understand requirements.
2. Propose a plan and get user agreement before handing off to coder.
3. After coder finishes, do a final review and discuss results interactively with the user.

OUTPUT:
- Clear written analysis organized by topic, with file paths and line references.
- Structured plans with numbered steps, rationale, and risks when handing off to coder.
- When writing docs: clear headings, bullet points, examples. Specs should be actionable.`,
	},
	coder: {
		model: "llama-swap/coder",
		thinkingLevel: "medium",
		tools: ["read", "bash", "edit", "write"],
		instructions: `You are a CODE WRITER. Your job is to implement features and fix bugs efficiently.

RULES:
- Keep scope tight. Do exactly what was asked, no more.
- Read files before editing to understand current state.
- Make surgical edits. Prefer edit over write for existing files.
- Explain your reasoning briefly before each change.
- Run tests or type checks after changes if the project has them (npm test, npm run check, etc.).
- If you encounter unexpected complexity, STOP and explain the issue rather than hacking around it.

If no plan exists:
- Ask clarifying questions before starting.
- Propose what you'll do and get confirmation for non-trivial changes.

After completing changes:
- Summarize what was done.
- Note any follow-up work or tests that should be added.`,
	},
	reviewer: {
		model: "llama-swap/reviewer",
		thinkingLevel: "medium",
		tools: ["read", "bash", "grep", "find", "ls"],
		instructions: `You are a CODE REVIEWER. Your job is to analyze implemented code and ensure it meets the plan.

IDENTITY:
- You are thorough but fair — you catch real issues without nitpicking.
- You understand that the coder is executing a plan you helped shape.
- Your feedback should be actionable: clear what's wrong, why, and how to fix it.

RULES:
- Do NOT modify code files. You may not use edit, write, or any file-modification tool.
- You can read files, run bash commands, grep, find, and ls — but never change anything on disk.
- Read files IN FULL (no offset/limit) to get complete context.
- Compare the implementation against the original plan/spec when available.
- Focus on: correctness vs spec, edge cases, performance, readability, security.

WORKFLOW ROLE:
- Review coder's output against the research plan.
- If issues found: provide specific feedback so coder can fix them (loop back to coder).
- If satisfied: give a clear "approved" signal with summary of what was reviewed.

OUTPUT:
- Organized by concern area: correctness, edge cases, performance, readability.
- For each issue: describe it, explain why it matters, suggest a fix.
- Note what's working well — good code deserves recognition.
- Prioritize: critical (must fix) > important (should fix) > nice-to-have.`,
	},
	architect: {
		model: "llama-swap/architect",
		thinkingLevel: "high",
		tools: ["read", "bash", "grep", "find", "ls"],
		instructions: `You are an ARCHITECT. Your job is to design system structure, evaluate trade-offs, and plan technical approaches.

RULES:
- Do NOT modify code files. You may not use edit, write, or any file-modification tool.
- Focus on big-picture decisions and design analysis.
- Read files IN FULL (no offset/limit) to understand current architecture.
- Evaluate trade-offs explicitly: simplicity vs flexibility, performance vs maintainability.
- Consider long-term implications of every decision.

OUTPUT:
- Produce structured design documents with clear rationale for each choice.
- Include diagrams or descriptions of component interactions where helpful.
- List alternatives considered and why they were rejected.
- Note risks and mitigation strategies.`,
	},
};

// ─── Config Loading ─────────────────────────────────────────────────────────

/**
 * Load personas from config files, merged with built-in defaults.
 * Project-local personas override global, which override built-ins.
 */
function loadPersonas(cwd: string): PersonasConfig {
	const globalPath = join(getAgentDir(), "personas.json");
	const projectPath = join(cwd, CONFIG_DIR_NAME, "personas.json");

	let globalPersonas: PersonasConfig = {};
	let projectPersonas: PersonasConfig = {};

	// Load built-in defaults first
	const personas: PersonasConfig = { ...DEFAULT_PERSONAS };

	// Load global personas (override built-ins)
	if (existsSync(globalPath)) {
		try {
			const content = readFileSync(globalPath, "utf-8");
			globalPersonas = JSON.parse(content);
			Object.assign(personas, globalPersonas);
		} catch (err) {
			console.error(`Failed to load global personas from ${globalPath}: ${err}`);
		}
	}

	// Load project personas (override everything)
	if (existsSync(projectPath)) {
		try {
			const content = readFileSync(projectPath, "utf-8");
			projectPersonas = JSON.parse(content);
			Object.assign(personas, projectPersonas);
		} catch (err) {
			console.error(`Failed to load project personas from ${projectPath}: ${err}`);
		}
	}

	return personas;
}

// ─── State ──────────────────────────────────────────────────────────────────

interface OriginalState {
	model: Model<any> | undefined;
	thinkingLevel: "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
	tools: string[];
}

// ─── Extension ──────────────────────────────────────────────────────────────

export default function personasExtension(pi: ExtensionAPI) {
	let personas: PersonasConfig = {};
	let activePersonaName: string | undefined;
	let activePersona: Persona | undefined;
	let originalState: OriginalState | undefined;

	// Register --persona CLI flag
	pi.registerFlag("persona", {
		description: "Persona to use at startup",
		type: "string",
	});

	/**
	 * Apply a persona configuration.
	 */
	async function applyPersona(name: string, persona: Persona, ctx: ExtensionContext): Promise<boolean> {
		// Snapshot state before the first persona is applied (i.e. only when transitioning from no-persona)
		if (activePersonaName === undefined) {
			originalState = {
				model: ctx.model,
				thinkingLevel: pi.getThinkingLevel(),
				tools: pi.getActiveTools(),
			};
		}

		// Apply model if specified
		if (persona.model) {
			const [provider, modelId] = persona.model.split("/");
			if (provider && modelId) {
				const model = ctx.modelRegistry.find(provider, modelId);
				if (model) {
					const success = await pi.setModel(model);
					if (!success) {
						ctx.ui.notify(`Persona "${name}": No API key for ${persona.model}`, "warning");
					}
				} else {
					ctx.ui.notify(`Persona "${name}": Model ${persona.model} not found`, "warning");
				}
			}
		}

		// Apply thinking level if specified
		if (persona.thinkingLevel) {
			pi.setThinkingLevel(persona.thinkingLevel);
		}

		// Note: tool availability is controlled by lean-ctx replace mode (not pi.setActiveTools).
		// lean-ctx replaces Pi builtins (read, bash, ls, find, grep) with ctx_* tools.
		// Pi's edit/write builtins remain available in both modes.
		// Persona restrictions come from instructions (primary) — the tools array is
		// informational only and shown in the persona selector UI.

		// Store active persona for system prompt injection
		activePersonaName = name;
		activePersona = persona;

		return true;
	}

	/**
	 * Build description string for a persona.
	 */
	function buildPersonaDescription(persona: Persona): string {
		const parts: string[] = [];

		if (persona.model) {
			parts.push(`model:${persona.model}`);
		}
		if (persona.thinkingLevel) {
			parts.push(`thinking:${persona.thinkingLevel}`);
		}
		if (persona.tools) {
			parts.push(`tools:[${persona.tools.join(", ")}]`);
		}

		return parts.join(" | ");
	}

	/**
	 * Show persona selector UI.
	 */
	async function showPersonaSelector(ctx: ExtensionContext): Promise<void> {
		const personaNames = Object.keys(personas).sort();

		if (personaNames.length === 0) {
			ctx.ui.notify(
				`No personas defined. Add personas to ${join(getAgentDir(), "personas.json")} or ${join(ctx.cwd, CONFIG_DIR_NAME, "personas.json")}`,
				"warning",
			);
			return;
		}

		const items: SelectItem[] = personaNames.map((name) => {
			const persona = personas[name];
			const isActive = name === activePersonaName;
			return {
				value: name,
				label: isActive ? `${name} (active)` : name,
				description: buildPersonaDescription(persona),
			};
		});

		items.push({
			value: "(none)",
			label: "(none)",
			description: "Clear active persona, restore defaults",
		});

		const result = await ctx.ui.custom<string | null>((tui, theme, _kb, done) => {
			const container = new Container();
			container.addChild(new DynamicBorder((str) => theme.fg("accent", str)));

			container.addChild(new Text(theme.fg("accent", theme.bold("Select Persona"))));

			const selectList = new SelectList(items, Math.min(items.length, 10), {
				selectedPrefix: (text) => theme.fg("accent", text),
				selectedText: (text) => theme.fg("accent", text),
				description: (text) => theme.fg("muted", text),
				scrollInfo: (text) => theme.fg("dim", text),
				noMatch: (text) => theme.fg("warning", text),
			});

			selectList.onSelect = (item) => done(item.value);
			selectList.onCancel = () => done(null);

			container.addChild(selectList);
			container.addChild(new Text(theme.fg("dim", "↑↓ navigate • enter select • esc cancel")));
			container.addChild(new DynamicBorder((str) => theme.fg("accent", str)));

			return {
				render(width: number) {
					return container.render(width);
				},
				invalidate() {
					container.invalidate();
				},
				handleInput(data: string) {
					selectList.handleInput(data);
					tui.requestRender();
				},
			};
		});

		if (!result) return;

		if (result === "(none)") {
			activePersonaName = undefined;
			activePersona = undefined;
			if (originalState) {
				if (originalState.model) {
					await pi.setModel(originalState.model);
				}
				pi.setThinkingLevel(originalState.thinkingLevel);
				pi.setActiveTools(originalState.tools);
			} else {
				pi.setActiveTools(["read", "bash", "edit", "write"]);
			}
			ctx.ui.notify("Persona cleared, defaults restored", "info");
			updateStatus(ctx);
			return;
		}

		const persona = personas[result];
		if (persona) {
			await applyPersona(result, persona, ctx);
			ctx.ui.notify(`Persona "${result}" activated`, "info");
			updateStatus(ctx);
		}
	}

	/**
	 * Update status bar indicator.
	 */
	function updateStatus(ctx: ExtensionContext) {
		if (activePersonaName) {
			ctx.ui.setStatus("persona", ctx.ui.theme.fg("accent", `persona:${activePersonaName}`));
		} else {
			ctx.ui.setStatus("persona", undefined);
		}
	}

	function getPersonaOrder(): string[] {
		return Object.keys(personas).sort();
	}

	async function cyclePersona(ctx: ExtensionContext): Promise<void> {
		const personaNames = getPersonaOrder();
		if (personaNames.length === 0) {
			ctx.ui.notify(
				`No personas defined. Add personas to ${join(getAgentDir(), "personas.json")} or ${join(ctx.cwd, CONFIG_DIR_NAME, "personas.json")}`,
				"warning",
			);
			return;
		}

		const cycleList = ["(none)", ...personaNames];
		const currentName = activePersonaName ?? "(none)";
		const currentIndex = cycleList.indexOf(currentName);
		const nextIndex = currentIndex === -1 ? 0 : (currentIndex + 1) % cycleList.length;
		const nextName = cycleList[nextIndex];

		if (nextName === "(none)") {
			activePersonaName = undefined;
			activePersona = undefined;
			if (originalState) {
				if (originalState.model) {
					await pi.setModel(originalState.model);
				}
				pi.setThinkingLevel(originalState.thinkingLevel);
				pi.setActiveTools(originalState.tools);
			} else {
				pi.setActiveTools(["read", "bash", "edit", "write"]);
			}
			ctx.ui.notify("Persona cleared, defaults restored", "info");
			updateStatus(ctx);
			return;
		}

		const persona = personas[nextName];
		if (!persona) return;

		await applyPersona(nextName, persona, ctx);
		ctx.ui.notify(`Persona "${nextName}" activated`, "info");
		updateStatus(ctx);
	}

	// ─── Event Handlers ─────────────────────────────────────────────────────

	pi.registerShortcut(Key.ctrlShift("u"), {
		description: "Cycle personas",
		handler: async (ctx) => {
			await cyclePersona(ctx);
		},
	});

	// Register /persona command
	pi.registerCommand("persona", {
		description: "Switch persona",
		handler: async (args, ctx) => {
			if (args?.trim()) {
				const name = args.trim();
				const persona = personas[name];

				if (!persona) {
					const available = Object.keys(personas).join(", ") || "(none defined)";
					ctx.ui.notify(`Unknown persona "${name}". Available: ${available}`, "error");
					return;
				}

				await applyPersona(name, persona, ctx);
				ctx.ui.notify(`Persona "${name}" activated`, "info");
				updateStatus(ctx);
				return;
			}

			await showPersonaSelector(ctx);
		},
	});

	// Inject persona instructions into system prompt (fires before every LLM call)
	pi.on("before_agent_start", async (event) => {
		if (activePersona?.instructions) {
			return {
				systemPrompt: `${event.systemPrompt}\n\n${activePersona.instructions}`,
			};
		}
	});

	// Initialize on session start
	pi.on("session_start", async (_event, ctx) => {
		personas = loadPersonas(ctx.cwd);

		const personaFlag = pi.getFlag("persona");
		if (typeof personaFlag === "string" && personaFlag) {
			const persona = personas[personaFlag];
			if (persona) {
				await applyPersona(personaFlag, persona, ctx);
				ctx.ui.notify(`Persona "${personaFlag}" activated`, "info");
			} else {
				const available = Object.keys(personas).join(", ") || "(none defined)";
				ctx.ui.notify(`Unknown persona "${personaFlag}". Available: ${available}`, "warning");
			}
		}

		// Restore persona from session state
		const entries = ctx.sessionManager.getEntries();
		const personaEntry = entries
			.filter((e: { type: string; customType?: string }) => e.type === "custom" && e.customType === "persona-state")
			.pop() as { data?: { name: string } } | undefined;

		if (personaEntry?.data?.name && !personaFlag) {
			const persona = personas[personaEntry.data.name];
			if (persona) {
				activePersonaName = personaEntry.data.name;
				activePersona = persona;
				// Don't re-apply model/tools on restore, just keep the name for instructions
			}
		}

		updateStatus(ctx);
	});

	// Persist persona state each turn
	pi.on("turn_start", async () => {
		if (activePersonaName) {
			pi.appendEntry("persona-state", { name: activePersonaName });
		}
	});
}
