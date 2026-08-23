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
# Every candidate's SOURCE repository is checked before its log is fetched: a run whose
# .head_repository.full_name is not --repo is skipped (skip=foreign_repo), and a run whose
# source cannot be read is skipped too (skip=provenance_unknown). There is no opt-out --
# an optional policy is not a policy. The --runs id,id path obeys the same check.
#
# Emits corpus rows on stdout (no header), ready to append:
#   run_id <TAB> mode <TAB> scenario <TAB> p95_ns <TAB> p99_ns <TAB> verdict
#
# The sixth column is the ROW'S OWN gate verdict: `pass`, a GateFailureReason raw value, or
# `none` for a summary line printed without --gate. It is the only place the corpus schema
# is written down. Readers accept legacy FIVE-column rows -- the committed corpus consists
# entirely of them -- and treat a missing verdict as admissible.
#
# derive-gate-budgets.sh and GateFloorTests then REFUSE, at read time, rows whose verdict is
# budget_exceeded, budget_absolute_exceeded or operation_failures: a summary line is printed
# BEFORE the gate verdict is checked, so a slow sample genuinely reaches a hosted log, and
# the 3*max term lets one such row set a budget by itself.
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

# Pure decision over (run id, observed head repository, expected repository).
#
# Neither `gh run list --json` nor `gh run view --json` exposes the source repository --
# both field lists were checked and it is absent. The datum lives at
# `gh api repos/{owner}/{repo}/actions/runs/{id}` as `.head_repository.full_name`.
#
# Rejected alternative: switching candidate selection to the workflow-runs API, which
# returns ids and sources together in one call. It rewrites the selection path wholesale
# and the --runs entry path would still need per-run lookups, so the policy would have two
# implementations. One call per candidate at N <= 40 is not worth a second code path.
# Likewise rejected: skipping the probe for `event != pull_request` runs, which cannot have
# a foreign head repository. It buys nothing the --corpus dedup does not already buy, and
# costs the same second code path.
admissible_source() {
  local id="$1" observed="$2" expected="$3"
  # Fail CLOSED on an unreadable source: that is the one state a fork can manufacture.
  # `null` is what `gh api --jq` prints for a null field -- it is not a repository name.
  if [[ -z "$observed" || "$observed" == "null" ]]; then
    printf 'skip=provenance_unknown run=%s\n' "$id"
  elif [[ "$observed" != "$expected" ]]; then
    printf 'skip=foreign_repo run=%s source=%s\n' "$id" "$observed"
  else
    printf 'plan=harvest run=%s\n' "$id"
  fi
}

