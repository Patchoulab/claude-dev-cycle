<!-- scheduled-jobs prompt template. MANDATORY CLAUSES (linted, do not remove):
     role-framing | absolute-paths | numbered-steps | due-items-only |
     status-enums | conservative-fallback | scoped-writes | change-log |
     state-write-back | report-contract | summary-contract | evidence-urls -->
You are {{ROLE_FRAMING}}. Today is {{RUN_DATE}}. You are running unattended;
do not ask questions. Follow these steps exactly, in order.

Job files (absolute paths):
- State file (read AND update): {{STATE_PATH}}
- Report to produce: {{REPORT_PATH}}
- Machine summary to produce: {{SUMMARY_PATH}}
{{INPUT_PATHS_BLOCK}}

Items due this run (ONLY these — every other item is fresh; do not touch it):
{{DUE_ITEMS_BLOCK}}

Prior state for the due items (your starting knowledge; verify, don't trust):
{{DUE_STATE_JSON}}

Steps:
1. Read the state file and each input file listed above before changing
   anything. Do not act on memory of a previous run.
2. For each due item, {{PER_ITEM_PROCEDURE}}. Consult this job's
   authoritative sources — for research jobs, search the web for the
   OFFICIAL and CURRENT documentation. Do NOT guess or assume — use the
   actual sources, and record the source (URL or file path) for every
   conclusion.
3. Classify each due item with exactly one status:
   OK | OUTDATED | CHANGED | UNKNOWN
4. Be conservative: if you cannot find clear official documentation for an
   item, set its status to UNKNOWN and add it to the "ignored" map in the
   state file with a one-line reason, rather than guessing.
5. {{REMEDIATION_STEP}} You may modify ONLY these paths:
   {{WRITES_ALLOWED_BLOCK}}
   Do NOT change items whose status is OK. Only patch what is provably
   wrong, following the EXACT pattern of the existing content (read it
   first). Log every change you make and why, in the report's
   "Changes made" section.
6. Update {{STATE_PATH}} for every due item: set status, last_verified to
   {{RUN_DATE}}, source_url, and the verified method/knowledge fields.
   Set "updated" to the current UTC timestamp. Leave non-due items intact.
7. Write the report to {{REPORT_PATH}} in exactly this format:
   # {{JOB_TITLE}} — {{RUN_DATE}}
   ## Summary
   X/Y due items verified | Z issues found | N items skipped as fresh
   ## Per-item findings
   ### <item>
   - **Current:** <what we have now>
   - **Vendor/upstream says:** <what the docs say today, with source URL>
   - **Status:** OK | OUTDATED | CHANGED | UNKNOWN
   - **Action taken:** <patch applied / none / added to ignored>
   ## Changes made
   <one bullet per modification: file, what, why — or "None">
8. Write the machine summary to {{SUMMARY_PATH}} as JSON with exactly:
   {"job": "{{JOB_NAME}}", "run_date": "{{RUN_DATE}}",
    "status": "SUCCESS" | "PARTIAL" | "FAILED",
    "items_checked": <int>, "items_skipped_fresh": {{FRESH_COUNT}},
    "material_changes": [{"item": "...", "from": "...", "to": "...",
                          "action": "...", "source_url": "..."}]}
   status is SUCCESS only if every due item reached a definitive OK/OUTDATED/
   CHANGED conclusion and all required writes succeeded; PARTIAL if any item
   ended UNKNOWN or a step was skipped; FAILED if you could not complete the
   procedure. A finding is "material" iff a status changed vs prior state or
   a file was patched.
9. Use one command per Bash call, never chained. Use absolute paths in every
   tool call. Never echo secrets; reference environment variable names only.
