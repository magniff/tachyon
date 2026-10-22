# Fix the errors

`gradebook` reads a class's test scores and prints each student's
average, grade and biggest swing between tests. It was written in a
hurry, with Rust habits, and half-changed: it does not compile. Three
files, about 130 lines, nine errors.

The session gets it to build the way an agent should: every error at
once, one line each; the mechanical ones fixed by `volec fix`; the
rest fixed by name with `edit patch` and `edit apply`, each edit checked
before it is written. Every command below is run by
`tests/walkthrough/run.sh` on a fresh copy of this directory, and its
output is checked against this file. (This directory is the one example
that is meant not to compile.)

## 1. Every error, one line each

A build stops at the errors; `check` runs only the front end (parse,
names, types, unsafe), which is fast, and prints every error of every
file, one per line, `FILE:LINE:COL: error[KIND] MESSAGE | help: ...`:

```console
$ volec check
main.vl:8:38: error[type error] 'letter' is private | help: make it public: `pub fn letter` at grades.vl:21:1 | try: volec fix --suggested main.vl
main.vl:9:14: error[type error] unresolved import 'roster::add_score'
main.vl:16:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:17:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:31:19: error[type error] undefined variable 'I64_MIN' | help: add `use std::I64_MIN;` | try: volec fix --suggested main.vl
grades.vl:18:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
grades.vl:39:17: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
roster.vl:26:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `var count`
[exit 1]
```

Most say what to do, in their `help:`. A `KIND` (`type error`,
`unsafe`, ...) or a tool's code (`patch.no-match`) is explained by
`explain`:

```console
$ volec explain unsafe
unsafe: error (compiler)
An unsafe operation (a raw pointer's dereference or indexing, a C call, a union field) outside unsafe code.
fix: Put it in an `unsafe { }` block, or the function in `unsafe fn`; the try: line, `volec fix --only unsafe ROOT`, wraps every such place (the check hook prints it once, with how many errors it answers). Through a `*T` parameter that only reads or writes one value: make it a let parameter `x: T`, or `x: inout T` when written through (`volec refactor signature F --convention x inout`), and keep `*T` for what stays raw (indexed, compared, cast, stored, given to C).
example:
    main.vl:39:13: error[unsafe] dereference of a raw pointer is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: volec fix --only unsafe main.vl
```

## 2. The mechanical ones: `fix`

A missing `use` line, an item that must become `pub`, a C call outside
`unsafe`: these have exactly one fix, and `fix` makes them all in one
edit. (An error whose `try:` is `volec fix --suggested` has an exact
fix the compiler knows, `totl` for `total` too: `fix --suggested` makes
those, then prints the errors left; `totl` is fixed by hand below, to
show `edit patch`.) `--dry-run` shows the diff first:

```console
$ volec fix --dry-run
--- a/main.vl
+++ b/main.vl
@@ -7,0 +8,2 @@
+use std::I64_MIN;
+
--- a/grades.vl
+++ b/grades.vl
@@ -21 +21 @@
-fn letter(avg: i64) -> u8 {
+pub fn letter(avg: i64) -> u8 {
@@ -39 +39 @@
-        let d = abs((scores[i] - scores[i - 1]) as i32) as i64;
+        let d = unsafe { abs((scores[i] - scores[i - 1]) as i32) as i64 };
$ volec fix
fixed 1 missing import, 1 pub, 1 unsafe block	2 files	+4 -2 lines
$ volec check
main.vl:11:14: error[type error] unresolved import 'roster::add_score'
main.vl:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
grades.vl:18:5: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
roster.vl:26:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `var count`
[exit 1]
```

## 3. The ones that need a decision: `edit patch`

The item at an error's position is `query show FILE:LINE`:

```console
$ volec query show roster.vl:26
// crate::roster::with_scores	roster.vl:21-30
// How many students have at least `n` scores.
pub fn with_scores(r: Roster, n: i64) -> i64 {
    let count = 0;
    for s in r.students.as_slice() {
        if s.scores.len() >= n {
            count += 1;
        }
    }
    count
}
warning query.program-errors: 6 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
```

`edit patch` changes text inside one item, named by name or by a
`FILE:LINE` inside it; OLD must occur exactly once in that item:

```console
$ volec edit patch roster.vl:26 --old 'let count' --new 'var count' --show
patched crate::roster::with_scores	roster.vl	+1 -1 lines
// roster.vl:23
23	    var count = 0;
```

