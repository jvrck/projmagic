#!/usr/bin/env bats
#
# Regression test for the resolve/select logic in
# .github/workflows/roll-sprint.yml (job `roll`, step `id: resolve`).
#
# WHY THIS SHAPE: `roll-sprint.yml` is a *reusable* workflow. At runtime the
# runner holds the CALLER's checkout, not projmagic's, so the resolve script has
# to live INLINE in the workflow — it can't be sourced from a sibling file. To
# test the *real shipped code* (not a copy that can silently drift) we extract
# the `resolve` step's `run:` block straight out of the YAML with `yq` and exec
# it against FIXTURE iteration-config + items JSON — no network. This mirrors how
# tests/norm.bats tests the add-to-project normalize step.
#
# If the step can't be extracted (workflow restructured / step renamed) this
# suite FAILS LOUD in setup_file — it never silently skips, because a
# self-skipping lane is exactly what lets broken logic ship unverified.
#
# Run locally:  yq (mikefarah) + jq + bats-core on PATH, then `bats tests/`.

WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/roll-sprint.yml"

# --- extract the real `resolve` run block once for the whole file --------------
setup_file() {
  command -v yq >/dev/null 2>&1 \
    || { echo "FATAL: yq (mikefarah) not on PATH — cannot extract the resolve step" >&2; return 1; }
  command -v jq >/dev/null 2>&1 \
    || { echo "FATAL: jq not on PATH — the resolve script needs it" >&2; return 1; }
  [ -f "$WORKFLOW" ] \
    || { echo "FATAL: workflow not found at $WORKFLOW" >&2; return 1; }

  # Select strictly by job `roll` + step `id: resolve`. Any restructure that
  # moves, renames, or removes the step makes this yield empty -> fail loud below.
  local block
  block="$(yq -r '.jobs.roll.steps[] | select(.id == "resolve") | .run' "$WORKFLOW")" \
    || { echo "FATAL: yq failed to read $WORKFLOW" >&2; return 1; }

  if [ -z "${block//[[:space:]]/}" ]; then
    echo "FATAL: could not extract job 'roll' step id 'resolve' from $WORKFLOW" >&2
    echo "       (workflow restructured?) — refusing to skip; failing loud." >&2
    return 1
  fi

  # Sanity: the block must be the resolve step — it writes the resolved
  # source-id into GITHUB_OUTPUT. If that's gone we grabbed the wrong step.
  case "$block" in
    *source-id=*GITHUB_OUTPUT*|*GITHUB_OUTPUT*source-id=*) : ;;
    *) echo "FATAL: extracted block isn't the resolve step (no source-id/GITHUB_OUTPUT write)" >&2
       return 1 ;;
  esac

  printf '%s\n' "$block" > "$BATS_FILE_TMPDIR/resolve.sh"
}

