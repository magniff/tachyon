# Sourced by tests/guide/run.sh, tests/query/run.sh and
# tests/refactor/run.sh (0.15): which of 0.15's features the compiler
# has yet. While 0.15 is built in parts (docs/design/errors-formatting.md,
# T1-T4), the guide's examples fenced ```tach 0.15 FEATURE... and the
# transcripts with a line `## needs: 0.15 FEATURE...` are skipped
# (`skip NAME`) by a compiler that lacks one of the features; with one
# that has them all, they are run as any other. POSIX sh.
#
# The features: try (`?`, T1), from (From/Into, generic traits, T1),
# widen (integer widening, T2), args (named and default arguments, T2),
# io (std's Result I/O API, T2), fmt (f-strings, Display, Debug, T3),
# derive (#[derive], Clone, T4).
#
# usage: has_015 COMPILER DIR FEATURE   (exit 0: it has it; DIR: scratch)
#        missing_015 COMPILER DIR       (prints the features it lacks)
has_015() {
    d="$2/probe015-$3"
    mkdir -p "$d" || return 1
    case "$3" in
        try) cat >"$d/main.tach" <<'EOF'
fn half(x: Option<i64>) -> Option<i64> {
    let v = x?;
    Some(v / 2)
}

fn main() -> i32 {
    match half(Some(6)) {
        Some(3) => match half(None) { None => 0, Some(_) => 1 },
        _ => 1,
    }
}
EOF
        ;;
        from) cat >"$d/main.tach" <<'EOF'
struct Meters { m: i64 }

impl From<i64> for Meters {
    fn from(x: i64) -> Meters { Meters { m: x } }
}

fn main() -> i32 {
    let a = Meters::from(3);
    let b: Meters = 4.into();
    (a.m + b.m - 7) as i32
}
EOF
        ;;
        widen) cat >"$d/main.tach" <<'EOF'
fn wide(x: i64) -> i64 { x }

fn main() -> i32 {
    let a: i32 = 5;
    let b: i64 = a;
    (wide(a) - b) as i32
}
EOF
        ;;
        args) cat >"$d/main.tach" <<'EOF'
fn f(a: i64, b: i64 = 2) -> i64 { a * b }

fn main() -> i32 {
    (f(3) + f(1, b: 4) - 10) as i32
}
EOF
        ;;
        io) cat >"$d/main.tach" <<'EOF'
fn main() -> i32 {
    match parse_int("x") {
        Ok(_) => 1,
        Err(_) => 0,
    }
}
EOF
        ;;
        fmt) cat >"$d/main.tach" <<'EOF'
fn main() -> i32 {
    let x = 7;
    let s = format(f"{x:>3}|{x:?}");
    if s.len() == 5 { 0 } else { 1 }
}
EOF
        ;;
        derive) cat >"$d/main.tach" <<'EOF'
#[derive(Eq, Clone, Debug)]
struct P { x: i64 }

fn main() -> i32 {
    let p = P { x: 3 };
    let q = p.clone();
    if p == q { 0 } else { 1 }
}
EOF
        ;;
        *) return 1 ;;
    esac
    "$1" "$d/main.tach" -o "$d/prog" >/dev/null 2>&1 && "$d/prog" >/dev/null 2>&1
}

missing_015() {
    for f in try from widen args io fmt derive; do
        has_015 "$1" "$2" "$f" || printf '%s ' "$f"
    done
}

# Whether the features after `0.15` in $3 (a fence's or a `## needs:`
# line's words) are all in $1 (missing_015's output, words then a space).
needs_ok_015() { # <missing> <dummy> <words...>
    m=$1
    shift 2
    for w in "$@"; do
        case "$w" in 0.15) continue ;; esac
        case " $m" in *" $w "*) return 1 ;; esac
    done
    return 0
}
