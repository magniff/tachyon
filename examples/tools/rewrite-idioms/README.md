# Rewrite idioms

`wordstat` counts the lines and words of a text, its commonest words and
a histogram of word lengths. It was written before std had
`Buf::push_str` and iterators, so it calls helpers from `compat.tach`
(`buf_add(b, s)`, `buf_add_int(b, n)`, `vec_at(v, i)`, each marked
deprecated) and walks slices with index loops. Five files, about 260
lines; `poem.txt` is the input.

The session replaces each old idiom with the new one across the whole
program with `tachyonc rewrite`: a search and replace over the
program's syntax tree rather than its text, with holes (`$x`) for
sub-expressions, typed by the checker (`--where`), and checked like
every edit. Every command below is run by `tests/walkthrough/run.sh` on
a fresh copy of this directory, and its output is checked against this
file.

## The program

```console
$ tachyonc main.tach -o wordstat && ./wordstat < poem.txt | tee before.txt
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
```

## 1. A deprecated helper becomes a method

`buf_add($b, $s)` matches any call of `buf_add` with two arguments, and
`$b.push_str($s)` puts each argument's exact text back where its hole
is. `--dry-run` prints the diff without writing it:

```console
$ tachyonc rewrite 'buf_add($b, $s)' '$b.push_str($s)' --dry-run | head -12
--- a/report.tach
+++ b/report.tach
@@ -9 +9 @@
-        buf_add(b, "#");
+        b.push_str("#");
@@ -14 +14 @@
-    buf_add(b, "lines ");
+    b.push_str("lines ");
@@ -16 +16 @@
-    buf_add(b, ", words ");
+    b.push_str(", words ");
@@ -18 +18 @@
$ tachyonc rewrite 'buf_add($b, $s)' '$b.push_str($s)'
rewrote 24 sites in 1 file	report.tach	+24 -24 lines
$ tachyonc rewrite 'buf_add_int($b, $n)' '$b.push_int($n)'
rewrote 10 sites in 1 file	report.tach	+10 -10 lines
$ tachyonc rewrite 'vec_at($v, $i)' '$v.get($i)' --show
rewrote 3 sites in 2 files	2 files	+3 -3 lines
// report.tach:32
32	        let c = top.get(i);
// stats.tach:65
65	        out.push(v.get(i));
// stats.tach:74
74	        if v.get(i).n == 1 {
```

That was 37 call sites in two files, none of them read or edited by
hand. A pattern matches syntax, not text: `vec_at(v, i)` inside
`out.push(...)` and inside the condition `vec_at(v, i).n == 1` are
found the same way, and a comment or a string that mentions `buf_add`
is not a call.

## 2. The helpers go

Nothing calls them any more, and the `use` lines that imported them are
now unused. `query unused` lists both; `fix --only unused` removes the
imports:

```console
$ tachyonc query unused
crate::compat::buf_add	compat.tach:7:8	fn
crate::compat::buf_add_int	compat.tach:12:8	fn
crate::compat::vec_at	compat.tach:17:8	fn
crate::compat::buf_add	report.tach:3:21	import
crate::compat::buf_add_int	report.tach:3:30	import
crate::compat::vec_at	report.tach:3:43	import
crate::compat::vec_at	stats.tach:3:20	import
$ tachyonc fix --only unused --show
fixed 4 unused imports	2 files	+0 -2 lines
// report.tach:2: 1 line removed after line 2
// stats.tach:2: 1 line removed after line 2
```

The module itself goes with `edit delete`, which removes its `mod` line
(the file stays on disk: `git rm` it):

```console
$ tachyonc edit delete compat && git rm -q compat.tach
deleted crate::compat	main.tach	+0 -1 lines
```

## 3. A rewrite that only fits some types

`v.len() == 0` is `v.is_empty()` for a `Vec`, but `Buf` has no
`is_empty`. Asked to rewrite every site, the tool makes the change,
checks the program, finds the site it would break, and writes nothing:

```console
$ tachyonc rewrite '$v.len() == 0' '$v.is_empty()'
./report.tach:68:8: error[type error] no method 'is_empty' on type '*Buf'  [edited: crate::report::finish]
error edit.breaks: 1 new error; nothing written
try: tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --no-check
[exit 1]
```

`--where` restricts a hole to a type, as the checker wrote it. The site
it skipped is reported with its type, and a command for it:

```console
$ tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: Vec<[u8]>' --show
rewrote 1 site in 1 file	main.tach	+1 -1 lines
// main.tach:19
19	    if ws.is_empty() {
note rewrite.types: 1 site matches but for --where; first: $v is *Buf at report.tach:68:8
try: tachyonc rewrite '$v.len() == 0' '$v.is_empty()' --where '$v: *Buf' --dry-run
```

## 4. Index loops become `for x in v`

A pattern can hold statements: `$s...` stands for the rest of a block.
This one matches a loop over the indices of `$v` whose first statement
reads `$v[$i]`, and writes a loop over the elements:

```console
$ tachyonc rewrite 'for $i in 0..$v.len { let $x = $v[$i]; $s... }' 'for $x in $v { $s... }' --show
rewrote 4 sites in 2 files	2 files	+4 -8 lines
// stats.tach:12
12	    for w in ws {
// stats.tach:41
41	    for w in ws {
// stats.tach:50
50	    for w in ws {
// text.tach:18
18	    for c in text {
note rewrite.dropped: 1 site is left: the replacement drops $i, which the code it keeps uses; first: text.tach:42:18
try: tachyonc query show text.tach:42
```

One loop was left: `longest_line` uses the index `i` after reading
`ls[i]` (it remembers where the longest line is), and the replacement
would drop `i`. The tool leaves such a site as it is and says where:

```console
$ tachyonc query show text.tach:42
// crate::text::longest_line	text.tach:33-45
// The length of the longest line, and its index.
pub fn longest_line(ls: [[u8]]) -> (i64, i64) {
    let mut best = 0;
    let mut at = 0;
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
$ tachyonc check && tachyonc main.tach -o wordstat && ./wordstat < poem.txt | diff before.txt - && echo same output
same output
$ git diff HEAD --stat
 compat.tach | 19 -----------------
 main.tach   |  3 +--
 report.tach | 71 ++++++++++++++++++++++++++++++-------------------------------
 stats.tach  | 14 +++++-------
 text.tach   |  3 +--
 5 files changed, 42 insertions(+), 68 deletions(-)
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