# --- fixtures ------------------------------------------------------------------
# A valid iteration field "Sprint": active iterations S-cur (contains 2026-06-30)
# and S-next; completed S-prev (latest completed) and S-old.
setup() {
  # completedIterations is deliberately NOT sorted (S-old, the OLDER one, is
  # element [0]) so the auto-source test discriminates max_by(.startDate) from a
  # naive `.[0]`/first.
  DEFAULT_CONFIG='{"fieldName":"Sprint","fieldFound":true,"isIterationField":true,"fieldId":"FIELD_SPRINT","iterations":[{"id":"it-cur","title":"S-cur","startDate":"2026-06-29","duration":14},{"id":"it-next","title":"S-next","startDate":"2026-07-13","duration":14}],"completedIterations":[{"id":"it-old","title":"S-old","startDate":"2026-06-01","duration":14},{"id":"it-prev","title":"S-prev","startDate":"2026-06-15","duration":14}],"boardIterationFields":["Sprint"]}'

  # In S-prev (it-prev): 2 open issues (#1,#2), 1 closed issue (#3), 1 open PR
  # (#4), 1 CLOSED PR (#7), 1 OPEN draft item (#8, type DraftIssue). In S-cur
  # (it-cur): 1 open issue (#5). No iteration: 1 open issue (#6). #7 and #8 prove
  # closed-PR and non-Issue/PR exclusion hold even with include-prs.
  DEFAULT_ITEMS='[{"type":"Issue","number":1,"state":"OPEN","url":"https://github.com/o/r/issues/1","itemId":"PVTI_1","iterationId":"it-prev"},{"type":"Issue","number":2,"state":"OPEN","url":"https://github.com/o/r/issues/2","itemId":"PVTI_2","iterationId":"it-prev"},{"type":"Issue","number":3,"state":"CLOSED","url":"https://github.com/o/r/issues/3","itemId":"PVTI_3","iterationId":"it-prev"},{"type":"PullRequest","number":4,"state":"OPEN","url":"https://github.com/o/r/pull/4","itemId":"PVTI_4","iterationId":"it-prev"},{"type":"Issue","number":5,"state":"OPEN","url":"https://github.com/o/r/issues/5","itemId":"PVTI_5","iterationId":"it-cur"},{"type":"Issue","number":6,"state":"OPEN","url":"https://github.com/o/r/issues/6","itemId":"PVTI_6","iterationId":null},{"type":"PullRequest","number":7,"state":"CLOSED","url":"https://github.com/o/r/pull/7","itemId":"PVTI_7","iterationId":"it-prev"},{"type":"DraftIssue","number":8,"state":"OPEN","url":"https://github.com/o/r/issues/8","itemId":"PVTI_8","iterationId":"it-prev"}]'

  CONFIG_NO_COMPLETED='{"fieldName":"Sprint","fieldFound":true,"isIterationField":true,"fieldId":"FIELD_SPRINT","iterations":[{"id":"it-cur","title":"S-cur","startDate":"2026-06-29","duration":14}],"completedIterations":[],"boardIterationFields":["Sprint"]}'

  CONFIG_FIELD_NOT_FOUND='{"fieldName":"Sprint","fieldFound":false,"isIterationField":false,"fieldId":null,"iterations":[],"completedIterations":[],"boardIterationFields":["Cycle"]}'

  CONFIG_NOT_ITERATION='{"fieldName":"Status","fieldFound":true,"isIterationField":false,"fieldId":"FIELD_STATUS","iterations":[],"completedIterations":[],"boardIterationFields":[]}'
}

# --- run the extracted script with controlled env ------------------------------
# Reads caller-set ITER_CONFIG/ITEMS/SOURCE_ITERATION/TARGET_ITERATION/
# INCLUDE_PRS/DRY_RUN/TODAY (each defaulted), captures $status/$output and the
# GITHUB_OUTPUT file in $GH_OUT.
run_resolve() {
  GH_OUT="$BATS_TEST_TMPDIR/github_output"
  : > "$GH_OUT"
  run env \
    GITHUB_OUTPUT="$GH_OUT" \
    ITER_CONFIG="${ITER_CONFIG:-$DEFAULT_CONFIG}" \
    ITEMS="${ITEMS:-$DEFAULT_ITEMS}" \
    SOURCE_ITERATION="${SOURCE_ITERATION:-}" \
    TARGET_ITERATION="${TARGET_ITERATION:-}" \
    INCLUDE_PRS="${INCLUDE_PRS:-false}" \
    DRY_RUN="${DRY_RUN:-true}" \
    TODAY="${TODAY:-2026-06-30}" \
    bash "$BATS_FILE_TMPDIR/resolve.sh"
}

# Read a single `key=value` output line written to GITHUB_OUTPUT.
get_out() {
  local line
  line="$(grep -m1 "^$1=" "$GH_OUT" || true)"
  printf '%s' "${line#"$1="}"
}

assert_ok() {
  [ "$status" -eq 0 ] || { echo "expected exit 0, got $status"; echo "output: $output"; return 1; }
}

