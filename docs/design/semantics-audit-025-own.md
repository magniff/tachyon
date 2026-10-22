# Semantics audit before 0.25: ownership (moves, drops, sink)

Branch `sem-own`, from `release-0.25` at 2476e990; the compiler is that
commit's head build (`volec 0.24.0`). Area: moves, drops and `sink`.

Every probe is a regression test, `tests/run/sem_own_*.vl` (367 programs).
A probe either expects a rejection (`// ERROR: own.…`) or prints its drops
(`// EXPECT`): the probes' owned type `D` prints `drop N` in its `Drop` and
owns a `Vec`, so a leak is a missing line and a double free is a repeated
line, also caught by `--check-alloc`. A finding is marked
`// XFAIL: CLASS one line`. Each program was checked with `volec check`,
run at -O0 and -O2, both with and without `--check-alloc`, and the suite
was run at `-O 0` and the default level (299 pass, 64 xfail, 0 fail at
both). The objects of the 198 runnable probes are byte-identical at -j1
and -j8, and no probe prints differently at -O0 and -O2: every finding
below behaves the same at both levels. The Linux valgrind row was not run:
`--check-alloc` reports every double free below with the lines where the
block was allocated, freed, and freed again.

## Findings

19 SOUNDNESS, 1 WRONG, 7 OVERSTRICT, 5 DIAG. Each finding names its test
in tests/run (`sem_own_` left out).

### SOUNDNESS: double frees and a use after free in safe code

1. **A field or tuple part of a Vec element moves out.** `w[0]` is
   `own.move_out`, but `w[0].f` and `w[0].1` are accepted, so the field
   is freed twice. The same code is refused through a slice (`s[0].d`),
   an array (`arr[0].1`) and `ww[0][0]`.
   - `eat(w[0].1)`: vec_elem_tuple_part;
   - `var x = w[0].v`: vec_elem_field_assign_out, elem_part_var;
   - `keep.push(w[0].v)`: elem_part_push;
   - `eat(w[0].d)`: elem_part_struct_field;
   - `fn f(w: Vec<D>) -> Vec<i64> { w[0].v }`: elem_field_return;
   - `P2 { v: w[0].v }`: elem_field_struct_lit;
   - `w[0].d.fin()` with `fin(sink self)`: elem_field_sink_self;
   - `let f = || w[0].v;`: borrow_closure_ret_field.

   ```vl
   var w: Vec<(i64, D)> = Vec::new_in(gpa);
   w.push((1, mk(1, gpa)));
   eat(w[0].1);                 // accepted; double free at w's drop
   ```
2. **The iterator stopgap misses `for` loops with a tuple pattern.**
   `for x in w.iter() { keep.push(x) }` is refused, but the same keep is
   accepted, and frees twice, with a tuple pattern:
   - `for (i, x) in w.iter().enumerate()`: stop_for_enum_keep;
   - `for (a, b) in w.iter().zip(w.iter())`: stop_zip_for_keep;
   - `for (k, v) in m.iter()` of a HashMap: stop_for_map_iter_keep;
   - `for (k, v) in m.iter()` of a BTreeMap: stop_btree_iter_for_keep.
   `for (i, d) in t.iter()` over a Vec of tuples is refused.
3. **The stopgap misses `keys()` and `values()` in a `for`.**
   - `for k in m.keys() { keep.push(k) }`, with owned keys: stop_keys_for_keep;
   - `for v in m.values() { r = Some(v); }`: stop_for_values_assign.
   `m.values().collect_in(gpa)` is refused.
4. **The stopgap does not cover HashSet.** HashSet's iter items are kept
   without an error:
   - `for k in s.iter() { keep.push(k) }`: stop_hashset_iter;
   - `s.iter().collect_in(gpa)`: stop_hashset_collect.
