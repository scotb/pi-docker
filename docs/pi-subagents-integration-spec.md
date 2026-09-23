# pi-subagents Integration Specification

**Status**: Draft  
**Date**: 2025-08-09  
**Author**: Lead  
**Goal**: Enable sub-agent delegation with context isolation and monitoring, compatible with single-GPU llama-swap setup.

---

## 1. Why pi-subagents

### The Problem

- Current persona switching keeps all history in one context session.
- 55% of lead's context is consumed by work that could be delegated.
- Coder context bloats during large implementations.
- Architect has only ~40k context — can't do deep codebase exploration.

### The Solution

Sub-agents get **fresh or forked context**, keeping the lead session lean. Only structured results flow back to the lead.

---

## 2. llama-swap Compatibility

### How it works

Each sub-agent spawn creates a new Pi process that makes its own API call through llama-swap. llama-swap queues requests per-model (FIFO).

### Swap pattern for your setup

```
Lead holds "lead" model in VRAM
  ↓
Lead spawns scout (request queued for "researcher")
  ↓
llama-swap queues → swaps lead→researcher → loads researcher model
  ↓
Scout runs, returns compact result
  ↓
llama-swap swaps researcher→lead → reloads lead model
  ↓
Lead reviews, decides next step
```

### Swap timing

| Step | Model swap? | Wait time |
|------|-------------|-----------|
| Lead clarifies | No | 0s |
| Scout (researcher) | lead→researcher | ~3-10s |
| Worker (fork, coder) | **None** — same model as lead | 0s |
| Reviewer (reviewer) | coder→reviewer | ~3-10s |
| Worker (fork, coder) | reviewer→coder | ~3-10s |

**Key optimization**: Using `context: "fork"` for workers means the child uses the same model as the lead (coder), avoiding a model swap entirely.

### Configuration

```json
// ~/.pi/agent/extensions/subagent/config.json
{
  "parallel": {
    "concurrency": 1,
    "maxTasks": 4
  },
  "intercomBridge": {
    "mode": "always"
  }
}
```

- `concurrency: 1` — prevents queue thrashing on single-GPU
- `intercomBridge: "always"` — enables relay questions (two-way communication)

---

## 3. Model Routing

### Configuration

```json
// ~/.pi/agent/settings.json (add to existing)
{
  "subagents": {
    "defaultModel": "llama-swap/coder",
    "agentOverrides": {
      "scout": {
        "model": "llama-swap/researcher",
        "defaultContext": "fresh"
      },
      "worker": {
        "model": "llama-swap/coder",
        "defaultContext": "fork"
      },
      "reviewer": {
        "model": "llama-swap/reviewer",
        "defaultContext": "fork"
      },
      "oracle": {
        "model": "llama-swap/architect",
        "defaultContext": "fork"
      }
    }
  }
}
```

### Rationale

| Agent | Model | Context | Why |
|-------|-------|---------|-----|
| scout | researcher | fresh | Needs clean slate to explore codebase without lead's history |
| worker | coder | fork | Same model as lead → no llama-swap swap. Fork gives access to lead's history for context without the full weight |
| reviewer | reviewer | fork | Same model as worker → no swap. Fork gives access to diff/plan context |
| oracle | architect | fork | Same model as worker → no swap. Fork for context on design questions |

### Context modes

| Mode | What child sees | Use when |
|------|-----------------|----------|
| `fresh` | Only the task prompt | Deep exploration, independent analysis, scout/researcher |
| `fork` | Branched from parent's current leaf | Workers/reviewers that need context on what was discussed |

---

## 4. Agent Contracts

### scout (researcher)

- **Role**: Fast codebase reconnaissance
- **Tools**: read, bash, grep, find, ls, web_search, fetch_content
- **Output**: Structured report — entry points, data flow, risks, recommended next steps
- **Context**: fresh
- **No file edits**

### worker (coder)

- **Role**: Implementation work
- **Tools**: read, bash, edit, write
- **Output**: Completed implementation + `<final_answer>` block with summary
- **Context**: fork
- **Follows approved plan**

### reviewer

- **Role**: Independent code review
- **Tools**: read, bash, grep, find, ls
- **Output**: Structured review — correctness, edge cases, performance, readability
- **Context**: fork
- **Read-only** — never modifies source files

### oracle (architect)

- **Role**: Second opinion on design decisions
- **Tools**: read, bash, grep, find, ls
- **Output**: Analysis with alternatives considered, risks, recommendation
- **Context**: fork
- **Advisory only** — does not implement

---

## 5. Workflow Patterns

### Pattern 1: Full Feature (Clarify → Scout → Worker → Reviewer)

```
Lead clarifies requirements
  ↓
scout: "Map the auth flow, identify entry points and risks"
  ↓
Lead reviews scout report, creates plan
  ↓
worker: "Implement auth middleware per plan. See: [plan.md]"
  ↓
reviewer: "Review the auth middleware for security and correctness"
  ↓
worker: "Fix the issues identified in review" (if needed)
```

