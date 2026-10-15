#!/bin/sh
# The test suite of this release, run with a tachyon compiler (no cargo
# needed): every tests/run/*.tach, tests/run/*/main.tach (a program of
# several modules, 0.5) and tests/examples/*.test case (examples/NAME/,
# 0.15) is compiled, assembled and linked with the C compiler, run, checked;
# alongside them, tests/query/run.sh (`tachyonc query`, 0.11),
# tests/refactor/run.sh (the refactoring tools, 0.11), tests/guide/run.sh
# (`tachyonc guide`, 0.13), tests/fmt/run.sh (`tachyonc fmt --check`
# of the tree, and formatting changes no program, 0.13) and
# tests/walkthrough/run.sh (the sessions of examples/tools/*/README.md,
# 0.15). POSIX sh and awk only, so it runs the same on macOS and Linux.
#
# usage: tests/run.sh [-c COMPILER] [-t TARGET] [-O LEVEL] [-j JOBS] [-a] [-d FORMAT] [FILTER]
#
#   -c COMPILER   the tachyonc binary to test (default: target/tachyonc,
#                 as left by bootstrap/bootstrap.sh)
#   -t TARGET     aarch64-macos, aarch64-linux, x86_64-linux or x86_64-macos
#                 (default: the host; x86_64-macos runs under Rosetta on
#                 Apple silicon)
#   -O LEVEL      the optimization level (0, 1 or 2; default: the
#                 compiler's default)
#   -j JOBS       cases run at once (default: the number of CPUs, or the
#                 slots of $TACHYON_JOBSERVER); the report is the same for
#                 every JOBS
#   -a            programs go through assembly (tachyonc -S, then cc), as
#                 before 0.7, instead of the compiler's own objects
#   -d FORMAT     the compiler's diagnostics: human (the default) or short
#                 (--diagnostics=short, 0.11); the ERROR and WARNING
#                 directives are written for human and hold for both
#   FILTER        run only the cases whose name contains FILTER
#
# Environment: CC is the linker (and the assembler with -a; default cc).
# TACHYON_JOBSERVER (0.11), when -j is not given, names a FIFO holding
# one line per free slot, shared by every runner bootstrap/gate.sh starts
# (tests/run.sh, tests/fuzz/run.sh, tests/abi/run.sh, tests/objcheck.sh):
# a case takes a line before it starts and puts it back when done.
#
# Directives, in `//` comments of the case file:
#   // ARGS: a b c       command-line arguments (whitespace separated)
#   // STDIN: text       stdin, one directive per line, joined with '\n'
#   // EXPECT: text      expected stdout, one directive per line
#   // EXIT: 3           expected exit code (default 0)
#   // STDERR: text      stderr contains text, one directive per line
#   // ERROR: text       compilation must fail (exit code 1) with an error
#                        containing this text; one directive per message,
#                        in the order they are reported
#   // ERROR-COUNT: n    exactly n errors are reported
#   // XFAIL: reason     a known bug: the case is expected to fail, and
#                        reported as a failure (XPASS) once it passes
#   // XFAIL(T): reason  the same, only for target T
#   // SOURCE: path      (.test files) the program, relative to the root
#   // CHEADER: name.h    the program's C header (--emit-header), made for
#                        its C sources to include
#   // CSOURCE: path     a C file to compile and link with the program,
#                        relative to the root (one directive per file)
#   // BUILD: reason     (.test files) only compile and link it
#   // CHECK: text       the optimized IR (--emit-ir) has a line containing
#                        text, after the previous CHECK's line
#   // CHECK-NOT: text   no line containing text between the neighbouring
#                        CHECKs' lines (or the start and end)
#   // CHECK-OPT: n      the level for the CHECKs (default 2)
#   // ASM(T): text      the assembly for target T (at the CHECK-OPT level)
#                        has a line containing text, after the previous
#                        ASM(T)'s line; checked only when testing T
#   // ASM-NOT(T): text  no line containing text between the neighbouring
#                        ASM(T)s' lines
#   // FIXIMPORTS: why   (0.8) a copy of the case (its directory, for a
#                        main.tach) is rewritten by tachyonc --fix-imports,
#                        which must then find nothing more to do; the copy
#                        is what the other directives check
#   // FIXED: text       the rewritten copy has a line (not a comment)
#                        containing text, one directive per line
#   // FIXUNSAFE: why    (0.9) the same with tachyonc --fix-unsafe
#   // FLAGS: flags      (0.9) more compiler options for the case (0.10:
#                        @ROOT@ stands for the root of the tree)
#   // WARNING: text     (0.9) the case compiles with a warning containing
#                        this text, one directive per message, in order
#   // PROFILE: why      (0.10) at -O1 and -O2, the case is first compiled
#                        with --profile-generate, run and checked; the
#                        other directives then check it compiled with
#                        --profile-use of that profile
# Every case is compiled with --deny-warnings, except the ones with WARNING
# directives (0.9's unsafe warnings are errors from 0.10; there are no
# warnings at the moment).
# Stdout is compared after removing trailing whitespace. Each program may
# run for 20 seconds.

