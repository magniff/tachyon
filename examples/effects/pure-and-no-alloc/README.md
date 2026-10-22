# Promises a function keeps: `#[pure]`, `#[no_alloc]`, `#[no_panic]`

A score, a histogram and the peak of a series of sensor samples. Three
of the functions promise something about what they do, and the compiler
holds them to it:

| function | promise | meaning |
|---|---|---|
| `score` | `#[pure]` | no allocation, no I/O, no statics (it may panic, loop, and write through its pointer parameters) |
| `histogram` | `#[no_alloc]` | allocates nothing: it fills memory its caller gives it |
| `peak` | `#[no_panic]` | cannot stop the program: no index that may be out of range, no `unwrap` |

A promise covers everything the function calls, however deep. The
compiler infers what every function may do (its *effects*: `alloc`,
`io`, `global`, `panic`, `diverge`, `unsafe`), from its body and its
callees', and checks each declaration against that. Break a promise
three calls down, and the error is at the promise, with the line that
broke it.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/effects-pure-and-no-alloc.test` runs the program.

## Run it

```console
$ volec main.vl -o samples && ./samples
score: 1936
histogram: 8 0 0 1 1
peak: Some(950), of none: None
outliers: [300, 950]
ok: built samples
```

## What each function may do

```console
$ volec query effects crate
crate::clamp	none
crate::scaled	none
crate::smoothed	panic
crate::score	panic
crate::bucket	none
crate::histogram	panic
crate::peak	none
crate::outliers	alloc(Gpa) panic
crate::main	alloc(Gpa) io global panic
```

`clamp`, `scaled` and `bucket` do nothing but compute: `none`.
`smoothed` indexes (`s[i + 1]` may be out of range: `panic`), and so
does `score`, which calls it; `#[pure]` allows that. `peak` is `none`:
it reads its slice with `get(0)` (an `Option`) and `for x in s`, neither
of which can fail. `outliers` takes no allocator, yet it is `alloc(Gpa)`:
it pushes onto a `Vec` it was given, and `push` grows the Vec with the
allocator the Vec holds. `main` prints: `io`, and `global` (std's print
buffer is a static).

## Breaking `#[pure]` three calls down

`score` calls `smoothed`, which calls `scaled`, which calls `clamp`. A
debugging print in `clamp`:

```console
$ volec edit patch clamp --old '    if x < lo {' --new '    println(f"clamp {x}");
>     if x < lo {'
main.vl:36:1: error[effect] 'score' is #[pure], but it does io: 'smoothed(s, i, gain)' at main.vl:39:14 calls 'smoothed' | help: return the data and let the caller print it, or remove #[pure] | try: volec query effects score --why io  [in crate::score]
error edit.breaks: 1 new error (1 in crate::score, which the edit does not change); nothing written
note edit.together: change crate::score in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: volec query show crate::score
try: volec edit patch clamp --old '    if x < lo {' --new '    println(f"clamp {x}");
    if x < lo {' --no-check
[exit 1]
```

The edit is refused, and nothing is written: the edit tools check the
program with the change first. The error is the compiler's, at `score`
(line 36 with the edit's new line in it), and names the first step of
the chain from it to the print; `query effects --why` gives the whole
chain. To see it, write the change anyway (`--no-check`, as the `try:`
line says):

```console
$ volec edit patch clamp --old '    if x < lo {' --new '    println(f"clamp {x}");
>     if x < lo {' --no-check
main.vl:36:1: error[effect] 'score' is #[pure], but it does io: 'smoothed(s, i, gain)' at main.vl:39:14 calls 'smoothed' | help: return the data and let the caller print it, or remove #[pure] | try: volec query effects score --why io  [in crate::score]
patched crate::clamp	main.vl	+1 -0 lines
warning edit.breaks: 1 new error (1 in crate::score, which the edit does not change); written anyway (--no-check)
try: volec check
$ volec query effects score --why io | head -5
crate::score	io global panic
  'smoothed(s, i, gain)' at main.vl:39:14 calls 'smoothed'
  'scaled(s[i], gain)' at main.vl:29:6 calls 'scaled'
  'clamp(x * gain / 10, 0, 1000)' at main.vl:23:5 calls 'clamp'
  'println(f"clamp {x}")' at main.vl:12:5 calls 'std::fmt::println'
warning query.program-errors: 1 error in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
$ volec undo
undid patched crate::clamp	main.vl	+1 -0 lines
```

(The chain goes on inside std, down to C's `write`; `head` cuts it at
the program's last step.) `undo` takes the last edit back. The help says what to do instead:
return the data and print in the caller, which is not pure; or drop the
promise.

## `#[no_alloc]` and the allocator a container holds

`histogram` keeps its promise: it writes into `bins`, which its caller
allocated (here, an array on the stack). `outliers` would not:

```console
$ volec edit patch outliers --old 'fn outliers' --new '#[no_alloc]
> fn outliers'
main.vl:89:1: error[effect] 'outliers' is #[no_alloc], but it allocates from Gpa: 'out.push(x)' at main.vl:92:13 grows a Vec<i64> | help: allocate in the caller and pass the memory in, or remove #[no_alloc] | try: volec query effects outliers --why alloc(Gpa)  [edited: crate::outliers]
error edit.breaks: 1 new error; nothing written
try: volec edit patch outliers --old 'fn outliers' --new '#[no_alloc]
fn outliers' --no-check
[exit 1]
```

The chain names the step that allocates, `out.push(x)`, and the type
it grows. The usual fix is the one `histogram` takes: the caller makes
room (`Vec::with_capacity_in`, or a slice of an array) and the function
only writes.

## `#[no_panic]`

`peak` reads its first element with `s.get(0)?`, an `Option`. With an
index instead:

```console
$ volec edit patch peak --old 'var best = s.get(0)?;' --new 'var best = s[0];'
main.vl:74:1: error[effect] 'peak' is #[no_panic], but it may panic: 's[0]' at main.vl:75:16 is a checked index | help: iterate ('for x in s'), or 's.get(i)' (an Option), or remove #[no_panic] | try: volec query effects peak --why panic  [edited: crate::peak]
error edit.breaks: 1 new error; nothing written
try: volec edit patch peak --old 'var best = s.get(0)?;' --new 'var best = s[0];' --no-check
[exit 1]
```

`s[0]` may be out of range (for an empty slice it is), so it may stop
the program. A counted `for i in 0..s.len` loop's `s[i]` is known to be
in range and is no `panic`; so are a constant index into an array of
that length, and `for x in s`.

## Why promise

- **For the reader.** A signature says what a function takes and
  returns; a promise says what it does not do, and stays true: a change
  anywhere below that breaks it is an error at the promise.
- **For the optimizer.** A call of a pure function with the same
  arguments gives the same result, so it can be computed once, or moved
  out of a loop. The optimizer uses the inferred effects whether or not
  a promise is written.
- **For an agent.** `query effects` answers "can this allocate, print,
  touch a static, fail?" for any function, without reading its callees;
  `--why` points at the line. See
  [effects-for-agents](../effects-for-agents/).

## Read more

- `volec guide effects`: the effects, `query effects`, the
  declarations (`#[no_io]` and `#[effects(...)]` too).
- [effect-bounds](../effect-bounds/): promises asked of closures.
- [trait-purity](../trait-purity/): std's `Hash`, `Eq` and `Ord` are
  `#[pure]`, and bind every impl.
