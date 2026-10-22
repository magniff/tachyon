# What `--check-alloc` still catches

In vole 0.16 a `Vec` was a handle that could be copied, freed through
one copy and used through another; a view of it could outlive a `push`
that moved its memory. 0.17's value semantics made those bugs compile
errors (the first section). Two kinds of memory bug are left, and
`volec --check-alloc` finds both at run time:

- **leaks**, which are safe: a block nobody frees (here an `Arena`, which
  is not dropped: its memory comes back only by `free_all`);
- bugs in **`unsafe` code**, whose raw pointers the compiler does not
  check: a pointer kept after its block moved, a block freed twice.

`main.vl` has one bug per argument, `leak`, `dangling` and `twice`; with
no argument it runs the correct version of each. Every command below is
run by `tests/walkthrough/run.sh` in a copy of this directory, and its
output is checked against this file;
`tests/examples/allocators-check-alloc*.test` run the program, correct
and with each bug.

## The bugs that are compile errors now

The bugs of the 0.16 version of this example, in safe code: a handle
copied into a struct and freed through the original, two frees through
two handles, a view kept across a `push`, a view returned from an
arena's scope.

```console
$ cat > old.vl <<'EOF'
> struct Shelf { name: [u8], counts: Vec<i64> }
>
> fn copied_handle(gpa: Gpa) {
>     var counts: Vec<i64> = Vec::new_in(gpa);
>     counts.push(3);
>     let shelf = Shelf { name: "fruit", counts: counts };
>     counts.free();
>     println(shelf.counts[0]);
> }
>
> fn freed_twice(gpa: Gpa) {
>     var counts: Vec<i64> = Vec::new_in(gpa);
>     var shelf = Shelf { name: "tools", counts: counts };
>     counts.free();
>     shelf.counts.free();
> }
>
> fn slice_after_push(gpa: Gpa) {
>     var v: Vec<i64> = Vec::new_in(gpa);
>     v.push(0);
>     let first = v.as_slice();
>     v.push(40);
>     println(first[0]);
> }
>
> fn view_out_of_scope(gpa: Gpa) {
>     let s = arena_scope(gpa, |a| {
>         var v: Vec<i64, ScopedArena> = Vec::new_in(a);
>         v.push(7);
>         v.as_slice()
>     });
>     println(s[0]);
> }
>
> fn main(gpa: Gpa) -> i32 {
>     copied_handle(gpa);
>     freed_twice(gpa);
>     slice_after_push(gpa);
>     view_out_of_scope(gpa);
>     0
> }
> EOF
$ volec check old.vl
old.vl:7:5: error[own.moved] 'counts' is used here after it moved at 6:48 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee read it: a let parameter ('x: T'), not 'sink' | try: volec edit patch old.vl:6 --old 'let shelf = Shelf { name: "fruit", counts: counts };' --new 'let shelf = Shelf { name: "fruit", counts: counts.clone() };'
old.vl:14:5: error[own.moved] 'counts' is used here after it moved at 13:48 | help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee read it: a let parameter ('x: T'), not 'sink' | try: volec edit patch old.vl:13 --old 'var shelf = Shelf { name: "tools", counts: counts };' --new 'var shelf = Shelf { name: "tools", counts: counts.clone() };'
old.vl:22:5: error[own.conflict] 'v.push(40)' may change 'v' while 'first' (old.vl:21:9) views it; 'first' is used at old.vl:23:13 | help: use the view before the change, keep an index instead of a view, or keep a copy | try: volec edit patch slice_after_push --old 'v.as_slice()' --new 'v.clone()' | try: volec query own old.vl:23:13
old.vl:30:9: error[own.escape] 'closure(ScopedArena) -> [i64] at old.vl:27:30' returns a view of 'v', which is dropped when 'closure(ScopedArena) -> [i64] at old.vl:27:30' returns | help: return the owner itself; a caller that wants a view takes '.as_slice()' of it | try: volec edit patch closure(ScopedArena) -> [i64] at old.vl:27:30 --old '-> [i64]' --new '-> Vec<i64, ScopedArena>' --old 'v.as_slice()' --new 'v'
[exit 1]
```

- **Values move.** `Shelf { name: "fruit", counts: counts }` moves
  `counts` into the struct; using `counts` afterwards, to free it or
  anything else, is `own.moved`. A value has one owner, dropped once at
  the end of its scope (no `free` to write), and `.clone()` is the
  explicit way to a second, independent copy.
- **Views cannot outlive their owner, or be invalidated under it.** A
  slice of the Vec is live until its last use, and a `push` while it is
  live is `own.conflict`; a view returned from the arena's scope, of a
  Vec dropped there, is `own.escape`.