set -u
LC_ALL=C
export LC_ALL

ROOT=$(cd "$(dirname "$0")/.." && pwd)
COMPILER="$ROOT/target/tachyonc"
CC=${CC:-cc}
TARGET=""
OPT=""
TIMEOUT=20
JOBS=""
OUT=prog.o
DIAG=human

usage() {
    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

while [ $# -gt 0 ]; do
    case "$1" in
        -c) [ $# -ge 2 ] || usage; COMPILER=$2; shift 2 ;;
        -t) [ $# -ge 2 ] || usage; TARGET=$2; shift 2 ;;
        -O) [ $# -ge 2 ] || usage; OPT="-O$2"; shift 2 ;;
        -j) [ $# -ge 2 ] || usage; JOBS=$2; shift 2 ;;
        -a) OUT=prog.s; shift ;;
        -d) [ $# -ge 2 ] || usage; DIAG=$2; shift 2 ;;
        -h|--help) usage ;;
        -*) usage ;;
        *) break ;;
    esac
done
FILTER=${1:-}
case "$DIAG" in
    # (0.15: a compiler whose stderr is not a terminal prints the short
    # form unless told otherwise)
    human) DIAG_FLAG="--diagnostics=human" ;;
    short) DIAG_FLAG="--diagnostics=short" ;;
    *) usage ;;
esac

