# Allocators (0.16)

Allocation is explicit: nothing allocates without being given an
allocator. A program's general-purpose allocator is the `gpa: Gpa` its
`main` takes; a function that allocates takes one as a parameter, or
works on a container it was given (a `Vec` holds its allocator: `push`,
`clone` and its drop use it). There is no global allocator to reach for,
so a function's signature says whether it allocates.

## Gpa, from main

```tach
fn squares(n: i64, gpa: Gpa) -> Vec<i64> {   // allocates: takes the allocator
    var v: Vec<i64> = Vec::with_capacity_in(n, gpa);
    for i in 0..n { v.push(i * i); }
    v
}

fn total(v: Vec<i64>) -> i64 {               // grows nothing: no allocator
    v.iter().sum()
}

fn main(gpa: Gpa) -> i32 {                    // or main(argc, argv, gpa)
    var v = squares(4, gpa);
    v.push(100);                              // the Vec's own allocator
    var b = Buf::new_in(gpa);
    b.push_int(total(v));
    let words: Vec<i64> = (1..4).map(|x| x * 10).collect_in(gpa);
    println(f"{b.as_slice()} {words:?}");
    0
}                                             // words, b, v dropped: freed
```
```out
114 [10, 20, 30]
```

`Gpa` is a zero-sized value, copied freely: an allocator is passed as a
let parameter (`gpa: Gpa`, no convention to write), and every container
made from it shares it. Only `main` gets one (std's
types are `#[sealed]`: no `Gpa {}` outside std). Each 0.15 form that
allocated has an `_in` form taking the allocator last: `Vec::new_in(a)`,
`with_capacity_in(n, a)`, `filled_in(n, x, a)`, `Buf::new_in(a)`,
`HashMap::new_in(a)`, `it.collect_in(a)`, `format_in(x, a)`,
`read_stdin_in(a)`, `split_in(s, sep, a)`, `split_whitespace_in(s, a)`,
`sort_stable_in(s, a)`, `sort_stable_by_in(s, f, a)`, `v.clone_in(b)`,
`BinaryHeap::new_in(a)`. The allocator is always the last argument, as
in Rust's allocator API (`Vec::with_capacity_in(cap, alloc)`), except
before a closure that is given it: `arena_scope(gpa, |a| ..)`.
The 0.15 forms are errors that name the `_in` form:

```tach
let v: Vec<i64> = Vec::new();
```
```err
error[type error] allocation is explicit: pass an allocator (try: Vec::new_in(gpa))
```

`volec fix --only alloc016` moves a 0.15 program over: each call
becomes its `_in` form, and `gpa: Gpa` is added to every function from
`main` down to the calls (and passed at each call). A function it cannot
change (an impl of std's `Display`, a function used as a value, a
parameter's default) is an error naming where it allocates: keep a
`gpa: Gpa` in the value it works on, or allocate in the caller.

## Containers and their allocator

`Vec<T, A: Allocator = Gpa>`, `Buf<A = Gpa>`, `HashMap<K, V, A = Gpa>`:
the allocator is a type parameter with a default, so `Vec<i64>` is
`Vec<i64, Gpa>` (and `Vec<i64>` costs what it did: `Gpa` takes no
bytes). Code generic over the allocator names it, and changes the
container through an `inout` parameter (called with `&v`); code that
only reads takes a slice:

```tach
fn fill<A: Allocator>(v: inout Vec<i64, A>, n: i64) {
    for i in 0..n { v.push(i); }
}

fn sum(s: [i64]) -> i64 {                     // any Vec's as_slice()
    s.iter().sum()
}

fn main(gpa: Gpa) -> i32 {
    var v: Vec<i64> = Vec::new_in(gpa);
    fill(&v, 5);
    println(sum(v.as_slice()));
    0
}
```
```out
10
```

An impl block writes every type argument, the defaulted ones too:
`impl<T, A: Allocator> Tr for Vec<T, A>`. A static cannot hold a `Gpa`:
keep containers in `main` and pass them (or views of them) down.

## Arenas

An arena allocates by bumping a pointer and frees everything at once.
`arena_scope(gpa, |a| ...)` makes one (its memory from `gpa`), runs the
closure with it, and frees all of it when the closure returns; nothing allocated from it may leave
the closure (the compiler rejects a result or a capture that holds the
`ScopedArena`). `Arena::new_in(gpa)` is a handle kept longer (it does
not drop yet: `unsafe { a.free_all(); }` returns its memory, 0.17),
`a.scope(|s| ...)` a scope of it; `FixedBuf::new(mem)` allocates from memory you give it.

```tach
fn longest(words: [[u8]], gpa: Gpa) -> i64 {
    arena_scope(gpa, |a| {
        var lens: Vec<i64, ScopedArena> = Vec::new_in(a);
        for w in words { lens.push(w.len()); }
        lens.iter().max().unwrap_or(0)        // an i64 leaves, the Vec does not
    })
}
```

## --check-alloc

`volec --check-alloc f.vl -o f` builds the program with a checking
`Gpa` (like `--check-unsafe`, at any `-O`): every block gets pages of
its own, never reused, so a use after free, a double free, a free of a
wrong pointer or size stop the program with where the block was
allocated and freed; leaks are listed at exit (`gpa.check_leaks()` in a
test). Arenas and `FixedBuf` are checked the same way: a block
used after their `reset`, after its scope ended, or after it moved is
reported. Views (`as_slice()`, a `[T]`) into memory that was freed or
moved are rejected in safe code since 0.17 (`volec guide views`);
this mode still finds them in `unsafe` code and under `--values=off`.
