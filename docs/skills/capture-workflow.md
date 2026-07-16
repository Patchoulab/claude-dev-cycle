# capture-workflow

**Purpose** — Turn a completed session or workflow into the right reusable artifact: a project slash command, a project or user skill, a plugin skill, or a scheduled job. The cardinal rule is to extract the *logic*, never the literals — every path, host, port, name, and number is classified before authoring so the artifact generalizes instead of hardcoding one run. Its job is everything around the authoring itself: pulling the workflow out of the session, deciding what kind of artifact it should be, validating it, and placing it.

## Invocation

```
/dev-cycle:capture-workflow [what to capture, optional]
```

The argument is an optional hint about what to capture (a task, a branch, an artifact). With no argument, the skill mines the current conversation. It also fires on natural phrasing like "turn this into a skill," "make this repeatable," or "I don't want to re-explain this next time."

## Contract

The skill runs a five-stage pipeline; each stage's output feeds the next. All user decisions (artifact type, name, location) are batched into a single question after classification.

1. **Extract** — Mine the finished work into a structured record: goal, the happy-path steps that actually worked, decision points, failure modes and their fixes, conventions honored, verification, a literals inventory, a secrets sweep, and an honest reuse-breadth estimate. Sources in preference order: the current conversation, artifacts the user names, the repo's handoff and progress files, then `git log`/diff of the session's branch.
2. **Classify** — Pick the artifact type with the decision table below. The skill recommends; it never silently decides.
3. **Author** — Produce the artifact plus a playbook reference doc. Commands additionally get a thin entry point that points at the playbook.
4. **Validate** — Run all four gates (below). An artifact that fails any gate is not packaged.
5. **Package** — Place and register the artifact. Commit only if preauthorized, otherwise ask. Never push — shipping is the user's call.

### Artifact-type decision table

| Artifact | Choose when | Trigger | Lives at |
|---|---|---|---|
| Project slash command | Repo-specific workflow started on demand with a per-request argument | Explicit `/name args` | `<repo>/.claude/commands/` + a playbook doc |
| Project skill | Repo-specific procedure Claude should auto-apply when matching work happens in that repo | Contextual (description match) | `<repo>/.claude/skills/<name>/` |
| User skill | Procedure that spans your repos but embeds personal facts that can't be externalized | Contextual, any repo | `~/.claude/skills/<name>/` |
| Plugin skill | Generic engine with every user-specific literal externalized to config or arguments; worth sharing | Contextual, distributable | plugin repo `skills/<name>/` + manifest bump |
| Scheduled job | Recurring chore on a clock, with no human trigger | Schedule | handed to `/dev-cycle:jobs:new` |

Tie-breakers, in order: trigger style first (a clock beats everything → scheduled job; an explicit-argument start → command; otherwise a skill), then the narrowest scope that covers the expected reuse. Personal literals that can't become parameters or config cap the scope at user level.

### The Literals Rule

Every proper noun, path, host, port, coordinate, name, and number in the extraction gets classified as exactly one of:

- **parameter** — the caller supplies it at invocation.
- **config** — read from `dev-cycle.json` or repo files.
- **invariant** — genuinely fixed for the artifact's scope (a repo's own script paths in a project command are invariants; an IP address in a plugin skill never is).
- **discard** — incidental to the original run.

A literal's legal classifications shrink as scope widens: what is an invariant in a project command becomes config or a parameter in a plugin skill. Validation greps the finished artifact for every literal marked parameter or discard; any hit is a failure.

## Config keys

Reads a `captureWorkflow` block in `dev-cycle.json`:

| Key | Meaning |
|---|---|
| `pluginRepo` | Target plugin repo for plugin-skill packaging (defaults to the current repo). |
| `playbookDir` | Where playbook docs land when the repo declares no owning domain (default `docs/playbooks/`). |
| `defaultScope` | The scope preferred when classification is otherwise a tie. |

It also reads the repo's `handoffFile` and `progressFile` settings as extraction sources during stage 1.

## Prerequisites

Git — extraction mines `git log`/diff of the session's branch, and packaging commits the artifact on a branch.

## Failure modes & remediation

- **One-off that won't recur** — If the reuse-breadth estimate comes back "probably never," the skill says so and stops. No artifact gets produced; a workflow that ran exactly once has no second use case to justify one.
- **Unclassifiable literals** — A personal fact (machine, account, habit) that can't be turned into a parameter or config caps the artifact's scope. It cannot graduate to a shareable plugin skill; it stays a user skill at most.
- **Trigger-gate failure** — If the description doesn't reliably fire on natural phrasings (or fires on adjacent workflows), fix the description keywords and re-run the gate before packaging.
- **Literal-leak failure** — If the leak scan finds a parameter/discard literal still hardcoded, re-parameterize and re-scan. Invariants must each carry a written justification.
- **Dry-run failure** — If a fresh run on a synthetic variant re-asks answered questions or rediscovers a known gotcha, the playbook is underspecified; tighten it and re-run.

## Optional integrations

- **superpowers:writing-skills** — When the superpowers plugin is installed, it owns the authoring discipline (description triggers, conciseness, frontmatter, loophole closing) and the skill invokes it at the author and validate stages. Without it, the skill authors by hand: a tight when-to-use description and minimal frontmatter.
- **Scheduled jobs** — When classification lands on a recurring chore, the skill doesn't package anything itself. It builds a pre-filled answer record from the extraction and hands it to `/dev-cycle:jobs:new`, then reports the hand-off.