case "$COMPILER" in
    /*) ;;
    *) COMPILER="$(pwd)/$COMPILER" ;;
esac
[ -x "$COMPILER" ] || { echo "run.sh: no compiler at $COMPILER (use -c)" >&2; exit 2; }
command -v "$CC" >/dev/null 2>&1 || { echo "run.sh: '$CC' not found (set CC)" >&2; exit 2; }

if [ -z "$TARGET" ]; then
    case "$(uname -s)-$(uname -m)" in
        Darwin-arm64) TARGET=aarch64-macos ;;
        Darwin-x86_64) TARGET=x86_64-macos ;;
        Linux-x86_64) TARGET=x86_64-linux ;;
        Linux-aarch64) TARGET=aarch64-linux ;;
        *) echo "run.sh: no tachyon target for this host ($(uname -s) $(uname -m)); use -t" >&2; exit 2 ;;
    esac
fi
# How the C compiler assembles and links for the target.
case "$TARGET" in
    aarch64-macos) LINK_FLAGS="-arch arm64" ;;
    x86_64-macos) LINK_FLAGS="-arch x86_64" ;;
    x86_64-linux|aarch64-linux) LINK_FLAGS="" ;;
    *) echo "run.sh: unknown target '$TARGET'" >&2; exit 2 ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/tachyon-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
FAILURES="$WORK/failures"
TALLY="$WORK/tally"
: >"$FAILURES"
: >"$TALLY"

# The C compiler, once more when it crashed (a signal, or gcc's "internal
# compiler error"): an emulated toolchain (x86-64 Linux under Rosetta)
# now and then does, and a crash of cc is not tachyon's. Its output (and
# the crash's, if any) on stdout.
cc_run() {
    cr_out=$("$CC" "$@" 2>&1)
    cr_rc=$?
    if [ $cr_rc -ne 0 ]; then
        case "$cr_rc:$cr_out" in
            1[3-9][0-9]:*|2[0-9][0-9]:*|*"internal compiler error"*|*"Segmentation fault"*|*"Bus error"*)
                printf '%s\n(%s crashed, exit %d: run again)\n' "$cr_out" "$CC" "$cr_rc"
                cr_out=$("$CC" "$@" 2>&1)
                cr_rc=$? ;;
        esac
    fi
    [ -z "$cr_out" ] || printf '%s\n' "$cr_out"
    return $cr_rc
}

# The first message of directives file $1 (ERROR or WARNING texts) that
# the compiler's output $2 lacks, each after the one before it; nothing
# when all are there. With -d short a diagnostic is one line
# (`file:line:col: error[kind] message | help: ...`): a directive
# `line L, column C` is looked for as `:L:C:` in the line of the message
# before it, `error[kind]: ` as `error[kind] `, and the next directive may
# be later in the same line.
missing_message() {
    awk -v out="$2" -v short="$( [ "$DIAG" = short ] && echo 1 || echo 0)" '
        BEGIN { while ((getline line < out) > 0) text[++n] = line; at = 0; col = 0 }
        {
            want = $0
            from_start = 0
            if (short) {
                if (match(want, /^line [0-9]+, column [0-9]+$/)) {
                    split(want, f, /[ ,]+/)
                    want = ":" f[2] ":" f[4] ":"
                    from_start = 1
                }
                while ((k = index(want, "]: ")) > 0) want = substr(want, 1, k) " " substr(want, k + 3)
            }
            if (!short) {
                while (at < n && index(text[at + 1], want) == 0) at++
                if (at >= n) { print $0; exit }
                at++
                next
            }
            # (short: from the previous match on, within its line first)
            if (at > 0) {
                rest = from_start ? text[at] : substr(text[at], col + 1)
                k = index(rest, want)
                if (k > 0) {
                    col = (from_start ? 0 : col) + k + length(want) - 1
                    next
                }
            }
            while (at < n && index(text[at + 1], want) == 0) at++
            if (at >= n) { print $0; exit }
            at++
            col = index(text[at], want) + length(want) - 1
        }' "$1"
}

# Writes the directives of case file $1 into directory $2: one file per
# directive (args, stdin, expect, exit, errors, xfail, source, build).
read_directives() {
    awk -v dir="$2" -v target="$TARGET" '
        {
            line = $0
            sub(/\r$/, "", line)
            sub(/^[ \t]+/, "", line)
            if (substr(line, 1, 2) != "//") next
            c = substr(line, 3)
            if (substr(c, 1, 1) == " ") c = substr(c, 2)
            i = index(c, ":")
            if (i == 0) next
            key = substr(c, 1, i - 1)
            value = substr(c, i + 1)
            if (substr(value, 1, 1) == " ") value = substr(value, 2)
            if (key == "ARGS") args = value
            else if (key == "STDIN") stdin = stdin (nstdin++ ? "\n" : "") value
            else if (key == "EXPECT") expect = expect (nexpect++ ? "\n" : "") value
            else if (key == "EXIT") exitcode = value + 0
            else if (key == "STDERR") stderrs = stderrs value "\n"
            else if (key == "ERROR") errors = errors value "\n"
            else if (key == "ERROR-COUNT") errcount = value
            else if (key == "XFAIL" || key == "XFAIL(" target ")") xfail = value
            else if (key == "SOURCE") source = value
            else if (key == "CSOURCE") csources = csources " " value
            else if (key == "CHEADER") cheader = value
            else if (key == "BUILD") build = 1
            else if (key == "CHECK") checks = checks "+" value "\n"
            else if (key == "CHECK-NOT") checks = checks "-" value "\n"
            else if (key == "CHECK-OPT") checkopt = value
            else if (key == "ASM(" target ")") asms = asms "+" value "\n"
            else if (key == "ASM-NOT(" target ")") asms = asms "-" value "\n"
            else if (key == "FIXIMPORTS") fiximports = 1
            else if (key == "FIXUNSAFE") fiximports = 2
            else if (key == "FIXED") fixed = fixed value "\n"
            else if (key == "FLAGS") flags = flags " " value
            else if (key == "WARNING") warnings = warnings value "\n"
            else if (key == "PROFILE") profile = 1
        }
        END {
            printf "%s", args > (dir "/args")
            printf "%s", stdin > (dir "/stdin")
            printf "%s", expect > (dir "/expect")
            printf "%d", exitcode > (dir "/exit")
            printf "%s", stderrs > (dir "/stderrs")
            printf "%s", errors > (dir "/errors")
            printf "%s", errcount > (dir "/errcount")
            printf "%s", xfail > (dir "/xfail")
            printf "%s", source > (dir "/source")
            printf "%s", csources > (dir "/csources")
            printf "%s", cheader > (dir "/cheader")
            printf "%d", build > (dir "/build")
            printf "%s", checks > (dir "/checks")
            printf "%s", asms > (dir "/asms")
            printf "%s", (checkopt == "" ? "2" : checkopt) > (dir "/checkopt")
            printf "%d", fiximports > (dir "/fiximports")
            printf "%s", fixed > (dir "/fixed")
            printf "%s", flags > (dir "/flags")
            printf "%s", warnings > (dir "/warnings")
            printf "%d", profile > (dir "/profile")
        }
    ' "$1"
}

# The file's content without trailing whitespace.
trimmed() {
    awk '{ text = text $0 "\n" } END { sub(/[ \t\r\n]+$/, "", text); printf "%s", text }' "$1"
}

# Runs $dir/prog with a timeout; sets RC.
run_program() {
    dir=$1
    (
        cd "$dir" || exit 1
        # shellcheck disable=SC2046
        exec ./prog $(cat args) <stdin >stdout 2>stderr
    ) &
    pid=$!
    (sleep "$TIMEOUT" && kill -9 "$pid" 2>/dev/null) >/dev/null 2>&1 &
    watchdog=$!
    wait "$pid"
    RC=$?
    kill "$watchdog" 2>/dev/null
    wait "$watchdog" 2>/dev/null
}

# Runs one case; prints nothing, returns 0 on success, and leaves the
# reason for a failure in $dir/why.
check_case() {
    file=$1
    dir=$2
    source=$(cat "$dir/source")
    if [ -n "$source" ]; then
        source="$ROOT/$source"
    else
        source=$file
    fi
    case "$(cat "$dir/fiximports")" in
        1) fix_case "$source" "$dir" --fix-imports || return 1 ;;
        2) fix_case "$source" "$dir" --fix-unsafe || return 1 ;;
    esac
    # The compiler's options for the case (0.9).
    FLAGS="--deny-warnings $DIAG_FLAG $(sed "s|@ROOT@|$ROOT|g" "$dir/flags")"
    # (--check-unsafe needs the IR: such a case runs at -O1 when -O0 is
    # asked for, 0.10.)
    if [ "$OPT" = -O0 ] && grep -q -- --check-unsafe "$dir/flags"; then
        OPT=-O1
    fi
    # (A profile's warnings come at -O1 and -O2 only: -O0 reads none.)
    if [ "$OPT" = -O0 ] && grep -q -- --profile-use "$dir/flags"; then
        : >"$dir/warnings"
    fi
    [ -s "$dir/warnings" ] && FLAGS="$DIAG_FLAG $(sed "s|@ROOT@|$ROOT|g" "$dir/flags")"
    if [ -s "$dir/errors" ]; then
        # shellcheck disable=SC2086
        "$COMPILER" --target "$TARGET" $OPT $FLAGS "$source" -o "$dir/prog.s" >"$dir/compile.out" 2>&1
        rc=$?
        if [ $rc -ne 1 ]; then
            { echo "expected a compile error (exit code 1), got exit code $rc:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        # Each message, in order (several errors are reported at once).
        missing=$(missing_message "$dir/errors" "$dir/compile.out")
        if [ -n "$missing" ]; then
            { echo "expected an error containing '$missing' (after the ones before it), got:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
        if [ -s "$dir/errcount" ]; then
            got=$(grep -c -E '^error\[|^[^ ]*: error\[' "$dir/compile.out")
            if [ "$got" -ne "$(cat "$dir/errcount")" ]; then
                { echo "expected $(cat "$dir/errcount") errors, got $got:"; cat "$dir/compile.out"; } >"$dir/why"
                return 1
            fi
        fi
        return 0
    fi
    PFLAGS=""
    if [ "$(cat "$dir/profile")" = 1 ] && ! profile_case "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/asms" ] && ! check_asm "$source" "$dir"; then
        return 1
    fi
    if [ -s "$dir/checks" ] && ! check_ir "$source" "$dir"; then
        return 1
    fi
    # shellcheck disable=SC2086
    [ "$OPT" = -O0 ] && PFLAGS=""
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" $OPT $FLAGS $PFLAGS "$source" -o "$dir/$OUT" >"$dir/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$dir/compile.out"; } >"$dir/why"
        return 1
    fi
    if [ -s "$dir/warnings" ]; then
        missing=$(missing_message "$dir/warnings" "$dir/compile.out")
        if [ -n "$missing" ]; then
            { echo "expected a warning containing '$missing' (after the ones before it), got:"; cat "$dir/compile.out"; } >"$dir/why"
            return 1
        fi
    fi
    csources=""
    for c in $(cat "$dir/csources"); do
        csources="$csources $ROOT/$c"
    done
    # The program's C header, for its C sources.
    if [ -s "$dir/cheader" ]; then
        # shellcheck disable=SC2086
        if ! "$COMPILER" --target "$TARGET" $FLAGS --emit-header "$source" -o "$dir/$(cat "$dir/cheader")" >"$dir/header.out" 2>&1; then
            { echo "--emit-header failed:"; cat "$dir/header.out"; } >"$dir/why"
            return 1
        fi
        csources="-I $dir $csources"
    fi
    # shellcheck disable=SC2086
    if ! cc_run $LINK_FLAGS -o "$dir/prog" "$dir/$OUT" $csources -lm >"$dir/link.out" 2>&1; then
        { echo "$CC failed:"; cat "$dir/link.out"; } >"$dir/why"
        return 1
    fi
    [ "$(cat "$dir/build")" = 1 ] && return 0
    run_program "$dir"
    expected_exit=$(cat "$dir/exit")
    trimmed "$dir/stdout" >"$dir/actual"
    trimmed "$dir/expect" >"$dir/wanted"
    if ! cmp -s "$dir/actual" "$dir/wanted"; then
        {
            echo "stdout mismatch"
            echo "--- expected"; cat "$dir/wanted"; echo
            echo "--- actual"; cat "$dir/actual"; echo
        } >"$dir/why"
        return 1
    fi
    if [ "$RC" -ne "$expected_exit" ]; then
        { echo "exit code: expected $expected_exit, got $RC"; cat "$dir/stderr"; } >"$dir/why"
        return 1
    fi
    while IFS= read -r message; do
        if ! grep -qF -- "$message" "$dir/stderr"; then
            { echo "expected stderr containing '$message', got:"; cat "$dir/stderr"; } >"$dir/why"
            return 1
        fi
    done <"$dir/stderrs"
    return 0
}

# FIXIMPORTS, FIXUNSAFE: a copy of case $1 (in $2/fix/run, next to a link
# to tests/c, which cases include from) is rewritten by option $3
# (--fix-imports or --fix-unsafe); `source` becomes the copy.
fix_case() {
    fixdir="$2/fix"
    mkdir -p "$fixdir/run"
    ln -s "$ROOT/tests/c" "$fixdir/c"
    case "$1" in
        */main.tach)
            cp -R "$(dirname "$1")" "$fixdir/run/"
            source="$fixdir/run/$(basename "$(dirname "$1")")/main.tach" ;;
        *)
            cp "$1" "$fixdir/run/"
            source="$fixdir/run/$(basename "$1")" ;;
    esac
    if ! "$COMPILER" --target "$TARGET" "$3" "$source" >"$2/fix.out" 2>&1; then
        { echo "$3 failed:"; cat "$2/fix.out"; } >"$2/why"
        return 1
    fi
    if ! "$COMPILER" --target "$TARGET" "$3" "$source" >"$2/fix2.out" 2>&1 || [ -s "$2/fix2.out" ]; then
        { echo "a second $3 did not leave the program as it was:"; cat "$2/fix2.out"; } >"$2/why"
        return 1
    fi
    find "$fixdir/run" -name '*.tach' -exec cat {} + | grep -v '^[[:space:]]*//' >"$2/fixed.txt"
    while IFS= read -r text; do
        if ! grep -qF -- "$text" "$2/fixed.txt"; then
            { echo "the rewritten program has no line containing '$text':"; cat "$2/fixed.txt"; } >"$2/why"
            return 1
        fi
    done <"$2/fixed"
    return 0
}