An OLD that is not there is refused, with the nearest line of the item
and a `try:` command built from it. Here it shows that the source
writes the field, `scores.len` (a slice has both, `.len` and `.len()`):

```console
$ volec edit patch grades.vl:18 --old 'totl / scores.len()' --new 'total / scores.len()'
error patch.no-match: OLD 1 is not in crate::grades::average; nearest, line 18: totl / scores.len
try: volec edit patch grades.vl:18 --old 'totl / scores.len' --new 'total / scores.len()'
[exit 1]
$ volec edit patch grades.vl:18 --old 'totl' --new 'total' --show
patched crate::grades::average	grades.vl	+1 -1 lines
// grades.vl:18
18	    total / scores.len
```

## 4. A fix that spans items: `edit apply`

What is left is one change seen from two sides: `main` calls
`enrol(&r, name, scores)` and imports `add_score`, but `roster` has a
two-argument `enrol` and no `add_score`.

```console
$ volec check
main.vl:11:14: error[type error] unresolved import 'roster::add_score'
main.vl:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
main.vl:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: inout Roster, name: [u8])` (roster.vl:17)
[exit 1]
$ volec query show roster::enrol
// crate::roster::enrol	roster.vl:16-19	effects: alloc(Gpa) panic
// A student with no scores yet.
pub fn enrol(r: inout Roster, name: [u8]) {
    r.students.push(Student { name: name, scores: Vec::new_in(r.students.allocator()) });
}
warning query.program-errors: 4 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
```

`edit apply` takes the new text of several items as blocks: `@@ NAME`
replaces an item, `@@ new after NAME` adds one, `@@ delete NAME`
removes one. All the blocks are one edit: checked together, written
together, undone together. (The output of `query show A B`, edited, is
a valid input.)

```console
$ volec edit apply --show <<'EOF'
> @@ roster::enrol
> // A student and their scores so far.
> pub fn enrol(r: inout Roster, name: [u8], scores: [i64]) {
>     var v: Vec<i64> = Vec::new_in(r.students.allocator());
>     v.extend_from_slice(scores);
>     r.students.push(Student { name: name, scores: v });
> }
> @@ new after roster::enrol
> // One more score for the student called `name`; false when there is none.
> pub fn add_score(r: inout Roster, name: [u8], score: i64) -> bool {
>     for i in 0..r.students.len() {
>         if r.students[i].name == name {
>             r.students[i].scores.push(score);
>             return true;
>         }
>     }
>     false
> }
> EOF
applied 2 blocks: replaced crate::roster::enrol; inserted after crate::roster::enrol	roster.vl	+16 -3 lines
// roster.vl:16-31
16	// A student and their scores so far.
17	pub fn enrol(r: inout Roster, name: [u8], scores: [i64]) {
18	    var v: Vec<i64> = Vec::new_in(r.students.allocator());
19	    v.extend_from_slice(scores);
20	    r.students.push(Student { name: name, scores: v });
21	}
22	
23	// One more score for the student called `name`; false when there is none.
24	pub fn add_score(r: inout Roster, name: [u8], score: i64) -> bool {
25	    for i in 0..r.students.len() {
26	        if r.students[i].name == name {
27	            r.students[i].scores.push(score);
28	            return true;
29	        }
30	    }
31	    false
```

## 5. It builds

```console
$ volec check && echo no errors
no errors
ok: 0 errors in main.vl
$ volec main.vl -o gradebook && ./gradebook
Ada     95 A  swing  6, with honours
Brook   75 C  swing 21
Cyd     64 D  swing 17
best: Ada (95); 3 students have 3 scores or more
ok: built gradebook
$ git diff --stat
 grades.vl |  6 +++---
 main.vl   |  2 ++
 roster.vl | 21 +++++++++++++++++----
 3 files changed, 22 insertions(+), 7 deletions(-)
```

## Why not by hand

- Nine errors in three files were listed by one command, before any
  build, each with its position and usually its fix. A compile-edit
  loop would have shown them a few at a time.
- Three of them were fixed by `fix` with no file opened; the edit is the
  same one a careful human would make (`pub fn letter`, an
  `unsafe { }` around the one call, the `use std::I64_MIN;` line).
- Each other fix named the item it changes, not a line number that
  moves after every edit, and was checked before it was written: a
  patch that had introduced a new error (`scores.size()` on a slice)
  would have been refused, with the error.
- `edit apply` made a change that is only correct as a whole (a new
  signature, a new function) in one step, so there was never a state of
  the program with more errors than before.
