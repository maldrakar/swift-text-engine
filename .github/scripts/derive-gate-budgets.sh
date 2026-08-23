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
# Usage: ./.github/scripts/derive-gate-budgets.sh --self-test
# Usage: ./.github/scripts/derive-gate-budgets.sh --window-run-ids [N]   (reads corpus on stdin)
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

# The verdict values this derivation REFUSES, as the corpus's sixth column records them.
# Classified by what happened to the MEASUREMENT: budget_exceeded and
# budget_absolute_exceeded mean the sample was SLOW (the regression-laundering case -- one
# such row can set a budget by itself through the 3*max term); operation_failures means the
# timed path was degenerate. budget_stale is ADMITTED on purpose: it means the sample was
# FAST, and the prescribed response to it is to re-derive from exactly these rows.
# A legacy five-column row has no verdict and is admitted as "unknown".
#
# Pinned byte-for-byte against `rejectedVerdicts` in GateFloorTests.swift by
# testAdmissibleRowsMatchDeriveScript, over the --admissible-rows seam below. Keep this a
# bare top-of-file space-separated assignment.
REJECTED_VERDICTS="budget_exceeded budget_absolute_exceeded operation_failures"

# Corpus on stdin (WITH header) -> the rows this derivation admits, verbatim, in order.
# VERDICT FILTER ONLY: windowing is a separate axis (Decision 8 -- the verdict filter runs
# AFTER windowing, so neither window pin is touched, and a run whose rows are all rejected
# still consumes a window slot). $6 is empty for a five-column legacy row, which is why the
# empty case is tested explicitly rather than left to the substring search.
admissible_rows() {
  awk -F'\t' -v rejected=" $REJECTED_VERDICTS " '
    NR == 1 { next }
    $6 == "" { print; next }
    index(rejected, " " $6 " ") == 0 { print }
  '
}

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
  # P3 #1: clean up on the red path too. assert_equal exits 1 before any trailing
  # rm, so without this a failing self-test orphans the fixture. Double-quoted so
  # $fixture is baked in now (the local is out of scope by the time EXIT fires).
  trap "rm -f '$fixture'" EXIT
  # Run ids out of chronological order on purpose: physical row order must not
  # matter, only the numeric ranking. Run 305 has two rows (a realistic_provider
  # run genuinely does) -- the run id, not the row, is the unit of recency.
  printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\n' > "$fixture"
  printf '100\tline_query\tuniform_1k\t24\t54\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1k\t30\t60\n'   >> "$fixture"
  printf '305\tline_query\tuniform_1m\t31\t61\n'   >> "$fixture"
  printf '210\tline_query\tuniform_1k\t28\t58\n'   >> "$fixture"
  printf '99\tline_query\tuniform_1k\t22\t52\n'    >> "$fixture"

  # Second scenario, deliberately carrying an outlier: p95 med=10, max=100, so
  # 3*max (300) beats 8*med (80) and the MAX term governs. The first scenario is
  # median-governed (8*24=192 vs 3*30=90), so the two cover both branches of gov_p95.
  # Reuses the four run ids above on purpose: adding a new one would change the
  # window_run_ids assertions above.
  printf '305\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '210\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '100\tcolumn_query\toutlier\t10\t20\n'  >> "$fixture"
  printf '99\tcolumn_query\toutlier\t100\t200\n' >> "$fixture"

  assert_equal "305
210" "$(window_run_ids 2 < "$fixture")" "keeps the 2 most-recent distinct run ids"

  # N >= distinct-run-count is a no-op: keep them all, still newest-first.
  assert_equal "305