# PROFILE: case $1 compiled with --profile-generate, run and checked; then
# FLAGS use the profile it wrote.
profile_case() {
    # (At the CHECK level: -O0 takes no profile.)
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS --profile-generate "$2/profile.data" "$1" -o "$2/$OUT" >"$2/compile.out" 2>&1; then
        { echo "--profile-generate failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    # shellcheck disable=SC2086
    if ! cc_run $LINK_FLAGS -o "$2/prog" "$2/$OUT" -lm >"$2/link.out" 2>&1; then
        { echo "link failed (instrumented):"; cat "$2/link.out"; } >"$2/why"
        return 1
    fi
    run_program "$2"
    if [ "$RC" -ne "$(cat "$2/exit")" ] || [ "$(trimmed "$2/stdout")" != "$(trimmed "$2/expect")" ]; then
        { echo "the instrumented program (exit $RC) printed:"; cat "$2/stdout"; } >"$2/why"
        return 1
    fi
    if [ ! -s "$2/profile.data" ]; then
        echo "the instrumented program wrote no profile" >"$2/why"
        return 1
    fi
    PFLAGS="--profile-use $2/profile.data"
    return 0
}

# Matches the CHECK directives against the optimized IR of $1.
check_ir() {
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS $PFLAGS --verify-ir --emit-ir "$1" -o "$2/ir.txt" >"$2/compile.out" 2>&1; then
        { echo "--emit-ir failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/ir.txt" "$2/checks" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- IR:"; cat "$2/ir.txt"; } >"$2/why"
    return 1
}

# Matches the ASM directives against the assembly of $1 for the target.
check_asm() {
    # shellcheck disable=SC2086
    if ! "$COMPILER" --target "$TARGET" "-O$(cat "$2/checkopt")" $FLAGS $PFLAGS "$1" -o "$2/check.s" >"$2/compile.out" 2>&1; then
        { echo "compile failed:"; cat "$2/compile.out"; } >"$2/why"
        return 1
    fi
    match_checks "$2/check.s" "$2/asms" "$2/check.out" && return 0
    { cat "$2/check.out"; echo "--- assembly:"; cat "$2/check.s"; } >"$2/why"
    return 1
}

# Matches the checks in file $2 (+text: a line containing text, after the
# previous one; -text: none until the next) against the lines of $1;
# writes what failed to $3.
match_checks() {
    awk -v checks="$2" '
        { line[NR] = $0 }
        END {
            n = 0
            while ((getline c < checks) > 0) { kind[n] = substr(c, 1, 1); text[n] = substr(c, 2); n++ }
            pos = 0
            nots = 0
            for (i = 0; i < n; i++) {
                if (kind[i] == "-") { pending[nots++] = text[i]; continue }
                found = 0
                for (j = pos + 1; j <= NR; j++) if (index(line[j], text[i])) { found = j; break }
                if (!found) { print "CHECK not found after line " pos ": " text[i]; exit 1 }
                for (k = 0; k < nots; k++)
                    for (j = pos + 1; j < found; j++)
                        if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
                nots = 0
                pos = found
            }
            for (k = 0; k < nots; k++)
                for (j = pos + 1; j <= NR; j++)
                    if (index(line[j], pending[k])) { print "CHECK-NOT found at line " j ": " pending[k]; exit 1 }
        }
    ' "$1" >"$3" 2>&1
}

# The number of CPUs, for -j.
cpu_count() {
    n=$(sysctl -n hw.ncpu 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || nproc 2>/dev/null || echo 4)
    case "$n" in
        ''|*[!0-9]*) echo 4 ;;
        *) echo "$n" ;;
    esac
}

