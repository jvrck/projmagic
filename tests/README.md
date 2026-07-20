# tests

Regression guards for the real inline logic in projmagic's reusable workflows:

- **`norm.bats`** — the board-URL **normalize** step in
  `.github/workflows/add-to-project.yml` (job `setup`, step `id: norm`): the
  bash+jq that turns `project-url` / `project-urls` into the `urls` JSON array
  the matrix fans out over.
- **`roll-sprint.bats`** — the **resolve/select** step in
  `.github/workflows/roll-sprint.yml` (job `roll`, step `id: resolve`): the pure
  transform that, given the iteration-field config + the board's items as JSON,
  computes the source iteration, the target iteration, and the move-list.
- **`runs-on.bats`** — the **`runs-on` input** on both reusable workflows. Not an
  inline script but workflow *structure*, so it asserts against the YAML rather
  than exec'ing anything: the input is declared, optional, documented, defaults
  to `["ubuntu-latest"]`, and is threaded to **every** job with no hardcoded
  runner left behind.

## Why they're shaped this way

Both files are **reusable** workflows: at runtime the runner holds the *caller's*
checkout, so the logic must stay **inline** in the YAML — it can't be sourced
from a sibling file. So each suite extracts its step's `run:` block straight out
of the workflow with `yq` and execs the **real shipped script** against fixture
JSON (no network). There is deliberately **no copy** of the logic in the tests (a
duplicate could drift from the workflow and pass while the real logic breaks).

If the step can't be extracted (workflow restructured / step renamed) the suite
**fails loud** in `setup_file` — it never silently skips, because a self-skipping
lane is exactly what lets broken logic ship unverified.

## Run locally

Needs `yq` (mikefarah), `jq`, and `bats-core` on `PATH`:

```sh
bats tests/
```

CI runs the same suites in the `test` job of `.github/workflows/ci.yml` with
pinned `yq` and `bats`.

## Cases

**norm** — single `project-url` · JSON-array `project-urls` · newline list ·
comma list · mixed `project-url`+`project-urls` · whitespace/CR stripped · blank
lines dropped · **duplicate URLs de-duped, order preserved** (the regression) ·
empty input → `::error::` + exit 1 · `[`-but-invalid-JSON → `::error::` + exit 1.

**roll-sprint** — auto target = the iteration whose date range contains `TODAY` ·
explicit `target-iteration` title override (incl. a completed iteration) · auto
source = the most-recently-completed iteration · explicit `source-iteration`
override · selection = **open issues in source** (closed excluded, PR excluded
unless `include-prs`, other-iteration excluded) · `include-prs` selects the open
PR · **dry-run collects the move-list but emits no mutation payload** ·
`dry-run: false` emits `moves == plan` · `source == target` → `::error::` + exit 1
· no active sprint today → `::error::` + exit 1 · no completed sprint to roll from
→ `::error::` + exit 1 · unknown / non-iteration field → `::error::` + exit 1 ·
unknown explicit source/target title → `::error::` + exit 1.

**runs-on** — input declared on both workflows · optional `string` · non-empty
description · **default is `["ubuntu-latest"]`** (the load-bearing one: projmagic
is public, and a non-hosted default would break every consumer that doesn't set
the input) · the default is valid JSON and survives `fromJSON` · every job —
enumerated by name, so a newly added job can't quietly miss it — uses
`${{ fromJSON(inputs.runs-on) }}` · no hardcoded runner label survives.