**Lead prompts:**

```
# After clarifying
Use scout to understand the auth flow. Focus on entry points, data flow, and potential risks.

# After scout returns
Based on the scout report, create a plan and save it to docs/plan.md.

# After plan approved
Use worker to implement the auth middleware. Follow the plan at docs/plan.md.

# After implementation
Run a reviewer to check the auth middleware implementation for security and correctness.
```

### Pattern 2: Quick Fix (Worker Only)

```
Lead identifies issue
  ↓
worker: "Fix the bug in src/auth.ts line 42"
```

**Lead prompt:**

```
Use worker to fix the token validation bug in src/auth.ts:42. The issue is [description].
```

### Pattern 3: Parallel Review

```
worker: "Implement feature X"
  ↓
parallel reviewers:
  - "Review for security issues"
  - "Review for edge cases"
  - "Review for test coverage"
  ↓
Lead synthesizes feedback
  ↓
worker: "Apply fixes from review"
```

**Lead prompt:**

```
Run parallel reviewers on the auth middleware: one for security, one for edge cases, one for test coverage.
```

### Pattern 4: Research Deep-Dive

```
Lead identifies unknown
  ↓
scout: "Research the current caching strategy and alternatives"
  ↓
scout can ask lead clarification questions via relay
  ↓
scout returns research brief
```

**Lead prompt:**

```
Use scout to research our current caching strategy and alternatives. Ask me if you need clarification on the requirements.
```

---

## 6. Monitoring & Recovery

### The Guardrails

pi-subagents has **built-in monitoring** that handles stuck agents without user intervention:

#### 6.1 Turn Budgets

```javascript
runs.run("worker", {
  agent: "worker",
  task: "Implement the auth middleware",
  turnBudget: {
    maxTurns: 25,  // Warn the child at 25 turns
    graceTurns: 2   // Hard abort after 27 turns
  }
})
```

- At `maxTurns`: child is warned to wrap up
- At `maxTurns + graceTurns`: hard abort, partial output returned
- **Best for**: bounded, well-scoped tasks

#### 6.2 Wall-Clock Timeouts

```javascript
runs.run("worker", {
  agent: "worker",
  task: "Implement the auth middleware",
  timeoutMs: 900000  // 15 minutes
})
```

- Cuts off the child after wall-clock time expires
- **Best for**: unbounded tasks where turn count is unpredictable

#### 6.3 Long-Running Guard (Auto-Attention)

```javascript
runs.run("worker", {
  agent: "worker",
  task: "Implement the auth middleware",
  control: {
    needsAttentionAfterMs: 600000,  // 10 minutes of silence
    notifyOn: ["needs_attention"]
  }
})
```

- If no observable activity for `needsAttentionAfterMs`, emits `needs_attention` notice
- Lead sees: "Worker is stuck — no activity in 10 minutes"
- Lead can: steer, resume, interrupt, or stop

#### 6.4 Mutating Failure Tracking

pi-subagents tracks consecutive file-edit failures:
- If a worker fails to apply an edit 3 times → escalation notice
- Detects repeated tool failures and patterns
- Includes summary of recent failures in the notice

#### 6.5 FleetView (Live Dashboard)

```
subagent({ action: "status" })           // All active runs
subagent({ action: "status", id: "..." }) // One run with details
subagent({ action: "status", view: "fleet" }) // Full fleet dashboard
```

Shows per-child:
- Current model and thinking level
- Context mode (fresh/fork)
- Turn count, token count, elapsed time
- Current tool being used
- Recent activity

### Recovery Actions

| Action | Use When | Effect |
|--------|----------|--------|
| `steer` | Agent is drifting, needs redirection | Sends guidance to running child |
| `interrupt` | Agent is clearly stuck | Pauses the child turn (soft abort) |
| `stop` | Agent is unresponsive | Cancels the run entirely |
| `resume` | Agent paused, needs new instructions | Revives child with follow-up |

**Recovery example:**

```javascript
// Lead detects worker stuck
subagent({ action: "interrupt", id: "worker-run-123" })

// Lead gives clearer instructions
subagent({ action: "resume", id: "worker-run-123", message: "You were stuck on the validation step. Focus only on auth middleware, skip the tests for now." })
```

### Recommended Guardrail Configuration

```json
// ~/.pi/agent/extensions/subagent/config.json
{
  "parallel": {
    "concurrency": 1,
    "maxTasks": 4
  },
  "intercomBridge": {
    "mode": "always"
  },
  "fleetView": true,
  "forceTopLevelAsync": false
}
```

And in agent definitions (optional, for additional safety):

```yaml
---
# ~/.pi/agent/agents/worker.md
name: worker
description: Implementation work
---
# Add to agent instructions:
# BOUNDARY: You have a max of 25 turns. If you haven't finished by turn 20, 
# summarize what you've done, what's remaining, and recommend next steps.
---
```

---

## 7. Two-Way Communication (Relay Questions)