`volec guide memory` and `volec guide views` have the rules.

## The program, correct

```console
$ volec main.vl -o shop && ./shop
a report nobody frees
first 1
shelf: 7
ok: built shop
```

## The bugs, built as usual

Built without the flag, each bug does whatever the freed memory happens
to hold. On macOS, one run printed this (another run, or another
machine, prints something else, or crashes):

```text
$ ./shop leak
a report nobody frees
$ ./shop dangling
first 53978760647200
$ ./shop twice
shelf: 7
[exit 134]
```

Nothing at all, a wrong number, and a crash in `free` with no message.

## The bugs, built with `--check-alloc`

```console
$ volec --check-alloc main.vl -o shop-checked
ok: built shop-checked
```

**A leak.** An `Arena` hands out memory from chunks it takes from its
`Gpa`, and gives them back only when told: it is not dropped, and
`free_all` is unsafe (a view into the arena could still be used after
it). The `Buf` on it is dropped at the end of its block, which on an
arena frees nothing; the arena's chunk is never freed:

```tach
let notes = Arena::new_in(gpa);
{
    var b: Buf<Arena> = Buf::new_in(notes);
    b.push_str("a report nobody frees");
    println(b.as_slice());
}
if fixed {
    unsafe { notes.free_all() };
}
```

A leak is not undefined behaviour, and the program's exit status is
unchanged; the blocks still allocated at exit are listed, with where
they were allocated:

```console
$ ./shop-checked leak
a report nobody frees
check-alloc: 1 block of Gpa not freed (8336 bytes):
  block #9 (8336 bytes), allocated at main.vl:17:17
```

**A raw pointer kept across a push.** A view of the Vec kept across the
`push` would be `own.conflict`, as above; the raw pointer `.ptr` of the
view is not checked. The `push` grows the Vec, which moves its memory
(`realloc`), and the pointer points at the old place:

```tach
let first = v.as_slice().ptr;
v.push(41);
println(f"first {unsafe { first[0] }}");
```

The checking allocator gives every block pages of its own and never
reuses an address; freeing a block takes its pages' access away, so the
next read faults, and the fault handler finds the block. Under
`--check-alloc` every resize moves the block, so the bug shows every
time, not only when the allocator happened to move it:

```console
$ ./shop-checked dangling
use after free: block #9 (32 bytes), allocated at main.vl:34:9, freed at main.vl:37:5
[exit 101]
```

Block #9 is the Vec's buffer, allocated by its first `push` (line 34)
and freed by the `push` that moved it (line 37); the blocks before it
are the command line's, which `std::cli` parsed and dropped.

**Freed twice.** `Pair` manages its memory by hand, through a raw
pointer, and has no `Drop`: it is a plain type, so `let shelf =
counts;` copies the pointer, not the memory. Each copy is freed:

```tach
let counts = pair_new(gpa, 3, 4);
let shelf = counts;
println(f"shelf: {unsafe { shelf.p[0] + shelf.p[1] }}");
unsafe { gpa.free(counts.p as *u8, 16, 8) };
unsafe { gpa.free(shelf.p as *u8, 16, 8) };
```

```console
$ ./shop-checked twice
shelf: 7
double free: block #9 (16 bytes), allocated at main.vl:52:13, freed at main.vl:68:14, freed again at main.vl:70:18
[exit 101]
```

The fix that keeps it from coming back is the one `volec guide unsafe`
gives: a type whose safe methods manage memory through raw pointers
implements `Drop`. That makes it owned: `let shelf = counts;` moves it,
and its drop frees it once.

**None of them.** A test can ask instead: `gpa.live_blocks()` is the
number of blocks not yet freed, and `gpa.check_leaks()` lists them and
returns false when there are some (both are known only under
`--check-alloc`: `live_blocks()` is -1 otherwise). The correct version
prints it:

```console
$ ./shop-checked | tail -1
blocks still allocated: 0
```

What the flag costs: a page or more per block (16 KB on Apple silicon),
a system call per allocation and per free, and on Linux a memory map per
live block (`vm.max_map_count`: the program stops with the command that
raises it). It is for tests and debugging, at any `-O`, not for
production builds. With `--check-unsafe` as well, raw-pointer accesses
are checked against the blocks too, out of bounds included (`volec guide
unsafe`, "Tools").

## Read more

- `volec guide allocators`, section "--check-alloc".
- `volec guide memory` and `volec guide views`: moves, drops, views and
  their lifetime.
- `volec guide unsafe`: raw pointers, and what unsafe code must keep.
- [gpa-from-main](../gpa-from-main/) and
  [scoped-arena](../scoped-arena/): `--check-alloc` finding nothing.
