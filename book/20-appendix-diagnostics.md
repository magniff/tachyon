# Appendix B: reading diagnostics

The compiler, the tools and your programs all report problems in a few
fixed shapes. This appendix shows each shape once, says what every part
of it means, and where to look next. With it, you can read a message
you've never seen before.

## Two forms of the same error

Here is a program with a typo:

```vole
fn main() {
    let total = 1;
    println(f"{totl}");
}
```

A build in a terminal prints the error in its *long form*, several
lines:

```err
error[type error]: undefined variable 'totl'
 --> main.vl: line 3, column 16
  = help: did you mean 'total'?
  = try: volec fix --suggested main.vl
```

- The first line is the *kind* or *code* in brackets, `type error`, then
  the message.
- `-->` says where: the file, the line and the column.
- `= help:` lines explain, or suggest a fix in words.
- `= try:` lines are something you can use exactly as written: code to
  put where the error is, or a command to run.

`volec check`, and a build whose output isn't a terminal (a pipe, an
editor, a script), prints the same error in its *short form*, one line:

```console
$ volec check main.vl
main.vl:3:16: error[type error] undefined variable 'totl' | help: did you mean 'total'? | try: volec fix --suggested main.vl
```

It has the same parts, in the same order, separated by ` | `, with the
position first as `FILE:LINE:COLUMN:`. One line per error is easy to
search, count and sort, which is why tools and editors read this form.
`--diagnostics=short` or `--diagnostics=human` picks a form yourself.

When a file has several errors, the compiler reports them all at once,
in order of position. Fix them from the top: a parser error early in a
function can cause others after it.

### Warnings

A *warning* is a problem that doesn't stop the build. It has the same
shapes, with `warning` instead of `error`:

```vole w.vl warn
fn main() {
    let x = 42;
    println("x = {x}");
}
```

```console
$ volec w.vl -o w
warning[format]: this string has '{x}' in it, as text: it is not an f-string
 --> w.vl: line 3, column 13
  = help: an f-string writes the local's value: 'println(f"x = {x}")'
ok: built w
$ ./w
x = {x}
```

## Kinds and codes

The word in brackets tells you which part of the compiler is
complaining. The broad *kinds* are:

```console
$ volec explain --list | grep -v '\.'
tokenizer error
parser error
module error
type error
C import
unsafe
effect
profile
format
```

| kind | what it's about |
|---|---|
| `tokenizer error` | the characters themselves: an unclosed string, a stray symbol |
| `parser error` | the shape of the code: a missing `;` or `}`, a Rust spelling vole doesn't have |
| `module error` | the module tree: a `mod` with no file, a wildcard import (chapter 11) |
| `type error` | names and types: most errors you'll meet |
| `C import` | an `import "header.h"` that can't be read (chapter 15) |
| `unsafe` | an unsafe operation outside `unsafe` (chapter 15) |
| `effect` | a broken effect promise (chapter 12) |
| `profile`, `format` | warnings: a stale profile (chapter 16), a string that looks like an f-string |

Newer checks have *codes* with a family prefix and a dot. The code is
stable: its message may be reworded, but the code stays, so it's what
to search for. The families are:

| family | what it's about | chapter |
|---|---|---|
| `own.*` | values, moves and views: a value used after it moved, a view used after its data changed | [4](04-value-semantics.md) |
| `conv.*` | parameter conventions: a missing `&`, an extra one, Rust's spellings | [4](04-value-semantics.md) |
| `contract.*` | `requires` and `ensures` | [13](13-contracts-testing.md) |
| `test.*` | tests and properties | [13](13-contracts-testing.md) |
| `sync.*` | what may cross to another thread | [14](14-threads.md) |
| `import.*` | `use` lines | [11](11-modules-and-programs.md) |
| `distinct.*` | distinct types | `volec guide types` |
| `arch.*` | CPU features and intrinsics | `volec guide arch` |

The compiler lists its codes itself. For example, the `own` family:

```console
$ volec explain --list | grep '^own\.'
own.moved
own.move_out
own.partial
own.conflict
own.escape
own.static
own.views
own.drop_view
own.readonly
```

and the `sync` family:

```console
$ volec explain --list | grep '^sync\.'
sync.borrow_escapes
sync.not_send
sync.not_sync
sync.global
sync.scope_write
sync.scope_shared_write
sync.scope_local
sync.scope_spawn
sync.spawn_closure
```

`volec explain --list` without the `grep` prints every code, the tools'
too, a couple of hundred of them.

## try: lines

A `try:` line is meant to be used as it is, with no editing:

- code, such as `try: [1.0, 9.5][..]` or a missing `match` arm, to put
  where the error points;
- a `use` line to add at the top of the file;
- a `volec` command to run, such as `volec fix --suggested main.vl`.

When a command's `try:` has a word in capitals, like `VALUE`, that part
is yours to fill in.

Many errors have an exact fix the compiler knows: a misspelled name with
one close match, a missing `use` or `pub`, a missing `&`, a Rust
spelling. Their `try:` line is `volec fix --suggested FILE`, which makes
every such fix in the program at once, checks the result, and prints the
errors that are left. Here's one:

```vole
fn main(gpa: Gpa) {
    var s = String::new_in(gpa);
    s.push_string("hi");
    println(f"{s}");
}
```

