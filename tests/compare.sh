#!/bin/sh
# Compares two tachyon compilers: both compile the same corpus, and their
# outputs must be byte-identical. Run after a refactoring of the compiler
# (OLD is the compiler before it, NEW after) to show it changed nothing.
#
# usage: tests/compare.sh [-j JOBS] [-n FUZZ] [-a ABI] [-x REGEX] [-q] OLD NEW
#
#   -j JOBS   comparisons run at once (default: the number of CPUs)
#   -n FUZZ   random programs from tests/fuzz/gen.awk (default 200; half of
#             them in the seed-compatible mode)
#   -a ABI    random C interop programs from tests/abi/gen.awk (default 100)
#   -x REGEX  expected differences: comparisons whose names match REGEX
#             (grep -E) are reported apart and do not fail
#   -q        print only the summary
#
# The corpus: tests/run/*.tach, examples/*.tach, bench/*.tach, the random
# programs, and two multi-file programs: the compiler's source in this tree
# and at the last release tag (its 0.2-style C declarations, `extern fn`,
# turned into extern "C" blocks, which both compilers accept). Each is compiled for every target at -O0,
# -O1 and -O2 (the assembly, the diagnostics and the exit status are
# compared), its IR is emitted at -O1 and -O2, and its tokens are dumped.
# Differing outputs are kept in target/compare/diff.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)

# A worker: `compare.sh --job OLD NEW OUTDIR NAME ARGS...` runs both
# compilers with ARGS (where `@OUT` stands for the output file) and writes
# NAME to OUTDIR/diffs if anything differs.
if [ "${1:-}" = "--job" ]; then
    old=$2 new=$3 dir=$4 name=$5
    shift 5
    run() { # compiler output args...
        rc=$1 rout=$2
        shift 2
        n=$#
        while [ $n -gt 0 ]; do
            arg=$1
            shift
            [ "$arg" = @OUT ] && arg=$rout.s
            set -- "$@" "$arg"
            n=$((n - 1))
        done
        rm -f "$rout.s"
        "$rc" "$@" >"$rout.stdout" 2>"$rout.stderr"
        echo "exit $?" >>"$rout.stdout"
        [ -f "$rout.s" ] || : >"$rout.s"
    }
    a="$dir/w/$name"
    run "$old" "$a.old" "$@"
    run "$new" "$a.new" "$@"
    if cmp -s "$a.old.s" "$a.new.s" && cmp -s "$a.old.stdout" "$a.new.stdout" \
        && cmp -s "$a.old.stderr" "$a.new.stderr"; then
        rm -f "$a".old.* "$a".new.*
    else
        mkdir -p "$dir/diff"
        mv "$a".old.* "$a".new.* "$dir/diff/"
        echo "$name" >>"$dir/diffs"
    fi
    exit 0
fi

JOBS=""
FUZZ=200
ABI=100
QUIET=0
EXPECTED=""
while [ $# -gt 0 ]; do
    case $1 in
        -j) JOBS=$2; shift 2 ;;
        -n) FUZZ=$2; shift 2 ;;
        -a) ABI=$2; shift 2 ;;
        -x) EXPECTED=$2; shift 2 ;;
        -q) QUIET=1; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "compare.sh: unknown option $1" >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -eq 2 ] || { sed -n '6,6p' "$0" | sed 's/^# //' >&2; exit 2; }
