# Prove it unchanged

`pack` run-length encodes its input, checks that the encoding decodes
back, and prints sizes and Adler-32 checksums. Three files, about 120
lines; `samples/` holds four inputs, `colleague.patch` a change that
arrives during the session.

A clean-up should change how the code reads and nothing else. This
session makes several (names, a named constant, a colleague's patch put
into shape, a function extracted) and proves each one changed nothing,
with the strongest evidence it can get: for edits that should not
change the compiled code, the assembly itself, byte for byte; for edits
that do change it, the program's output on every sample. Every command
below is run by `tests/walkthrough/run.sh` on a fresh copy of this
directory, and its output is checked against this file.

## The evidence to compare against

The assembly (`-o FILE.s` writes it; `--no-positions` leaves out the
positions the run-time checks print, which move with the text) and the
output on every sample, before any change:

```console
$ volec main.vl --no-positions -o before.s
ok: wrote before.s
$ volec main.vl -o pack && for f in samples/*.txt; do ./pack < $f; done > before.out
ok: built pack
$ cat before.out
in        0 bytes  adler32 00000001
out       0 bytes  adler32 00000001  (0% of the input)
longest run 0
in       13 bytes  adler32 21e70493
out      24 bytes  adler32 35740434  (184% of the input)
longest run 2
in      301 bytes  adler32 518f4787
out       6 bytes  adler32 08a801b2  (1% of the input)
longest run 255
in      108 bytes  adler32 a2d92845
out      30 bytes  adler32 52c80529  (27% of the input)
longest run 20
```

## 1. Names: the compiled code must not change at all

`a`, `b`, `c1`, `c2` and `p` say little. Locals are renamed as
`FUNCTION::name`:

```console
$ volec refactor rename adler32::a low --show
renamed local a to low in crate::adler::adler32, 4 uses	adler.vl	+4 -4 lines
// adler.vl:4
4	    var low: u64 = 1;
// adler.vl:7-8
7	        low = (low + x as u64) % 65521;
8	        b = (b + low) % 65521;
// adler.vl:10
10	    (b << 16) | low
$ volec refactor rename adler32::b high
renamed local b to high in crate::adler::adler32, 3 uses	adler.vl	+3 -3 lines
$ volec refactor rename main::c1 sum_in
renamed local c1 to sum_in in crate::main, 1 use	main.vl	+2 -2 lines
$ volec refactor rename main::c2 sum_out
renamed local c2 to sum_out in crate::main, 1 use	main.vl	+2 -2 lines
$ volec refactor rename main::p out
renamed local p to out in crate::main, 4 uses	main.vl	+4 -4 lines
$ volec main.vl --no-positions -o after.s && cmp before.s after.s && echo same assembly
same assembly
ok: wrote after.s
```

`65521` deserves a name. The constant goes in first, then a rewrite
replaces the number with it. A rewrite of every `65521` would also hit
the constant's own value, `const MOD_ADLER: u64 = MOD_ADLER;`, and the
check refuses that; the pattern `$e % 65521` only matches the uses:

```console
$ volec edit insert --before adler32 <<'EOF'
> // the largest prime below 2^16
> const MOD_ADLER: u64 = 65521;
> EOF
inserted before crate::adler::adler32	adler.vl	+3 -0 lines
$ volec rewrite '65521' 'MOD_ADLER'
adler.vl:4:1: error[type error] constant 'MOD_ADLER' is defined in terms of itself  [edited: crate::adler::MOD_ADLER]
error edit.breaks: 1 new error; nothing written
try: volec rewrite 65521 MOD_ADLER --no-check
[exit 1]
$ volec rewrite '$e % 65521' '$e % MOD_ADLER' --show
rewrote 2 sites in 1 file	adler.vl	+2 -2 lines
// adler.vl:10-11
10	        low = (low + x as u64) % MOD_ADLER;
11	        high = (high + low) % MOD_ADLER;
$ volec main.vl --no-positions -o after.s && cmp before.s after.s && echo same assembly
same assembly
ok: wrote after.s
```

