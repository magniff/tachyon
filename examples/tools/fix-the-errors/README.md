# Fix the errors

`gradebook` reads a class's test scores and prints each student's
average, grade and biggest swing between tests. It was written in a
hurry, with Rust habits, and half-changed: it does not compile. Three
files, about 130 lines, nine errors.

The session gets it to build the way an agent should: every error at
once, one line each; the mechanical ones fixed by `tachyonc fix`; the
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
$ tachyonc check
main.tach:8:38: error[type error] 'letter' is private | help: make it public: `pub fn letter` at grades.tach:21:1 | try: tachyonc fix --only pub main.tach
main.tach:9:14: error[type error] unresolved import 'roster::add_score'
main.tach:17:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:23:19: error[type error] unknown type 'HashMap' | help: add `use std::HashMap;` | try: tachyonc fix --only imports main.tach
grades.tach:18:5: error[type error] undefined variable 'totl' | help: did you mean 'total'?
grades.tach:39:17: error[unsafe] calling a C function is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: tachyonc fix --only unsafe main.tach
roster.tach:26:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `let mut count`
[exit 1]
```

Most say what to do, in their `help:`. A `KIND` (`type error`,
`unsafe`, ...) or a tool's code (`patch.no-match`) is explained by
`explain`:

```console
$ tachyonc explain unsafe
unsafe: error (compiler)
An unsafe operation (a raw pointer's dereference or indexing, a C call, a union field) outside unsafe code.
fix: Put it in an `unsafe { }` block, or the function in `unsafe fn`; the try: line, `tachyonc fix --only unsafe ROOT`, wraps every such place (the check hook prints it once, with how many errors it answers).
example:
    main.tach:39:13: error[unsafe] dereference of a raw pointer is unsafe | help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place) | try: tachyonc fix --only unsafe main.tach