abs() { case $1 in /*) echo "$1" ;; *) echo "$PWD/$1" ;; esac; }
OLD=$(abs "$1")
NEW=$(abs "$2")
[ -x "$OLD" ] && [ -x "$NEW" ] || { echo "compare.sh: OLD and NEW must be executables" >&2; exit 2; }
if [ -z "$JOBS" ]; then
    JOBS=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
fi

DIR="$ROOT/target/compare"
rm -rf "$DIR"
mkdir -p "$DIR/w" "$DIR/corpus/fuzz" "$DIR/corpus/abi" "$DIR/corpus/src-head" "$DIR/corpus/src-release"
: >"$DIR/diffs"

# The corpus.
i=1
while [ $i -le "$FUZZ" ]; do
    nz=$((i % 2))
    awk -v seed="$i" -v nonzero="$nz" -f "$ROOT/tests/fuzz/gen.awk" >"$DIR/corpus/fuzz/f$i.tach"
    i=$((i + 1))
done
i=1
while [ $i -le "$ABI" ]; do
    awk -v seed="$i" -v cfile="$DIR/corpus/abi/a$i.c" -v tfile="$DIR/corpus/abi/a$i.tach" \
        -f "$ROOT/tests/abi/gen.awk"
    rm -f "$DIR/corpus/abi/a$i.c"
    i=$((i + 1))
done
cp "$ROOT"/compiler/src/*.tach "$DIR/corpus/src-head/"
release=$(cd "$ROOT" && git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null)
if [ -n "$release" ]; then
    (cd "$ROOT" && git archive "$release" compiler/src) | tar -x -C "$DIR/corpus/src-release" --strip-components=2
    for f in "$DIR"/corpus/src-release/*.tach; do
        sed 's/^extern fn \(.*\)$/extern "C" { fn \1 }/' "$f" >"$f.new" && mv "$f.new" "$f"
    done
fi

TARGETS="aarch64-macos x86_64-linux x86_64-macos"
jobs="$DIR/jobs"
: >"$jobs"
add() { # name args...
    n=$1
    shift
    printf '%s' "$n" >>"$jobs"
    for a in "$@"; do printf ' %s' "$a" >>"$jobs"; done
    printf '\n' >>"$jobs"
}
program() { # name files...
    name=$1
    shift
    for t in $TARGETS; do
        for o in 0 1 2; do
            add "$name.$t.O$o" --target $t -O$o "$@" -o @OUT
        done
    done
    for t in aarch64-macos x86_64-linux; do
        for o in 1 2; do
            add "$name.$t.ir$o" --target $t -O$o --emit-ir "$@" -o @OUT
        done
    done
}
for f in "$ROOT"/tests/run/*.tach "$ROOT"/examples/*.tach "$ROOT"/bench/*.tach \
    "$DIR"/corpus/fuzz/*.tach "$DIR"/corpus/abi/*.tach; do
    [ -f "$f" ] || continue
    base=$(basename "$(dirname "$f")")-$(basename "$f" .tach)
    program "$base" "$f"
    add "$base.tokens" --tokens "$f"
done
program src-head "$DIR"/corpus/src-head/*.tach
[ -n "$release" ] && program "src-$release" "$DIR"/corpus/src-release/*.tach

total=$(wc -l <"$jobs" | tr -d ' ')
[ $QUIET -eq 1 ] || echo "compare: $total compilations each, $JOBS at a time"
xargs -P "$JOBS" -L 1 sh "$0" --job "$OLD" "$NEW" "$DIR" <"$jobs"

if [ -n "$EXPECTED" ]; then
    grep -E "$EXPECTED" "$DIR/diffs" | sort >"$DIR/expected"
    grep -vE "$EXPECTED" "$DIR/diffs" >"$DIR/diffs.rest"
    mv "$DIR/diffs.rest" "$DIR/diffs"
    nexp=$(wc -l <"$DIR/expected" | tr -d ' ')
    [ "$nexp" -eq 0 ] || echo "compare: $nexp expected differences ($(sed 's/\..*//' "$DIR/expected" | sort -u | tr '\n' ' '))"
fi
ndiff=$(wc -l <"$DIR/diffs" | tr -d ' ')
if [ "$ndiff" -eq 0 ]; then
    echo "compare: $((total - ${nexp:-0})) of $total compilations identical"
    rm -rf "$DIR/w"
    exit 0
fi
echo "compare: $ndiff of $total compilations differ (kept in target/compare/diff):"
sort "$DIR/diffs" | head -40 | sed 's/^/  /'
exit 1
