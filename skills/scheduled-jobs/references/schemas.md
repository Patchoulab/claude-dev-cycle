# scheduled-jobs data contracts

## job.json

```jsonc
{
  "version": 1,
  "name": "tool-audit",
  "description": "Verify the tool-update script's methods against current vendor docs; patch what is provably outdated.",
  "created": "2026-07-02",
  "schedule": {
    "backend": "launchd",                    // launchd | cron | scheduled-agent
    "calendar": { "Hour": 9, "Minute": 0 },  // launchd StartCalendarInterval
    "period_hours": 24,                      // watchdog uses this for gap math
    "unit_path": "~/Library/LaunchAgents/com.example.scheduled-jobs.tool-audit.plist"  // label prefix resolved at scaffold time (@LABEL_PREFIX@)
  },
  "ttl_days": 30,                            // default staleness for items
  "max_runtime_s": 1800,                     // wrapper kills claude past this
  "writes_allowed": [                        // ONLY paths the job may patch;
    "~/scripts/update-tool.sh"     // [] means report-only
  ],
  "inputs": [                                // linted for existence pre-launch
    "~/scripts/update-tool.sh",
    "~/scripts/tool-registry.json"
  ],
  "expected_artifacts": [                    // watchdog mtime checks, relative
    "reports/report-{RUN_DATE}.md",          //   to job dir unless absolute
    "reports/summary-{RUN_DATE}.json"
  ],
  "health": { "min_duration_s": 5, "min_turns": 3, "max_gap_factor": 2.0 },
  "notify": {
    "on": ["material_change", "failure", "lint_fail", "launch_fail"],
    "channels": ["macos"]                    // macos | tts | both
  },
  "claude": { "model": "sonnet", "extra_args": [] }
}
```

## state.json

```jsonc
{
  "version": 1,
  "job": "tool-audit",
  "updated": "2026-07-02T09:04:12Z",         // written back by the Claude run
  "items": {
    "wrangler": {
      "kind": "cli-tool",                     // job-defined taxonomy
      "status": "OK",                         // OK | OUTDATED | CHANGED | UNKNOWN | FAILED
      "last_verified": "2026-06-29",          // ISO date of last successful research
      "source_url": "https://developers.cloudflare.com/workers/wrangler/install-and-update/",
      "method": "npm install -g wrangler@latest",  // cached verified knowledge
      "consecutive_failures": 0,
      "notes": ""
    }
    // ... one entry per known item
  },
  "ignored": {                                // conservative-fallback bucket
    ".docker": { "reason": "app-config, not a CLI tool", "added": "2026-06-02" }
  },
  "seen": {                                   // detection memory (discovery-class
    ".config": "2026-06-02"                   //   jobs): item -> first-seen date
  }
}
```

## Report contract

- Human report: `reports/report-YYYY-MM-DD.md`, skeleton mandated in step 7 above. Never overwritten across days; a same-day re-run overwrites that day's file (idempotent by date).
- Machine summary: `reports/summary-YYYY-MM-DD.json`, schema in step 8. This is the wrapper's single source of truth for notify decisions; the human report is never parsed.
- Diff: `reports/diff-YYYY-MM-DD.txt` (unified diff vs the previous dated report), produced by the wrapper.
- `reports/latest.md` symlink for humans and legacy consumers.

## runs.jsonl

```json
{"run_id":"20260702T090003Z","started":"2026-07-02T09:00:03Z","ended":"2026-07-02T09:05:11Z","duration_s":308,"status":"SUCCESS","exit_code":0,"num_turns":41,"note":"1 material change(s)"}
```

`status` enum: `SUCCESS | PARTIAL | FAILED | NOTHING_TO_DO | LINT_FAIL | LAUNCH_FAIL`. `NOTHING_TO_DO` records are the audit trail proving detection ran and found nothing — the exact evidence that was missing when the discovery job fired vacuously for 30 days.

## Per-job settings.json

Starts from the review-gate unattended-agent recipe (cross-skill contract): read-only git/ls/rg allowlist plus `Bash(jq:*)` (no curl), `WebSearch`/`WebFetch` allowed only if the interview said the job researches, `Edit`/`Write` allowed only on `writes_allowed` paths plus the job's own state/report paths, everything else default-deny. Rationale: permission prompts are fatal to unattended runs — an unexpected "This command requires approval" stalls a headless session with no one to answer it.