assert_error_exit1() {
  local needle="$1"
  [ "$status" -eq 1 ] || { echo "expected exit 1, got $status"; echo "output: $output"; return 1; }
  case "$output" in
    *"$needle"*) : ;;
    *) echo "expected friendly error containing: $needle"; echo "output: $output"; return 1 ;;
  esac
  # On the error path the script must NOT have written any resolution outputs.
  [ -z "$(get_out source-id)" ] || { echo "unexpected source-id written on error path"; return 1; }
}

# --- the fail-loud guard is itself observable ----------------------------------
@test "resolve step extracted from the real workflow (fail-loud guard)" {
  [ -s "$BATS_FILE_TMPDIR/resolve.sh" ]
  grep -q 'GITHUB_OUTPUT' "$BATS_FILE_TMPDIR/resolve.sh"
  grep -q 'source-id=' "$BATS_FILE_TMPDIR/resolve.sh"
}

# --- target resolution ---------------------------------------------------------
@test "auto target = the iteration whose date range contains TODAY" {
  SOURCE_ITERATION="S-prev" TODAY="2026-06-30" run_resolve
  assert_ok
  [ "$(get_out target-title)" = "S-cur" ]
  [ "$(get_out target-id)" = "it-cur" ]
}

@test "explicit target-iteration title overrides the date-based pick" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-next" TODAY="2026-06-30" run_resolve
  assert_ok
  [ "$(get_out target-title)" = "S-next" ]
}

@test "explicit target title may resolve to a completed iteration" {
  SOURCE_ITERATION="S-old" TARGET_ITERATION="S-prev" run_resolve
  assert_ok
  [ "$(get_out target-title)" = "S-prev" ]
  [ "$(get_out target-id)" = "it-prev" ]
}

# Boundary cases pin the half-open window [startDate, startDate+duration). This
# workflow is built to run ON the sprint-turnover day, so these are the most
# operationally-likely dates — a '<'->'<=' or '>='->'>' off-by-one must fail here.
@test "date window is START-INCLUSIVE: TODAY == S-cur startDate picks S-cur" {
  SOURCE_ITERATION="S-prev" TODAY="2026-06-29" run_resolve
  assert_ok
  [ "$(get_out target-title)" = "S-cur" ]
}

@test "date window is END-EXCLUSIVE: TODAY == S-cur end == S-next start picks S-next" {
  SOURCE_ITERATION="S-prev" TODAY="2026-07-13" run_resolve
  assert_ok
  [ "$(get_out target-title)" = "S-next" ]
}

@test "a day in the gap before any active sprint -> no-active-target error" {
  # 2026-06-28 falls only inside the COMPLETED S-prev; auto-target searches active
  # iterations only, so there is no active sprint -> fail loud.
  SOURCE_ITERATION="S-prev" TODAY="2026-06-28" run_resolve
  assert_error_exit1 "::error::projmagic: no active sprint contains today (2026-06-28)"
}

# --- source resolution ---------------------------------------------------------
@test "auto source = the most-recently-completed iteration" {
  TODAY="2026-06-30" run_resolve
  assert_ok
  [ "$(get_out source-title)" = "S-prev" ]
  [ "$(get_out source-id)" = "it-prev" ]
}

@test "explicit source-iteration title overrides latest-completed" {
  SOURCE_ITERATION="S-old" TODAY="2026-06-30" run_resolve
  assert_ok
  [ "$(get_out source-title)" = "S-old" ]
}

@test "explicit source AND target titles both honoured" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-cur" run_resolve
  assert_ok
  [ "$(get_out source-title)" = "S-prev" ]
  [ "$(get_out target-title)" = "S-cur" ]
}

# --- selection = in source AND open -------------------------------------------
# DEFAULT_ITEMS in it-prev: #1,#2 open issues; #3 closed issue; #4 open PR;
# #7 closed PR; #8 open draft. #5 open issue is in it-cur; #6 has no iteration.
@test "selection = open issues in source (closed/PR/draft/other-iteration all excluded)" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-cur" run_resolve
  assert_ok
  [ "$(get_out match-count)" = "2" ]
  [ "$(printf '%s' "$(get_out plan)" | jq -c 'map(.number)')" = "[1,2]" ]
}

