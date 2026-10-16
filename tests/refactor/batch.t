## tachyonc batch (0.15): several commands in one call, each output after
## a header line `## $ tachyonc ARGS`, then `## exit N` when it failed.
## (The transcripts' comments start with `##` too: the headers are shown
## as `#> ` here.)
$ batch $T/inputs/batch-queries.txt | sed 's/^## /#> /'
#> $ tachyonc query items calc
# crate::calc	calc.tach
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
#> $ tachyonc query show clamp
// crate::calc::clamp	calc.tach:3-12	effects: none
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
#> $ tachyonc query refs clamp --count
3
$ batch < $T/inputs/batch-queries.txt | sed 's/^## /#> /'
#> $ tachyonc query items calc
# crate::calc	calc.tach
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
#> $ tachyonc query show clamp
// crate::calc::clamp	calc.tach:3-12	effects: none
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
#> $ tachyonc query refs clamp --count
3
## An edit is written; the commands after it see it. A failing command
## does not end the batch; the first failing status is the batch's.
$ batch $T/inputs/batch-edit.txt | sed 's/^## /#> /'
#> $ tachyonc edit patch clamp --old 'v > hi' --new 'v >= hi'
patched crate::calc::clamp	calc.tach	+1 -1 lines
#> $ tachyonc query show nosuchthing
error query.no-match: no definition 'nosuchthing'
try: tachyonc query items
#> exit 1
#> $ tachyonc query show clamp
// crate::calc::clamp	calc.tach:3-12	effects: none
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
#> $ tachyonc check
ok: 0 errors in main.tach
% git checkout -q calc.tach
$ batch $T/inputs/batch-edit.txt >/dev/null
[exit 1]
## --stop: the first failure ends it.
% git checkout -q calc.tach
$ batch $T/inputs/batch-edit.txt --stop | sed 's/^## /#> /'
#> $ tachyonc edit patch clamp --old 'v > hi' --new 'v >= hi'
patched crate::calc::clamp	calc.tach	+1 -1 lines
#> $ tachyonc query show nosuchthing
error query.no-match: no definition 'nosuchthing'
try: tachyonc query items
#> exit 1
## <<WORD gives a command its stdin; a word that is no command.
% git checkout -q calc.tach
$ batch $T/inputs/batch-stdin.txt | sed 's/^## /#> /'
#> $ tachyonc edit insert --in sum_to --after 'i += 1;' <<END
inserted in crate::calc::sum_to	calc.tach	+1 -0 lines
#> $ tachyonc edit patch sum_to < no-such.pairs
error batch.usage: cannot read 'no-such.pairs'
#> exit 2
#> $ tachyonc query show sum_to
// crate::calc::sum_to	calc.tach:14-24	effects: diverge
// 1 + 2 + ... + n.
pub fn sum_to(n: i64) -> i64 {
    let mut total = 0;
    let mut i = 1;
    while i <= n {
        total += i;
        i += 1;
        total += 0;
    }
    total
}
#> $ tachyonc build calc.tach
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
error batch.usage: one FILE of commands; usage: tachyonc batch [FILE] [--root R] [--stop], one command per line
[exit 2]
$ batch --all
error batch.usage: unknown option '--all' (--root R, --stop)
[exit 2]
## --root: every command's root.
% mkdir sub
% cd sub && "$COMPILER" batch --root ../main.tach < $T/inputs/batch-queries.txt | sed "s/^## /#> /" | head -4
#> $ tachyonc query items calc
# crate::calc	../calc.tach
4	fn	pub fn clamp(v: i64, lo: i64, hi: i64) -> i64
15	fn	pub fn sum_to(n: i64) -> i64