```err
error[type error]: no method 'push_string' on type 'String'
 --> main.vl: line 3, column 5
  = help: did you mean 'push_str'?
  = try: volec query items String main.vl
  = try: volec fix --suggested main.vl
```

The first `try:` lists every method a `String` has; the second makes the
fix. `--dry-run` shows the change without making it:

```console
$ volec fix --suggested --dry-run main.vl
--- a/main.vl
+++ b/main.vl
@@ -3 +3 @@
-    s.push_string("hi");
+    s.push_str("hi");
```

`volec undo` takes back the last fix or edit a tool made.

## volec explain

`volec explain` takes a kind or a code and prints what it means, how to
fix it, and an example:

```console
$ volec explain effect
effect: error (compiler)
(0.16) A function does more than its effect declaration allows (`#[pure]`, `#[no_alloc]`, `#[no_io]`, `#[no_panic]`, `#[effects(...)]`, or its trait method's), a closure more than its parameter's `effects(...)` bound, or a declaration names an unknown effect or a value instead of an allocator type.
fix: Follow the chain (`volec query effects NAME --why EFFECT`) to the source and remove it, or widen the declaration; effects are alloc(A), io, global, panic, diverge, unsafe.
example:
    sum.vl:3:1: error[effect] 'total' is #[no_alloc], but it allocates from Gpa: 'v.push(x)' at sum.vl:7:9 grows a Vec<i64>
```

The text is written in the compiler's terse reference style, like
`volec guide`. A number in parentheses, `(0.16)`, is the release that
added the check. Some entries are older than the language they describe
and still use Rust's words (`&mut`, `move`); where they disagree with the
error message, trust the message, and this book.

`volec guide --find WORDS` finds the paragraphs of the guide about a
subject, which is often the next step after `explain`.

## Run-time failures

When a check fails while a program runs, the program stops with one
line on stderr and exit status 101. Here's a loop that goes one step too
far:

```vole
fn main() {
    let v = [1, 2];
    for i in 0..3 {
        println(f"{v[i]}");
    }
}
```

```out exit=101
1
2
main.vl:4:20: index out of bounds: index 2, length 2
```

The line is `FILE:LINE:COLUMN: message`, and the position is the
expression that failed. The output before it is still printed. The
messages you'll meet most are:

| message | what failed |
|---|---|
| `index out of bounds: index I, length N` | `v[i]` with `i` outside the slice, array or Vec |
| `slice range out of bounds: A..B, length N` | `v[a..b]` outside it, or `a` past `b` |
| `called unwrap on None`, `called unwrap on Err` | `unwrap` on an empty `Option` or a failed `Result` |
| `invalid value V for enum E` | `n as E` with a number that is no variant of `E` |
| `requires failed: ...`, `ensures failed: ...` | a contract (chapter 13), or its own `else` message |
| `assertion failed: 'COND': x = 3` | `assert` or `assert_eq`, with the values of the variables in it |

A contract or an assertion prints the values of the variables in its
condition, which is often all you need to see what went wrong.
`panic("message")` stops the program with its message and status 101
too.

### Where it was called from

The failing line is sometimes not where the mistake is: the index came
from a caller. Build with `--trace`, and a failure also prints the
chain of calls that led to it, innermost first:

```vole trace.vl
fn pick(v: [i64], i: i64) -> i64 {
    v[i]
}

fn main() {
    let v = [10, 20, 30];
    println(f"{pick(v, 3)}");
}
```

```console
$ volec trace.vl -o trace --trace
ok: built trace
$ ./trace
trace.vl:2:5: index out of bounds: index 3, length 3
trace, innermost call first:
  trace.vl:2  pick
  trace.vl:7  main
$ echo $?
101
```

`volec test` always builds with `--trace`. `volec guide debug` has
the other tools for finding a bug: printing values at a line without
editing the program, and shrinking a failing input.

### Errors from main

A `main` that returns a `Result` (chapter 6) and returns an `Err`
prints `Error: ` and the error's debug form, and exits with status 1,
not 101: the program didn't crash, it reported a failure. Chapter 11
shows it with a missing file.

## Tool problems

The tools, `volec query`, `edit`, `refactor`, `fix` and the others,
report their own problems in one more shape: a severity, a stable code,
and a message, then `try:` lines, each a complete command:

```console
$ volec query show nosuch trace.vl
error query.no-match: no definition 'nosuch'
try: volec query items trace.vl
$ echo $?
1
$ volec query show nosuch
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query show nosuch path/to/main.vl
$ echo $?
2
```

The first command asked for something that isn't in `trace.vl`. The
second didn't say which program to look in, and there's no `main.vl`
here for the tools to find by themselves, so the command itself was
incomplete. The severity is `error`, `warning` or `note`. The exit
status says how it went:

| status | meaning |
|---|---|
| 0 | done |
| 1 | refused or failed; nothing was written |
| 2 | the command itself was wrong (a usage error) |

A tool that changes code never leaves it half changed: when an edit
would add an error, it writes nothing and prints the error instead.
`volec explain` knows the tools' codes too (`volec explain
query.no-match`), and chapter 17 is about the tools themselves.

## Where to look next

- `volec explain CODE`: what an error means and how to fix it.
- `volec guide --find WORDS`: the guide's paragraphs about something.
- `volec guide errors`: the errors newcomers meet most, with their
  fixes.
- `volec query show FILE:LINE`: the whole item an error points into.
