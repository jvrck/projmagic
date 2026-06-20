# Issue authoring guide

projmagic is built one **scoped issue per work item**. Each issue maps to a single PR,
implemented in its own git worktree, dual-reviewed, and squash-merged.

## Title convention

Use a [Conventional Commits](https://www.conventionalcommits.org/) prefix so the title
doubles as the squash-merge commit subject:

| Prefix | Use for |
| --- | --- |
| `feat:` | A new capability (a new workflow, a new input, a new example). |
| `fix:` | A bug fix in an existing workflow or doc. |
| `chore:` | Repo plumbing — CI, scaffolding, tooling, housekeeping. |
| `docs:` | Documentation-only changes. |

Example: `feat: reusable add-to-project workflow (single board)`

## A good issue

- **One outcome.** If it needs two PRs, it's two issues.
- **States the observable done condition.** For workflow changes that means: what a
  consumer's caller looks like, and how you'd prove it worked (e.g. the item appears via
  `gh project item-list`).
- **Notes the review-reject criteria** it must satisfy, if any.

## The loop

1. Open the scoped issue.
2. `git worktree add -b <type>/<slug> ../projmagic-wt/<slug> main`
3. Implement → push → open PR (link the issue).
4. Dual-review (a fresh reviewer + an independent tool) until both are clean.
5. CI green → squash-merge → delete the branch and worktree.
