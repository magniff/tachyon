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
- passing a pointer that is not a borrow to a pointer parameter, calling
  a plain `fn` pointer with one, using an `unsafe fn` or a function with
  pointer parameters as a value.

## Borrows

Tachyon has one pointer type, `*T`. A pointer known to be valid is a
*borrow*, and dereferencing a borrow is safe:

- `&place` written directly where the pointer is used (`f(&x)`, the
  receiver of `x.m()`): the address of a local, a static, a field or a
  checked element;
- a parameter declared with a pointer type and not `mut` (`self: *T`
  included).

Everything else is raw: a local holding a pointer, a pointer field,
`malloc`'s result, `c"..."` (read-only memory). Indexing a borrow is
unsafe (a borrow is one value, not an array), except that `p[i]` on a
pointer to a Vec, a Buf or a slice (`dist: *Vec<i64>`) is `(*p)[i]`, the
element of the one it points to, checked: safe through a borrow, unsafe
through a raw pointer, the same in both. `p[0]` on any other pointer is
pointer arithmetic: the value it points to is `*p` (`*out = acc`), safe
through a borrow.

```tach
extern "C" {
    fn malloc(n: u64) -> *u8;
    fn free(p: *u8);
}

struct Stats { count: i64, sum: i64 }

fn add(s: *Stats, x: i64) {          // s is a borrow: safe to use
    s.count += 1;
    s.sum += x;
}

// The caller promises that p points to n valid i64s.
unsafe fn total(p: *i64, n: i64) -> i64 {
    let mut t = 0;
    for i in 0..n { t += p[i]; }      // allowed: the body is unsafe code
    t
}

fn main() -> i32 {
    let mut st = Stats { count: 0, sum: 0 };
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
defined: every pointer it hands to safe code points to live memory of
its type, and every slice it makes is valid for its length while used.

## The one gap

Tachyon has no lifetimes yet: a slice used after its memory is gone (a
`Vec`'s `as_slice()` after a push that reallocated or a `free`, a slice
of a returned local array) is undefined behaviour in safe code. Keep
views short-lived; re-take `as_slice()` after pushing.

## Tools

- `tachyonc fix --only unsafe` puts each unsafe operation outside unsafe
  code into an `unsafe { }` block (the statement around it).
- `tachyonc --check-unsafe -O1 prog.tach -o prog` checks raw-pointer
  accesses against the heap blocks at run time (`malloc`/`free`):
  out-of-bounds and use-after-free stop the program with `unsafe access
  ...` and exit 101. Programs run tens of times slower.
- `tachyonc --check-alloc` (0.16) puts every block of Gpa on pages of
  its own: a use after free (a copied `Vec` handle, a view after a push)
  faults and is reported with where the block was allocated and freed;
  bad frees and leaks are reported too (`tachyonc guide memory`). With
  `--check-unsafe`, raw accesses are checked against those blocks.
- Statics, `static mut` included, are safe: tachyon has no threads.