@test "include-prs=true adds the OPEN PR but still excludes the closed PR and the draft" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-cur" INCLUDE_PRS="true" run_resolve
  assert_ok
  # open issues #1,#2 + open PR #4; closed PR #7 (state) and draft #8 (type) excluded.
  [ "$(get_out match-count)" = "3" ]
  [ "$(printf '%s' "$(get_out plan)" | jq -c 'map(.number)')" = "[1,2,4]" ]
}

# --- dry-run gating ------------------------------------------------------------
@test "dry-run (default) collects the move-list but emits NO mutation payload" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-cur" run_resolve
  assert_ok
  # plan is populated...
  [ "$(printf '%s' "$(get_out plan)" | jq 'length')" = "2" ]
  # ...but moves (what the mutation step consumes) is empty.
  [ "$(get_out moves)" = "[]" ]
}

@test "dry-run=false emits moves == plan (the mutation payload)" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="S-cur" DRY_RUN="false" run_resolve
  assert_ok
  [ "$(printf '%s' "$(get_out moves)" | jq -c 'map(.number)')" = "[1,2]" ]
  [ "$(get_out moves)" = "$(get_out plan)" ]
}

# --- error paths (fail loud, no silent no-op) ----------------------------------
@test "source == target -> friendly ::error:: and exit 1" {
  SOURCE_ITERATION="S-cur" TARGET_ITERATION="S-cur" run_resolve
  assert_error_exit1 "::error::projmagic: source and target iteration are the same"
}

@test "no active sprint contains today -> friendly ::error:: and exit 1" {
  TODAY="2026-05-01" run_resolve
  assert_error_exit1 "::error::projmagic: no active sprint contains today"
}

@test "no completed sprint to roll from (auto source) -> friendly ::error:: and exit 1" {
  ITER_CONFIG="$CONFIG_NO_COMPLETED" TODAY="2026-06-30" run_resolve
  assert_error_exit1 "::error::projmagic: no completed sprint to roll from"
}

@test "unknown iteration-field -> friendly ::error:: and exit 1" {
  ITER_CONFIG="$CONFIG_FIELD_NOT_FOUND" run_resolve
  assert_error_exit1 "::error::projmagic: iteration field 'Sprint' not found"
}

@test "field exists but is not an iteration field -> friendly ::error:: and exit 1" {
  ITER_CONFIG="$CONFIG_NOT_ITERATION" run_resolve
  assert_error_exit1 "::error::projmagic: field 'Status' is not an iteration field"
}

@test "unknown explicit target-iteration title -> friendly ::error:: and exit 1" {
  SOURCE_ITERATION="S-prev" TARGET_ITERATION="Nope" run_resolve
  assert_error_exit1 "::error::projmagic: target-iteration 'Nope' not found"
}

@test "unknown explicit source-iteration title -> friendly ::error:: and exit 1" {
  SOURCE_ITERATION="Nope" TARGET_ITERATION="S-cur" run_resolve
  assert_error_exit1 "::error::projmagic: source-iteration 'Nope' not found"
}

# --- in-script defaults (run under set -u without the env injected) ------------
@test "missing ITER_CONFIG/ITEMS exercise the in-script defaults and fail loud (no raw crash)" {
  # Bypass run_resolve so ITER_CONFIG/ITEMS/SOURCE/TARGET/INCLUDE_PRS/DRY_RUN are
  # genuinely UNSET: the script's `${VAR:-...}` defaults must hold under set -u,
  # yielding ITER_CONFIG='{}' -> field-not-found friendly error (not a jq crash).
  GH_OUT="$BATS_TEST_TMPDIR/github_output"
  : > "$GH_OUT"
  run env GITHUB_OUTPUT="$GH_OUT" TODAY="2026-06-30" bash "$BATS_FILE_TMPDIR/resolve.sh"
  [ "$status" -eq 1 ]
  case "$output" in
    *"::error::projmagic: iteration field"*) : ;;
    *) echo "expected friendly field-not-found error; got: $output"; return 1 ;;
  esac
  [ -z "$(grep '^source-id=' "$GH_OUT" || true)" ]
}
