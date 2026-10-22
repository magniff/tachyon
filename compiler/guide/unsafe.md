# unsafe

Safe code has no undefined behaviour: arithmetic wraps, `/ 0` is 0,
indexing is checked, every variable is initialized. What can have
undefined behaviour is an *unsafe operation*, allowed only inside
`unsafe { ... }` (an expression: `let x = unsafe { *p };`) or in the body
of an `unsafe fn`:

- calling a C function (an `extern "C"` declaration, an `import`ed one,
  an `extern "C" fn` pointer) or an `unsafe fn`;
- dereferencing a raw pointer: `*p`, `p.f`, a method called through `p`;
- indexing or slicing a raw pointer: `p[i]`, `p[lo..hi]` (unchecked);
- casting an integer to a pointer (except the literal `0`, null);
- reading a union's field;
- using an `unsafe fn` as a value.

A `*T` is raw wherever it comes from, a parameter too. Passing,
comparing and casting one is safe; dereferencing it is not. `*` means
only this: an access (a let or inout parameter, an `inout` local, an
access field) is used as its value, with no `*`.

## Accesses and raw pointers

Parameters taken let, inout or sink, `inout r = &x;` locals and access
fields are checked by the compiler (`guide memory`, `guide views`), so
using them is safe. `*T` is the raw pointer, the escape hatch: nothing
checks what it points to.

- `&place` passed where a `*T` is wanted (C's parameters, `&x as *u8`)
  converts to the raw pointer; the call takes an exclusive loan of
  `place` for its duration, sound for C's `const T*` too.
- A raw pointer: a `*T` local or field, `malloc`'s result, `c"..."`
  (read-only memory), and `&(*p).f` of a place reached through a raw
  `p`. In `unsafe` code `&*p` makes an inout access of the pointee
  (`bump(&*p)`, `inout r = &*p;`): the code vouches. A raw pointer never
  becomes an access by itself.
- To read or change a caller's value, take it let or inout, not `*T`:
  `fn read(x: i64)`, `fn set(x: inout i64) { x = 4; }`. `fix --only
  unsafe` wraps what stays raw in `unsafe { }`.
- `p[i]` on an access to a Vec, a Buf or a slice is that element,
  checked; `p[i]` on a raw pointer is pointer arithmetic, unchecked and
  unsafe.

```tach
extern "C" {
    fn malloc(n: u64) -> *u8;
    fn free(p: *u8);
}

struct Stats { count: i64, sum: i64 }

fn add(s: inout Stats, x: i64) {     // an access: safe to use
    s.count += 1;
    s.sum += x;
}

// The caller promises that p points to n valid i64s.
unsafe fn total(p: *i64, n: i64) -> i64 {
    var t = 0;
    for i in 0..n { t += p[i]; }      // allowed: the body is unsafe code
    t
}

fn main() -> i32 {
    var st = Stats { count: 0, sum: 0 };
    add(&st, 5);
    add(&st, 7);
    let p = unsafe { malloc(3 * 8) as *i64 };
    defer { unsafe { free(p as *u8); } }
    unsafe {
        p[0] = 1;
        p[1] = 2;
        p[2] = 3;
    }
    let raw = unsafe { p[0..3] };     // a slice of raw memory: valid while p is
    std::print_int(st.sum + unsafe { total(p, 3) } + raw[2]);
    println("");
    0
}
```
```out
21
```

Write the contract of an `unsafe fn` in its comment: its callers take it
on. What unsafe code must keep so that the safe code around it stays
defined:

- every pointer it hands to safe code as an access (`&*p`) points to
  live memory of its type, and every slice it makes is valid for its length
  while it is used;
- it makes no second live alias of a place under an inout access (the
  optimizer relies on an `inout` parameter being the only way to its
  memory);
- a type whose safe methods manage memory through raw pointers (a
  growable buffer of its own) implements `Drop`: that makes it owned and
  move-only, so a copy cannot outlive a reallocation.

## Tools

- `volec fix --only unsafe` puts each unsafe operation outside unsafe
  code into an `unsafe { }` block (the statement around it).
- `volec --check-unsafe -O1 prog.vl -o prog` checks raw-pointer
  accesses against the heap blocks at run time (`malloc`/`free`):
  out-of-bounds and use-after-free stop the program with `unsafe access
  ...` and exit 101. Programs run tens of times slower.
- `volec --check-alloc` (0.16) puts every block of Gpa on pages of
  its own: a use after free through raw pointers faults and is reported
  with where the block was allocated and freed;
  bad frees and leaks are reported too (`volec guide memory`). With
  `--check-unsafe`, raw accesses are checked against those blocks.
- Statics, `static var` included, are safe: a `static var` is for the
  main thread, and code another thread runs may not reach one
  (`sync.global`, `guide threads`).