# Runs case $1 in directory $2: its outcome in $2/status.
run_case() {
    file=$1
    dir=$2
    if check_case "$file" "$dir"; then
        if [ -s "$dir/xfail" ]; then echo xpass; else echo pass; fi
    elif [ -s "$dir/xfail" ]; then
        echo xfail
    else
        echo fail
    fi >"$dir/status"
}

# The standard library built into the compiler must be its source's (0.5).
if [ -x "$ROOT/compiler/std/embed.sh" ] && ! "$ROOT/compiler/std/embed.sh" -c; then
    exit 1
fi

# The optimizer's rewrite rules, on random values (0.9).
if "$COMPILER" --check-rules >"$WORK/rules.out" 2>&1; then :; else
    grep -q 'rewrite rules' "$WORK/rules.out" && { cat "$WORK/rules.out"; exit 1; }
fi

# The cases, in order; up to JOBS at once (a FIFO holds the free slots).
CASES="$WORK/cases"
: >"$CASES"
for file in "$ROOT"/tests/run/*.tach "$ROOT"/tests/run/*/main.tach "$ROOT"/tests/examples/*.test; do
    [ -f "$file" ] || continue
    base=${file##*/}
    name=${base%.*}
    case "$file" in
        *.test) name="example_$name" ;;
        # A program of several modules: a directory with main.tach (0.5).
        */main.tach) name=${file%/main.tach}; name=${name##*/} ;;
    esac
    case "$name" in
        *"$FILTER"*) ;;
        *) continue ;;
    esac
    echo "$name $file" >>"$CASES"
