# Memory bugs that compile, caught by `--check-alloc`

Five memory bugs, each in a function of its own, chosen by the
program's argument: `copy`, `push`, `scope`, `twice`, `leak`. With no
argument the program runs the correct version of each. All five
compiled in vole 0.16; the first four are undefined behaviour, the
one gap 0.16 left open. 0.17 closes it: they are compile errors now
(the last section). The program is 0.16 code, so the sessions build it
with `--values=off`, 0.16's semantics (no moves, no drops, no view
checks), to show what `volec --check-alloc` does with such bugs: it
builds the program with a checking allocator that stops at each of them
with the block, where it was allocated and where it was freed. It still
matters in 0.17 for leaks, for unsafe code and for code built with
`--values=off`.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-check-alloc*.test` run the program, correct
and with each bug.

## The correct version

```console
$ volec --values=off main.vl -o shop && ./shop
fruit: 7
fruit: 7
first 0
7
tools: 1
a report nobody frees
ok: built shop
```

## The bugs, built as usual

Built without the flag, each bug does whatever the freed memory happens
to hold. On macOS, one run printed this (another run, or another
machine, prints something else, or crashes):

```text
$ ./shop copy
fruit: 7
fruit: 4819786546360956236
$ ./shop push
first 3
$ ./shop scope
7
$ ./shop twice
tools: 1
[exit 133]
$ ./shop leak
a report nobody frees
```

A wrong number, a right-looking number, a crash in `free` with no
message, and nothing at all.

## The bugs, built with `--check-alloc`

```console
$ volec --values=off --check-alloc main.vl -o shop-checked
ok: built shop-checked
```

**A handle copied, then freed through one copy.** A `Vec` is a handle
(a pointer, a length, a capacity, its allocator): assigning it copies
the handle, and both copies share the memory. `Shelf { counts: counts }`
puts a copy in the struct; `counts.free()` frees the memory under both.

```tach
let shelf = Shelf { name: "fruit", counts: counts };
println(f"{shelf.name}: {stock(&shelf)}");
counts.free();
println(f"{shelf.name}: {stock(&shelf)}");   // reads freed memory
```

```console
$ ./shop-checked copy
fruit: 7
use after free: block #1 (32 bytes), allocated at main.vl:20:5, freed at main.vl:29:9
[exit 101]
```

The checking allocator gives every block pages of its own and never
reuses an address; freeing a block takes its pages' access away, so the
next read faults, and the fault handler finds the block: #1, 32 bytes,
allocated by the `push` at line 20 (the Vec's first push makes its
buffer) and freed at line 29.

**A view kept across a push.** `as_slice()` is a view of the Vec's
memory; a `push` that grows the Vec moves it (`realloc`), and the view
points at the old place. Under `--check-alloc` every resize moves the
block, so the bug shows every time, not only when the allocator
happened to move it:

```console
$ ./shop-checked push
use after free: block #1 (32 bytes), allocated at main.vl:39:9, freed at main.vl:42:5
[exit 101]
```

**A view out of an arena's scope.** The scope's `Vec` cannot be its
value (a compile error: see [scoped-arena](../scoped-arena/)), but a
slice of it can, and the scope's end freed what it points at:

```console
$ ./shop-checked scope
use after release: block #2 (32 bytes) of an arena, allocated at main.vl:65:13, released at main.vl:63:17 (the arena's reset or scope end)
[exit 101]
```

**Freed twice**, through two copies of a handle:

```console
$ ./shop-checked twice
tools: 1
double free: block #1 (32 bytes), allocated at main.vl:75:5, freed at main.vl:78:5, freed again at main.vl:80:9
[exit 101]
```

**A leak** is not undefined behaviour, and the program's exit status is
unchanged; the blocks still allocated at exit are listed, with where
they were allocated:

```console
$ ./shop-checked leak
a report nobody frees
check-alloc: 1 block of Gpa not freed (21 bytes):
  block #1 (21 bytes), allocated at main.vl:87:5
```

A test can ask instead: `gpa.live_blocks()` is the number of blocks not
yet freed, and `gpa.check_leaks()` lists them and returns false when
there are some (both are known only under `--check-alloc`:
`live_blocks()` is -1 otherwise). The correct version prints it:

```console
$ ./shop-checked | tail -1
blocks still allocated: 0
```

What the flag costs: a page or more per block (16 KB on Apple silicon),
a system call per allocation and per free, and on Linux a memory map per
live block (`vm.max_map_count`: the program stops with the command that
raises it). It is for tests and debugging, at any `-O`, not for
production builds.

## How 0.17 makes these compile errors

0.17 brings mutable value semantics, and they are on by default: the
program as it is does not compile: the first four bugs are errors.

```console
$ volec check main.vl
main.vl:27:9: error[own.moved] 'counts' is used here after it moved at 22:48 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee borrow it: a let parameter ('x: T'), not 'sink' | try: volec edit patch main.vl:22 --old 'let shelf = Shelf { name: "fruit", counts: counts };' --new 'let shelf = Shelf { name: "fruit", counts: counts.clone() };'
main.vl:42:5: error[own.conflict] 'v.push(40)' may change 'v' while 'first' (main.vl:41:9) views it; 'first' is used at main.vl:47:26 | help: use the view before the change, keep an index instead of a view, or keep a copy | try: volec edit patch slice_after_push --old 'v.as_slice()' --new 'v.clone()' | try: volec query own main.vl:47:26
main.vl:66:13: error[own.escape] 'closure(ScopedArena) -> [i64] at main.vl:63:34' returns a view of 'v', which is dropped when 'closure(ScopedArena) -> [i64] at main.vl:63:34' returns | help: return the owner itself; a caller that wants a view takes '.as_slice()' of it | try: volec edit patch closure(ScopedArena) -> [i64] at main.vl:63:34 --old '-> [i64]' --new '-> Vec<i64, ScopedArena>' --old 'v.as_slice()' --new 'v'
main.vl:78:5: error[own.moved] 'counts' is used here after it moved at 76:48 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee borrow it: a let parameter ('x: T'), not 'sink' | try: volec edit patch main.vl:76 --old 'var shelf = Shelf { name: "tools", counts: counts };' --new 'var shelf = Shelf { name: "tools", counts: counts.clone() };'
[exit 1]
```

- **Values move.** `Shelf { name: "fruit", counts: counts }` moves
  `counts` into the struct; using `counts` afterwards, to free it or
  anything else, is `own.moved`. One owner, so no `copy` bug and no
  `twice` bug: the owner is dropped once, at the end of its scope (a
  `Drop` impl replaces `free` and most `defer`s), and `.clone()` is the
  explicit way to get a second, independent copy.
- **Views cannot outlive or be invalidated under their owner.** A slice
  of the Vec is live until its last use, and a `push` while it is live
  is `own.conflict`; a view returned from the arena's scope, of a Vec
  dropped there, is `own.escape`. No `push` bug and no `scope` bug.
- **Leaks** stay possible (they are safe), and drops make them rare;
  `--check-alloc` keeps listing them.

`volec fix --values` migrates the common patterns (`defer x.free()`
removed where the value drops, parameters to references), with exact
diagnostics for the rest (`volec guide memory`).

## Read more

- `volec guide allocators`, section "--check-alloc".
- `volec guide memory`: moves, drops, views and their lifetime.
- [gpa-from-main](../gpa-from-main/) and
  [arena-parser](../arena-parser/): leaks found by `--check-alloc`.
