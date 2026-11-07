---
name: "aidlc-setup"
description: "Set up the AWS AI-DLC v1 workflow in a repo: copy the baked rule files to .aidlc-rule-details/, place core-workflow.md at .aidlc-rules/, and add the workflow pointer to AGENTS.md. Use when asked to 'set up AI-DLC', 'add AI-DLC to this repo', 'adopt the AWS AI-DLC workflow', or 'configure AI-DLC'."
version: 1.0.0
created: "2026-11-07"
updated: "2026-11-07"
---
## When to Use
Use when asked to set up, add, adopt, or enable the AWS AI-DLC workflow in a repo. The setup is idempotent — re-running refreshes the rule files and leaves an existing pointer alone.

## Procedure
1. Verify the baked source: `/opt/aidlc-rules/aws-aidlc-rules/core-workflow.md` and `/opt/aidlc-rules/aws-aidlc-rule-details/` must exist (pin recorded in `/opt/aidlc-rules.sha`). If missing, stop and report — do not fetch from the network.
2. Find the repo root (git root of the working directory).
3. Copy the rule details into the repo:
   ```
   mkdir -p <root>/.aidlc-rule-details
   cp -a /opt/aidlc-rules/aws-aidlc-rule-details/. <root>/.aidlc-rule-details/
   cp /opt/aidlc-rules/VERSION <root>/.aidlc-rule-details/VERSION
   ```
   Overwriting existing files is intended — a re-run updates a stale copy.
4. Copy the workflow file:
   ```
   mkdir -p <root>/.aidlc-rules
   cp /opt/aidlc-rules/aws-aidlc-rules/core-workflow.md <root>/.aidlc-rules/core-workflow.md
   ```
5. Wire the pointer: if `<root>/AGENTS.md` has no `## AI-DLC workflow` section, append exactly:
   ```
   ## AI-DLC workflow
   When the user requests software development, read `.aidlc-rules/core-workflow.md` and follow it — it overrides other workflows.
   ```
   Create `AGENTS.md` if it does not exist. Never replace or rewrite existing AGENTS.md content.
6. Verify and report: `.aidlc-rule-details/` contains `common/`, `inception/`, `construction/`, `extensions/`, `operations/` plus `VERSION`; `core-workflow.md` is in place; the AGENTS.md pointer is present. Report the pin SHA from `/opt/aidlc-rules.sha`.

## Pitfalls
- Never paste `core-workflow.md` (~540 lines) into `AGENTS.md` — the pointer is the contract. The workflow loads lazily when development work starts, not on every turn.
- Copy the files into the repo; do not symlink to `/opt`. `core-workflow.md` resolves rule details relative to the repo, and the repo must stay self-contained (it also works in other harnesses unchanged).
- The baked layout mirrors upstream on purpose: rule details land at `.aidlc-rule-details/`, which is already an entry in `core-workflow.md`'s resolution order — no file modification is needed.
