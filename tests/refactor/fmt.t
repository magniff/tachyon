## volec fmt (0.13): one layout, no options. --check lists the files
## that are not formatted, and writes nothing.
$ fmt --check
main.vl
util.vl
error fmt.unformatted: 2 of 2 files are not formatted
try: volec fmt --dry-run main.vl
try: volec fmt main.vl
[exit 1]
## --dry-run prints the change as a diff.
$ fmt --dry-run util.vl
--- a/util.vl
+++ b/util.vl
@@ -4,0 +5 @@
+
## fmt writes them, as one edit (undo takes it back).
$ fmt
formatted	2 files	+18 -13 lines
% cat main.vl
// A program laid out by hand, for `volec fmt`.
mod util;
use util::{Kind, Pair, sum, twice};

struct Point { x: i64, y: i64 }

fn area(p: Point) -> i64 {
    let w = p.x * 2; // the width
    let h = -p.y;
    if w > 0 && h < 0 { return w * (0 - h); }
    else if w == 0 { return 0; }
    0
}

fn describe(k: Kind) -> i64 {
    match k {
        Kind::Small => 1,
        Kind::Large(n) => n * 1000 + twice(n) * 100 + sum(n, n + 1) * 10 + n,
    }
}

fn main() -> i32 {
    let p = Point { x: 3, y: -4 };
    let pair: Pair<i64> = Pair {
        first: area(p), second: describe(Kind::Large(2)) + describe(Kind::Small),
    };

    /* a block comment
       on two lines */
    let total = pair.first + pair.second + twice(twice(twice(1))) + sum(sum(1, 2), sum(3, 4)) - 2;
    let s = "a string \
        continued";
    if total != 2469 || s.len != 18 { return 1; }
    0
}
% cat util.vl
pub struct Pair<T> { first: T, second: T }
pub enum Kind { Small, Large(i64) }

pub fn twice(n: i64) -> i64 { n * 2 }

pub fn sum(a: i64, b: i64) -> i64 {
    a + b
}
$ fmt
note fmt.none: 2 files formatted already
$ fmt --check
## The program is the same: only blanks changed.
% "$COMPILER" main.vl -o prog && ./prog && echo ran
ran
ok: built prog
$ undo
undid formatted	2 files	+18 -13 lines
$ fmt --check util.vl
util.vl
error fmt.unformatted: 1 of 1 file is not formatted
try: volec fmt --dry-run util.vl
try: volec fmt util.vl
[exit 1]
## A module of the program (with its children), and a file that does not
## lex: left as it is.
$ fmt crate::util --check
util.vl
error fmt.unformatted: 1 of 1 file is not formatted
try: volec fmt --dry-run util.vl
try: volec fmt util.vl
[exit 1]
% printf 'fn main() -> i32 {\n    let s = "x;\n    0\n}\n' >bad.vl
$ fmt bad.vl
error fmt.unreadable: bad.vl:2: newline in string literal; left as it is
[exit 1]
$ fmt nowhere/
error fmt.no-file: no .vl file at 'nowhere/'
[exit 1]
$ fmt --width 80
error fmt.usage: unknown option '--width'
try: volec fmt --check --all
[exit 2]
## Edits are laid out as fmt does it, their lines only.
$ fmt
formatted	2 files	+18 -13 lines
$ edit replace sum < $T/inputs/fmt_helper.vl
replaced crate::util::sum	util.vl	+1 -0 lines
% cat util.vl
pub struct Pair<T> { first: T, second: T }
pub enum Kind { Small, Large(i64) }

pub fn twice(n: i64) -> i64 { n * 2 }

pub fn sum(a: i64, b: i64) -> i64 {
    if a > b && b > 0 { return b + a; }
    a + b
}
## An edit that adds `use` lines: their run is tidied as fmt does it.
$ edit insert --before crate::use < $T/inputs/fmt_use.vl
inserted before crate::use	main.vl	+1 -0 lines
$ query text main.vl:1-5
// main.vl:1-5
1	// A program laid out by hand, for `volec fmt`.
2	mod util;
3	use util::{Kind, Pair, sum, twice};
4	use util::Pair as P;
5	
## volec explain CODE: what a diagnostic means, how to fix it.
$ explain fmt.unreadable
fmt.unreadable: error, exit 1
The one file given does not lex or its brackets do not balance (or formatting it would change its tokens, a bug of fmt): it is left as it is.
fix: Fix the error at the line named, then fmt it again.
example:
    error fmt.unreadable: main.vl:3: newline in string literal; left as it is
$ explain type-error
type error: error (compiler)
The program is not well typed, or names something that is not there or not visible: an undefined name, a private item, a wrong type or argument count.
fix: Read the message and its help, and use its try: lines (0.17) as they are: code to paste (a conversion, the missing match arms, std's function for a method, a `use` line), or a command to run (`volec fix --only imports|pub|alloc016 ROOT`, `volec edit delete FILE:LINE` for a duplicate, `volec query items TYPE` for a type's methods); VALUE in one is yours to fill in.
example:
    main.vl:4:5: error[type error] 'secret' is private | help: make it public: `pub fn secret` at util.vl:2:1 | try: volec fix --only pub main.vl
$ explain fmt
fmt.bad-in	error, exit 1
fmt.no-file	error, exit 1
fmt.none	note, exit 0
fmt.skipped	note, exit 0
fmt.unformatted	error, exit 1
fmt.unreadable	error, exit 1
fmt.usage	error, exit 2
$ explain fmt.unformated
error explain.unknown: no code 'fmt.unformated'
try: volec explain fmt.unformatted
[exit 1]
