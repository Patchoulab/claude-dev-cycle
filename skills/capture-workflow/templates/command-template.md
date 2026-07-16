---
description: Start a <workflow> (<typical variations>), preloaded with the <domain> playbook + workflow.
argument-hint: e.g. "<realistic example argument>"
---

You are starting a <workflow> for <scope/system>.

The request: **$ARGUMENTS**

Before designing anything, read the playbook so you have the full
context — boundaries, the pipeline, the gotchas:

**Read first:** `<repo-relative path to playbook>`

Then follow the workflow it describes:

1. <Step — include the brainstorm/spec gates the original used>
2. <Recon/verify-before-build step with the concrete check>
3. <Build steps, referencing the pipeline scripts by repo-relative path>
4. <Verification step with the exact success criterion>
5. <Journal/register step>

Respect the boundaries: <secrets rule>, <commit/approval rule>,
<anything approval-gated surfaced explicitly>.
