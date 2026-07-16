---
name: finish-branch
description: Finish the current branch — merge PR, update submodule pointer, verify clean, sync main
---
Invoke the dev-cycle:finish-branch skill and follow it exactly, starting from Phase 0,
for the repository containing the current working directory. $ARGUMENTS may name
a PR number or submodule path; otherwise auto-detect.
