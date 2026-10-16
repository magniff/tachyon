# Memory

Tachyon manages no memory for you: there are no destructors, no
garbage collector, no reference counting. Values live on the stack, in
statics, or on the heap through std's types (`Vec`, `Buf`, `HashMap`,
which call C's `malloc`/`realloc`/`free`) and C's allocator.

## Copies

Every value is copied by `=`, by a call and by a return, bit for bit;
nothing is moved. For plain values (numbers, arrays, structs of them)
the copy is independent. A `Vec`, `Buf` or `HashMap` is a small handle
(a pointer, a length, a capacity): its copy points to the same memory,
and a push through one copy is not seen by the other.

```tach
fn add_one(v: *Vec<i64>) { v.push(1); }   // through a pointer: the caller's Vec

fn lost(v: Vec<i64>) {                    // a copy of the handle
    let mut w = v;
    w.push(2);                            // the caller's len does not change
}

fn main(gpa: Gpa) -> i32 {
    let mut v: Vec<i64> = Vec::new_in(gpa);
    defer v.free();
    add_one(&v);
    add_one(&v);
    std::print_int(v.len());
    print(" ");
    let a = [1, 2, 3];
    let mut b = a;                        // arrays are values
    b[0] = 9;
    std::print_int(a[0]);
    println("");
    0
}
```
```out
2 1
```

Write functions that change a container to take `*Vec<T>` and pass
`&v`; return a new container by value (`fn make(gpa: Gpa) -> Vec<i64>`:
making one takes an allocator, `guide allocators`), which the caller
then owns and frees.

## Freeing: defer

`defer stmt;` (or `defer { ... }`) runs when control leaves the block:
at its end, or by `return`, `break` or `continue`, last deferred first.
The value a block returns is computed before the deferred statements
run. They do not run on `exit` or a failed check (exit 101).

```tach
fn describe(n: i64, gpa: Gpa) -> i64 {
    let mut b = Buf::new_in(gpa);
    defer b.free();                       // on every path out
    if n < 0 { return -1; }
    b.push_int(n);
    b.len()                               // computed before the free
}

fn main(gpa: Gpa) -> i32 {
    defer println("done");
    std::print_int(describe(12345, gpa) + describe(-5, gpa));
    println("");
    0
}
```
```out
4
done
```

## Views

A slice (`[T]`) does not own memory. One from `v.as_slice()` is valid
until `v` grows (a push may reallocate) or is freed; one of an array,
while the array lives (not after the function holding it returns).
Using a view after its memory is gone is undefined behaviour, the one
case in safe code (tachyon has no lifetimes yet). Take the slice again
after pushing:

```tach
let mut v: Vec<i64> = Vec::new_in(gpa);
defer v.free();
v.push(1);
let s = v.as_slice();
std::print_int(s[0]);
for i in 0..100 { v.push(i); }            // may move the elements
let s2 = v.as_slice();                    // a fresh view; do not use s now
std::print_int(s2.len);
println("");
```
```out
1101
```

Views without a name count too: `for x in v` and `v.iter()` view `v`
for the whole loop (do not push to `v` inside it; collect into another
Vec), and in `f(v.as_slice(), g(&v))` the slice is taken before `g`
runs. A view kept in a variable or a field and re-taken after each push
is fine, even inside an index: in `s[grow(&v, &s)]` the slice `s` is
read after `grow` returns (0.14).

`tachyonc --check-alloc` (0.16) finds these at run time: Gpa gives each
block pages of its own, never reused, and moves a block on every resize,
so a view of freed or moved memory faults and the program stops with
`use after free: block #3 (32 bytes), allocated at main.tach:4:5, freed
at main.tach:9:5` (exit 101). Double, invalid and wrong-size frees stop
it too, and the blocks not freed are listed at exit (`gpa.live_blocks()`,
`gpa.check_leaks()` for tests). Each live block takes a page: for tests
and debugging, at any `-O` level; `TACHYON_ALLOC_TRAP=N` raises SIGTRAP
when block N is allocated, for a debugger.

## Raw memory

`malloc` and `free` from C, in `unsafe` (see `tachyonc guide unsafe`).
`tachyonc --check-unsafe -O1` checks heap accesses through raw pointers
at run time. Memory nobody wrote (from `malloc`) has an unspecified
value: write it before reading it.