done

# The tools' suites (below) run alongside the cases: they are serial, and
# take seconds.
case query in
    *"$FILTER"*) "$ROOT/tests/query/run.sh" -c "$COMPILER" >"$WORK/query.out" 2>&1 & ;;
esac
case refactor in
    *"$FILTER"*) "$ROOT/tests/refactor/run.sh" -c "$COMPILER" >"$WORK/refactor.out" 2>&1 & ;;
esac
case guide in
    *"$FILTER"*) "$ROOT/tests/guide/run.sh" -c "$COMPILER" >"$WORK/guide.out" 2>&1 & ;;
esac
case fmt in
    *"$FILTER"*) "$ROOT/tests/fmt/run.sh" -c "$COMPILER" -j 1 >"$WORK/fmt.out" 2>&1 & ;;
esac
case walkthrough in
    *"$FILTER"*) "$ROOT/tests/walkthrough/run.sh" -c "$COMPILER" >"$WORK/walkthrough.out" 2>&1 & ;;
esac

# The slots: JOBS of them in a FIFO of our own, or the shared ones of
# $TACHYON_JOBSERVER (see above).
if [ -z "$JOBS" ] && [ -n "${TACHYON_JOBSERVER:-}" ] && [ -p "$TACHYON_JOBSERVER" ]; then
    exec 3<>"$TACHYON_JOBSERVER"
