#!/bin/sh
# The agent's own test: a new tests/run/*.tach (not in the starter, not
# the hidden eval_peephole_* one) with CHECK lines on the IR, passing.
found=""
for f in tests/run/*.tach; do
    name=$(basename "$f" .tach)
    case "$name" in eval_peephole_*) continue ;; esac
    [ -e "$EVAL_STARTER_TREE/tests/run/$name.tach" ] && continue
    grep -q '^// CHECK' "$f" || continue
    found="$found $name"
done
if [ -z "$found" ]; then
    echo "no new tests/run/*.tach with // CHECK lines (the task asks for one)" >&2
    exit 1
fi
for name in $found; do
    if ! /bin/sh tests/run.sh -c "$TACHYONC" "$name" >/dev/null 2>&1; then
        echo "the agent's test $name fails (tests/run.sh $name)" >&2
        exit 1
    fi
done
exit 0
