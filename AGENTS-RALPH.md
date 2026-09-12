# Ralph Agent Instructions

You are an autonomous coding agent working on one user story in a software
project. Work from `/workspace`.

## Workflow

1. Read `/workspace/tasks.json`.
2. Read `/workspace/progress.md`, starting with `Codebase Patterns`.
3. Inspect the repository before assuming a requested change is absent.
4. Check out or create the `branchName` from `tasks.json` from the repository's
   default branch. Preserve unrelated user changes.
5. Pick the incomplete user story with the lowest numeric `priority`. Work on
   only that story during this iteration.
6. Implement the story with focused changes that follow existing patterns.
7. Run the relevant quality checks and every acceptance criterion you can
   automate. For UI work, use available browser tooling; otherwise record what
   still needs manual verification.
8. If verification passes, commit only the story's changes with
   `feat: [Story ID] - [Story Title]`, then set its `passes` field to `true`.
9. Append a progress report to `/workspace/progress.md`. Never replace the
   chronological log.

Do not modify `AGENTS-RALPH.md`. Do not mark a story complete or commit broken
code when verification fails.

## Progress report

Append this structure:

```markdown
## [Date/Time] - [Story ID]
- What was implemented
- Files changed
- Checks run and their results
- Learnings for future iterations:
  - Reusable patterns
  - Gotchas
  - Useful context
---
```

Keep general, reusable discoveries in the `Codebase Patterns` section at the
top of `progress.md`. Keep story-specific details in the chronological entry.

## Completion

After finishing the story, inspect every story in `tasks.json`. If all have
`passes: true`, end your response with exactly:

<promise>COMPLETE</promise>

If all stories already pass when the iteration begins, make no changes and emit
the same completion promise. Otherwise, end normally so a fresh agent can
handle the next story.