210
100
99" "$(window_run_ids 10 < "$fixture")" "keeps all runs when N exceeds the run count"

  # gov_p95 lives in the awk program BELOW the --self-test dispatch, so it is not
  # reachable as a function: re-invoke the script itself. `local` on its own line --
  # `local x="$(cmd)"` would take the builtin's status, masking a failing child.
  local derived
  derived="$("$0" "$fixture")" || {
    echo "self_test=fail label=gov_p95_derivation_exited status=$?"
    exit 1
  }

  gov_of() { printf '%s\n' "$derived" | awk -v k="$1" '$1 == k {
    for (i = 1; i <= NF; i++) if ($i ~ /^gov_p95=/) { split($i, a, "="); print a[2] } }'; }

  assert_equal "median" "$(gov_of 'line_query|uniform_1k')" \
    "gov_p95=median when 8*med >= 3*max"
  assert_equal "max" "$(gov_of 'column_query|outlier')" \
    "gov_p95=max when 3*max > 8*med"

  # The reject set, at the seam the Swift pin drives. Kept here as well so a shell-only
  # change (someone editing REJECTED_VERDICTS without running swift test) still fails.
  local verdict_fixture
  verdict_fixture="$(mktemp)"
  {
    printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict\n'
    printf '901\tline_query\tuniform_1k\t10\t20\tpass\n'
    printf '902\tline_query\tuniform_1k\t11\t21\tbudget_exceeded\n'
    printf '903\tline_query\tuniform_1k\t12\t22\tbudget_stale\n'
    printf '904\tline_query\tuniform_1k\t13\t23\n'
  } > "$verdict_fixture"

  local expected_admitted
  expected_admitted="$(
    printf '901\tline_query\tuniform_1k\t10\t20\tpass\n'
    printf '903\tline_query\tuniform_1k\t12\t22\tbudget_stale\n'
    printf '904\tline_query\tuniform_1k\t13\t23\n'
  )"
  assert_equal "$expected_admitted" "$(admissible_rows < "$verdict_fixture")" \
    "admissible_rows drops budget_exceeded, keeps budget_stale and legacy rows"
  rm -f "$verdict_fixture"

  # The SAME rule, driven through the FULL derivation -- the code path an operator runs.
  #
  # This case exists because the reject rule is written TWICE, in two awk programs sharing
  # only the REJECTED_VERDICTS constant: admissible_rows above (the seam
  # testAdmissibleRowsMatchDeriveScript pins across languages) and the main awk below, which
  # never calls admissible_rows. Deleting only the main awk filter line left EVERY automated
  # check in this repository green -- --self-test passed because it exercised the seam, the
  # cross-language pin passed because the seam was still correct, and
  # testEveryCommittedBudgetReproducesFromCorpus passed because the committed corpus is
  # entirely five-column so its output was byte-identical -- while a laundered
  # budget_exceeded row loosened a budget by four orders of magnitude. So this case must not
  # touch --admissible-rows: it invokes the script the way the recipe does, over a corpus
  # file, and asserts the derived BUDGET rather than a zero exit.
  local production_fixture production_stderr
  production_fixture="$(mktemp)"
  production_stderr="$(mktemp)"
  trap "rm -f '$fixture' '$production_fixture' '$production_stderr'" EXIT
  {
    printf 'run_id\tmode\tscenario\tp95_ns\tp99_ns\tverdict\n'
    printf '801\tline_query\tuniform_1k\t20\t40\tpass\n'
    printf '802\tline_query\tuniform_1k\t24\t44\tbudget_stale\n'
    printf '803\tline_query\tuniform_1k\t30\t50\n'
    # Absurd on purpose. Admitted, this single row governs through 3*max and takes
    # budget_p95 from 200 to 3000000 -- a 15 000x move, so the assertion below cannot pass
    # by rounding or by a near-miss.
    printf '804\tline_query\tuniform_1k\t1000000\t2000000\tbudget_exceeded\n'
  } > "$production_fixture"

  local production_out
  if ! production_out="$("$0" "$production_fixture" 2> "$production_stderr")"; then
    echo "self_test=fail label=production_filter_derivation_exited"
    cat "$production_stderr"
    exit 1
  fi

  budget_p95_of() { printf '%s\n' "$production_out" | awk -v k="$1" '$1 == k {
    for (i = 1; i <= NF; i++) if ($i ~ /^budget_p95=/) { split($i, a, "="); print a[2] } }'; }

  # 8*median(20,24,30) = 192 beats 3*max = 90, so the admitted rows alone yield 200.
  assert_equal "200" "$(budget_p95_of 'line_query|uniform_1k')" \
    "the derivation ITSELF drops budget_exceeded (admitting it would read 3000000)"

  # And the drop is loud, naming its reason (spec Decision 12): a filter nobody can see
  # firing is how a scenario silently loses its evidence.
  assert_equal "dropped=budget_exceeded rows=1" "$(cat "$production_stderr")" \
    "the derivation reports the dropped row on stderr, by reason"

  echo "self_test=pass"
}