# The corpus-row parser: a hosted CI log on stdin, six-column TSV rows on stdout.
# $1 = run id.
#
# Extracted from the network branch (spec Decision 9) so --self-test can drive it over a
# fixture. Leaving it inline would have made the verdict rule a guard with no way to fail --
# the exact defect class this slice exists to prevent -- and it retroactively brings the
# existing five-column parser under test for the first time, including the exact-key rule
# that keeps the prefixed wrap lines from emitting rows.
extract_rows() {
  awk -v run="$1" '
    # Row-level verdict for one summary line.
    #
    # `failures=` OUTRANKS the gate verdict, and that is not belt-and-braces. formatSummary
    # prints failures=N UNCONDITIONALLY, outside the --gate branch
    # (BenchmarkSupport.swift:103), whereas gate=/reason= appear only on gated steps -- and
    # the FIRST hosted evidence for a new mode necessarily comes from an ungated step,
    # because its budget does not exist yet. Reading degeneracy from the verdict alone would
    # therefore miss it on exactly the line shape node 6 bootstraps with.
    #
    # gate=fail with no reason= cannot be produced by formatSummary; if one ever appears,
    # something is wrong, so it takes the REJECTING verdict rather than the admitting one.
    function verdict(g, r, f) {
      if (f != "" && f + 0 != 0) return "operation_failures"
      if (g == "pass") return "pass"
      if (g == "fail") return (r != "" ? r : "budget_exceeded")
      return "none"
    }

    function emit_pairs(a, b,   x, y, n, m, i) {
      if (a == "" || b == "") return
      n = split(a, x, ",")
      m = split(b, y, ",")
      if (n != m) return
      for (i = 1; i <= n; i++)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", run, "realistic_provider", "100k_lines_10mb_text", x[i], y[i], "none"
    }

    # Shape 2 must be tested first: it carries mode= and *_p95_ns_values= but no
    # bare p95_ns=, so shape 1 would not match it anyway -- the order is for the
    # reader, not the parser. It comes from a step run WITHOUT --gate, so `none`.
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

    # The regex is a cheap line filter; the EXACT key is what decides. That distinction is
    # what makes the wrap modes inert: `query_p95_ns=37` matches the regex and then fails
    # kv[1] == "p95_ns", so the line yields no row until node 6 un-prefixes it deliberately.
    /p95_ns=[0-9]+/ && /p99_ns=[0-9]+/ {
      mode = ""; scenario = ""; p95 = ""; p99 = ""; gate = ""; reason = ""; failures = ""
      for (i = 1; i <= NF; i++) {
        split($i, kv, "=")
        if (kv[1] == "mode") mode = kv[2]
        else if (kv[1] == "scenario") scenario = kv[2]
        else if (kv[1] == "p95_ns") p95 = kv[2]
        else if (kv[1] == "p99_ns") p99 = kv[2]
        else if (kv[1] == "gate") gate = kv[2]
        else if (kv[1] == "reason") reason = kv[2]
        else if (kv[1] == "failures") failures = kv[2]
      }
      if (mode != "" && scenario != "" && p95 != "" && p99 != "")
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", run, mode, scenario, p95, p99, verdict(gate, reason, failures)
    }
  '
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

  # ------------------------------------------------------------------
  # extract_rows: the parser, previously unreachable from --self-test because it
  # lived inside the network branch. Putting the new verdict rule there as-is would
  # have produced a guard with no way to fail -- the defect class this slice exists
  # to prevent. Extracting it also brings the EXISTING five-column parser under test
  # for the first time, including the prefixed-token protection both wrap modes rely on.
  # ------------------------------------------------------------------
  local logfixture
  logfixture="$(mktemp)"
  {
    # 1. A gated pass line.
    printf 'mode=line_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 line_count=1000 p95_ns=24 p99_ns=54 failures=0 budget_p95_ns=190 budget_p99_ns=440 headroom_p95=7.9x headroom_p99=8.1x budget_absolute_p99_ns=1666666 headroom_absolute_p99=30864.1x gate=pass checksum=1\n'
    # 2. The regression-laundering row: slow, and must never enter the corpus as evidence
    #    of normal cost. The summary line is printed BEFORE the verdict is checked, so it
    #    genuinely reaches a hosted log.
    printf 'mode=line_query provider=uniform scenario=uniform_100k p95_ns=30 p99_ns=60 failures=0 budget_p95_ns=280 budget_p99_ns=560 gate=fail reason=budget_exceeded checksum=2\n'
    # 3. budget_stale: the sample was FAST. Admitted -- its prescribed fix needs it.
    printf 'mode=line_query provider=uniform scenario=uniform_1m p95_ns=31 p99_ns=61 failures=0 budget_p95_ns=320 budget_p99_ns=640 gate=fail reason=budget_stale checksum=3\n'
    # 4. A step run WITHOUT --gate: no gate= token at all. Admitted as `none` -- a new
    #    mode's first hosted evidence necessarily looks like this, because its budget does
    #    not exist yet, and rejecting it would make a gate unbootstrappable.
    printf 'mode=column_query provider=uniform scenario=uniform_1k iterations=5000 operations_per_sample=256 p95_ns=40 p99_ns=70 failures=0 checksum=4\n'
    # 5. THE NODE-6 BOOTSTRAP HOLE: no gate= token AND failures=3. Degeneracy must be read
    #    from failures=, which formatSummary prints unconditionally, or this line -- the
    #    exact shape node 6's first harvest produces -- is admitted as healthy.
    printf 'mode=column_query provider=uniform scenario=uniform_100k p95_ns=41 p99_ns=71 failures=3 checksum=5\n'
    # 6. failures= OUTRANKS the verdict: gate=pass cannot launder a degenerate timing.
    printf 'mode=point_query provider=uniform scenario=uniform_1k p95_ns=42 p99_ns=72 failures=2 budget_p95_ns=900 budget_p99_ns=1800 gate=pass checksum=6\n'
    # 7. A wrap_row_query line: PREFIXED latency tokens -> NO ROW. Nothing on the shell side
    #    pinned this before.
    printf 'mode=wrap_row_query scenario=uniform_1k total_rows=1000 query_operations_per_sample=256 query_p95_ns=37 query_p99_ns=41 checksum=7\n'
    # 8. A wrap_compute line, full node-6-ready shape (scenario=, drain_p99_ns=) with the
    #    latency tokens still prefixed -> NO ROW.
    printf 'mode=wrap_compute scenario=width_40 width=40 total_rows=200000 compute_operations_per_sample=256 compute_p95_ns=210 compute_p99_ns=260 drain_operations_per_sample=16 drain_p95_ns=4100 drain_p99_ns=5200 reindex_operations_per_sample=1 reindex_ns=61000000\n'
    # 9. Shape 2, the pre-slice-45 realistic relative observation: 2 base + 2 head -> 4 rows.
    printf 'mode=realistic_relative_observation base_p95_ns_values=11,12 base_p99_ns_values=21,22 head_p95_ns_values=13,14 head_p99_ns_values=23,24\n'
    # 10. A real `gh run view --log` line carries a job/step/timestamp prefix. awk scans all
    #     fields, so the prefix is inert -- pinned rather than assumed.
    printf 'Host tests and benchmark gate\tSynthetic gate\t2026-08-23T10:00:00Z mode=pipeline provider=uniform scenario=uniform_1k p95_ns=50 p99_ns=80 failures=0 budget_p95_ns=500 budget_p99_ns=1000 gate=pass checksum=10\n'
    # 11. Beyond the spec truth table, fail-closed: gate=fail with no reason= cannot be
    #     produced by formatSummary, so if one ever appears something is wrong. Treat it as
    #     the rejecting verdict rather than admitting it.
    printf 'mode=pipeline provider=uniform scenario=uniform_100k p95_ns=51 p99_ns=81 failures=0 budget_p95_ns=500 budget_p99_ns=1000 gate=fail checksum=11\n'
  } > "$logfixture"

  local expected_rows
  expected_rows="$(
    printf '999\tline_query\tuniform_1k\t24\t54\tpass\n'
    printf '999\tline_query\tuniform_100k\t30\t60\tbudget_exceeded\n'
    printf '999\tline_query\tuniform_1m\t31\t61\tbudget_stale\n'
    printf '999\tcolumn_query\tuniform_1k\t40\t70\tnone\n'
    printf '999\tcolumn_query\tuniform_100k\t41\t71\toperation_failures\n'
    printf '999\tpoint_query\tuniform_1k\t42\t72\toperation_failures\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t11\t21\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t12\t22\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t13\t23\tnone\n'
    printf '999\trealistic_provider\t100k_lines_10mb_text\t14\t24\tnone\n'
    printf '999\tpipeline\tuniform_1k\t50\t80\tpass\n'
    printf '999\tpipeline\tuniform_100k\t51\t81\tbudget_exceeded\n'
  )"

  assert_equal "$expected_rows" "$(extract_rows 999 < "$logfixture")" \
    "extract_rows: six columns, failures= outranks the verdict, prefixed wrap lines emit nothing"

  rm -f "$logfixture"

  # ------------------------------------------------------------------
  # admissible_source: the run-level axis. A fork executes its own code and can print
  # gate=pass beside any number it likes, so no per-row check helps here -- and the
  # --runs id,id entry path bypassed even the workflow filter, so this was the one
  # unauthenticated link in a chain carrying twelve blocking budgets.
  # ------------------------------------------------------------------
  assert_equal "plan=harvest run=555" \
    "$(admissible_source 555 'maldrakar/swift-text-engine' 'maldrakar/swift-text-engine')" \
    "admissible_source admits a run whose head repository is the harvested one"

  assert_equal "skip=foreign_repo run=555 source=attacker/swift-text-engine" \
    "$(admissible_source 555 'attacker/swift-text-engine' 'maldrakar/swift-text-engine')" \
    "admissible_source rejects a fork's run and names the source it saw"

  # Fails CLOSED. An unreadable provenance (deleted branch, 404, expired token, rate
  # limit) is the one state a fork can manufacture, so unknown must mean rejected --
  # there is deliberately no --allow-failed escape hatch: an optional policy is not one.
  assert_equal "skip=provenance_unknown run=555" \
    "$(admissible_source 555 '' 'maldrakar/swift-text-engine')" \
    "admissible_source fails closed when the source cannot be read"

  # `gh api --jq` prints the four characters `null` for a null field, which is not a
  # repository name and must not be compared as one.
  assert_equal "skip=provenance_unknown run=555" \
    "$(admissible_source 555 'null' 'maldrakar/swift-text-engine')" \
    "admissible_source treats a null head repository as unknown, not as a foreign name"

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

  # --dry-run stays NETWORK-FREE: it previews the dedup decision only. The provenance
  # decision below costs one API call per candidate, which is the thing a dry run exists to
  # avoid. A dry run therefore over-reports what a real harvest would take.
  if [[ "$dry_run" == 1 ]]; then
    echo "$decision" >&2
    continue
  fi

  # Provenance, per run. Placed after the dedup skip and before the log fetch, so a run
  # already in the corpus still costs ZERO API calls -- the existing property this must not
  # break. Applied to BOTH entry paths, --runs included: that path bypassed even the
  # workflow filter, so a caller passing an inadmissible id now gets a loud skip= and no
  # row (a deliberate behaviour change to a documented flag).
  #
  # `< /dev/null` so gh cannot swallow the while-loop's stdin, exactly as the log fetch
  # below does. `|| true` turns any gh failure into an empty source, which admissible_source
  # rejects -- fail-closed by construction rather than by a second branch.
  source_repo="$(gh api "repos/$repo/actions/runs/$id" \
    --jq '.head_repository.full_name' < /dev/null 2>/dev/null || true)"
  source_decision="$(admissible_source "$id" "$source_repo" "$repo")"
  if [[ "$source_decision" == skip=* ]]; then
    echo "$source_decision" >&2
    continue
  fi

  # A run whose log has aged out of retention, or that never produced benchmark
  # lines, must not abort the harvest: skip it loudly and keep going. Without the
  # `|| true` the pipefail on an expired log would kill the whole sweep, and a
  # partial corpus is exactly the failure mode the slice-38 record warns about
  # ("harvest EVERY available hosted run, not a convenient subset"). Since slice 54
  # "available" means "available AND admissible": a run whose source repository is not
  # this one, and a row whose own line reports a slow or degenerate measurement, are
  # excluded on purpose and said out loud on stderr. That is a policy, not a convenience.
  log="$(gh run view "$id" -R "$repo" --log < /dev/null 2>/dev/null || true)"
  if [[ -z "$log" ]]; then
    echo "warn=log_unavailable run=$id" >&2
    continue
  fi

  printf '%s\n' "$log" | extract_rows "$id"
done
