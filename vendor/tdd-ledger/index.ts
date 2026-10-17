// tdd-ledger — forensic TDD record (v1, record-only).
//
// Captures, for every shell/write tool call made in a (sub)agent session:
//   - a snapshot of all .cs files under src/ and tests/ as [rawHash, activeHash]
//     where activeHash = hash of the file with comments stripped.
//   - for `dotnet test` runs: the command, parsed pass/fail result, failed
//     test names, output tail, and git head/dirty.
//
// Why activeHash: the "commented-out implementation" trick leaves rawHash
// different but activeHash identical; the "revert to stub" trick leaves
// activeHash equal to a PRIOR state. The verifier compares these across the
// timeline. The recorder never judges — it only records.
//
// Ledger: /home/ubuntu/.pi/tdd-ledger/<repo-basename>.jsonl (outside repo).
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync, mkdirSync, readFileSync, readdirSync, statSync } from "node:fs";
import { createHash } from "node:crypto";
import { basename, join } from "node:path";
import { execFileSync } from "node:child_process";

const LEDGER_DIR = "/home/ubuntu/.pi/tdd-ledger";
const SHELL_TOOLS = new Set(["bash", "shell", "ctx_shell"]);
const WRITE_TOOLS = new Set(["write", "edit", "ctx_edit", "ctx_write", "ctx_patch", "ctx_fill", "apply_patch"]);
const SKIP_DIRS = new Set(["bin", "obj", ".git", "node_modules", ".vs"]);

function sha(s: string): string {
  return createHash("sha256").update(s).digest("hex").slice(0, 32);
}

// Single-pass comment stripper that copies string/char literals verbatim.
// Not a full C# parser; CONSISTENCY across states is what matters for diffs.
function stripComments(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      i = src.indexOf("\n", i);
      i = i === -1 ? n : i;
      continue;
    }
    if (c === "/" && d === "*") {
      i = src.indexOf("*/", i + 2);
      i = i === -1 ? n : i + 2;
      continue;
    }
    if (c === '"' || c === "'") {
      const q = c;
      out += c;
      i++;
      while (i < n && src[i] !== q) {
        if (src[i] === "\\") {
          out += src[i] + (src[i + 1] ?? "");
          i += 2;
          continue;
        }
        out += src[i];
        i++;
      }
      if (i < n) {
        out += src[i];
        i++;
      }
      continue;
    }
    out += c;
    i++;
  }
  return out;
}

function walkCs(dir: string, rel: string, acc: string[], depth: number) {
  if (depth > 4) return;
  let entries: string[] = [];
  try {
    entries = readdirSync(dir);
  } catch {
    return;
  }
  for (const e of entries.sort()) {
    if (SKIP_DIRS.has(e) || e.startsWith(".")) continue;
    const p = join(dir, e);
    const r = rel ? rel + "/" + e : e;
    let st;
    try {
      st = statSync(p);
    } catch {
      continue;
    }
    if (st.isDirectory()) walkCs(p, r, acc, depth + 1);
    else if (e.endsWith(".cs")) acc.push(r);
  }
}

// Returns { relpath: [rawHash, activeHash] } or null if snapshot failed.
function snapshot(cwd: string): Record<string, [string, string]> | null {
  const files: string[] = [];
  walkCs(join(cwd, "src"), "src", files, 0);
  walkCs(join(cwd, "tests"), "tests", files, 0);
  const out: Record<string, [string, string]> = {};
  for (const f of files) {
    try {
      const c = readFileSync(join(cwd, f), "utf8");
      out[f] = [sha(c), sha(stripComments(c))];
    } catch {
      /* unreadable file: skip */
    }
  }
  return Object.keys(out).length ? out : null;
}

function textOf(content: unknown): string {
  try {
    if (Array.isArray(content)) {
      return content.map((c: any) => (c && typeof c.text === "string" ? c.text : "")).join("");
    }
    return String(content ?? "");
  } catch {
    return "";
  }
}

function parseTestOutput(output: string): Record<string, unknown> | null {
  const m = output.match(/(Passed|Failed)!\s*-\s*Failed:\s*(\d+),\s*Passed:\s*(\d+)/);
  if (!m) {
    if (/error\s+CS\d+|Build FAILED/i.test(output)) return { buildFailed: true };
    return null;
  }
  const res: Record<string, unknown> = {
    ok: m[1] === "Passed",
    failed: parseInt(m[2], 10),
    passed: parseInt(m[3], 10),
  };
  const failedNames = [...output.matchAll(/^\s{2}Failed (\S+) \[/gm)].map((x) => x[1]);
  if (failedNames.length) res.failedTests = failedNames.slice(0, 25);
  const passedNames = [...output.matchAll(/^\s{2}Passed (\S+) \[/gm)].map((x) => x[1]);
  if (passedNames.length) res.passedTests = passedNames.slice(0, 50);
  return res;
}

function gitInfo(cwd: string): { head: string; dirty: boolean } | null {
  try {
    const head = execFileSync("git", ["rev-parse", "--short", "HEAD"], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const dirty = execFileSync("git", ["status", "--porcelain"], {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim().length > 0;
    return { head, dirty };
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  pi.on("tool_result", (event: any, ctx: any) => {
    try {
      const tool: string = event?.toolName ?? "";
      const isShell = SHELL_TOOLS.has(tool);
      const isWrite = WRITE_TOOLS.has(tool);
      if (!isShell && !isWrite) return;
      const input: any = event?.input ?? {};
      const cwd: string = ctx?.cwd ?? process.cwd();
      let sid: string | null = null;
      try {
        sid = ctx?.sessionManager?.getSessionId?.() ?? null;
      } catch {
        sid = null;
      }

      const entry: Record<string, unknown> = {
        ts: new Date().toISOString(),
        sid,
        tool,
        files: snapshot(cwd),
      };

      if (isShell) {
        const cmd: string = typeof input.command === "string" ? input.command : "";
        entry.cmd = cmd.slice(0, 500);
        entry.kind = "cmd";
        if (/dotnet\s+test/i.test(cmd)) {
          const out = textOf(event?.content);
          const parsed = parseTestOutput(out);
          if (parsed) {
            entry.test = parsed;
            entry.outTail = out.slice(-1200);
            entry.git = gitInfo(cwd);
            entry.kind = parsed.buildFailed ? "build-failed" : "test";
          } else {
            entry.testError = true;
          }
        }
      } else {
        entry.kind = "state";
        entry.path = typeof input.path === "string" ? input.path : null;
      }

      const ledger = join(LEDGER_DIR, basename(cwd) + ".jsonl");
      mkdirSync(LEDGER_DIR, { recursive: true });
      appendFileSync(ledger, JSON.stringify(entry) + "\n");
    } catch {
      // Ledger must never break the session.
    }
  });
}
