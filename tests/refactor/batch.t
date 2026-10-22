## volec batch (0.15): several commands in one call, each output after
## a header line `## $ volec ARGS`, then `## exit N` when it failed.
## (The transcripts' comments start with `##` too: the headers are shown
## as `#> ` here.)
$ batch $T/inputs/batch-queries.txt | sed 's/^## /#> /'
#> $ volec query items calc
# crate::calc	calc.vl
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
#> $ volec query show clamp
// crate::calc::clamp	calc.vl:3-12	effects: none
// v, kept within [lo, hi].
pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
    if v < lo {
        return lo;
    }
    if v > hi {
        return hi;
    }
    v
}
#> $ volec query refs clamp --count
3
$ batch < $T/inputs/batch-queries.txt | sed 's/^## /#> /'
#> $ volec query items calc
# crate::calc	calc.vl
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
#> $ volec query show clamp
// crate::calc::clamp	calc.vl:3-12	effects: none
// v, kept within [lo, hi].
pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
    if v < lo {
        return lo;
    }
    if v > hi {
        return hi;
    }
    v
}
#> $ volec query refs clamp --count
3
## An edit is written; the commands after it see it. A failing command
## does not end the batch; the first failing status is the batch's.
$ batch $T/inputs/batch-edit.txt | sed 's/^## /#> /'
#> $ volec edit patch clamp --old 'v > hi' --new 'v >= hi'
patched crate::calc::clamp	calc.vl	+1 -1 lines
#> $ volec query show nosuchthing
error query.no-match: no definition 'nosuchthing'
try: volec query items
#> exit 1
#> $ volec query show clamp
// crate::calc::clamp	calc.vl:3-12	effects: none
// v, kept within [lo, hi].
pub fn clamp(v: i64, lo: i64, hi: i64) -> i64 {
    if v < lo {
        return lo;
    }
    if v >= hi {
        return hi;
    }
    v
}
#> $ volec check
ok: 0 errors in main.vl
% git checkout -q calc.vl
$ batch $T/inputs/batch-edit.txt >/dev/null
[exit 1]
## --stop: the first failure ends it.
% git checkout -q calc.vl
$ batch $T/inputs/batch-edit.txt --stop | sed 's/^## /#> /'
#> $ volec edit patch clamp --old 'v > hi' --new 'v >= hi'
patched crate::calc::clamp	calc.vl	+1 -1 lines
#> $ volec query show nosuchthing
error query.no-match: no definition 'nosuchthing'
try: volec query items
#> exit 1
## <<WORD gives a command its stdin; a word that is no command.
% git checkout -q calc.vl
$ batch $T/inputs/batch-stdin.txt | sed 's/^## /#> /'
#> $ volec edit insert --in sum_to --after 'i += 1;' <<END
inserted in crate::calc::sum_to	calc.vl	+1 -0 lines
#> $ volec edit patch sum_to < no-such.pairs
error batch.usage: cannot read 'no-such.pairs'
#> exit 2
#> $ volec query show sum_to
// crate::calc::sum_to	calc.vl:14-24	effects: diverge
// 1 + 2 + ... + n.
pub fn sum_to(n: i64) -> i64 {
    var total = 0;
    var i = 1;
    while i <= n {
        total += i;
        i += 1;
        total += 0;
    }
    total
}
#> $ volec build calc.vl
error batch.usage: 'build' is not a command batch runs (query, edit, undo, check, fix, fmt, refactor, rewrite, explain, guide, lint)
#> exit 2
## Lines that cannot be read: nothing runs.
$ batch < $T/inputs/batch-bad.txt
error batch.format: stdin:2: no line 'END' ends the text of <<END
[exit 2]
$ batch < $T/inputs/batch-quote.txt
error batch.format: stdin:1: a quote is not closed; nothing run
[exit 2]
$ batch
note batch.usage: no commands in stdin
$ batch a.txt b.txt
error batch.usage: one FILE of commands; usage: volec batch [FILE] [--root R] [--stop], one command per line
[exit 2]
$ batch --all
error batch.usage: unknown option '--all' (--root R, --stop)
[exit 2]
## --root: every command's root.
% mkdir sub
% cd sub && "$COMPILER" batch --root ../main.vl < $T/inputs/batch-queries.txt | sed "s/^## /#> /" | head -4
#> $ volec query items calc
# crate::calc	../calc.vl
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