else
    [ -n "$JOBS" ] || JOBS=$(cpu_count)
    mkfifo "$WORK/slots"
    exec 3<>"$WORK/slots"
    i=0
    while [ "$i" -lt "$JOBS" ]; do
        echo >&3
        i=$((i + 1))
    done
fi
while read -r name file; do
    dir="$WORK/$name"
    mkdir -p "$dir"
    read_directives "$file" "$dir"
    read -r _ <&3
    ( run_case "$file" "$dir"; echo >&3 ) &
done <"$CASES"
wait
exec 3>&-

count=0
while read -r name file; do
    dir="$WORK/$name"
    category=${name%%_*}
    [ -s "$dir/errors" ] && category=error
    status=fail
    [ -f "$dir/status" ] && read -r status <"$dir/status"
    if [ "$status" = xpass ]; then
        echo "$category fail" >>"$TALLY"
        echo "XPASS $name: passes but is marked XFAIL ($(cat "$dir/xfail")); remove the directive" >>"$FAILURES"
    elif [ "$status" = fail ]; then
        echo "$category fail" >>"$TALLY"
        { echo "FAIL $name:"; sed 's/^/    /' "$dir/why"; echo; } >>"$FAILURES"
    else
        echo "$category $status" >>"$TALLY"
    fi
    count=$((count + 1))
done <"$CASES"

# `tachyonc query` (0.11): tests/query/run.sh (run above), its transcripts
# and its checks on the compiler's own source; category "query".
case query in
    *"$FILTER"*)
        while read -r status _; do
            case "$status" in
                pass) echo "query pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "query fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/query.out"
        if ! grep -q '^pass' "$WORK/query.out"; then
            echo "query fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/query.out" >>"$FAILURES"
        ;;
esac

# The refactoring tools (0.11: edit, undo, check, fix, lint, same-output,
# the planning queries): tests/refactor/run.sh (run above); category
# "refactor".
case refactor in
    *"$FILTER"*)
        while read -r status _; do
            case "$status" in
                pass) echo "refactor pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "refactor fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/refactor.out"
        if ! grep -q '^pass' "$WORK/refactor.out"; then
            echo "refactor fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/refactor.out" >>"$FAILURES"
        ;;
esac

# `tachyonc guide` (0.13): tests/guide/run.sh (run above), the guide's
# examples compiled and run, its std section, its budget; category
# "guide".
case guide in
    *"$FILTER"*)
        while read -r status _; do
            case "$status" in
                pass) echo "guide pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "guide fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/guide.out"
        if ! grep -q '^pass' "$WORK/guide.out"; then
            echo "guide fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/guide.out" >>"$FAILURES"
        ;;
