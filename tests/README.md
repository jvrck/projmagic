# tests

Regression guard for the one piece of real logic in this repo: the board-URL
**normalize** step in `.github/workflows/add-to-project.yml` (job `setup`, step
`id: norm`) — the bash+jq that turns `project-url` / `project-urls` into the
`urls` JSON array the matrix fans out over.

## Why it's shaped this way

`add-to-project.yml` is a **reusable** workflow: at runtime the runner holds the
*caller's* checkout, so the normalize script must stay **inline** in the YAML — it
can't be sourced from a sibling file. So `norm.bats` extracts the `norm` step's
`run:` block straight out of the workflow with `yq` and execs the **real shipped
script**. There is deliberately **no copy** of the jq in the test (a duplicate
could drift from the workflow and pass while the real logic breaks).

If the step can't be extracted (workflow restructured / step renamed) the suite
**fails loud** — it never silently skips.

## Run locally

Needs `yq` (mikefarah), `jq`, and `bats-core` on `PATH`:

```sh
bats tests/
```

CI runs the same suite in the `test` job of `.github/workflows/ci.yml` with
pinned `yq` and `bats`.

## Cases

single `project-url` · JSON-array `project-urls` · newline list · comma list ·
mixed `project-url`+`project-urls` · whitespace/CR stripped · blank lines dropped
· **duplicate URLs de-duped, order preserved** (the regression) · empty input →
`::error::` + exit 1 · `[`-but-invalid-JSON → `::error::` + exit 1.
