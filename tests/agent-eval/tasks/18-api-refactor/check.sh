#!/bin/sh
# Structural check for 18-api-refactor, run in the finished workspace with
# EVAL_LANG=tach|rust. The hidden tests check that behaviour is unchanged;
# this checks that the three API changes were made.

case "$EVAL_LANG" in
    tach) ext=tach ;;
    rust) ext=rs ;;
    *) echo "check: EVAL_LANG must be tach or rust, got '$EVAL_LANG'" >&2; exit 2 ;;
esac

fail() {
    echo "check: $*" >&2
    exit 1
}

for m in main grid level world report; do
    [ -f "$m.$ext" ] || fail "$m.$ext is missing"
done
files=$(find . -name "*.$ext" -not -path './.git/*' | sort)
# All the sources as one line, for signatures that may be wrapped.
flat=$(cat $files | tr '\n\t' '  ')

# 1. Positions are Pos, not (i64, i64).
hit=$(for f in $files; do tr -d ' \t' < "$f" | grep -n -F '(i64,i64)' | sed "s|^|$f:|"; done | head -n 1 | cut -c1-100)
[ -z "$hit" ] || fail "'(i64, i64)' still appears: $hit"
pos=$(cat $files | awk '/(^|[^A-Za-z0-9_])struct[ \t]+Pos([ \t]|\{|$)/ { on = 1 } on { print } on && /\}/ { exit }')
[ -n "$pos" ] || fail "no struct Pos"
echo "$pos" | grep -Eq '(^|[^A-Za-z0-9_])row[[:space:]]*:[[:space:]]*i64' || fail "struct Pos has no field 'row: i64'"
echo "$pos" | grep -Eq '(^|[^A-Za-z0-9_])col[[:space:]]*:[[:space:]]*i64' || fail "struct Pos has no field 'col: i64'"
for m in grid level world; do
    grep -wq Pos "$m.$ext" || fail "$m.$ext does not use Pos"
done

# 2. run_commands is split into parse_command, apply_move, apply_query.
# Prints the lines of fn $1 (in any file): from its `fn` line to the first
# later line that is its closing brace, at the indentation of the `fn`.
body() {
    for f in $files; do
        awk -v name="$1" '
            !on && $0 ~ "^[ \t]*(pub[ \t]+)?fn[ \t]+" name "[ \t]*[<(]" {
                on = 1; match($0, /^[ \t]*/); ind = substr($0, 1, RLENGTH); print; next
            }
            on { print; if ($0 == ind "}") exit }
        ' "$f"
    done
}
for f in run_commands parse_command apply_move apply_query; do
    n=$(body "$f" | wc -l | tr -d ' ')
    [ "$n" -gt 0 ] || fail "no fn $f"
    [ "$n" -le 120 ] || fail "fn $f is $n lines long (at most 120)"
done
n=$(body run_commands | wc -l | tr -d ' ')
[ "$n" -le 80 ] || fail "fn run_commands is $n lines long (at most 80)"
for f in parse_command apply_move apply_query; do
    body run_commands | sed '1d' | grep -Eq "(^|[^A-Za-z0-9_])$f[[:space:]]*(::<[^>]*>)?\\(" ||
        fail "run_commands does not call $f"
done
grep -Eq '^[[:space:]]*(pub[[:space:]]+)?fn[[:space:]]+run_commands[[:space:]]*[<(]' "main.$ext" ||
    fail "run_commands is no longer in main.$ext"

# 3. load_level returns Result<Level, LoadError>; the error codes are gone.
en=$(cat $files | awk '/(^|[^A-Za-z0-9_])enum[ \t]+LoadError([ \t]|\{|$)/ { on = 1 } on { print } on && /\}/ { exit }')
[ -n "$en" ] || fail "no enum LoadError"
for v in EmptyMap NoSeparator RaggedRow UnknownTile NoRobot SecondRobot OddTeleporters; do
    echo "$en" | grep -Eq "(^|[^A-Za-z0-9_])$v([^A-Za-z0-9_]|\$)" || fail "enum LoadError has no variant $v"
done
echo "$flat" | grep -Eq 'fn[[:space:]]+load_level[[:space:]]*\([^)]*\)[[:space:]]*->[[:space:]]*Result[[:space:]]*<[[:space:]]*Level[[:space:]]*,[[:space:]]*LoadError[[:space:]]*>' ||
    fail "load_level does not return Result<Level, LoadError>"
params=$(echo "$flat" | grep -Eo 'fn[[:space:]]+load_level[[:space:]]*\([^)]*\)' | head -n 1)
echo "$params" | grep -wq Level && fail "load_level still takes a Level to fill: $params"
for w in dest error_at error_tile error_num; do
    hit=$(grep -nw -- "$w" $files | head -n 1 | cut -c1-100)
    [ -z "$hit" ] || fail "'$w' still appears: $hit"
done
hit=$(grep -nE '(^|[^A-Za-z0-9_])ERR_[A-Z_]+' $files | head -n 1 | cut -c1-100)
[ -z "$hit" ] || fail "an ERR_ code still appears: $hit"
exit 0
