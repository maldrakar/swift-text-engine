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

limit=40
repo="maldrakar/swift-text-engine"
runs=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="${2:?--limit needs a value}"; shift 2 ;;
    --repo)  repo="${2:?--repo needs a value}"; shift 2 ;;
    --runs)  runs="${2:?--runs needs a comma-separated list}"; shift 2 ;;
    *) echo "usage: harvest-gate-corpus.sh [--limit N] [--repo OWNER/NAME] [--runs id,id,...]" >&2; exit 2 ;;
  esac
done

if [[ -n "$runs" ]]; then
  run_ids="$(printf '%s' "$runs" | tr ',' '\n')"
else
  run_ids="$(gh run list -R "$repo" --workflow swift-ci.yml --limit "$limit" \
    --json databaseId --jq '.[].databaseId')"
fi

printf '%s\n' "$run_ids" | while read -r id; do
  [[ -n "$id" ]] || continue

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
