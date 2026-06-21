# projmagic

> Auto-add newly-opened issues to a [GitHub Projects v2](https://docs.github.com/issues/planning-and-tracking-with-projects) board — a one-line reusable workflow you drop into any repo.

[![CI](https://github.com/jvrck/projmagic/actions/workflows/ci.yml/badge.svg)](https://github.com/jvrck/projmagic/actions/workflows/ci.yml)

**projmagic** wraps [`actions/add-to-project`](https://github.com/actions/add-to-project)
into a shareable reusable workflow. Add one small caller workflow to your repository and
every new issue is added to your project board automatically.

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

---

## Inputs & secrets

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `project-url` | **yes** | — | URL of the Projects v2 board to add the issue to. |
| `labeled` | no | `''` | Comma-separated label filter; empty means add every issue. |
| `label-operator` | no | `OR` | How `labeled` matches: `OR` (any), `AND` (all), `NOT` (exclude). |

| Secret | Required | Description |
| --- | --- | --- |
| `token` | **yes** | Classic PAT with the `project` scope (+ `read:org` for org boards). **Not** the repo `GITHUB_TOKEN`. |

## Which events fire it?

The caller's trigger controls this. `actions/add-to-project` (which projmagic wraps)
supports issue events `opened`, `reopened`, `transferred`, and `labeled`. Most repos use
`opened` (plus `labeled` if filtering by label).

## Pinning

`@v1` tracks the latest `v1.x` release. For full immutability pin to an exact release
(`@v1.0.0`) or a commit SHA.

## Verify it worked

A green run isn't enough (see the failure symptom above). Confirm the item actually landed:

```bash
gh project item-list <number> --owner <owner> --format json \
  | jq '.items[] | {title: .content.title, url: .content.url}'
```

## Roadmap

- **Multiple boards** — add one issue to *several* boards at once via a list input + matrix
  fan-out. Landing in `v1.1` (`@v1` will pick it up automatically).
- **GitHub App auth** — a future hardened, no-PAT distribution path (via
  `actions/create-github-app-token`) for when projmagic has external users. Not built yet;
  the classic PAT above is the supported path today.
- Field-setting "magic" (set status/fields by name) — deferred to a later increment.

## License

[MIT](./LICENSE) © Jim Vrckovski
