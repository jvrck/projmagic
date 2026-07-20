#!/usr/bin/env bats
#
# Regression guard for the `runs-on` input on both reusable workflows.
#
# WHY THIS SHAPE: unlike norm.bats / roll-sprint.bats there is no inline script
# to exec here — `runs-on` is workflow *structure*, resolved by the Actions
# runner before any step runs, so it can only be asserted against the YAML
# itself. We read the REAL shipped workflows with yq (never a copy) so a
# restructure can't leave this suite green against a stale duplicate.
#
# WHAT IT PROTECTS: projmagic is public and has consumers who never set this
# input. The default MUST keep resolving to `ubuntu-latest` — a self-hosted
# default would break every one of them. That is the assertion below that
# matters most; the rest guard the plumbing around it.
#
# Run locally:  yq (mikefarah) + jq + bats-core on PATH, then `bats tests/`.

REUSABLE_WORKFLOWS=(
  "add-to-project"
  "roll-sprint"
)

# The exact expression every job must use to consume the input. Pinned as a
# literal so a job that silently reverts to a hardcoded runner fails here.
EXPECTED_RUNS_ON='${{ fromJSON(inputs.runs-on) }}'

# The default, as it must appear in both workflows.
EXPECTED_DEFAULT='["ubuntu-latest"]'

setup_file() {
  command -v yq >/dev/null 2>&1 \
    || { echo "FATAL: yq (mikefarah) not on PATH — cannot read the workflows" >&2; return 1; }
  command -v jq >/dev/null 2>&1 \
    || { echo "FATAL: jq not on PATH — needed to parse the default" >&2; return 1; }

  local wf
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    [ -f "$BATS_TEST_DIRNAME/../.github/workflows/${wf}.yml" ] \
      || { echo "FATAL: workflow not found: .github/workflows/${wf}.yml" >&2; return 1; }
  done
}

# Path to a reusable workflow by short name.
wf_path() {
  printf '%s\n' "$BATS_TEST_DIRNAME/../.github/workflows/${1}.yml"
}

# --- the input is declared on both workflows ----------------------------------

@test "both reusable workflows declare a 'runs-on' workflow_call input" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    run yq -r '.on.workflow_call.inputs["runs-on"] // "MISSING"' "$(wf_path "$wf")"
    [ "$status" -eq 0 ]
    [ "$output" != "MISSING" ] || {
      echo "FAIL: ${wf}.yml declares no 'runs-on' workflow_call input" >&2
      return 1
    }
  done
}

@test "the input is an optional string on both workflows" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    run yq -r '.on.workflow_call.inputs["runs-on"].type' "$(wf_path "$wf")"
    [ "$status" -eq 0 ]
    [ "$output" = "string" ]

    run yq -r '.on.workflow_call.inputs["runs-on"].required' "$(wf_path "$wf")"
    [ "$status" -eq 0 ]
    [ "$output" = "false" ]
  done
}

@test "the input is documented (non-empty description) on both workflows" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    run yq -r '.on.workflow_call.inputs["runs-on"].description // ""' "$(wf_path "$wf")"
    [ "$status" -eq 0 ]
    [ -n "${output//[[:space:]]/}" ]
  done
}

# --- THE load-bearing assertion ------------------------------------------------

@test "the default is ubuntu-latest on both workflows (public consumers must not move)" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    run yq -r '.on.workflow_call.inputs["runs-on"].default' "$(wf_path "$wf")"
    [ "$status" -eq 0 ]
    [ "$output" = "$EXPECTED_DEFAULT" ] || {
      echo "FAIL: ${wf}.yml default is '${output}', expected '${EXPECTED_DEFAULT}'." >&2
      echo "      projmagic is public: a non-hosted default breaks every consumer" >&2
      echo "      that does not set this input." >&2
      return 1
    }
  done
}

@test "the default is a valid JSON array of exactly ubuntu-latest" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    local def
    def="$(yq -r '.on.workflow_call.inputs["runs-on"].default' "$(wf_path "$wf")")"

    # It must survive fromJSON at runtime — a malformed default would fail every
    # job at expression-evaluation time, for every consumer.
    run jq -e 'type == "array"' <<<"$def"
    [ "$status" -eq 0 ]

    run jq -r -e '. == ["ubuntu-latest"]' <<<"$def"
    [ "$status" -eq 0 ]
  done
}

# --- the input is actually threaded to every job -------------------------------

@test "every job in both reusable workflows consumes the input" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    local path job_count
    path="$(wf_path "$wf")"

    job_count="$(yq -r '.jobs | length' "$path")"
    [ "$job_count" -gt 0 ] || {
      echo "FAIL: ${wf}.yml declares no jobs — workflow restructured?" >&2
      return 1
    }

    # Every job, by name, so a NEW job added later that forgets the input is
    # caught too (add-to-project.yml already has two — `setup` is easy to miss).
    while IFS= read -r job; do
      [ -n "$job" ] || continue
      local actual
      actual="$(yq -r ".jobs.\"${job}\".\"runs-on\"" "$path")"
      [ "$actual" = "$EXPECTED_RUNS_ON" ] || {
        echo "FAIL: ${wf}.yml job '${job}' has runs-on '${actual}'," >&2
        echo "      expected '${EXPECTED_RUNS_ON}'." >&2
        return 1
      }
    done < <(yq -r '.jobs | keys | .[]' "$path")
  done
}

@test "no hardcoded runner label survives in either reusable workflow" {
  for wf in "${REUSABLE_WORKFLOWS[@]}"; do
    run grep -nE '^\s*runs-on:\s*(ubuntu|macos|windows|self-hosted|\[)' "$(wf_path "$wf")"
    # grep must find NOTHING — every runs-on is the expression form.
    [ "$status" -ne 0 ] || {
      echo "FAIL: ${wf}.yml still hardcodes a runner:" >&2
      echo "$output" >&2
      return 1
    }
  done
}