### How It Works

Children can ask the lead for decisions without the lead having to orchestrate every step:

```
Lead spawns worker with:
  "Implement the auth middleware. If you encounter ambiguous requirements, 
   ask me through the relay channel instead of guessing."

Worker runs, encounters ambiguity:
  Worker raises: relay_question: "Should auth use JWT or session-based?
                          Current codebase uses sessions but the plan mentions JWT."

Lead reads the question (appears as a notification), replies:
  "Use JWT. It matches the new auth plan."

Worker continues with clarified direction.
```

### When Children Ask

| Reason | Meaning |
|--------|---------|
| `need_decision` | Blocking decision — can't continue without user input |
| `interview_request` | Needs structured input (multiple questions) |
| `progress_update` | Non-blocking — something important changed the plan |

### Lead Prompts for Two-Way

```
Use scout to analyze the codebase. If you need clarification on requirements, 
use the relay channel to ask me instead of guessing.

Have worker implement the feature. If you hit ambiguous areas, escalate them 
via relay rather than making assumptions.
```

---

## 8. Installation

### Step 1: Install pi-subagents

```bash
pi install npm:pi-subagents
```

### Step 2: Verify Installation

```bash
pi /subagents-doctor
```

Expected: All checks pass (runtime paths, discovery, async support, intercom bridge).

### Step 3: Configure Model Routing

Add to `~/.pi/agent/settings.json`:

```json
{
  "subagents": {
    "defaultModel": "llama-swap/coder",
    "agentOverrides": {
      "scout": {
        "model": "llama-swap/researcher",
        "defaultContext": "fresh"
      },
      "worker": {
        "model": "llama-swap/coder",
        "defaultContext": "fork"
      },
      "reviewer": {
        "model": "llama-swap/reviewer",
        "defaultContext": "fork"
      },
      "oracle": {
        "model": "llama-swap/architect",
        "defaultContext": "fork"
      }
    }
  }
}
```

### Step 4: Configure Subagent Runtime

Create `~/.pi/agent/extensions/subagent/config.json`:

```json
{
  "parallel": {
    "concurrency": 1,
    "maxTasks": 4
  },
  "intercomBridge": {
    "mode": "always"
  },
  "fleetView": true
}
```

### Step 5: Restart Pi

```bash
# Restart the Pi session to pick up configuration
```

### Step 6: Test

```
# Try a simple scout delegation
Use scout to map the entry points in this project.
```

---

## 9. Testing Checklist

After installation, verify:

- [ ] `pi /subagents-doctor` passes all checks
- [ ] `Use scout to list the main directories in this project` returns a structured result
- [ ] `Ask oracle to review our current project structure and challenge the architecture` returns analysis
- [ ] `Use worker to create a file called /tmp/test-subagent.md with the text 'test'` creates the file
- [ ] `Run a reviewer to check the test file` provides review output
- [ ] FleetView shows active runs (if using TUI)
- [ ] No llama-swap errors in output (model swaps working correctly)

---

## 10. Rollback

If something goes wrong:

```bash
# Uninstall pi-subagents
pi uninstall npm:pi-subagents

# Remove configuration
rm ~/.pi/agent/extensions/subagent/config.json

# Remove model overrides from settings
# (Manually edit ~/.pi/agent/settings.json to remove subagents section)

# Restart Pi
```

The llama-swap configuration is unaffected.

---

## Appendix A: Common Lead Prompts Cheat Sheet

| Goal | Prompt |
|------|--------|
| Understand codebase | "Use scout to map the [feature/area]. Focus on entry points, data flow, and risks." |
| Implement feature | "Use worker to implement [feature] following this plan: [plan.md]" |
| Quick fix | "Use worker to fix the bug in [file:line]. The issue is: [description]" |
| Review code | "Run a reviewer to check [component] for correctness, edge cases, and test coverage." |
| Parallel review | "Run parallel reviewers: one for security, one for tests, one for readability." |
| Design decision | "Ask oracle to review this approach and challenge assumptions: [approach]" |
| Research topic | "Use scout to research [topic]. Ask me if you need clarification." |
| Implementation loop | "Have worker implement the approved plan, then run reviewers and apply fixes." |
| Check progress | "Show me the current async runs." or "subagent status" |
| Fix stuck agent | "Interrupt run [id] and steer: [clearer instructions]" |

## Appendix B: Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2025-08-09 | Use orchestrator→worker pattern, not P2P | Single-GPU llama-swap constraints; lead manages model swaps deliberately |
| 2025-08-09 | `context: "fork"` for workers | Same model as lead → no llama-swap swap needed |
| 2025-08-09 | `concurrency: 1` | Prevent queue thrashing on single-GPU |
| 2025-08-09 | Install pi-subagents, not custom build | Matt Pocock's implementation saves weeks of work; covers 90% of needs |
| 2025-08-09 | Keep persona switching for interactive mode | Personas handle interactive switching; sub-agents handle delegated background work |
