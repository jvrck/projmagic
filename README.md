# projmagic

> Auto-add newly-opened issues to one — or more — [GitHub Projects v2](https://docs.github.com/issues/planning-and-tracking-with-projects) boards — a one-line reusable workflow you drop into any repo.

[![CI](https://github.com/jvrck/projmagic/actions/workflows/ci.yml/badge.svg)](https://github.com/jvrck/projmagic/actions/workflows/ci.yml)

**projmagic** wraps [`actions/add-to-project`](https://github.com/actions/add-to-project)
into a shareable reusable workflow. Add one small caller workflow to your repository and
every new issue is added to your project board automatically — to a single board, or
fanned out across several at once.

projmagic also ships a second reusable workflow, **`roll-sprint.yml`**, that rolls every
open issue from the previous sprint into the current one when a sprint turns over — see
[Roll open issues into the current sprint](#roll-open-issues-into-the-current-sprint) below.

---

## ⚠️ Read this first — you need a `project`-scoped token

GitHub's built-in `GITHUB_TOKEN` **cannot add items to Projects v2 boards.**

Projects v2 boards are owned by a **user or organization**, not by the repository, so the
automatic per-repo `GITHUB_TOKEN` has no authority over them. If you use it (or any token
missing the `project` scope), **the add silently fails**:

> **Failure symptom:** the Actions run is **green ✅** but the issue never appears on the
> board. Under the hood the Projects GraphQL call returns **`403` / "Resource not
> accessible by integration"** and the action no-ops. A green run is *not* proof it worked
> — verify with `gh project item-list`.

You must supply a **classic personal access token (PAT) with the `project` scope** as a
repository secret.

### 1. Mint the token

**Settings → Developer settings → Personal access tokens → Tokens (classic) → Generate new
token (classic)**, then select:

| Scope | When you need it |
| --- | --- |
| **`project`** | **Always** — read/write access to Projects v2. |
| `repo` | If the issues live in a **private** repository. |
| `read:org` | If the board is owned by an **organization**. |

Copy the generated `ghp_…` value.

### 2. Store it as a secret (`PROJMAGIC_TOKEN`)

The convention is to name the secret **`PROJMAGIC_TOKEN`**:

```bash
gh secret set PROJMAGIC_TOKEN -R <owner>/<repo>          # paste the PAT when prompted
# non-interactive:
printf '%s' "$YOUR_PAT" | gh secret set PROJMAGIC_TOKEN -R <owner>/<repo>
```

Sharing across many repos? Set it once as an **organization secret** and grant it to the
repositories that need it.

---

## Usage

Add **one** caller workflow to your repo. The `issues: opened` trigger lives in **your**
workflow — reusable workflows run in the *caller's* event context, so projmagic's workflow
declares no issue trigger of its own.

`.github/workflows/add-to-project.yml`:

```yaml
name: Add issues to my project

on:
  issues:
    types: [opened]

jobs:
  add-to-project:
    uses: jvrck/projmagic/.github/workflows/add-to-project.yml@v1
    with:
      project-url: https://github.com/users/<you>/projects/<number>
    secrets:
      token: ${{ secrets.PROJMAGIC_TOKEN }}
```

Open an issue → it appears on the board. Your board URL is the address bar when you view
the project:

- user board: `https://github.com/users/<you>/projects/<number>`
- org board: `https://github.com/orgs/<org>/projects/<number>`

A ready-to-copy version lives in [`examples/single-board.yml`](./examples/single-board.yml).

### Optional: filter by label

```yaml
jobs:
  add-to-project:
    uses: jvrck/projmagic/.github/workflows/add-to-project.yml@v1
    with:
      project-url: https://github.com/users/<you>/projects/<number>
      labeled: bug, needs-triage    # comma-separated
      label-operator: OR            # OR (any) | AND (all) | NOT (exclude)
    secrets:
      token: ${{ secrets.PROJMAGIC_TOKEN }}
```

When you filter by label, also trigger on `labeled` so issues that gain the label later are
added: `types: [opened, labeled]`.

### Multiple boards

To add the same issue to **several** boards at once, use `project-urls` instead of
`project-url`. It accepts a newline-separated list (most readable) or a JSON array. The
issue is added to **every** board — one matrix leg per board, so one bad board never blocks
the others.

```yaml
jobs:
  add-to-project:
    uses: jvrck/projmagic/.github/workflows/add-to-project.yml@v1
    with:
      project-urls: |
        https://github.com/users/<you>/projects/<number>
        https://github.com/orgs/<org>/projects/<number>
    secrets:
      token: ${{ secrets.PROJMAGIC_TOKEN }}
```

Equivalent JSON-array form: `project-urls: '["https://.../projects/1", "https://.../projects/2"]'`.
A ready-to-copy version lives in [`examples/multi-board.yml`](./examples/multi-board.yml).

---

## Inputs & secrets

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `project-url` | yes\* | `''` | A single Projects v2 board URL. |
| `project-urls` | yes\* | `''` | Multiple board URLs — a JSON array or a newline/comma-separated list. Combined with `project-url`; duplicates removed. |
| `labeled` | no | `''` | Comma-separated label filter; empty means add every issue. |
| `label-operator` | no | `OR` | How `labeled` matches: `OR` (any), `AND` (all), `NOT` (exclude). |
| `runs-on` | no | `["ubuntu-latest"]` | Runner labels for the workflow's jobs, as a **JSON array** string. See [Choosing a runner](#choosing-a-runner). |

\* Provide **`project-url`** (single board) **or** **`project-urls`** (one or more). At least one URL must resolve, or the run fails fast with a clear error.

| Secret | Required | Description |
| --- | --- | --- |
| `token` | **yes** | Classic PAT with the `project` scope (+ `read:org` for org boards). **Not** the repo `GITHUB_TOKEN`. |

## Which events fire it?

The caller's trigger controls this. `actions/add-to-project` (which projmagic wraps)
supports issue events `opened`, `reopened`, `transferred`, and `labeled`. Most repos use
`opened` (plus `labeled` if filtering by label).

## Choosing a runner

Both reusable workflows run on **`ubuntu-latest`** by default — you can ignore this
section entirely. If you need them on your own runners (a self-hosted fleet, or a
GitHub-hosted minutes allowance that has run out), pass `runs-on`:

```yaml
    with:
      project-url: https://github.com/users/<you>/projects/<number>
      runs-on: '["self-hosted", "linux"]'
```

A caller **cannot** override a reusable workflow's `runs-on` directly — that is why this
input exists.

**Why a JSON array and not a bare label.** `runs-on` takes a label *set*, not a single
label: a self-hosted target is normally written `[self-hosted, my-label]`. A bare string
would be read as one label named literally `[self-hosted, my-label]`, matching no runner
and leaving the job **queued forever** instead of failing. So the input is a JSON array
string, which the workflow feeds through `fromJSON`. A single label is just a one-element
array: `'["ubuntu-latest"]'`.

## Pinning

`@v1` tracks the latest `v1.x` release. For full immutability pin to an exact release
(`@v1.0.0`) or a commit SHA.

## Verify it worked

A green run isn't enough (see the failure symptom above). Confirm the item actually landed:

```bash
gh project item-list <number> --owner <owner> --format json \
  | jq '.items[] | {title: .content.title, url: .content.url}'
```

## Roll open issues into the current sprint

Sprint turnover strands unfinished work: when a sprint ends, its still-open issues sit in
the old iteration until someone drags them onto the new sprint by hand. The
**`roll-sprint.yml`** reusable workflow does it in one click — it moves every **open** issue
still in the **previous** sprint of a Projects v2 board into the **current** sprint. Run it
from the Actions tab when a sprint rolls over.

Add a caller workflow to your repo, triggered by `workflow_dispatch`:

`.github/workflows/roll-sprint.yml`:

```yaml
name: Roll open issues into the current sprint

on:
  workflow_dispatch:
    inputs:
      dry_run:
        description: Preview only — list what would move, mutate nothing.
        type: boolean
        default: true

jobs:
  roll-sprint:
    uses: jvrck/projmagic/.github/workflows/roll-sprint.yml@v1
    with:
      project-url: https://github.com/users/<you>/projects/<number>
      dry-run: ${{ inputs.dry_run }}
    secrets:
      token: ${{ secrets.PROJMAGIC_TOKEN }}
```

By default it moves open issues from the **most-recently-completed** sprint into the
**current** sprint (the iteration whose date range contains today). Override either end by
iteration **title** with `source-iteration` / `target-iteration`. A ready-to-copy version
lives in [`examples/roll-sprint.yml`](./examples/roll-sprint.yml).

### ⚠️ Dry-run first, and it fails loud

- **`dry-run: true` is the default.** The first run only **previews** the move plan (written
  to the run summary) and mutates nothing. Re-run with `dry-run: false` to perform the moves.
- **It never silently no-ops.** A malformed board URL, a missing / mis-named iteration field,
  a field that isn't an iteration field, no active sprint today, no completed sprint to roll
  from, `source == target`, or a token without the `project` scope each **fail the run** with
  a friendly `::error::projmagic: …`. A green run means work happened — or an honest "0 open
  items in `<sprint>`".
- **Same token contract** as add-to-project: a classic PAT with the `project` scope (+
  `read:org` for org boards) supplied as the `PROJMAGIC_TOKEN` secret. The repo `GITHUB_TOKEN`
  cannot touch Projects v2 — see [the token section above](#️-read-this-first--you-need-a-project-scoped-token).

### roll-sprint inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `project-url` | **yes** | — | The Projects v2 board URL. |
| `iteration-field` | no | `Sprint` | Name of the board's iteration field (`Sprint`/`Iteration`/`Cycle`). |
| `source-iteration` | no | `''` | Iteration **title** to move FROM; empty ⇒ the most-recently-completed sprint. |
| `target-iteration` | no | `''` | Iteration **title** to move TO; empty ⇒ the current/active sprint. |
| `include-prs` | no | `false` | Also move open PRs (default: issues only). |
| `dry-run` | no | `true` | Preview only; set `false` to perform the moves. |
| `runs-on` | no | `["ubuntu-latest"]` | Runner labels for the workflow's job, as a **JSON array** string. See [Choosing a runner](#choosing-a-runner). |

| Secret | Required | Description |
| --- | --- | --- |
| `token` | **yes** | Classic PAT with the `project` scope (+ `read:org` for org boards). **Not** the repo `GITHUB_TOKEN`. |

## License

[MIT](./LICENSE) © Jim Vrckovski
