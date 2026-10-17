---
name: "pi-subagents-workflow"
description: "Correct patterns for using pi-subagents: no interrupting children, no gate/acceptance on read-only tasks, wait for needs_attention signals before intervening"
version: 1
created: "2026-08-10"
updated: "2026-08-10"
---
## When to Use
When launching any subagent or managing subagent workflows

## Procedure
1. Launch subagents via: subagent({ workflowScript: `return runs.run('key', { agent: 'agent-name', cwd: '/path', mission: false, context: 'fork', task: 'Plain text task.' })` })
2. NEVER pass gate= or acceptance= for investigation/read-only tasks — this triggers acceptance verification that fails before the task completes
3. NEVER pass worktree:true unless git working tree is clean
4. NEVER pass turnBudget or hard toolBudget to mutation-capable children
5. For read-only scouts/research, use mission: false (no mission tracking needed)
6. Use simple ASCII task strings without backslashes, ampersands, or other JS-breaking characters
7. After launching an async child, DO NOT call subagent_wait() or subagent({ action: 'status' }) immediately — return control to the user and let Pi wake you on completion
8. Only use subagent_wait() when the current request is run-to-completion (user asked you to stay with the task and report results, or a skill must finish in one turn)
9. When you DO need to wait, use subagent_wait({ id: '...', nonBlocking: true }) to arm a subscription and return immediately, then check status later
10. DO NOT interrupt/resume/stop children just because they produce no output for a few minutes — silence is normal during long tool calls. The docs say: 'Do not interrupt just because a child has briefly produced no output.'
11. Only intervene when you see an actual needs_attention or failed signal from subagent status
12. For worker/implementation: omit turnBudget and toolBudget entirely — the docs say: 'do not pass turnBudget, a hard toolBudget, or a tight usageBudget to mutation-capable workers'
13. For complex multi-step workflows, use the Fable mode sequence: scout → oracle → worker → reviewer → worker (fix) → reviewer (final)

## Pitfalls
- No notable pitfalls recorded yet.

## Verification
1. Subagent completes without failure or interruption
2. Child reports success/failure status without needing manual intervention
3. Output is available and complete when retrieved via subagent status