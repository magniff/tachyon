# Rewrite idioms

`wordstat` counts the lines and words of a text, its commonest words and
a histogram of word lengths. It was written before std had
`Buf::push_str` and iterators, so it calls helpers from `compat.vl`
(`buf_add(&b, s)`, `buf_add_int(&b, n)`, `vec_at(v, i)`, each marked
deprecated) and walks slices with index loops. Five files, about 260
lines; `poem.txt` is the input.

The session replaces each old idiom with the new one across the whole
program with `volec rewrite`: a search and replace over the
program's syntax tree rather than its text, with holes (`$x`) for
sub-expressions, typed by the checker (`--where`), and checked like
every edit. Every command below is run by `tests/walkthrough/run.sh` on
a fresh copy of this directory, and its output is checked against this
file.

## The program

```console
$ volec main.vl -o wordstat && ./wordstat < poem.txt | tee before.txt
lines 8, words 47 (34 distinct, 29 used once), mean length 3.9
commonest:
  the     7
  and     4
  that    3
  in      2
  is      2
word lengths:
   2 #######
   3 ############
   4 ##############
   5 #########
   6 #
   7 ##
   8 ##
longest line: 3 (37 bytes): And sings the tune without the words,
--
ok: built wordstat
```

## 1. A deprecated helper becomes a method

`buf_add(&$b, $s)` matches any call of `buf_add` with two arguments,
the first lent inout (`&b`), and `$b.push_str($s)` puts each argument's
exact text back where its hole is (a method call lends its receiver
itself, so the `&` goes). `--dry-run` prints the diff without writing it:

```console
$ volec rewrite 'buf_add(&$b, $s)' '$b.push_str($s)' --dry-run | head -12
--- a/report.vl
+++ b/report.vl
@@ -5 +5 @@
-use crate::compat::{buf_add, buf_add_int, vec_at};
+use crate::compat::{buf_add_int, vec_at};
@@ -10 +10 @@
-        buf_add(&b, "#");
+        b.push_str("#");
@@ -15 +15 @@
-    buf_add(&b, "lines ");
+    b.push_str("lines ");
@@ -17 +17 @@
note rewrite.imports: removed 1 import the rewrite left unused
$ volec rewrite 'buf_add(&$b, $s)' '$b.push_str($s)'
rewrote 24 sites in 1 file	report.vl	+25 -25 lines
note rewrite.imports: removed 1 import the rewrite left unused
$ volec rewrite 'buf_add_int(&$b, $n)' '$b.push_int($n)'
rewrote 10 sites in 1 file	report.vl	+11 -11 lines
note rewrite.imports: removed 1 import the rewrite left unused
$ volec rewrite 'vec_at($v, $i)' '$v[$i]' --show
rewrote 3 sites in 2 files	2 files	+3 -6 lines
// report.vl:4: 1 line removed after line 4
// report.vl:32
32	        let c = top[i];
// stats.vl:4: 2 lines removed after line 4
// stats.vl:64
64	        out.push(v[i]);
// stats.vl:73
73	        if v[i].n == 1 {
note rewrite.imports: removed 2 imports the rewrite left unused
```

That was 37 call sites in two files, none of them read or edited by
hand. A pattern matches syntax, not text: `vec_at(v, i)` inside
`out.push(...)` and inside the condition `vec_at(v, i).n == 1` are
found the same way, and a comment or a string that mentions `buf_add`
is not a call.

## 2. The helpers go

Nothing calls them any more. The `use` names that imported them went
with the last call in each file (`note rewrite.imports`), so only the
functions are left; `query unused` lists them:

```console
$ volec query unused
crate::compat::buf_add	compat.vl:7:8	fn
crate::compat::buf_add_int	compat.vl:12:8	fn
crate::compat::vec_at	compat.vl:17:8	fn
```

The module goes with `edit delete`: its `mod` line and its file, in one
edit (`undo` brings both back):

```console
$ volec edit delete compat
deleted crate::compat	2 files	+0 -20 lines
```