esac

# The formatter (0.13): tests/fmt/run.sh (run above): the tree is
# formatted (`fmt --all --check`), and formatting changes no program;
# category "fmt".
case fmt in
    *"$FILTER"*)
        while read -r status _; do
            case "$status" in
                pass) echo "fmt pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "fmt fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/fmt.out"
        if ! grep -q '^pass' "$WORK/fmt.out"; then
            echo "fmt fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/fmt.out" >>"$FAILURES"
        ;;
esac

# The examples (0.15: one folder each, examples/NAME/, or a group of them,
# examples/GROUP/NAME/ under a README.md): each has a main.tach, a
# README.md and a case in tests/examples (a .test whose SOURCE is its
# main.tach); category "example". examples/tools/ (walkthroughs of the
# tools, some failing to compile on purpose) has its own runner.
case example_layout in
    *"$FILTER"*)
        for d in "$ROOT"/examples/*/ "$ROOT"/examples/*/*/; do
            [ -d "$d" ] || continue
            ex=${d%/}
            ex=${ex#"$ROOT"/examples/}
            case "$ex" in tools | tools/*) continue ;; esac
            why=""
            case "$ex" in
                */*) ;;
                # a group: its README; its folders are the examples
                *) [ -f "$d/main.tach" ] || { [ -f "$d/README.md" ] && continue; } ;;
            esac
            # (a folder of a program's modules, not an example)
            case "$ex" in */*) [ -f "${d%/}/../main.tach" ] && continue ;; esac
            [ -f "$d/main.tach" ] || why="no main.tach"
            [ -f "$d/README.md" ] || why="$why${why:+; }no README.md"
            grep -qx "// SOURCE: examples/$ex/main.tach" "$ROOT"/tests/examples/*.test \
                || why="$why${why:+; }no tests/examples/*.test with '// SOURCE: examples/$ex/main.tach'"
            if [ -n "$why" ]; then
                echo "example fail" >>"$TALLY"
                printf 'FAIL example_layout %s:\n    %s\n\n' "$ex" "$why" >>"$FAILURES"
            else
                echo "example pass" >>"$TALLY"
            fi
            count=$((count + 1))
        done
        ;;
esac

# The tool examples' sessions (0.15): tests/walkthrough/run.sh (run
# above), each examples/tools/NAME/README.md run as a transcript;
# category "walkthrough".
case walkthrough in
    *"$FILTER"*)
        while read -r status _; do
            case "$status" in
                pass) echo "walkthrough pass" >>"$TALLY"; count=$((count + 1)) ;;
                FAIL) echo "walkthrough fail" >>"$TALLY"; count=$((count + 1)) ;;
            esac
        done <"$WORK/walkthrough.out"
        if ! grep -q '^pass' "$WORK/walkthrough.out"; then
            echo "walkthrough fail" >>"$TALLY"
            count=$((count + 1))
        fi
        awk '/^FAIL/ { p = 1 } /^pass/ { p = 0 } p' "$WORK/walkthrough.out" >>"$FAILURES"
        ;;
esac

[ $count -gt 0 ] || { echo "run.sh: no cases match '$FILTER'" >&2; exit 2; }
cat "$FAILURES"
echo "tests for $TARGET with $("$COMPILER" --version 2>/dev/null || echo "$COMPILER"):"
awk '
    { n[$1, $2]++; cats[$1] = 1; total[$2]++ }
    END {
        printf "  %-10s %5s %6s %5s\n", "category", "pass", "xfail", "fail"
        for (c in cats) list = list c "\n"
        count = split(list, sorted, "\n")
        # Insertion sort, for awks without asort.
        for (i = 2; i < count; i++)
            for (j = i; j > 1 && sorted[j - 1] > sorted[j]; j--) {
                t = sorted[j]; sorted[j] = sorted[j - 1]; sorted[j - 1] = t
            }
        for (i = 1; i < count; i++) {
            c = sorted[i]
            printf "  %-10s %5d %6d %5d\n", c, n[c, "pass"], n[c, "xfail"], n[c, "fail"]
        }
        printf "  %-10s %5d %6d %5d\n", "total", total["pass"], total["xfail"], total["fail"]
    }
' "$TALLY"
if grep -q ' fail$' "$TALLY"; then
    exit 1
fi
exit 0
