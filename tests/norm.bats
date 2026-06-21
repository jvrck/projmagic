#!/usr/bin/env bats
#
# Regression test for the board-URL normalize logic in
# .github/workflows/add-to-project.yml (job `setup`, step `id: norm`).
#
# WHY THIS SHAPE: `add-to-project.yml` is a *reusable* workflow. At runtime the
# runner holds the CALLER's checkout, not projmagic's, so the normalize script
# has to live INLINE in the workflow — it can't be sourced from a sibling file.
# To test the *real shipped code* (not a copy that can silently drift) we extract
# the `norm` step's `run:` block straight out of the YAML with `yq` and exec it.
#
# If the step can't be extracted (workflow restructured / step renamed) this
# suite FAILS LOUD in setup_file — it never silently skips, because a
# self-skipping lane is exactly what lets broken logic ship unverified.
#
# Run locally:  yq (mikefarah) + jq + bats-core on PATH, then `bats tests/`.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/add-to-project.yml"

# --- extract the real `norm` run block once for the whole file -----------------
setup_file() {
  command -v yq >/dev/null 2>&1 \
    || { echo "FATAL: yq (mikefarah) not on PATH — cannot extract the norm step" >&2; return 1; }
  command -v jq >/dev/null 2>&1 \
    || { echo "FATAL: jq not on PATH — the norm script needs it" >&2; return 1; }
  [ -f "$WORKFLOW" ] \
    || { echo "FATAL: workflow not found at $WORKFLOW" >&2; return 1; }

  # Select strictly by job `setup` + step `id: norm`. Any restructure that moves,
  # renames, or removes the step makes this yield empty -> we fail loud below.
  local block
  block="$(yq -r '.jobs.setup.steps[] | select(.id == "norm") | .run' "$WORKFLOW")" \
    || { echo "FATAL: yq failed to read $WORKFLOW" >&2; return 1; }

  if [ -z "${block//[[:space:]]/}" ]; then
    echo "FATAL: could not extract job 'setup' step id 'norm' from $WORKFLOW" >&2
    echo "       (workflow restructured?) — refusing to skip; failing loud." >&2
    return 1
  fi

  # Sanity: the block must be the normalize step — it resolves URLs into the
  # GITHUB_OUTPUT `urls=` value. If that's gone we grabbed the wrong/changed step.
  case "$block" in
    *GITHUB_OUTPUT*urls=*|*urls=*GITHUB_OUTPUT*) : ;;
    *) echo "FATAL: extracted block isn't the URL-normalize step (no urls=/GITHUB_OUTPUT write)" >&2
       return 1 ;;
  esac

  printf '%s\n' "$block" > "$BATS_FILE_TMPDIR/norm.sh"
}

# --- run the extracted script in an isolated dir with controlled env -----------
# Usage: run_norm <project-url> <project-urls>
# Sets:  $status (exit code), $output (merged stdout+stderr), and $GH_OUT file.
run_norm() {
  local pu="$1" pus="$2"
  local wd="$BATS_TEST_TMPDIR/wd"
  rm -rf "$wd"; mkdir -p "$wd"
  GH_OUT="$BATS_TEST_TMPDIR/github_output"
  : > "$GH_OUT"
  # cd into the temp dir so the script's candidates.txt scratch file lands there,
  # not in the repo; override only the three inputs, keep PATH for jq/yq.
  run env GITHUB_OUTPUT="$GH_OUT" PROJECT_URL="$pu" PROJECT_URLS="$pus" \
      bash -c 'cd "$0" && bash "$1"' "$wd" "$BATS_FILE_TMPDIR/norm.sh"
}

get_urls() {
  local line
  line="$(grep '^urls=' "$GH_OUT" || true)"
  printf '%s' "${line#urls=}"
}

assert_ok_urls() {
  local expected="$1" urls
  [ "$status" -eq 0 ] || { echo "expected exit 0, got $status"; echo "output: $output"; return 1; }
  urls="$(get_urls)"
  [ "$urls" = "$expected" ] || {
    echo "urls mismatch"; echo "  expected: $expected"; echo "  actual:   $urls"; return 1;
  }
}

assert_error_exit1() {
  local needle="$1"
  [ "$status" -eq 1 ] || { echo "expected exit 1, got $status"; echo "output: $output"; return 1; }
  case "$output" in
    *"$needle"*) : ;;
    *) echo "expected friendly error containing: $needle"; echo "output: $output"; return 1 ;;
  esac
  # On the error path the script must NOT have written a urls= value.
  [ -z "$(get_urls)" ] || { echo "unexpected urls= written on error path: $(get_urls)"; return 1; }
}

# --- the fail-loud guard is itself observable ----------------------------------
@test "norm step extracted from the real workflow (fail-loud guard)" {
  [ -s "$BATS_FILE_TMPDIR/norm.sh" ]
  grep -q 'GITHUB_OUTPUT' "$BATS_FILE_TMPDIR/norm.sh"
}

# --- happy paths ---------------------------------------------------------------
@test "single project-url -> one-element array" {
  run_norm "https://github.com/users/jvrck/projects/34" ""
  assert_ok_urls '["https://github.com/users/jvrck/projects/34"]'
}

@test "project-urls as a JSON array" {
  run_norm "" '["https://a/projects/1","https://b/projects/2"]'
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

@test "project-urls as a newline-separated list" {
  run_norm "" $'https://a/projects/1\nhttps://b/projects/2'
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

@test "project-urls as a comma-separated list" {
  run_norm "" "https://a/projects/1,https://b/projects/2"
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

@test "project-url + project-urls combined (project-url first)" {
  run_norm "https://x/projects/9" $'https://a/projects/1\nhttps://b/projects/2'
  assert_ok_urls '["https://x/projects/9","https://a/projects/1","https://b/projects/2"]'
}

@test "leading/trailing whitespace and CR are stripped" {
  run_norm "" $'  https://a/projects/1 \r\n\thttps://b/projects/2  '
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

@test "blank lines are dropped" {
  run_norm "" $'https://a/projects/1\n\n\nhttps://b/projects/2\n'
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

# THE regression: dedup with order preserved. A revert to the buggy
# `any(.[] == $u)` form makes jq error ("Cannot iterate over string"), the script
# exits non-zero, and this test fails loud.
@test "duplicate URLs are de-duped, original order preserved" {
  run_norm "https://a/projects/1" $'https://a/projects/1\nhttps://b/projects/2\nhttps://a/projects/1'
  assert_ok_urls '["https://a/projects/1","https://b/projects/2"]'
}

# --- error paths ---------------------------------------------------------------
@test "no input -> friendly ::error:: and exit 1" {
  run_norm "" ""
  assert_error_exit1 "::error::projmagic: no board URL provided"
}

@test "project-urls starts with '[' but is invalid JSON -> friendly ::error:: and exit 1" {
  run_norm "" '[not json'
  assert_error_exit1 "::error::projmagic: 'project-urls' starts with '['"
}
