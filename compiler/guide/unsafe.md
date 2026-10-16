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
- passing a raw pointer to a pointer parameter, calling a plain `fn`
  pointer with one, using an `unsafe fn` or a function with pointer
  parameters as a value.

## References and raw pointers

`&T` and `&mut T` (0.17) are references: checked by the compiler
(`guide memory`, `guide views`), so dereferencing one is safe. `*T` is
the raw pointer, the escape hatch: nothing checks what it points to.

- `&place` and `&mut place` are references, kept in a local too (`let r
  = &mut x; r.f = 1;`); a reference converts to a raw `*T` wherever one
  is expected (`malloc`'s callers, C's parameters).
- A raw pointer: a `*T` local or field, `malloc`'s result, `c"..."`
  (read-only memory), and `&(*p).f` of a place reached through a raw
  `p`. In `unsafe` code `&*p` makes a reference of it: the code vouches.
- A `*T` parameter written without `mut`, in a safe function, is
  accepted as `&mut T` until 0.18.1 (the legacy rule, which ends with
  0.18.1: from then on every `*T` is raw, `mut` or not; `tachyonc fix
  --values` rewrites it to `&mut T` or `&T`). A `mut p: *T` parameter
  and any `*T` of an `unsafe fn` or of C are raw.
- `p[i]` on a reference to a Vec, a Buf or a slice is the element of the
  one it points to, checked; `p[i]` on a raw pointer is pointer
  arithmetic, unchecked and unsafe. On `out: &mut i64` the value is
  `*out` (`*out = acc`).

```tach
extern "C" {
    fn malloc(n: u64) -> *u8;
    fn free(p: *u8);
}

struct Stats { count: i64, sum: i64 }

fn add(s: &mut Stats, x: i64) {      // a reference: safe to use
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
    add(&mut st, 5);
    add(&mut st, 7);
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

- every pointer it hands to safe code as a reference points to live
  memory of its type, and every slice it makes is valid for its length
  while it is used;
- it makes no second live alias of a place under a `&mut` (the optimizer
  relies on a `&mut` parameter being the only way to its memory);
- a type whose safe methods manage memory through raw pointers (a
  growable buffer of its own) implements `Drop`: that makes it owned and
  move-only, so a copy cannot outlive a reallocation.

## Tools

- `tachyonc fix --only unsafe` puts each unsafe operation outside unsafe
  code into an `unsafe { }` block (the statement around it).
- `tachyonc --check-unsafe -O1 prog.tach -o prog` checks raw-pointer
  accesses against the heap blocks at run time (`malloc`/`free`):
  out-of-bounds and use-after-free stop the program with `unsafe access
  ...` and exit 101. Programs run tens of times slower.
- `tachyonc --check-alloc` (0.16) puts every block of Gpa on pages of
  its own: a use after free through raw pointers faults and is reported
  with where the block was allocated and freed;
  bad frees and leaks are reported too (`tachyonc guide memory`). With
  `--check-unsafe`, raw accesses are checked against those blocks.
- Statics, `static mut` included, are safe: tachyon has no threads.
