#!/usr/bin/env bash
#
# Every headless test in this repo, in one command.
#
# WHY THIS EXISTS. There are TWO runners and THREE success formats, and any sweep written by hand
# gets some of them wrong — mine did, all session, and so did the block this replaces in README.md:
#
#   scene tests   godot/tests/<n>.tscn   run as a scene, print "all good (0 checks failed)"
#                                        ...except journal_carousel, which prints "journal_carousel: OK"
#   script tests  godot/tests/<n>.gd     NO .tscn — run with --script, print "<n> OK"
#   audits        tools/regression/*_audit.py   plain exit code
#
# A `for t in godot/tests/*.tscn` loop silently skips the four script tests (test_store, test_world,
# test_persist, state_graph_render) and grades journal_carousel as a failure or, worse, greps for a
# string it never prints and calls it a pass. Every one of those mistakes was made here first.
#
# A NEW TEST SHOULD PRINT `all good (0 checks failed)` and live in a .tscn. The other two shapes are
# grandfathered, not a menu.
#
#   tools/run_tests.sh            everything
#   tools/run_tests.sh godot      just the Godot tests
#   tools/run_tests.sh audits     just the Python audits
#
# Exits non-zero if anything failed. Close any running Raves first — it holds an instance lock and
# quits a headless test having printed NOTHING, which reads exactly like a pass.
set -uo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-$(python3 -c 'import sys;sys.path.insert(0,"tools/capture");import plat;print(plat.godot_bin())' 2>/dev/null)}"
WHAT="${1:-all}"
pass=0; fail=0; failed=""

run_godot() {  # name, then the args that address it
  local n="$1"; shift
  local out; out="$("$GODOT" --headless --path godot/ --quit-after 400 "$@" 2>&1)"
  # the three shapes, and nothing else counts
  if grep -qE "^all good \(0 checks failed\)|^${n}:? OK( |$)" <<<"$out" \
     && ! grep -qE "SCRIPT ERROR|Parse Error|checks failed:" <<<"$out"; then
    printf "  ok   %s\n" "$n"; pass=$((pass+1))
  else
    printf "  FAIL %s\n" "$n"; fail=$((fail+1)); failed="$failed $n"
    grep -E "FAIL |checks failed|SCRIPT ERROR|Parse Error" <<<"$out" | head -3 | sed 's/^/         /'
  fi
}

if [ -z "$GODOT" ] || [ ! -x "$GODOT" ]; then
  echo "error: no Godot found. Set GODOT=/path/to/Godot (see README)." >&2; exit 1
fi

if [ "$WHAT" = all ] || [ "$WHAT" = godot ]; then
  echo "── Godot scenes ──"
  for t in godot/tests/*.tscn; do
    n="$(basename "$t" .tscn)"; run_godot "$n" "res://tests/$n.tscn"
  done
  echo "── Godot scripts (no scene — these are the ones a *.tscn sweep misses) ──"
  for g in godot/tests/*.gd; do
    n="$(basename "$g" .gd)"; [ -f "godot/tests/$n.tscn" ] && continue
    run_godot "$n" --script "res://tests/$n.gd"
  done
fi

if [ "$WHAT" = all ] || [ "$WHAT" = audits ]; then
  echo "── regression audits ──"
  for a in tools/regression/*_audit.py; do
    n="$(basename "$a" .py)"
    if python3 "$a" >/dev/null 2>&1; then printf "  ok   %s\n" "$n"; pass=$((pass+1))
    else printf "  FAIL %s\n" "$n"; fail=$((fail+1)); failed="$failed $n"; fi
  done
fi

echo
if [ "$fail" -eq 0 ]; then echo "all good — $pass passed"; exit 0; fi
echo "$fail FAILED of $((pass+fail)):$failed"; exit 1
