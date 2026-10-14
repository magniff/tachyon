# Sourced by tests/guide/run.sh, tests/query/run.sh and
# tests/refactor/run.sh (0.14): whether the compiler checks closures and
# iterators yet. While 0.14 is built in parts, the guide's examples
# fenced ```tach 0.14 and the transcripts with a line `## needs: 0.14`
# are skipped (`skip NAME`) by a compiler that does not; with one that
# does, they are run as any other. POSIX sh.
#
# usage: has_014 COMPILER DIR   (exit 0: it does; DIR: a scratch directory)
has_014() {
    mkdir -p "$2/probe014" || return 1
    cat >"$2/probe014/main.tach" <<'EOF'
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 {
    f(x)
}

fn main() -> i32 {
    let k = 2;
    let mut v: Vec<i64> = Vec::new();
    v.push(3);
    let n = v.iter().map(|x| x * k).sum() + apply(|x| x + k, 1);
    v.free();
    (n - 9) as i32
}
EOF
    "$1" "$2/probe014/main.tach" -o "$2/probe014/prog" >/dev/null 2>&1 \
        && "$2/probe014/prog" >/dev/null 2>&1
}
