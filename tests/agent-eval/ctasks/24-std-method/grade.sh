#!/bin/sh
# Task 24-std-method, run last in the graded tree's root (the suite filters
# eval_std_strip, std and guide have passed): the guide's std topic teaches
# the two functions with an example, the compiler prints it, and a test of
# the agent's own (not the hidden ones) uses them and passes.
fail() { echo "$*" >&2; exit 1; }
md=compiler/guide/std.md
[ -f "$md" ] || fail "no $md"
for name in strip_prefix strip_suffix; do
    # The topic's text by hand: its API listing (@STD-API@) comes from std's
    # source by itself, so it does not count.
    grep -v '@STD-API@' "$md" | grep -q "$name" || fail "$md does not mention $name (only the generated API listing does)"
    "$TACHYONC" guide std 2>/dev/null | grep -q "$name" || fail "tachyonc guide std does not print $name"
done
# An example: a ```tach block of the topic (compiled and run by the guide
# filter) that calls one of them.
awk '/^```tach/ { inb = 1; next } /^```/ { inb = 0 } inb && /strip_(prefix|suffix)\(/ { found = 1 } END { exit !found }' "$md" ||
    fail "no tach example in $md calls strip_prefix or strip_suffix"
# A test of the agent's own in tests/run/ (the hidden eval_std_strip_*
# cases do not count) for each function, and it passes.
own=""
for name in strip_prefix strip_suffix; do
    found=""
    for f in tests/run/*.tach tests/run/*/*.tach; do
        [ -f "$f" ] || continue
        case "$f" in tests/run/eval_std_strip_*) continue ;; esac
        if grep -q "$name" "$f"; then
            found="$f"
            case " $own " in *" $f "*) ;; *) own="$own $f" ;; esac
        fi
    done
    [ -n "$found" ] || fail "no test in tests/run/ (besides the hidden ones) uses $name"
done
for f in $own; do
    case "$f" in */main.tach) case_name=$(basename "$(dirname "$f")") ;; *) case_name=$(basename "$f" .tach) ;; esac
    out=$(sh tests/run.sh -c "$TACHYONC" "$case_name" 2>&1) ||
        fail "the test $f fails: $(printf '%s\n' "$out" | grep -m1 -E 'FAIL|no cases' || echo "tests/run.sh $case_name failed")"
done
exit 0
