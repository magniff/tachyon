# Semantics audit before 0.25: mutability and the law of exclusivity

Branch sem-excl, from release-0.25 at 2476e990, compiler `volec 0.24.0`
built from that tree. 375 probes in tests/run/sem_excl_*.vl. Each one
states what vole should do: an `// ERROR:` it must report, or the
`// EXPECT:` output at every level. 97 of them fail today and carry
`// XFAIL: CLASS ...`. Every program that compiles was run at -O0 and -O2,
each with and without `--check-alloc`. The suite runs them at the default
level and at `-O 0`: 278 pass, 97 xfail, 0 fail.

The rules were taken from conventions.md (D1–D28, §3 call sites, §5
bindings, the let-as-borrow rule of 0.22.1 and 0.24), value-semantics.md
§2.4 (exclusivity, statics, closures), the guide (memory, views, types,
threads) and grammar.md's 0.20 section ("Not yet": projections and `for
inout`).

## Coverage

Rule × context. **ok**: every probe in the cell behaves as specified.
**BUG**: at least one finding, listed after the table. **—**: not
applicable, or not built yet.

| rule | locals | fields / nested | elements / slices | tuples / patterns | params | receivers | generics / traits | closures | control flow | threads | statics |
|---|---|---|---|---|---|---|---|---|---|---|---|
| R1 a `let` binding is not assigned | ok | ok | ok | ok | ok | ok | ok | ok | ok (match, if let, for) | — | ok |
| R2 a `let` place is not lent inout | BUG W1 | BUG W1 | BUG W1 | BUG W1 | BUG W1 (plain); ok (owned) | BUG W1 | BUG W1 | BUG W1 | BUG W1 (match &) | — | BUG S1 |
| R3 two inout accesses of one place overlap | ok | ok (disjoint fields allowed) | ok (`v[i]`, `v[j]` collapse) | ok | ok (reborrows) | ok (`a.f(&a)`, `v[0].f(&v[1])`) | ok | BUG S3, S4 | ok | BUG S11 | ok |
| R4 an inout plus a let of one owned value; a plain let is a copy (D5) | ok | ok | BUG S2 | ok | ok | BUG S2 | ok | BUG S6 | ok | — | BUG S10 |
| R5 views and loans live across an inout or write | ok | ok | ok | ok | ok | ok (two-phase) | ok | BUG S5 | ok (NLL, loops, branches) | ok | ok |
| R6 move-only views (inout fields) | ok | BUG S8, S9 | ok (`inout [T]` field) | — | ok | ok | — | — | ok | — | — |
| R7 copy independence (`var b = a`, clone) | ok | ok | ok | ok | ok | ok | ok | ok | ok (loops) | ok (sink) | — |
| R8 assignment through inout drops the old value once | ok | ok | BUG S12 | — | ok | BUG S12 | ok | — | — | — | — |
| R9 swap-like patterns | ok | ok | ok | — | ok | ok | ok | — | — | — | — |
| R10 call-site markers, `&` of a temporary | ok | — | — | — | BUG W2 | — | — | — | — | — | — |
| R11 call-argument order (§3) | ok | — | ok | — | BUG W3 | ok | — | — | ok (`?`) | — | — |
| R12 captured values used as slices | — | — | BUG S7 | — | — | — | — | BUG S7 | — | BUG S7 | — |

Probe prefixes: `let_` R1, `letin_` R2, `ex_` R3/R4 in call arguments,
`rc_` receivers and two-phase, `il_` inout locals and live loans, `cl_`
closures, `cp_` copies, `as_` assignments and drops, `sw_` swaps, `pl_`
kinds of place and markers, `vf_` structs with inout fields, `gx_`
generics and traits, `cf_` control flow, `sk_` sink, `lb_` let-as-borrow,
`st_` statics, `th_` threads, `pj_` projections, `lv_` more let/var
patterns, `hm_` HashMap accessors.

## Findings

Counts: SOUNDNESS 12, WRONG 3, OVERSTRICT 3, DIAG 7. The test names
below omit the `sem_excl_` prefix.

### SOUNDNESS

**S1. An immutable static lent inout is written: a bus error.**
`letin_static`. This is the known `let n; bump(&n)` bug, but on a static
in read-only memory.

```vl
static N: i64 = 1;
fn bump(n: inout i64) { n += 1; }
fn main() { bump(&N); println(f"{N}"); }     // Bus error at -O0 and -O2
```

**S2. An inout element and the whole Vec lent let in one call.**
`ex_vec_elem_let_slice` (-O0 prints 105, -O2 prints 101),
`ex_vec_elem_let_whole`, `ex_vec_elem_let_whole_O2`,
`gx_elem_recv_vec_let_arg` (`v[0].look(v)`). An array (`f(&a[0],
a[..])`) and a field (`f(&s.n, s)`) are rejected. Only a Vec place
passed let, as a Vec or coerced to a slice, is missed.

```vl
fn f(a: inout i64, v: [i64]) -> i64 { let before = v[0]; a = 5; before * 100 + v[0] }
fn main(gpa: Gpa) { var v: Vec<i64> = Vec::new_in(gpa); v.push(1); println(f"{f(&v[0], v)}"); }
```

**S3. A closure called with an inout of a var it captures.**
`cl_alias_O2` (prints `105 5`: x and the capture are one place),
`cl_alias_O2_slice`, `cl_closure_inout_param`,
`cl_closure_inout_param_alias`, `cl_closure_inout_param_alias_vec`.
Passing that closure to a function with `&n` is rejected
(`call(f, &n)`). Only a direct call of a closure local is missed.

```vl
fn main() { var n = 1; let f = |x: inout i64| -> i64 { let before = n; x = 5; before * 100 + n }; let r = f(&n); println(f"{r} {n}"); }
```

**S4. Two live closures over one var.** `cl_two_closures` (`var f = ||
{ n += 10; }; var g = || { n += 100; }; f(); g(); f();`) and
`cl_two_closures_generic` (`both(|| n, || { n += 1; })`). A capture by
inout is a loan while the closure lives (value-semantics.md §2.4,
"Closures"). Two such loans on one var are accepted.

**S5. Calling a closure does not count as a write to what it captures.**
`cl_view_live_closure_call` and `cl_view_made_after_closure` (use after
free: garbage at -O0 and -O2, aborted by --check-alloc),
`cl_closure_passed_inout_and_capture_called` (-O0 prints 105, -O2 prints
101).

```vl
var v: Vec<i64> = Vec::new_in(gpa); v.push(1);
let s = v.as_slice();
var g = || { for i in 0..1000 { v.push(i); } };
g();
println(f"{s[0]}");                          // reads freed memory
```

**S6. A let argument next to a closure argument that changes the same
var.** `cl_let_vec_capture_realloc` (use after free: --check-alloc says
"use after free: block #1"), `cl_let_vec_capture_free`,
`cl_let_vec_capture_write`, `cl_let_arg_after_closure`,
`cl_let_vec_closure_local`, `cl_slice_arg_capture_write`,
`cl_let_recv_capture_write` (a let receiver). The same call with an
inout argument instead of the let one is rejected
(`cl_inout_capture_write`).

```vl
fn f<F: FnMut()>(p: Vec<i64>, w: F) -> i64 { let s = p.as_slice(); w(); s[0] }
fn main(gpa: Gpa) { var v: Vec<i64> = Vec::new_in(gpa); v.push(1); let r = f(v, || { v.clear(); for i in 0..1000 { v.push(i + 7); } }); println(f"{r}"); }
```

**S7. A captured Vec or Buf used where its slice is wanted.**
`cl_capture_vec_as_slice_let` and `cl_capture_vec_as_slice_inout`
segfault at -O0; at -O2 the compiler fails with "internal error: an
operand not in a register" (and is killed, status 137, for
`cl_capture_let_vec_as_slice`). `cl_capture_buf_as_slice` prints
4377414937 for a 2-byte Buf. `cl_capture_let_vec_as_slice` prints
-8417117753156041712. Also `th_vec_slice_noscope`. Writing `v[..]` works
(`cl_capture_vec_range_inout`). The coercion of a Vec place to its slice
seems to read the capture's pointer as if it were the Vec.

```vl
fn first(s: [i64]) -> i64 { s[0] }
fn main(gpa: Gpa) { var v: Vec<i64> = Vec::new_in(gpa); v.push(7); let f = || first(v); println(f"{f()}"); }
```

**S8. A move-only view is copied.** `vf_inout_field_copy`. `struct C {
n: inout i64 }`, then `let c = C { n: &x }; let d = c; d.n += 1; c.n +=
1;` is accepted and prints 3. That gives two live inout accesses of x.
It should be `own.moved` (guide views: "it moves, it is not copied").

**S9. A view holding an inout of x, and x itself, passed to one call.**
`vf_inout_field_passed` and `vf_inout_field_passed_O2`: `f(&c, &x)`
prints 105, so the two parameters alias. The same call with an `inout
[i64]` field is rejected.

**S10. A static lent to a function that writes it.**
`st_inout_static_global` and `st_inout_static_global_indirect`: `f(&G)`,
where f (or its callee) writes G, prints 105 at -O0 and 101 at -O2.
value-semantics.md §2.4 makes `&S` to a function with `global` an error.
`st_let_static_vec_global`: a static array passed let to a function that
writes the static and returns a view of the parameter. The view sees the
write.

```vl
static var G: i64 = 1;
fn f(x: inout i64) -> i64 { let before = x; G = 5; before * 100 + x }
fn main() { println(f"{f(&G)}"); }
```

**S11. Scoped threads share an inout whole slice.**
`th_scope_slice_race` (two threads each run `bump(&a[..])`: the count is
a different number from 1.0M to 2.0M on each run), `th_scope_slice_inout`
(`&a[0..2]`), `th_scope_vec_slice_race` (`&v`, which also hits S7).
Elements, fields, `a[0] += 1`, `v.push` and `v.as_mut_slice()` are
rejected with `sync.scope_shared_write`.

**S12. Assigning an element does not drop the element it replaces.**
`as_drop_elem_local`, `as_drop_elem_through_inout`,
`as_drop_elem_inout_local`, `as_drop_slice_elem`,
`as_drop_array_elem_inout`, `as_drop_field_elem_inout`,
`as_drop_self_elem`. Each has a Drop type that prints; "drop 1" is
never printed. `as_drop_elem_vec_local` and `as_drop_elem_vec_inout`
show it under `--check-alloc` with `gpa.live_blocks()`. A whole value
(`d = D { .. }` through inout) and a field (`h.d = ..`) are dropped
correctly.

```vl
var v: Vec<D> = Vec::new_in(gpa); v.push(D { id: 1 }); v[0] = D { id: 2 };   // D 1 leaks
```

### WRONG

**W1. The family of the known `let n = 1; bump(&n)` bug.** Every inout
access of a `let` place is accepted, except through a let parameter of
an owned type (`own.readonly`) and through a D13 borrow (`let x =
vs[0]; x.push(5)` is `own.readonly`). Accepted:

| case | tests |
|---|---|
| a field, an element, a tuple part, a pattern binding | `letin_field`, `letin_array_elem`, `letin_vec_elem`, `letin_tuple`, `letin_pat_bind` |
| the whole value, a slice of it | `letin_vec_whole`, `letin_slice`, `letin_slice_vec`, `letin_as_mut_slice` |
| an inout local; `match &o` | `letin_local`, `letin_local_field`, `letin_match` |
| an inout method | `let_vec_push` (`v.push(1)` on `let v: Vec`), `let_vec_elem` (`v[0] = 5`), `letin_method_plain`, `letin_method_field`, `letin_get_mut`, `lv_let_after_var_move` |
| a let parameter or a let self that is a copy | `letin_param` (`bump(&x)`), `letin_self_field`, `letin_self_method`, `letin_trait_direct` (`t.inc()` on a generic let `t`) |
| generic and trait calls; `std::swap` | `letin_generic`, `letin_trait`, `letin_swap` |
| closures | `letin_closure`, `lv_closure_let_owned_capture` |
| the raw-pointer conversion | `letin_raw_conv` (`&n as *i64`) |

The values change as the program asks, and -O0 and -O2 agree. The one
case that crashes is S1. `letin_for` waits for `for inout`.

**W2. `conv.place` is never reported.** `pl_temp` (`bump(&one())`),
`pl_literal` (`bump(&5)`), `pl_cast_place` (`bump(&(x as i64))`, where
x stays 1) and `pl_method_result` (`grow(&v[0].clone())`) are accepted.
The change is lost silently. explain documents the code (D7, §3).

**W3. Reads in later arguments of a value lent inout to an earlier one.**
conventions.md §3 says "`f(&a, a.len())` conflicts, as `f(&mut a,
a.len())` did". `cf_arg_inout_then_len`, `cf_arg_inout_then_index`,
`cf_arg_inout_then_call_let` (`add(&v, n(v))`) and `cf_question_vec`
(`add(&v, parse(v)?)`) are accepted. Each read ends before the call, so
nothing can go wrong. Either the doc or the checker should change.

### OVERSTRICT

**O1. A map of lists cannot be changed in place.**
`HashMap<K, Vec<T>>::get_mut` and `::get_or_insert` do not instantiate:
"<std>:7544:32: expected 'inout [Vec<i64>]', got 'inout [i64]'" (see
`hm_get_mut_vec_value`, `hm_get_or_insert_vec_value`,
`cp_hashmap_nested_clone`). std builds the one-element view as `&p[0..1]`
with `p: *V`, and for V = Vec, `p[..]` on a pointer to a Vec indexes
the pointee (0.17's familiar form). A plain value type works
(`hm_get_mut_struct_value`).

**O2. The let-as-borrow rule covers results, not stores.**
`lb_stores_into_inout_ok`: `fn keep(h: inout H, y: [i64; 2]) { h.s =
y[..]; }` is `own.escape` ("'y' is dropped when 'keep' returns").
conventions.md's 0.22.1 rule names "stores one (into an inout parameter
or a field)"; 0.24 built only the result half. `lb_stores_into_inout`
is the conflict that should follow once the store is accepted.

**O3. `v = v` through an inout access is `own.move_out`**
(`as_self_assign_through_inout`), while a local's `v = v` is accepted
(`as_self_assign_local`). See D5 for its words.

### DIAG

- **D1.** own.conflict speaks of references: "'x' is borrowed mutably
  by '&x' and mutably again by '&x'" (§10.1 designs "'a' is lent inout
  to argument 1 and to argument 2 of 'transfer'"). For `a.f(&a)` with
  both inout, the help says "the call changes its receiver while this
  argument still views it: copy what it views first ('.clone()')", but
  nothing views anything (`rc_self_inout_arg`). A second
  `get_or_insert` while the first result is live is "'m' is read while
  'a' borrows it mutably" (`pj_get_mut_twice`); it is a second inout,
  not a read.
- **D2.** `-> inout T` and `-> let T` (not built yet): "'pick' returns
  a reference ('inout i64'): references as results come in 0.17.1".
  0.17.1 is long past, and "reference" is not vole's word
  (`pj_inout_result`, `pj_inout_from_let`).
- **D3.** `for inout x in &v` (not built yet, D18): "'inout' is a
  keyword (...): a name cannot be spelled so | help: rename it". The
  message should say that `for inout` is not built yet, and give the
  index loop (`pl_for_inout*`).
- **D4.** `&(if c { a } else { b })`: "cannot take address of non-lvalue
  expression", C's words where the code is conv.place (`pl_if_expr`).
- **D5.** `v = v` through an inout (O3): "cannot move 'v = v' out of a
  reference ... it is borrowed read-only (let)", for an inout `v`.
- **D6.** An assignment to a let parameter: "take it `p: inout P`
  (called with `&x`)". It names `x`, not the argument
  (`let_param_field`).
- **D7.** guide memory#accesses says "`f(&a, a)` and `f(&a, &a)` are
  errors". For a plain `a`, `f(&a, a)` is legal and passes a copy (D5,
  `ex_inout_let_plain`).

## What held

These all behave as specified:
- two inouts of one place, as arguments, locals, reborrows, receivers
  (`a.f(&a)`) and elements (`v[0].f(&v[1])`), in generic and trait
  code, and through closures' and function values' parameters;
- disjoint fields, and the collapsing of indexes;
- two-phase receivers (`v.push(v.len())`; `v.extend_from_slice(v[..])`
  rejected);
- NLL liveness across branches, loops, early returns and defers;
- inout locals;
- views across `push`, `clear` and an inout call;
- D13 borrows of owned elements;
- copies of structs, arrays, tuples and enums, and clones of Vec,
  String, Buf, HashMap and nested Vecs;
- moves on `var b = a`;
- drops when a whole value or a field is assigned through an inout;
- `std::swap`, `replace`, `Vec::swap` (including `swap(i, i)`) and
  hand-written swaps;
- `sink` and its interactions with inout;
- the markers `conv.marker` and `conv.marker_extra`;
- `sync.*` on elements, fields and methods.

Not run: the Linux container's valgrind row. --check-alloc confirms the
use-after-free findings (S5, S6) and the leaks (S12) on macOS.
