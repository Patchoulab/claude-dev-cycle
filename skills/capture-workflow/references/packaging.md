# Packaging Procedure

By artifact type. All git operations: one command per Bash call;
commit only if dev-cycle.json preauthorized contains
"commit-approved-artifacts", else ask. NEVER push.

## Project slash command
1. Write `<repo>/.claude/commands/<name>.md`.
2. Write the playbook into the owning domain's directory if the repo
   declares domains (repo-structure.yaml `owns` globs decide);
   otherwise `<playbookDir>` from dev-cycle.json (default docs/playbooks/).
3. If repo-structure.yaml exists and `.claude/` or the playbook path
   is unregistered: add the domain entry in the established format
   (path, purpose, owns, indexed_by), then run the dev-cycle.json
   `structureChecker` and require a clean pass.
4. Report the exact invocation line the user will type.

## Project skill
Same as above with `<repo>/.claude/skills/<name>/SKILL.md`
(+ references/ if the playbook rides inside the skill dir).

## User skill
`~/.claude/skills/<name>/SKILL.md`. No repo registration. Note in the
report that this artifact is personal and unshareable by design.

## plugin skill (this repo, or a new plugin in a marketplace)
1. Scaffold `skills/<name>/SKILL.md` (+ references/, templates/) in the
   plugin repo (dev-cycle.json captureWorkflow.pluginRepo, default this repo).
2. Bump `.claude-plugin/plugin.json` version: minor for a new skill,
   patch for edits.
3. Add the skill to README.md's skill table (one row: name, trigger
   summary).
4. Verify plugin.json parses (`python3 -m json.tool`).
5. Branch `<type>/<name>`, commit artifact + manifest + README together.
6. Stop. Report: "push and marketplace release are your call."

## scheduled-jobs job
Do not package. Hand a pre-filled answer record (built from the
extraction record) to /dev-cycle:jobs:new and report the hand-off.
