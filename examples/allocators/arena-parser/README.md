# A parser that builds its tree in an arena

A tokenizer and a recursive-descent parser for arithmetic written as
S-expressions, `(+ 1 (* 2 3) (max 4 5))`, building a syntax tree whose
every list is a `Vec` of its children; then the tree's value. The same
generic code runs on the general-purpose allocator (`Gpa`: a `malloc`
per list, and a walk over the tree to free each one) and on an arena (a
pointer bump per list, and the whole tree freed at once). The two are
compared on 1.7 MB of generated input.

Trees are the textbook case for an arena: many small allocations made
together, used together, and dropped together. What the example
measures is where that pays and where it does not.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-arena-parser.test` runs the program.

## Run it

```console
$ tachyonc main.tach -o parser && ./parser 2>/dev/null
(+ 1 (* 2 3) (max 4 5) (- 10 1 2)) = 19
(+ 1 (* 2 3): a '(' is not closed
(+ 1 2)): unexpected ')' at byte 7
(1 2): no operator at byte 1
input: 1771952 bytes, 134180 lists (one allocation each)
value: -9194208206490895369, the same three ways: true
the tree in the arena: 33773 KB
```

The times go to stderr (they differ from run to run). On an Apple
M-series laptop, with other work on the machine, at the default `-O2`:

```text
                   parse     eval     free (best of 5, microseconds)
Gpa                  7549     2475     3038
arena_scope          8262     2692        4
Arena::scope         8176     2721        0
```

## One parser, any allocator

The tree's type names its allocator:

```tach
struct Node<A: Allocator> { op: u8, num: i64, kids: Vec<Node<A>, A> }
```

and every function that builds one is generic over it, taking the
allocator as a value (`a: A`) and passing it to each `Vec` it makes:

```tach
fn parse<A: Allocator>(src: [u8], a: A) -> Result<(Node<A>, i64), ParseError>
fn parse_expr<A: Allocator>(p: &mut Parser<A>, t: Tok) -> Result<Node<A>, ParseError>
```

The caller chooses. On `Gpa`, `parse(text, gpa)` returns a
`Node<Gpa>`, which is dropped list by list when the caller is done with
it (the drop glue of `Node` and `Vec`: a walk over the whole tree). In
an arena:

```tach
values[1] = arena_scope(gpa, |a| {
    let (tree, _) = parse(text, a).unwrap();
    let v = eval(&tree);
    std::forget(tree);
    v
});
```

`arena_scope(gpa, f)` makes an arena (its memory from `gpa`), calls `f`
with it (an `a: ScopedArena`), and frees all of it when `f` returns.
Dropping the tree would walk it to free each list, which on an arena
frees nothing: `std::forget(tree)` skips the walk, and the scope's end
frees the memory (a forgotten value is a leak only on an allocator
that frees block by block). The tree cannot
outlive the scope either: returning it, or anything holding a
`ScopedArena`, is a compile error (see [scoped-arena](../scoped-arena/));
here only the `i64` value leaves.

The third way keeps one `Arena` for every round: `Arena::new_in(gpa)`
once, and `arena.scope(|a| ...)` per round, which rewinds the arena at
its end but keeps its memory for the next round (instead of giving it
back to `Gpa` and asking again). `unsafe { arena.free_all() }` gives it
back at the end: unsafe because nothing stops a view into the arena
from being used after it (0.17.1's arena references close that; a scope
has no such hole).

## Arena-friendly allocation

An arena allocates by moving a pointer forward, and frees nothing until
the end: it can grow or shrink only its *last* block in place. A `Vec`
that grows by doubling while other blocks are made after it leaves each
of its old copies behind. The first version of this parser pushed each
child straight onto its parent's `Vec`, and in the arena most of the
memory it used held dead copies.

So the children of the lists being parsed wait on one shared stack, and
when a list's `)` comes, its children are moved into a `Vec` of exactly
their number:

```tach
Tok::Close => {
    // moved off the stack, in order
    let n = p.stack.len() - base;
    let mut kids: Vec<Node<A>, A> = Vec::with_capacity_in(n, p.a);
    for _ in 0..n {
        kids.push(p.stack.remove(base));
    }
```

One allocation of the right size per list, on either allocator: the
comparison is the allocator's cost, not a different algorithm.

## What the numbers say

- **Freeing**: 3 ms for 134,180 `free` calls and the walk that finds
  them, against nothing measurable: the arena's chunks go back in one
  call each (and the forgotten tree is not walked). This is the arena's
  real win, and it grows with the tree.
- **Parsing**: no faster. Allocating is a small part of it (without
  any allocation the parse takes 6.0 ms; macOS's `malloc` for small
  blocks is about 12 ns), and a bump saves little of that small part.
- **Bigger nodes**: a container carries its allocator. A `Gpa` is zero
  bytes, so `Vec<Node<Gpa>>` is 24 bytes and a node 40; a `ScopedArena`
  is a 16-byte handle, so the same node is 56 bytes, the tree is 40%
  larger, and copying the nodes around costs more (most of the
  difference in the parse column). `Arena` is an 8-byte handle.
- **Memory held**: the arena's scope used 33 MB, about what the nodes
  take (plus the stack's growth); `query effects` below shows that the
  arena instances allocate nothing from `Gpa` directly.

## What the effects say

```console
$ tachyonc query effects parse eval
parse<Gpa>	alloc(Gpa) panic diverge
parse<ScopedArena>	alloc(ScopedArena) panic diverge
eval<Gpa>	diverge
eval<ScopedArena>	diverge
```

Each generic function has one line per instance: `parse<ScopedArena>`
allocates only from the arena, `parse<Gpa>` only from `Gpa`. `eval` was
declared `#[no_alloc]`, and the compiler checked it for both trees.
(`diverge` is the recursion: a parser of nested lists recurses.)

## The bug the arena would have hidden

On `Gpa`, a parse error halfway (`(+ 1 (* 2 3)`, an unclosed list)
returns with lists already built: the finished children waiting on the
stack. A 0.16 version leaked them, and `--check-alloc` listed the two
blocks at exit; it had to free what waited on the stack before
returning the error. Since 0.17 the stack and what it holds are dropped
on every exit of `parse`, the early return of `?` included, so there is
nothing to remember; in an arena the scope's end frees them with the
rest. (`--check-alloc` gives each block pages
of its own: the whole program takes about 7 seconds under it, most of
them in the kernel.)

## Read more

- `tachyonc guide allocators`, section "Arenas".
- [scoped-arena](../scoped-arena/): per-request scratch memory, and the
  compile errors that keep arena values in their scope.
- `examples/algorithms` for the timing conventions (stderr, best of
  several rounds).
