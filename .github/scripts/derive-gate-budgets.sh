#!/usr/bin/env bash
# Derive gate budgets from a corpus of observed hosted-CI samples.
#
# Recipe (Slice 38 design, Decision 2) — the 3x floor is inside the formula, not
# a check applied afterwards, and it covers BOTH statistics because the gate can
# fail on either:
#
#   budget_p95 = round_up_2sf(max(8 * median(p95), 3 * max(p95)))
#   budget_p99 = round_up_2sf(max(2 * budget_p95, 8 * median(p99), 3 * max(p99)))
#
# Usage: ./.github/scripts/derive-gate-budgets.sh <corpus.tsv> [mode ...]
#
# A mode may be spelled either way -- `line-query` (as the CLI flag and every CI
# step name spell it) or `line_query` (as the corpus does). A mode that matches no
# corpus row is an error, not an empty success: this script is the only sanctioned
# source of a budget, and silence here is what sends someone back to hand-typing one.
set -euo pipefail

# Trailing window: derive median/max over the most-recent N distinct runs only,
# not all corpus history, so an aged-out freak sample can release the budget it
# inflated. N is the single documented value in AGENTS.md "## Gate budgets" and is
# pinned to GateFloorTests.swift's `windowSize` by a test. Keep this a bare
# top-of-file `WINDOW=<int>` assignment: that test reads it by line prefix.
WINDOW=20

# Corpus on stdin (WITH header) -> its N most-recent distinct run ids, newest first.
# `sort -rnu` = reverse numeric unique: GitHub databaseId is monotonic with run
# creation, so numeric-descending IS recency-descending. This is the exact window
# GateFloorTests.mostRecentRunIDs computes in Swift; the two must not drift.
window_run_ids() {
  local n="${1:-$WINDOW}"
  tail -n +2 | cut -f1 | sort -rnu | head -n "$n"
}

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
  # Run ids out of chronological order on purpose: physical row order must not
  # matter, only the numeric ranking. Run 305 has two rows (a realistic_provider
  # run genuinely does) -- the run id, not the row, is the unit of recency.
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n' > "$fixture"
  printf '100\tline_query\tuniform_1k\t24\t54\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1k\t30\t60\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1m\t31\t61\n'   >> "$fixture"
  printf '210\tline_query\tuniform_1k\t28\t58\n'   >> "$fixture"
  printf '99\tline_query\tuniform_1k\t22\t52\n'    >> "$fixture"

  assert_equal "305
210" "$(window_run_ids 2 < "$fixture")" "keeps the 2 most-recent distinct run ids"

  # N >= distinct-run-count is a no-op: keep them all, still newest-first.
  assert_equal "305
210
100
99" "$(window_run_ids 10 < "$fixture")" "keeps all runs when N exceeds the run count"

  rm -f "$fixture"
  echo "self_test=pass"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

corpus="${1:?usage: derive-gate-budgets.sh <corpus.tsv> [mode ...]}"
shift || true

modes="$(printf '%s' "$*" | tr '-' '_')"

awk -F'\t' -v modes="$modes" '
function ru2(x,   e, n) {          # round up to 2 significant figures
  if (x <= 0) return 0
  e = 1
  while (x / e >= 100) e *= 10
  n = x / e
  if (n == int(n)) return int(n) * e
  return (int(n) + 1) * e
}
function med(arr, n,   i, j, t) {  # lower median of a 1..n array, sorts in place
  for (i = 1; i < n; i++)
    for (j = i + 1; j <= n; j++)
      if (arr[i] + 0 > arr[j] + 0) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
  return arr[int((n + 1) / 2)] + 0
}
FNR == NR { KEEP[$1] = 1; next }   # first file: the windowed run ids
!($1 in KEEP) { next }             # skip the corpus header (id "run_id" is not in KEEP) and out-of-window rows
{
  seen[$2] = 1
  if (modes != "" && index(" " modes " ", " " $2 " ") == 0) next
  matched[$2] = 1
  k = $2 "|" $3
  n[k]++
  p95[k, n[k]] = $4
  p99[k, n[k]] = $5
}
END {
  # A requested mode with no rows is an operator error (a typo, or a mode the
  # corpus has never been harvested for). Say so and fail, rather than printing
  # nothing and exiting 0 -- which reads as "the corpus supports no change".
  if (modes != "") {
    want_count = split(modes, want, " ")
    for (i = 1; i <= want_count; i++) {
      if (!(want[i] in matched)) {
        known = ""
        for (m in seen) known = known (known == "" ? "" : ",") m
        printf "error=no_corpus_rows mode=%s known=%s\n", want[i], known > "/dev/stderr"
        exit 1
      }
    }
  }

  for (k in n) {
    cnt = n[k]
    for (i = 1; i <= cnt; i++) { a[i] = p95[k, i]; b[i] = p99[k, i] }
    m95 = med(a, cnt); x95 = a[cnt] + 0     # med() leaves the array sorted
    m99 = med(b, cnt); x99 = b[cnt] + 0

    b95 = ru2(8 * m95 > 3 * x95 ? 8 * m95 : 3 * x95)
    lo99 = 2 * b95
    if (8 * m99 > lo99) lo99 = 8 * m99
    if (3 * x99 > lo99) lo99 = 3 * x99
    b99 = ru2(lo99)

    printf "%-46s n=%-3d p95[med=%-6d max=%-6d] p99[med=%-6d max=%-6d] budget_p95=%-7d budget_p99=%-7d margin_p95=%.1fx margin_p99=%.1fx\n", \
           k, cnt, m95, x95, m99, x99, b95, b99, b95 / x95, b99 / x99
  }
}
' <(window_run_ids < "$corpus") "$corpus" | sort