## 2. A colleague's patch, put into shape

A patch arrives that documents `run_at`'s loop, written by hand:

```console
$ git apply colleague.patch && git diff --stat rle.vl
 rle.vl | 9 ++++-----
 1 file changed, 4 insertions(+), 5 deletions(-)
$ volec fmt --check
rle.vl
error fmt.unformatted: 1 of 3 files are not formatted
try: volec fmt --dry-run rle.vl
try: volec fmt rle.vl
[exit 1]
```

`fmt --check` is the gate a project runs in CI: one line per file,
and the commands that fix it. `fmt` lays the file out (as one edit,
journaled like any other), and the assembly shows that it changed only
the layout:

```console
$ volec fmt rle.vl
formatted	rle.vl	+4 -4 lines
$ volec query show run_at
// crate::rle::run_at	rle.vl:4-9	effects: panic diverge
fn run_at(s: [u8], i: i64) -> i64 {
    var n = 1;
    // a run ends at the end of s, at another byte, or at 255 (one count byte)
    while i + n < s.len && s[i + n] == s[i] && n < 255 { n += 1; }
    n
}
$ volec main.vl --no-positions -o after.s && cmp before.s after.s && echo same assembly
same assembly
ok: wrote after.s
$ volec fmt --check && echo formatted
formatted
```

## 3. A function extracted: same output

`main` checks the round trip inline. `extract-function` moves lines of
a function into a new one: the locals the lines use become its
parameters (in the order of their first use), the one they define and
`main` uses after them its result:

```console
$ volec refactor extract-function main --lines 21-24 --to round_trips --show
extracted lines 21-24 of crate::main into round_trips(out, gpa, s) -> bool	main.vl	+9 -4 lines
// main.vl:21
21	    let ok = round_trips(out, gpa, s);
// main.vl:34-41
34	}
35	
36	fn round_trips(out: [u8], gpa: Gpa, s: [u8]) -> bool {
37	    let ok = match rle::decode(out, gpa) {
38	        Some(back) => back.as_slice() == s,
39	        None => false,
40	    };
41	    ok
```

The compiled code changes now (there is a new function), so the
evidence is the program's behaviour, on every sample:

```console
$ volec main.vl --no-positions -o after.s && cmp -s before.s after.s || echo the assembly differs
the assembly differs
ok: wrote after.s
$ volec main.vl -o pack && for f in samples/*.txt; do ./pack < $f; done | diff before.out - && echo same output
same output
ok: built pack
```

## 4. When the compiler is what changed

The same question, asked of two compilers instead of two versions of a
program: does a new `volec` compile my programs to the same code as
the old one? `same-output OLD` compiles every program of a corpus with
both, for every target, at `-O0`, `-O1` and `-O2`, and compares the
assembly, the messages and the exit status. It is how vole's own
refactorings of the compiler are proven ([docs/refactor.md](../../../docs/refactor.md));
OLD is a path to the other compiler, here a copy of this one:

```console
$ cp "$(command -v volec)" old-volec && volec same-output ./old-volec --corpus main.vl --work so
identical	12 compilations	1 programs	4 targets	-O0 -O1 -O2
```

## The whole change

```console
$ git diff --stat
 adler.vl | 13 ++++++++-----
 main.vl  | 23 ++++++++++++++---------
 rle.vl   |  5 ++---
 3 files changed, 24 insertions(+), 17 deletions(-)
```

## Why not by hand

- A rename done with an editor's search and replace, or a reformat by
  hand, can be checked by eye for a few lines. `cmp before.s after.s`
  checks every one: when the assembly is identical, the program is the
  same program, whatever the diff looks like.
- The rewrite that would have made `MOD_ADLER` refer to itself was
  refused before it was written; a text replacement would have left a
  program that does not compile, or, with a different constant, one
  that silently means something else.
- `fmt` is an edit like the others: one layout, applied by a tool,
  verifiable (`--check`), undoable.
- Extracting a function by hand means choosing its parameters and its
  result; the tool computes them from what the lines read and write.
