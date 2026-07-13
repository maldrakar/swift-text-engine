#!/usr/bin/env bash
# Harvest hosted-CI latency samples into the corpus TSV that
# derive-gate-budgets.sh consumes.
#
# This is the *append* half of the loop AGENTS.md prescribes when a gate reports
# `reason=budget_stale`: re-derive from fresh hosted evidence. Without it, only
# the derive half was executable and the corpus could be refreshed by hand alone
# -- which is how a budget gets hand-typed, the practice the gate exists to stop.
#
# Usage:
#   ./.github/scripts/harvest-gate-corpus.sh [--limit N] [--repo OWNER/NAME]
#   ./.github/scripts/harvest-gate-corpus.sh --runs 29150501304,29187553818
#
# Emits corpus rows on stdout (no header), ready to append:
#   run_id <TAB> mode <TAB> scenario <TAB> p95_ns <TAB> p99_ns
#
# Two hosted line shapes carry latency, and both are harvested:
#
#   1. Benchmark summary lines (`mode=<m> ... p95_ns=N p99_ns=M`) -- every gate
#      step and every non-gate benchmark step prints one per scenario.
#   2. The realistic-provider relative-observation line
#      (`mode=realistic_relative_observation ... base_p95_ns_values=a,b,c,d ...`).
#      That step runs --realistic-provider WITHOUT --gate and keeps the raw
#      benchmark output in a temp file, so shape 1 never reaches the log for this
#      mode; its per-repetition values are the only hosted evidence there is.
#      Base and head are different trees, but both measure the same hosted
#      workload, and the corpus already mixes trees across slices, so both sides
#      are taken.
set -euo pipefail

# ---------------------------------------------------------------------------
# Pure selection logic (covered by --self-test, no network required)
# ---------------------------------------------------------------------------

# Corpus on stdin -> the run ids it already carries, one per line, sorted unique.
# The run id is the dedup key, not the row: one run legitimately contributes many
# rows (a realistic_provider run contributes 8), and two of them can be identical.
# That is why `sort -u` over the corpus is NOT a substitute for this -- it would
# collapse two genuine repetitions that happened to measure the same nanoseconds.
harvested_run_ids() {
  tail -n +2 | cut -f1 | sort -u
}

# $1 = candidate run ids (newline-separated), $2 = already-harvested ids.
# Emits one decision per candidate, so the caller never has to re-derive it and
# --dry-run can print exactly what a real harvest would do.
plan_runs() {
  local candidates="$1" harvested="$2" id
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if [[ -n "$harvested" ]] && printf '%s\n' "$harvested" | grep -qxF -- "$id"; then
      printf 'skip=already_harvested run=%s\n' "$id"
    else
      printf 'plan=harvest run=%s\n' "$id"
    fi
  done <<< "$candidates"
}

# ---------------------------------------------------------------------------
# Self-test (pure selection logic, no network, no gh)
# ---------------------------------------------------------------------------

assert_equal() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "self_test=fail label=$label"
    echo "  expected: [$expected]"
    echo "  actual:   [$actual]"
    exit 1
  fi
}

run_self_test() {
  local fixture
  fixture="$(mktemp)"
  # A corpus already carrying runs 111 and 222. Run 222 has several rows, as a
  # realistic_provider run genuinely does -- the run id, not the row, is the key.
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n' > "$fixture"
  printf '111\tline_query\tuniform_1k\t24\t54\n' >> "$fixture"
  printf '222\trealistic_provider\t100k_lines_10mb_text\t12130\t12423\n' >> "$fixture"
  printf '222\trealistic_provider\t100k_lines_10mb_text\t12130\t12423\n' >> "$fixture"

  assert_equal "111
222" "$(harvested_run_ids < "$fixture")" "harvested_run_ids drops the header and dedups"

  # The bug this guards: a corpus append that re-harvests a run it already has
  # double-weights that run in median(), the term governing most budgets.
  assert_equal "skip=already_harvested run=111
plan=harvest run=333
skip=already_harvested run=222
plan=harvest run=444" \
    "$(plan_runs "111
333
222
444" "$(harvested_run_ids < "$fixture")")" \
    "plan_runs skips runs already in the corpus"

  # No corpus given (rebuilding from scratch, e.g. after the parser learns a new
  # line shape) -- every candidate must be harvested.
  assert_equal "plan=harvest run=111
plan=harvest run=333" "$(plan_runs "111
333" "")" "plan_runs harvests everything when no corpus is given"

  # A header-only corpus is empty, not a skip-everything corpus.
  local empty
  empty="$(mktemp)"
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n' > "$empty"
  assert_equal "plan=harvest run=111" \
    "$(plan_runs "111" "$(harvested_run_ids < "$empty")")" \
    "plan_runs treats a header-only corpus as empty"

  rm -f "$fixture" "$empty"
  echo "self_test=pass"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

limit=40
repo="maldrakar/swift-text-engine"
runs=""
corpus=""
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit)   limit="${2:?--limit needs a value}"; shift 2 ;;
    --repo)    repo="${2:?--repo needs a value}"; shift 2 ;;
    --runs)    runs="${2:?--runs needs a comma-separated list}"; shift 2 ;;
    --corpus)  corpus="${2:?--corpus needs a path}"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "usage: harvest-gate-corpus.sh [--limit N] [--repo OWNER/NAME] [--runs id,id,...] [--corpus PATH] [--dry-run] [--self-test]" >&2; exit 2 ;;
  esac