if [[ "${1:-}" == "--self-test" ]]; then
  run_self_test
  exit 0
fi

# Test seam: expose the exact window_run_ids selection the derivation uses via
# <(window_run_ids < "$corpus"), so GateFloorTests.testWindowSelectionMatchesDeriveScript
# can pin it to Swift's mostRecentRunIDs. Reads the corpus (WITH header) on stdin;
# N defaults to WINDOW. Delegates -- it duplicates none of the selection logic.
if [[ "${1:-}" == "--window-run-ids" ]]; then
  window_run_ids "${2:-$WINDOW}"
  exit 0
fi

# Test seam mirroring --window-run-ids: exposes the exact verdict filter the derivation
# applies at read time, so GateFloorTests.testAdmissibleRowsMatchDeriveScript can pin it to
# the Swift reader. Reads the corpus (WITH header) on stdin. Delegates -- it duplicates none
# of the rule.
if [[ "${1:-}" == "--admissible-rows" ]]; then
  admissible_rows
  exit 0
fi

corpus="${1:?usage: derive-gate-budgets.sh <corpus.tsv> [mode ...]}"
shift || true

modes="$(printf '%s' "$*" | tr '-' '_')"

awk -F'\t' -v modes="$modes" -v rejected=" $REJECTED_VERDICTS " '
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
  # Read-time verdict filter (spec Decision 6): the corpus is append-only full history, and
  # what is COUNTED is decided here, exactly as the N=20 window already is. A rejected row is
  # a sample whose own hosted line said the measurement was slow or degenerate; admitting it
  # would let one bad run set a looser budget through the 3*max term, and
  # testEveryCommittedBudgetReproducesFromCorpus would then REQUIRE that loosened budget to
  # be committed for swift test to go green.
  if ($6 != "" && index(rejected, " " $6 " ") > 0) { dropped[$6]++; next }

  seen[$2] = 1
  if (modes != "" && index(" " modes " ", " " $2 " ") == 0) next
  matched[$2] = 1
  k = $2 "|" $3
  n[k]++
  p95[k, n[k]] = $4
  p99[k, n[k]] = $5
}
END {
  # Rejections are LOUD (spec Decision 12): silent filtering produces a corpus that looks
  # complete and is not. stderr, so stdout stays byte-identical for a corpus with nothing to
  # drop -- which is every corpus until the first post-slice-54 harvest lands. Emission order
  # is awk hash order; these are diagnostics, not a parsed format.
  #
  # FIRST in END, ahead of the no_corpus_rows check below, and that order is the point: a
  # rejected row never reaches seen[], so a mode whose every windowed row was rejected exits
  # through that check -- and printing the counts afterwards would print them never. The one
  # case the spec names these counts as the explanation for is exactly the case that exits
  # early.
  #
  # NOTE: no apostrophes anywhere inside this awk program -- it is single-quoted in the
  # shell, so one would terminate the quote and break the script.
  for (r in dropped)
    printf "dropped=%s rows=%d\n", r, dropped[r] > "/dev/stderr"

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
    # `>=`, NOT the `>` on the line above, and the asymmetry is deliberate. Up there a
    # tie is harmless: both terms yield the same number, so either branch is correct.
    # Here a tie is MEANINGFUL -- the token answers "is this budget resting on the
    # median term alone?", and on a tie it is. Harmonizing the two operators would
    # silently change the rule.
    gov95 = (8 * m95 >= 3 * x95) ? "median" : "max"
    lo99 = 2 * b95
    if (8 * m99 > lo99) lo99 = 8 * m99
    if (3 * x99 > lo99) lo99 = 3 * x99
    b99 = ru2(lo99)

    printf "%-46s n=%-3d p95[med=%-6d max=%-6d] p99[med=%-6d max=%-6d] budget_p95=%-7d budget_p99=%-7d gov_p95=%-6s margin_p95=%.1fx margin_p99=%.1fx\n", \
           k, cnt, m95, x95, m99, x99, b95, b99, gov95, b95 / x95, b99 / x99
  }
}
' <(window_run_ids < "$corpus") "$corpus" | sort
