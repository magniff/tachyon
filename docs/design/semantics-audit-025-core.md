# Semantics audit before 0.25: core (no-UB, effects, contracts, -O levels)

Branch `sem-core`, from `release-0.25` (2476e990). 212 probe programs,
all in `tests/run/sem_core_*.vl`. Each probe was run through `volec
check`, built and run at -O0, -O1 and -O2, compared across the three
levels, run under `--check-alloc`, and compiled at -O2 with -j1 and -j8
(the objects were compared). A known bug is `// XFAIL: CLASS ...`; the
expectation is the correct behaviour. A probe that only shows at -O2
has `// FLAGS: -O2`, because the suite's default level is lower.

Counts: 16 SOUNDNESS (3 root causes plus 3 aliasing bugs), 5 WRONG,
1 OVERSTRICT (all XFAIL), and the DIAG notes below (not XFAIL'd). No
-j1/-j8 object differed, and `--check-alloc` found nothing except
finding 5.

## Coverage

| rule | contexts probed | probes |
|---|---|---|
| integer wrap `+ - *` and unary `-` | i8..u64, constants and run time, compound assignment, narrow results compared/divided/shifted/widened/indexed/passed/stored/matched, `x + 1 > x` loop | `wrap_*`, `opt_cmp_fold` |
| `/ 0`, `% 0`, MIN / -1 | every width, constants and run time, compound, divisions by constants (magic numbers) at the extremes | `div`, `opt_magic_div` |
| shifts mod 64 / mod 32 | every width, both directions, negative amounts, constants vs run time, compound | `shift` |
| float to int, int to float | NaN, inf, saturation, u64 wrap below 0, f32, narrow targets | `float_to_int`, `float_to_narrow_signed` |
| `as` between integers, to enums | truncation, sign/zero extension, chains, bool, checked enum casts (low byte valid) | `as_int`, `as_enum*` |
| checked indexing | Vec (neg, len, MIN, MAX, a scaled offset that wraps, store, `+=`, after pop, below the capacity, `get`), arrays (i32/u32/u64/u8 indexes, nested, fields through inout, `0..=N`), slices (lo > hi, neg lo, near MAX, `..=`, subslices), str bytes, Buf, SIMD load/lane | `idx_*` |
| optimizer range facts | `x % 8`, `x >> 61`, `x & 7`, abs of MIN, i32/i8 indexes, `i + 1 < len`, `i < len` then `i - 1`, unsigned guards, loops past the end, reversed ranges, wrapping induction, `i * 2`, narrow sums, subslices | `rf_*`, `opt_range_facts` |
| ranges at the extremes | `max-2..max`, `..=max`, `min..`, u8/i8 `..=` at the top, empty | `opt_range_extremes` |
| floats without fast-math | `x*0`, `x-x`, NaN compares, -0.0, reassociation, contraction | `opt_float_nofast` |
| raw pointers and C need unsafe | deref, field, index, slice, store, int-to-ptr, C call, import, unsafe fn call/value, extern fn pointer, union read, method through `*T`, `&*p`, `inout r = &*p`, NonNull, `s.ptr`; in a closure, default argument, requires, f-string, match guard, defer, generic, trait default, assert, static initializer | `unsafe_*` |
| effect bounds | `#[no_io]`, `#[no_alloc]`, `#[no_panic]`, `#[pure]`, `#[effects(..)]`, `F: Fn + effects(..)`, trait-bound purity (Eq, Ord, Hash); reached through fn values (default argument, generic instance, method, struct field, returned, coerced closure, elsewhere), closures (generic, field, nested), traits (generic, default, operator), drops (sink param, temporary, assignment, Vec elements, Option, fields, `?`, sink closure, generic), user iterators, defer, C callbacks (qsort), std (clone, HashMap, remove, unwrap, requires, ensures, NonNull, exit, spawn), static atomics | `eff_*` |
| contracts | requires at direct, method, generic, trait-impl, recursive and closure calls; argument order; through a fn value; ensures at early returns, `?`, match arms, closures' returns, `old`; contract.effect; facts: `x % n`, wrapping `i + 1 <= len`, no lower bound, stale facts after the body or the callee shrinks a Vec, `debug requires` | `ctr_*` |
| -O0 = -O2: LICM | guarded checked loads in while/for/nested loops, slices, Vec, fields, params, tuples, nested arrays, match arms, after a break, zero-trip loops; guarded raw loads, null checks, enum casts, unwrap, lanes, subslices, stores, readonly calls, slow pure calls, calls with requires | `licm_*`, `opt_licm_*` |
| -O0 = -O2: GVN, if-conversion, memory | calls reading a changed argument, loads across inout calls, C mem*/str*, `if c { v[i] }`, null-guarded raw loads | `opt_gvn_call`, `opt_ifconv_index`, `opt_c_mem`, `opt_load_across_inout` |
| noalias from conventions | statics lent inout/let while the callee writes them (whole, a field, an inout self), inout locals of statics, two inouts, overlapping/disjoint slices, element + whole, inout self + field, closures | `static_*`, `opt_static_*`, `noalias_*` |

## SOUNDNESS

1. **-O2 LICM hoists a guarded element load above its bounds check.**
   The load of `a[i]` under a never-true `if` goes into the loop's
   preheader, before the check, so safe code reads out of bounds (it
   segfaults for i = -2^40). It also happens with counted `for` loops,
   nested loops, slices, array fields and parameters, tuples, match
   arms, and an index after a `break` that is always taken. Vec
   elements and raw loads are not hoisted. `sem_core_opt_licm_hoist_load`,
   `sem_core_licm_{for_array,nested,slice,struct_field,param,break_first,match_arm,tuple_array}`.
   ```vl
   let a = [1, 2, 3];
   while k < 5 + Z { if k > 100 { t += a[i]; } k += 1; }   // -O2: segfault
   ```
2. **A static lent to a call aliases the static named in the callee.**
   -O0 and -O1/-O2 print different values. The own pass has
   `own.static` for an `inout r = &G` local, which is rejected, but not
   for a call:
   - `g(&G)` with g writing `G.a`: -O0 prints 99, -O2 prints 5
     (`sem_core_opt_static_inout_alias`);
   - `g(&G.a)`: the same (`sem_core_static_inout_field`);
   - `G.bump()` with `inout self`: the same (`sem_core_static_method_receiver`);
   - `f(A[..])`, a let slice, with f writing `A[0]`: -O0 prints 1099,
     -O2 prints 1001 (`sem_core_opt_static_view`).
3. **A pure, willreturn call under a never-true condition is hoisted
   speculatively.** `if k == 5 { s += slow(2^62) }`: -O0 prints 3, and
   -O2 runs 2^62 iterations (`sem_core_opt_licm_slow`).
4. **A view survives a closure call that grows its Vec** (views area):
   `let s = v.as_slice(); var grow = || v.push(..); grow(); s[0]`.
   `--check-alloc` reports a use after free (`sem_core_noalias_closure_grow_view`).
5. **`f(&v[0], v)` is accepted**: the let Vec parameter aliases the
   inout element and changes under the callee (`sem_core_noalias_vec_elem_and_vec`).
   For plain arrays and fields the let argument is a copy, which is
   fine (`noalias_inout_elem_and_let_arr`, `noalias_self_and_field`).

## WRONG

- **An assert makes a body's effects unknown, and an unknown function's
  declarations are not checked.** This holds when the body calls
  nothing with a `requires`. `#[pure] fn g(x) { assert(x > 0);
  println(..) }` and `#[no_alloc]` with `v.push` are accepted, and
  `--print-effects` shows `(unknown)`. Callers become unknown too, up
  to main. The optimizer and the thread checks treat unknown
  conservatively, so this is not UB.
  `sem_core_eff_assert_unknown`, `sem_core_eff_assert_no_panic`.
  Note that `volec check` run from the worktree root (with its cache)
  does report both errors, while the build and a check from another
  directory accept them: check and build disagree.
- **A requires condition that does io through a fn value is not
  `contract.effect`.** `f$pre` has `io global panic` and prints when
  the requires is checked (`sem_core_eff_contract_cond`).
- **`static P: *i64 = 4096 as *i64;` is accepted outside unsafe.** A
  run-time cast of the same kind is `error[unsafe]`
  (`sem_core_unsafe_static_init`).
- **Float to i8/i16 does not saturate at the target's bounds**, which
  grammar.md says it does. They saturate at i32's bounds and keep the
  low bits: `1e30 as i16 == -1`, `128.0 as i8 == -128`. The existing
  `cast_float_int_saturate.vl` codifies the implementation, so either
  the doc or the code must change (`sem_core_float_to_narrow_signed`).

## OVERSTRICT

- `f(&x[0..2], x[2..4])`, with disjoint constant ranges, is
  `own.conflict` (`sem_core_noalias_disjoint_slices`). Rust rejects it
  too.

## DIAG (not XFAIL'd)

- `own.conflict` says "borrowed mutably" and "mutably again", which is
  Rust-era wording (`sem_core_static_two_inout`, `noalias_*`).
- An effect error's source text is empty, `'' at FILE:L:C calls
  'Noisy::drop'`, for a dropped temporary, an assignment's drop, and an
  operator call (`eff_drop_temp`, `eff_drop_assign`, `eff_op_trait`).
- `p as NonNull<i64>` is described as "a checked conversion to an enum"
  (`eff_nonnull_cast`).
- `const F: fn(..) = at;` gives the help "a `static` holds other
  values: `static F: fn ...`", but a static holding a fn is then
  rejected ("'at' is not a constant").
- `sync.global` is reported twice per spawn when the closure's body has
  unknown effects (an assert).

## Not bugs (checked)

- Wrapping, division, shifts, conversions and the enum checks follow
  grammar.md at every level, constant and run time, except the
  narrow-signed float casts above.
- Every out-of-bounds index probed stops with the right message at
  every level. No range fact drops a check wrongly: `x % n` with a
  negative x, a wrapping `i + 1`, a missing lower bound, stale facts
  after the body or a callee shrinks the Vec, `debug requires`, and
  facts through a fn value all keep their checks.
- No effect inference hole was found through closures, fn values,
  traits, generics, drops, iterators, defer or C callbacks. Every bound
  probed is enforced except in the assert case above.
- requires and ensures are checked on every call form and return path
  probed.