## 3. A rewrite that only fits some types

`v.len() == 0` is `v.is_empty()` for a `Vec`, but `Buf` has no
`is_empty`. Asked to rewrite every site, the tool makes the change,
checks the program, finds the site it would break, and writes nothing;
the hole has two types at the sites, and each gets a command:

```console
$ volec rewrite '$v.len() == 0' '$v.is_empty()'
report.vl:69:8: error[type error] no method 'is_empty' on type 'Buf' | help: no `is_empty`: `x.len() == 0` | try: volec query items Buf main.vl  [edited: crate::report::finish]
error edit.breaks: 1 new error; nothing written
note rewrite.where: $v has 2 types at the sites: Vec<[u8]> (1 site), Buf (1 site); --where takes the ones the replacement fits
try: volec rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: Vec<[u8]>'
try: volec rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: Buf'
try: volec rewrite '$v.len() == 0' '$v.is_empty()' --no-check
[exit 1]
```

`--where` restricts a hole to a type, as the checker wrote it. The site
it skipped is reported with its type, and a command for it:

```console
$ volec rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: Vec<[u8]>' --show
rewrote 1 site in 1 file	main.vl	+1 -1 lines
// main.vl:17
17	    if ws.is_empty() {
note rewrite.types: 1 site matches but for --where; first: $v is Buf at report.vl:69:8
try: volec rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: Buf' --dry-run
```

## 4. Index loops become `for x in v`

A pattern can hold statements: `$s...` stands for the rest of a block.
This one matches a loop over the indices of `$v` whose first statement
reads `$v[$i]`, and writes a loop over the elements:

```console
$ volec rewrite 'for $i in 0..$v.len { let $x = $v[$i]; $s... }' 'for $x in $v { $s... }' --show
rewrote 4 sites in 2 files	2 files	+4 -8 lines
// stats.vl:12
12	    for w in ws {
// stats.vl:41
41	    for w in ws {
// stats.vl:50
50	    for w in ws {
// text.vl:18
18	    for c in text {
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: text.vl:42:18
try: volec query show text.vl:42
```

One loop was left: `longest_line` uses the index `i` after reading
`ls[i]` (it remembers where the longest line is), and the replacement
would drop `i`. The tool leaves such a site as it is and says where:

```console
$ volec query show text.vl:42
// crate::text::longest_line	text.vl:33-45	effects: none
// The length of the longest line, and its index.
pub fn longest_line(ls: [[u8]]) -> (i64, i64) {
    var best = 0;
    var at = 0;
    for i in 0..ls.len {
        let l = ls[i];
        if l.len > best {
            best = l.len;
            at = i;
        }
    }
    (best, at)
}
```

## 5. The same program

```console
$ volec check && volec main.vl -o wordstat && ./wordstat < poem.txt | diff before.txt - && echo same output
same output
ok: 0 errors in main.vl
ok: built wordstat
$ git diff HEAD --stat
 compat.vl | 19 -----------------
 main.vl   |  3 +--
 report.vl | 71 +++++++++++++++++++++++++++++++--------------------------------
 stats.vl  | 15 +++++---------
 text.vl   |  3 +--
 5 files changed, 42 insertions(+), 69 deletions(-)
```

## Why not by hand

- `sed 's/buf_add(\([^,]*\), \(.*\))/\1.push_str(\2)/'` breaks on the
  first argument that holds a comma or a call, and on `buf_add_int`,
  which it also matches. The rewrite's holes are whole expressions,
  parsed by the compiler.
- A text replacement has no types: `len() == 0` to `is_empty()` would
  have broken `finish`, found at the next build. The rewrite was
  checked first and refused, and `--where` said which sites to take.
- The loop rewrite is a change of structure (the loop header, the `let`
  in its body, the variable) that no line-based tool can make, and it
  knows when the change would be wrong (`rewrite.dropped`).
- 42 sites changed by five rewrites, each one checked, each one a
  single `undo` away.
