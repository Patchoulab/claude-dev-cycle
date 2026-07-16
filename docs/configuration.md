# Configuration — `.claude/dev-cycle.json`

Every skill reads an optional per-repo manifest at `<repo-root>/.claude/dev-cycle.json`.
The file is optional: with no manifest, each skill falls back to documented
defaults and says so. Shared/cross-skill keys live at the top level; each skill's
private tunables live in one camelCase block named for the skill.

`scheduled-jobs` deliberately has no block here — its config lives per-job under
`~/.claude/dev-cycle/jobs/jobs/<name>/job.json` (see docs/skills/scheduled-jobs.md).

## Annotated example

```jsonc
{
  // ── shared core ──────────────────────────────────────────────────────────
  "canonicalRoot": "~/projects/my-app",       // the one true absolute repo root
  "retiredPaths": ["~/old/my-app"],            // known-dead path variants agents must not probe
  "submodules": [                              // omit/empty → plain-repo mode everywhere
    { "path": "packages/core", "remote": "origin", "defaultBranch": "main" }
  ],
  "handoffFile": ".claude/dev-cycle/next-session.md",  // session-handoff, project-planning, capture-workflow
  "progressFile": ".claude/dev-cycle/progress.md",     // the running progress log
  "structureChecker": "tools/check_structure.py",      // run by finish-branch / capture-workflow when present
  "preauthorized": [                           // standing grants — skills act instead of asking
    "push-to-origin",
    "merge-pr-after-green-review",
    "gitlink-bump",
    "branch-cleanup",
    "commit-approved-artifacts"
    // History rewrites (rebase -i, filter-repo, force-push to shared branches)
    // are NEVER a preauthorizable class.
  ],
  "botsToIgnore": ["vercel[bot]"],             // pr-monitor comment filter + finish-branch preflight

  // ── shared singles owned by one skill ────────────────────────────────────
  "mergeStrategy": "merge",                    // finish-branch: merge | squash | rebase
  "kickoff": [],                               // handoff:resume applies these Skill/command invocations at session start

  // ── per-skill blocks ─────────────────────────────────────────────────────
  "prMonitor": { "speak": false },
  "review":    { "enabled": false, "model": "sonnet", "maxTurns": 40,
                 "timeoutSeconds": 900, "dedupTtlSeconds": 3600, "maxDiffBytes": 204800,
                 "monorepoHint": "", "neverSkipGlobs": [], "verification": { "required": true } },
  "planning":  { "roadmapFile": "ROADMAP.md", "plansDir": "plans", "bundlesDir": "bundles",
                 "projectRoots": ["~/projects"], "memoryDirs": [], "clusters": [],
                 "excludeDirs": ["node_modules", ".git", ".venv", "dist"],
                 "executor": "current-opus", "maxSurveyAgents": 6, "staleClaimDays": 7 },
  "whitepaper":{ "siteDir": "presentation-site", "aesthetic": "", "brandKit": "",
                 "allowlistFile": ".claude/whitepaper-allowlist.json",
                 "extraSources": [], "excludeSources": [], "publishSkill": "" },
  "demoPrep":  { "audience": "", "locales": ["en"], "themes": ["light", "dark"],
                 "presentation": {}, "github": {}, "audit": {} },
  "captureWorkflow": { "pluginRepo": "", "playbookDir": "docs/playbooks", "defaultScope": "project" }
}
```

## Shared-core keys

| Key | Type | Default | Consumed by |
|---|---|---|---|
| `canonicalRoot` | string (abs path) | repo toplevel | all skills — the one true path for spawned agents |
| `retiredPaths` | string[] | `[]` | finish-branch, review-gate — dead path variants to never probe |
| `submodules` | object[] | `[]` (plain-repo mode) | finish-branch, worktree-sessions, review-gate |
| `handoffFile` | string (rel path) | `.claude/dev-cycle/next-session.md` | session-handoff, project-planning, capture-workflow |
| `progressFile` | string (rel path) | `.claude/dev-cycle/progress.md` | session-handoff, finish-branch, capture-workflow |
| `structureChecker` | string (rel path) | none | finish-branch, capture-workflow (run when present) |
| `preauthorized` | string[] | `[]` (always ask) | finish-branch, pr-monitor, worktree-sessions, capture-workflow |
| `botsToIgnore` | string[] | `["vercel[bot]"]` | pr-monitor, finish-branch |
| `mergeStrategy` | `merge`\|`squash`\|`rebase` | `merge` | finish-branch |
| `kickoff` | string[] | `[]` | session-handoff (`handoff:resume` runs each at session start) |

`preauthorized` is the standing-grant registry: when an action's class is listed,
the skill performs it and reports rather than asking. Anything not listed still
asks. History rewrites are never a valid class.

## Per-skill blocks

Field semantics live in each skill's doc:

- `prMonitor` → [docs/skills/pr-monitor.md](skills/pr-monitor.md)
- `review` → [docs/skills/review-gate.md](skills/review-gate.md)
- `planning` → [docs/skills/project-planning.md](skills/project-planning.md)
- `whitepaper` → [docs/skills/repo-whitepaper.md](skills/repo-whitepaper.md)
- `demoPrep` → [docs/skills/demo-prep.md](skills/demo-prep.md)
- `captureWorkflow` → [docs/skills/capture-workflow.md](skills/capture-workflow.md)
