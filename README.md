# projmagic

> Make [GitHub Projects v2](https://docs.github.com/issues/planning-and-tracking-with-projects) easier — for you *and* everyone you share with.

**projmagic** is an open-source toolkit for GitHub Projects v2. Its first artifact is a
**reusable GitHub Actions workflow that auto-adds a newly-opened issue to one _or more_
Projects v2 boards** — a one-line drop-in for any repository.

[![CI](https://github.com/jvrck/projmagic/actions/workflows/ci.yml/badge.svg)](https://github.com/jvrck/projmagic/actions/workflows/ci.yml)

---

## Status

🚧 **Bootstrapping.** The reusable workflow, examples, and the token-first usage guide land
in the PRs that follow. This README is a skeleton; the full token-first documentation
arrives with the workflow.

## What it will do

- Add a newly-opened issue to a Projects v2 board with a one-line caller workflow.
- Add the same issue to **multiple** boards at once (fan-out over a list).
- Optionally filter by label.

## Why a token is required (read this first)

GitHub's built-in `GITHUB_TOKEN` **cannot** touch Projects v2 — boards are owned by a user
or org, not by the repository. You must supply a **classic PAT with the `project` scope**
(plus `read:org` for org-owned boards) as a repository secret. The full token guide ships
with the workflow.

## Layout

| Path | Purpose |
| --- | --- |
| `.github/workflows/add-to-project.yml` | The reusable workflow (`on: workflow_call`). |
| `examples/` | Copy-paste caller workflows (single-board and multi-board). |
| `docs/ISSUE_AUTHORING_GUIDE.md` | How issues / work items are scoped in this repo. |

## License

[MIT](./LICENSE) © Jim Vrckovski