done

if [[ -n "$runs" ]]; then
  run_ids="$(printf '%s' "$runs" | tr ',' '\n')"
else
  run_ids="$(gh run list -R "$repo" --workflow swift-ci.yml --limit "$limit" \
    --json databaseId --jq '.[].databaseId')"
fi

# An unreadable --corpus fails closed. Silently treating it as empty would harvest
# every run and re-append the whole corpus -- the exact duplication this guards.
harvested=""
if [[ -n "$corpus" ]]; then
  if [[ ! -r "$corpus" ]]; then
    echo "error=corpus_unreadable path=$corpus" >&2
    exit 2
  fi
  harvested="$(harvested_run_ids < "$corpus")"
fi

plan_runs "$run_ids" "$harvested" | while read -r decision; do
  id="${decision##*run=}"

  # Skipping happens BEFORE the log is fetched, so a re-harvest costs no API calls
  # for runs already in the corpus. stderr, so it never lands in the corpus itself.
  if [[ "$decision" == skip=* ]]; then
    echo "$decision" >&2
    continue
  fi

  if [[ "$dry_run" == 1 ]]; then
    echo "$decision" >&2
    continue
  fi

  # A run whose log has aged out of retention, or that never produced benchmark
  # lines, must not abort the harvest: skip it loudly and keep going. Without the
  # `|| true` the pipefail on an expired log would kill the whole sweep, and a
  # partial corpus is exactly the failure mode the slice-38 record warns about
  # ("harvest EVERY available hosted run, not a convenient subset").
  log="$(gh run view "$id" -R "$repo" --log < /dev/null 2>/dev/null || true)"
  if [[ -z "$log" ]]; then
    echo "warn=log_unavailable run=$id" >&2
    continue
  fi

  printf '%s\n' "$log" | awk -v run="$id" '
    function emit_pairs(a, b,   x, y, n, m, i) {
      if (a == "" || b == "") return
      n = split(a, x, ",")
      m = split(b, y, ",")
      if (n != m) return
      for (i = 1; i <= n; i++)
        printf "%s\t%s\t%s\t%s\t%s\n", run, "realistic_provider", "100k_lines_10mb_text", x[i], y[i]
    }

    # Shape 2 must be tested first: it carries mode= and *_p95_ns_values= but no
    # bare p95_ns=, so shape 1 would not match it anyway -- the order is for the
    # reader, not the parser.
    /mode=realistic_relative_observation/ {
      bp95 = ""; bp99 = ""; hp95 = ""; hp99 = ""
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "base_p95_ns_values") bp95 = kv[2]
        else if (kv[1] == "base_p99_ns_values") bp99 = kv[2]
        else if (kv[1] == "head_p95_ns_values") hp95 = kv[2]
        else if (kv[1] == "head_p99_ns_values") hp99 = kv[2]
      }
      emit_pairs(bp95, bp99)
      emit_pairs(hp95, hp99)
      next
    }

    /p95_ns=[0-9]+/ && /p99_ns=[0-9]+/ {
      mode = ""; scenario = ""; p95 = ""; p99 = ""
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "mode") mode = kv[2]
        else if (kv[1] == "scenario") scenario = kv[2]
        else if (kv[1] == "p95_ns") p95 = kv[2]
        else if (kv[1] == "p99_ns") p99 = kv[2]
      }
      if (mode != "" && scenario != "" && p95 != "" && p99 != "")
        printf "%s\t%s\t%s\t%s\t%s\n", run, mode, scenario, p95, p99
    }
  '
done
