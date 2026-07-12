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
NR == 1 { next }                   # header
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
' "$corpus" | sort