5. **`BTreeMap::first_key_value()` hands out a copy that can be kept.**
   Keeping it frees the value twice (stop_btree_first_kv). The other copying
   getters are refused when the copy is kept: `Vec::get`, `first`,
   `last`, `HashMap::get`, `value_at`, `key_at`, `BTreeMap::get`,
   `BTreeSet::first`, `BinaryHeap::peek`. They are accepted when the copy is
   only read.
6. **A user iterator that owns its data is consumed through a bit copy.**
   Iterator's provided methods (`count`, `collect_in`, `take`, …) take a
   let `self` and call `next(inout self)` on a bit copy. The consumer frees
   the copy, and the original is freed again at its scope end. With owned
   items the program prints garbage drops (`drop 184344310104192`) and
   aborts at -O0 and -O2. `for x in p` and `while let` are fine.
   - user_iter_count;
   - generic_user_iterator_collect;
   - generic_user_iterator_partial.

   ```vl
   struct Pop { v: Vec<i64> }
   impl Iterator for Pop { type Item = i64; fn next(inout self) -> Option<i64> { self.v.pop() } }
   let n = p.count();           // double free (abort at -O2)
   ```
7. **`x.drop()` is accepted, and the value is dropped again at its scope
   end.** Its `Drop` runs twice (drop_call_method). value-semantics.md
   §2.2 says it is an error with `try: drop(x)`; the roadmap lists that
   error as left over from 0.17. std's types survive the second drop
   (Vec's free is idempotent), but a user Drop runs twice.

### SOUNDNESS: leaks of owned values (safe, but "dropped exactly once" fails)

8. **A pattern that binds some owned parts leaks the parts it skips** with
   `_` or `..`:
   - `let (a, _) = t;`: tuple_wild;
   - `match b { E::B(_, x) => .. }`: enum_glue;
   - `if let E::B(x, _) = e`: iflet_partial;
   - `E::C { d, .. }`: enum_named_variant.
   A pattern that binds nothing (`E::A(_)`) drops the whole value.
9. **A `for` over an owned Vec temporary never drops the Vec.** Both the
   Vec and its items leak:
   - `for x in mkv(gpa)`: for_temp_vec;
   - `for x in v.take()`: for_vec_take.
10. **A `for` over an iterator of owned items never drops the items.**
    `for d in (0..2).map(|i| mk(i, gpa))` leaks every item
    (iter_owned_for, for_owned_break). `while let Some(d) = it.next()`
    drops them.
11. **`count()` and `filter()` drop nothing they discard.** `count()`
    leaks every item (iter_owned_count), and `filter()` leaks the items it
    rejects (iter_owned_filter). `find`, `any`, `position` and `take` are
    fine.
12. **A later argument's `?` leaks the owned arguments evaluated before
    it.** In `two(mk(1, gpa), g()?)`, the first argument leaks when the
    `?` returns early (try_in_arg).
13. **`Vec::set(i, x)` leaks the element it replaces**
    (drop_vec_pop_remove). It is probably the index-assignment leak below,
    inside std.
14. **A matched owned temporary is never dropped when no binding takes its
    payload.** `match me(gpa) { E::A(_) => .., E::N => {} }` leaks it
    (temp_match_scrutinee_unbound).
15. **A field moved out of a temporary leaks the temporary's other
    fields.** `let a = mp(gpa).a;` and `let b = mt(gpa).1;` leak the rest:
    0.24's `make().v` double-free fix now leaks instead
    (temp_return_field_of_call, temp_tuple_index_of_call).
16. **Owned operands of an operator are never dropped.** In
    `let c = mk(1, gpa) + mk(2, gpa);` with a let-parameter `Add`, both
    temporaries leak (add_owned_temps).
17. **An assignment through an index leaks the old element** (known since
    0.17, value-semantics.md §4):
    - `v[i] = x`: assign_elem_drops_old;
    - `a[i] = x` on an array: assign_array_elem_drops_old;
    - `s[0] = x` through `get_or_insert`'s `inout [V]` slot:
      hashmap_get_or_insert.
18. **`let _ = e` of an owned value never drops it** (known since 0.17,
    temp_let_underscore).
19. **A closure's sink parameter is never dropped** (the known leak). Its
    scope is every closure literal whose sink parameter the body does not
    move on:
    - `Option::map`: closure_byvalue_param_map;
    - `and_then`: leak_and_then;
    - `Result::map_err`: leak_map_err;
    - `unwrap_or_else`: leak_unwrap_or_else;
    - `fold`'s accumulator and its item: leak_fold_acc_replaced, iter_owned_fold;
    - `for_each`: iter_owned_for_each;
    - `map` over owned items: iter_owned_map_map;
    - a user `F: FnMut(sink D)` bound: closure_byvalue_param_generic.

    Not affected:
    - a named `fn` with a sink parameter passed where `Fn(sink D)` is
      wanted (closure_byvalue_param_fnptr);
    - a closure that moves its parameter on (closure_byvalue_param_moved_on);
    - a fold accumulator returned again (closure_byvalue_param_fold).

    Borrowed items given to such closures (`w.iter().for_each`,
    `m.values().fold`) are correctly not dropped
    (leak_borrowed_items_ok, leak_borrowed_map_fold_ok): those tests guard
    the fix.

### WRONG

1. **Owned temporaries given to a let parameter drop at the end of the
   enclosing block, not of their statement.** Examples are
   `let n = add(mk(1), mk(2));`, `peek(mk(5));` and `println(f"{add(..)}")`.
   This breaks value-semantics.md §2.2 ("temporaries drop at the end of
   their statement") and 0.20's release note ("arguments to let parameters
   (generic too)"). tests/run/own_temps.vl tests only sink parameters.
   - temp_nested_calls;
   - temp_nested_calls_scope.

### OVERSTRICT

1. **An `impl From<T>` cannot keep an owned argument** (from_owned).
   `From::from(x: T)` takes `x` let, so `W { d: x }` is own.move_out, and
   an impl writing `x: sink D` is refused as not the trait's signature.
   `W::from(mk(1))` is "this value has no place".
2. **`collect_in` cannot infer `A` after `zip` or a BTreeMap's `iter()`.**
   `let w: Vec<(D, D)> = a.zip(b).collect_in(gpa)` is "cannot infer type
   parameter 'A' of 'Zip::collect_in'", though `Map` and `Enumerate`
   infer it (iter_owned_zip).
3. **A closure that reads only `p.a`, after `p.b` moved, is own.moved**
   (flag_closure_partial). Rust 2021 captures the field alone.
4. **A sink closure cannot move a field of a capture out**
   (borrow_sink_closure_ret_field). The guide says such a closure may move
   a whole capture out.
5. **A sink closure literal given to a let `F` parameter is refused.** Two
   cases: `run(sink || d.id)` with `F: Fn() -> i64`
   (closure_temp_to_let_param), and `(0..2).map(sink |i| i + d.id)`
   (map_sink_closure_count). The error is "expected 'let closure() ->
   i64 at …', got 'closure() -> i64 at …'".
6. **A destructured closure item over a borrowing iterator is refused**
   (stop_ok_enum_map_destructure). In `w.iter().enumerate().map(|(i, d)|
   d.id + i)` only `d` is read. This is the breadth 0.24 documents.
7. **A closure parameter cannot be annotated `sink`.** `|d: sink D|` is
   conv.sink_type (closure_byvalue_param), so a closure takes ownership
   only through an `Fn(sink T)` bound.

### DIAG

1. **conv.sink_type's text is wrong for a closure parameter.** On `|d:
   sink D|` it says "'sink' is a parameter's convention: a field or a
   result of type T owns its value already", but `d` is a parameter
   (closure_byvalue_param).
2. **A bound's `sink` is dropped from the message.** `w.iter().map(idof)`
   with `fn idof(d: D)` says "'fn(let D) -> i64' does not satisfy the
   bound 'F: FnMut(D) -> i64'", but the bound is `FnMut(sink D)`
   (stop_ok_map_named_fn).
3. **own.move_out on a destructured closure parameter shows internals.**
   It names `'{param0}'` (an internal name), and its `try:` writes
   `|(i, d).clone()|`, which does not parse
   (stop_ok_enum_map_destructure).
4. **`ma(gpa)[1]` uses a C word and a `try:` that does not fix it.** It is
   "cannot take address of non-lvalue expression" with `try: let t =
   ma(gpa)[1]; let b = &t;` (temp_array_index_of_call).
5. **Keeping an `iter_ref()` item advises `*`, which vole does not have on
   accesses.** It is "expected 'D', got 'let D' | help: it is a reference:
   read through it with '*' | try: *x" (slice_iter_ref_keep).

## Coverage: rule × context

`ok` means probed and held. `F#` names a finding above (S = SOUNDNESS,
W = WRONG, O = OVERSTRICT). `-` means not applicable or not probed. A
rejection that should happen and happens counts as ok.

| rule \ context | locals | fields | Vec/array elements | tuples | enums, Options | let/inout/sink params | receivers (`sink self`) | generics, traits | closures, `sink \|\|` | loops | `?`, early return | match, if let | temporaries | threads |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a move transfers ownership; the source is dead (own.moved) | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| a partial move leaves the rest dropped once | ok | ok | S1 | ok, S8 | S8 | ok | ok | ok | O3, O4 | - | ok | S8 | S15 | - |
| no move out of a borrow, an element or an access (own.move_out) | ok | ok | ok (whole), S1 (part) | ok | ok | ok | ok | ok, O1 | ok | ok | - | ok | - | - |
| every owned value dropped exactly once at scope end or when consumed | ok | ok | ok, S17 | ok | ok | ok | ok, S7 | ok, S6 | S19 | S9, S10, S11 | ok, S12 | S14 | S15, S16, S18 | ok |
| drop order: reverse declaration; fields, tuples, arrays in order; Drop before its fields' glue | ok | ok | ok | ok | ok | ok | - | ok | ok | ok | ok | ok | W1 | - |
| drop flags (a value moved on some paths) | ok | ok | - | ok | ok | ok | - | - | ok | ok | ok | ok | - | - |
| assignment drops the old value (after the right side) | ok | ok | S13, S17 | ok | ok | ok (inout) | - | ok (replace, swap) | ok | ok | - | ok (`match &x`) | - | - |
| sink parameters, `sink self` and returns move | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| `clone` gives an independent value | ok | ok | ok | - | ok | - | - | ok (derive) | - | - | - | - | - | - |
| iterator items stay borrowed: keeping one is own.move_out | - | - | S2–S5 | S2 | - | - | - | S6 | O6 | S2, S3 | - | - | - | - |

## The iterator stopgap, in detail

Refused, as it should be:
- `collect_in`, `filter`, `take`, `map(|x| x)` and `map(|x| (x, 1))` over
  `w.iter()`;
- `find` and `next().unwrap()` kept;
- `fold` pushing into the accumulator;
- `values().collect_in`, `keys().collect_in`, `w.as_slice().iter()`;
- `for x in w.iter()` (or `for x in w`) keeping, sinking, dropping,
  assigning or putting into a tuple;
- `for (i, d) in t.iter()` over a Vec of tuples;
- a named sink `fn` given to `map`;
- the generic versions (`fn gcollect<T>(s: [T]) -> Vec<T>`, `gkeep`,
  `s[0]`, `v.get(0)` instantiated with `D`).

Accepted, as they should be (stop_ok_*): reading through `map`, `filter`
+ `count`, `any`, `fold` summing, `for` reading, `for (i, d) in
….enumerate()` reading, `m.values()` reading, and `iter_ref().map(|x|
x.clone())`.

Missed: findings 2–5 above.

Too strict: O6, and a let fn given to `map` (DIAG 2).