```

## 2. The mechanical ones: `fix`

A missing `use` line, an item that must become `pub`, a C call outside
`unsafe`: these have exactly one fix, and `fix` makes them all in one
edit. `--dry-run` shows the diff first:

```console
$ tachyonc fix --dry-run
--- a/main.tach
+++ b/main.tach
@@ -9,0 +10 @@
+use std::HashMap;
--- a/grades.tach
+++ b/grades.tach
@@ -21 +21 @@
-fn letter(avg: i64) -> u8 {
+pub fn letter(avg: i64) -> u8 {
@@ -39 +39 @@
-        let d = abs((scores[i] - scores[i - 1]) as i32) as i64;
+        let d = unsafe { abs((scores[i] - scores[i - 1]) as i32) as i64 };
$ tachyonc fix
fixed 1 missing import, 1 pub, 1 unsafe block	2 files	+3 -2 lines
$ tachyonc check
main.tach:9:14: error[type error] unresolved import 'roster::add_score'
main.tach:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
grades.tach:18:5: error[type error] undefined variable 'totl' | help: did you mean 'total'?
roster.tach:26:13: error[type error] cannot assign to immutable variable 'count' | help: make it mutable: `let mut count`
[exit 1]
```

## 3. The ones that need a decision: `edit patch`

The item at an error's position is `query show FILE:LINE`:

```console
$ tachyonc query show roster.tach:26
// crate::roster::with_scores	roster.tach:21-30
// How many students have at least `n` scores.
pub fn with_scores(r: *Roster, n: i64) -> i64 {
    let count = 0;
    for s in r.students.iter() {
        if s.scores.len() >= n {
            count += 1;
        }
    }
    count
}
warning query.program-errors: 6 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short main.tach -c -o /dev/null
```

`edit patch` changes text inside one item, named by name or by a
`FILE:LINE` inside it; OLD must occur exactly once in that item:

```console
$ tachyonc edit patch roster.tach:26 --old 'let count' --new 'let mut count' --show
patched crate::roster::with_scores	roster.tach	+1 -1 lines
// roster.tach:23
23	    let mut count = 0;
```

An OLD that is not there is refused, with the nearest line of the item
and a `try:` command built from it. Here it shows that `len` is a field,
not a method:

```console
$ tachyonc edit patch grades.tach:18 --old 'totl / scores.len()' --new 'total / scores.len()'
error patch.no-match: OLD 1 is not in crate::grades::average; nearest, line 18: totl / scores.len
try: tachyonc edit patch grades.tach:18 --old 'totl / scores.len' --new 'total / scores.len()'
[exit 1]
$ tachyonc edit patch grades.tach:18 --old 'totl' --new 'total' --show
patched crate::grades::average	grades.tach	+1 -1 lines
// grades.tach:18
18	    total / scores.len
```

## 4. A fix that spans items: `edit apply`

What is left is one change seen from two sides: `main` calls
`enrol(&r, name, scores)` and imports `add_score`, but `roster` has a
two-argument `enrol` and no `add_score`.

```console
$ tachyonc check
main.tach:9:14: error[type error] unresolved import 'roster::add_score'
main.tach:18:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:19:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
main.tach:20:5: error[type error] function 'roster::enrol' expects 2 arguments, got 3 | help: its signature: `fn enrol(r: *Roster, name: [u8])` (roster.tach:17)
[exit 1]
$ tachyonc query show roster::enrol
// crate::roster::enrol	roster.tach:16-19	effects: alloc(Gpa) panic
// A student with no scores yet.
pub fn enrol(r: *Roster, name: [u8]) {
    r.students.push(Student { name: name, scores: Vec::new_in(r.students.allocator()) });
}
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short main.tach -c -o /dev/null
```

`edit apply` takes the new text of several items as blocks: `@@ NAME`
replaces an item, `@@ new after NAME` adds one, `@@ delete NAME`
removes one. All the blocks are one edit: checked together, written
together, undone together. (The output of `query show A B`, edited, is
a valid input.)

```console
$ tachyonc edit apply --show <<'EOF'
> @@ roster::enrol
> // A student and their scores so far.
> pub fn enrol(r: *Roster, name: [u8], scores: [i64]) {
>     let mut v: Vec<i64> = Vec::new_in(r.students.allocator());
>     v.extend_from_slice(scores);
>     r.students.push(Student { name: name, scores: v });
> }
> @@ new after roster::enrol
> // One more score for the student called `name`; false when there is none.
> pub fn add_score(r: *Roster, name: [u8], score: i64) -> bool {
>     for i in 0..r.students.len() {
>         let mut s = r.students.get(i);
>         if s.name == name {
>             s.scores.push(score);
>             r.students.set(i, s);
>             return true;
>         }
>     }
>     false
> }
> EOF
applied 2 blocks: replaced crate::roster::enrol; inserted after crate::roster::enrol	roster.tach	+18 -3 lines
// roster.tach:16-33
16	// A student and their scores so far.
17	pub fn enrol(r: *Roster, name: [u8], scores: [i64]) {
18	    let mut v: Vec<i64> = Vec::new_in(r.students.allocator());
19	    v.extend_from_slice(scores);
20	    r.students.push(Student { name: name, scores: v });
21	}
22	
23	// One more score for the student called `name`; false when there is none.
24	pub fn add_score(r: *Roster, name: [u8], score: i64) -> bool {
25	    for i in 0..r.students.len() {
26	        let mut s = r.students.get(i);
27	        if s.name == name {
28	            s.scores.push(score);
29	            r.students.set(i, s);
30	            return true;
31	        }
32	    }
33	    false
```

## 5. It builds

```console
$ tachyonc check && echo no errors
no errors
$ tachyonc main.tach -o gradebook && ./gradebook
Ada     95 A  swing  6, with honours
Brook   75 C  swing 21
Cyd     64 D  swing 17
best: Ada (95); 3 students have 3 scores or more
$ git diff --stat
 grades.tach |  6 +++---
 main.tach   |  1 +
 roster.tach | 23 +++++++++++++++++++----
 3 files changed, 23 insertions(+), 7 deletions(-)
```

## Why not by hand

- Nine errors in three files were listed by one command, before any
  build, each with its position and usually its fix. A compile-edit
  loop would have shown them a few at a time.
- Three of them were fixed by `fix` with no file opened; the edit is the
  same one a careful human would make (`pub fn letter`, an
  `unsafe { }` around the one call, the `use std::HashMap;` line).
- Each other fix named the item it changes, not a line number that
  moves after every edit, and was checked before it was written: a
  patch that had introduced a new error (`scores.len()` on a slice)
  would have been refused, with the error.
- `edit apply` made a change that is only correct as a whole (a new
  signature, a new function) in one step, so there was never a state of
  the program with more errors than before.
