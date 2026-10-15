# tachyon 0.17 design: memory safety by mutable value semantics

I read the language from `/Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15` (release-0.15) using `tachyonc guide memory|unsafe|types`, `query show/items/grep/refs`, `try`, docs/grammar.md ("Indexing", "Undefined behaviour", "Additions of 0.9", "Escape"), docs/optimizer.md, the commits c51304d/7229534 (the index-order fix), docs/design/closures-iterators.md and errors-formatting.md. The decided 0.16 design comes from `/Users/magniff/workspace/tachyon/.claude/worktrees/design-016/docs/design/effects-allocation.md`. I modified nothing.

## 1. Current state and every known safety gap

**What exists.**
- Every `=`, argument and return copies bits; nothing moves.
- `Vec<T> {ptr,len,cap}`, `Buf` and `HashMap` are handles. `Vec::free` is safe: it frees, then nulls the handle.
- There are no destructors. `defer v.free()` is the idiom: 131 of the 156 `.free()` lines in tests are `defer x.free()`.
- Tachyon has one pointer type, `*T`. A *borrow* is `&place` written directly as an argument, or a non-`mut` pointer parameter, and dereferencing one is safe. A pointer held anywhere else (a local, a field, a call result) is raw and needs `unsafe`. So `*T` references are already second-class *across* calls.
- Slices `[T]` are first-class. They are writable and need no `mut`. They are stored freely: `Scanner { text: [u8] }`, `SliceIter { s: [T] }`, `split() -> Vec<[u8]>`, `HashMap<[u8], i64>`, `HashMap::get_mut -> Option<[V]>` (a one-element view).
- Closures that capture by reference are confined by 0.14's scope-escape check. Borrowed locals keep their frame slot for the whole function.
- 0.16 adds `Vec<T, A: Allocator = Gpa>`, `Arena`, `ScopedArena` (`#[scoped]`, rules S2/S3), `FixedBuf`, `#[sealed]` and `--check-alloc`. It makes `Arena::reset`/`free_all` `unsafe fn`, and lists four gaps under "waits for 0.17".

**The gaps (all are undefined behaviour in safe code today):**

| # | gap | example |
|---|---|---|
| G1 | named view after growth or free | `let s = v.as_slice(); v.push(1); s[0]` (also `get_mut`, `get_or_insert`, `read_line` into a Buf you hold a view of) |
| G2 | unnamed views | `take(v.as_slice(), grow(&v))`; `v.as_slice()[grow(&v)]`; `for x in v { v.push(x) }`; `let it = v.iter(); v.push(1); it.next()`; std's `extend_from_slice` survives `v.extend_from_slice(v.as_slice())` only by a special case |
| G3 | a borrow dangling through a sibling argument | `f(&s[0], &v)`, where `f` pushes to `v` and then writes `*x` (`&s[i]` is a borrow, "a checked element") |
| G4 | copied handles | `let w = v; v.free(); w.as_slice()[0]` (use after free); `w.free(); v.free()` (double free); a struct holding a Vec copied and both copies freed; `Vec::filled(n, inner)` gives n handles to one buffer |
| G5 | views outliving their owner | `fn f() -> [i64] { let a = [1,2]; a[..] }`; `fn g() -> [u8] { let b = format(x); defer b.free(); b.as_slice() }`; a `Scanner`/`split` result kept after its text is freed; `Fmt::to_buf(&b)` returned out of `b`'s block (std stores the borrow as a raw field) |
| G6 | arenas (0.16's list) | views into reset or freed arena memory; a slice returned out of `arena_scope`; `FixedBuf` over a dead stack array |
| G7 | views of statics across calls | `let t = TYPES.as_slice(); intern(..); t[i]`, with `intern` growing `TYPES`. This is the compiler's own bug class (7229534, agents.md §6), reachable from safe code once 0.16 lets statics hold Vecs |
| G8 | copyable unsafe abstractions | any plain struct of raw pointers with safe growing methods (the compiler's `IntVec`): copy it, grow one copy, and the other dangles. The language has no rule for this |

Not a gap: frame slots (pinned) and closures (escape-checked).

## 2. The model (decided)

### 2.1 Three kinds of types, computed structurally

| kind | definition | `=` / pass by value | examples |
|---|---|---|---|
| **plain** | numbers, bool, fieldless enums, fn pointers, raw `*T`; arrays, tuples, structs and enums of plain types | bit copy (as today) | `Point`, `[i64; 4]`, `Node {left: *Node, ..}` |
| **owned** | has a `Drop` impl, or a part that is owned | **move**; `.clone()` copies | `Vec<T>`, `Buf`, `HashMap`, `Arena`, `struct Inv { items: Vec<Item> }` |
| **view** | holds a slice, a reference (`&T`, `&mut T`), a closure capturing by reference, a `#[scoped]` type, or a part that is a view | copy (`&mut` and `&mut [T]`: move) but **second-class** (§2.4) | `[u8]`, `Scanner`, `SliceIter<T>`, `Map<SliceIter, C>`, `Fmt`, `Vec<[u8]>` (owned *and* a view) |

There is no `Copy` derive. "Plain" is structural, so a struct copies if and only if it owns nothing. `Copy` exists as an intrinsic bound (`T: Copy` holds for plain T) so that a template can state it. The kind is memoized per type id, like 0.14's `type_borrow`, and `query` shows it: `struct Inv  owned (Vec<Item> at .items)`.

### 2.2 Moves, copies, Drop

- **Moves.** `let y = x`, a by-value argument, `return x`, a struct literal field, and a `move` capture all move an owned value. The source is dead until it is reassigned. Moving out of a field is allowed (a partial move) unless the struct has `Drop`. Moving out of an index, `*r`, a static or a borrowed parameter is an error with `try:` lines: `v.remove(i)`, `std::take(&mut v[i])`, `std::replace(..)`, `.clone()`.
- **`Drop`.** `trait Drop { fn drop(self: &mut Self); }` is in the prelude. A type without an impl gets field-wise *drop glue*. Calling `x.drop()` directly is an error (`try: drop(x)`). `std::drop(x: T)` consumes. `std::forget(x)` is safe: leaks are not UB, and `--check-alloc` lists them. **A view type may not implement `Drop`.** This removes Rust's dropck problem: no destructor can read a view whose owner died first.
- **When drops run.** At scope end, in reverse declaration order, interleaved with `defer`s as if each owned `let` registered one. They run on every exit: block end, `return`, `break`, `continue`, `?`.
  - They do not run on `exit` or a failed check (exit 101), which is today's defer rule.
  - Temporaries drop at the end of their statement.
  - Assigning an owned place evaluates the right side, drops the old value, then writes (the grammar's existing order).
  - A conditionally moved local carries a drop flag.
  - Statics are never dropped.
- **`free`.** `v.free()` becomes `fn free(self: Vec<T>)`, which consumes, so a second free or a later use is a use-after-move error. It stays as a deprecated alias of `drop`. `defer v.free()` stays legal (a deferred consumption cancels the implicit drop), and `fix --values` deletes it.
- **Moves cost nothing new.** A move is the same bit copy that today's handle copy is. The only new code is the inlined destructor that replaces the hand-written free.

### 2.3 References and parameters

U1 decides the spelling. The recommendation, used below, is Rust's:

- `x: T` takes by value: a move for owned types, a copy for plain ones.
- `x: &T` is a shared reference; the call site is `f(&v)`.
- `x: &mut T` is an exclusive reference; the call site is `f(&mut v)`. This is the roadmap's `inout`.
- Method receivers (`self: &T`, `self: &mut T`, `self: T`) are referenced automatically, as now. A `&mut self` receiver is a *two-phase* borrow: it is taken when the call happens, after the arguments are evaluated. So `v.push(v.len())` is fine, and `v.extend_from_slice(v.as_slice())` is an error.
- Fields and methods go through references automatically, as with `p.f` today. Values need `*r`.
- **`&place` in any position is now a tracked reference.** `let r = &x;` is safe and checked; today it is a raw `*T`. A reference converts to a raw `*T` implicitly wherever `*T` is expected, which is safe because raw dereference stays unsafe.
- **Legacy `*T` parameters.** A non-`mut` `p: *T` parameter of a safe function is accepted through 0.17 as `&mut T` and checked as one. The bootstrap needs this: 0.17's compiler source is compiled by 0.16, which has no `&mut`, and it uses `*IntVec`/`*i64` parameters about 540 times. `fix --values` rewrites them. From 0.18, after the compiler has migrated, `*T` parameters are raw.

### 2.4 Views: second-class, with origins and no lifetime syntax

Every view value has an **origin**: the set of loans it may point through. A loan is a place (a local or static plus a field path; indexes collapse to their base) and a kind (shared or mut). The empty origin ∅ is for string literals, constant and static data, and slices made in unsafe code (the unsafe author vouches, as Rust's unbounded lifetimes do).

**Where views may go:**
- Locals, parameters, temporaries, and other view types, so containers of views are allowed: `Vec<[u8]>` and `HashMap<[u8], i64>` are views of their keys' text.
- Statics hold only ∅ views.
- A value whose origin includes a loan on local `x` cannot outlive `x`, and `x` cannot be moved, dropped or conflictingly accessed while that value is live. This subsumes 0.14's closure-escape rule and 0.16's S2/S3.

**The signature rule ("one region").** No lifetime is ever written.

- *Caller side.* A call's result, and anything the call may store into its `&mut` arguments, has as origin the union of:
  - a loan on every place passed by reference (`&x` or `&mut x`, of the reference's kind);
  - the origins of every view passed or referenced.

  After the call, each `&mut` argument whose referent holds views gains that union.
- *The pure-view exception (Swift's `copy` vs `borrow` dependence).* When the referent is a *pure view* (a view type that owns nothing: `Scanner`, `SliceIter`, `Fmt`), the result takes on the referent's origins without borrowing the referent itself. So this works:

  ```tach
  let a = sc.next_token();
  let b = sc.next_token();
  ```

- *Callee side.* What the body returns, or stores into a `&mut` argument's views, must have an origin inside the region: the parameters' referents and the views it was given. Pointing into a callee local is the error `own.escape` ("returns a view of 'buf', which is dropped when 'make' returns"). For pure-view parameters, the result may carry only the views they hold, not point into the parameter itself.

**Returning views and projections (decided).**
- `fn first_word(s: [u8]) -> [u8]` and `fn as_slice(self: &Vec<T>) -> [T]` are allowed in 0.17.
- `fn first(v: &Vec<T>) -> &T` and `fn get_mut(self: &mut HashMap<K, V>, k: K) -> Option<&mut V>` (references as results and as type arguments: Hylo's projections, Rust's elided `&self -> &T`) follow the same rule. They come in 0.17.1, because they need reference types as type arguments. Until then, std keeps its one-element `[V]` views, now checked.
- `Vec` and `Buf` get `v[i]` and `v[a..b]` as places (they are not indexable today), with the same two-phase rule as receivers.

**Slices (U2, recommended).** `[T]` (and `&[T]`, the same type) is a shared, read-only view. `&mut [T]` is the exclusive, writable one: `sort(s: &mut [T])`, `v.as_mut_slice()`, `&mut a[..]`.

**Exclusivity.** Aliasing XOR mutation, checked within one function, with live ranges ending at the last use (NLL-style, not lexical scopes):
- While a shared loan on P is live, nothing may write, move or drop P, or take `&mut` of any place overlapping P.
- While a mut loan is live, P is reachable only through it.
- Disjoint fields don't overlap; `v[i]` and `v[j]` do.

Consequences:
- `f(&mut a, &a)` is an error ("'a' is borrowed mutably by argument 1 and read by argument 2"). `f(&mut a.x, &a.y)` is fine.
- `f(&mut v[i], &v[j])` is an error. The help names `v.swap(i, j)`, or copying a plain value out first.
- **Iterator invalidation.** `for x in v` holds a shared loan on `v` for the whole loop, so `v.push` inside it is an error. Over plain elements `x` is a copy, as today; over owned elements `x: &T`. `for x in &mut v` (`iter_mut`, 0.14's open question 4) yields `&mut T`. `for x in v.into_iter()` consumes.
- **Unnamed views.** G2's cases are errors at the growing call, which names the view and the use that keeps it alive.
- **Statics.** A view of a static S has the origin "static S". It is invalidated by writes to S and by any call whose 0.16 effects include `global`.
  - Passing `&S` or `&mut S` to a function with `global` is an error, because noalias would be a lie.
  - 0.17.1 refines `global` into written-static sets (a bitmask, like 0.16's `allocs`), which makes this precise. It also lets a function return a view of statics, the statics it views inferred and shown like effects (`-> [u8] views NAMES`).
- **Closures.** A closure capturing by reference holds shared or mut loans while it is live. `move` moves owned captures. 0.14's rule that an immutable binding is captured by copy applies to plain values only; an owned immutable binding is captured by shared reference.

### 2.5 Allocators and arenas (0.16)

- An owned container carries its allocator (`alloc: A`), and its drop glue frees through it. `Gpa` is zero-sized, so `Vec<i64>` drop is today's `free`, inlined.
- **Arena handles become references (U3, 0.17.1).** `Arena` is owned (its `Drop` frees the chunks), and containers use `Vec<T, &Arena>`: 8 bytes, the same representation as 0.16's handle.
  - A container on an arena is a view of it, so it cannot outlive the arena.
  - `arena.reset()` and `free_all` take `&mut self`, so they are **safe**: they are legal only when nothing views the arena.
  - `#[scoped]` becomes "a view type". `ScopedArena`/`arena_scope` remain as sugar.
  - `FixedBuf::new(&mut buf[..])` is a view of `buf`, which closes G6's stack case.
- **Values in an arena skip per-value destruction.** `Vec<T, &Arena>` drop calls `Arena`'s `free`, an empty `#[inline]` function. The element loop is guarded by `std::needs_drop::<T>()`, a constant, so the whole drop disappears even at -O0.
- Effects still name types: `alloc(Arena)`. 0.16's U2 (value-level naming, `alloc(a)`) becomes cheap through origins; it is planned for 0.17.1.

### 2.6 C interop and unsafe

- Raw pointers are unchanged and remain the escape hatch, checked by `--check-unsafe` and `--check-alloc`.
- A reference passed where an extern expects `*T` converts implicitly; exclusivity is still checked at that call.
- An owned type in an extern signature, or as a by-value field of a `#[repr(C)]` struct passed to C, is an error ("Vec<i64> owns memory; pass v.as_ptr() and v.len()"). `#[repr(C)]` with `Drop` is allowed on the tachyon side.
- Callbacks take raw pointers. `longjmp` over frames that drop is UB, the same contract as for defers.
- Unsafe code must not create a second live alias of a place under `&mut`; this is documented in the unsafe contract. G8 becomes a rule: a type whose safe methods manage memory through raw pointers must implement `Drop`, which makes it owned and move-only. The guide says so, and a lint flags safe methods that write through raw fields of a plain struct.

### 2.7 Generics, traits, `?`, defer, f-strings, match

- **Generics.** They are checked per instance, as now, so moves and drops are decided per instance. Errors carry the "in instantiation of" note. `Copy`/`Clone` bounds let templates state intent, and `Vec::filled(n, x)` requires `T: Clone`.
- **Traits.** Trait methods declare receivers as `&Self`, `&mut Self` or `Self`. Derived `Clone` (0.15) becomes the deep copy. `Eq`/`Ord`/`Hash` take `&Self`, as they already take `*Self`.
- **`?`.** It desugars to a `return` (0.15), so pending drops run. Moving the error into `From` is a move.
- **`defer`.** Defers and drops share one exit list. A `defer` body that uses a local is checked at every exit, against the join of the exit states.
- **f-strings.** The holes are shared borrows: the `Interp` closure is a view. `println(f"{v}")` is free. `let m = f"{v}"; v.push(1); println(m)` is an error with "format(...) it to a Buf, or build it after the push".
- **`match`.** Matching an owned place moves the bindings out (a partial move). Matching `&x` binds `&T` for owned parts and copies for plain ones, as Rust's default binding modes do. Today's "bindings are copies" stays true for plain types.
- **`main -> Result`.** Its body closure drops before the error is printed.

### 2.8 Alternatives considered

- **Rust lifetimes.** They buy:
  - several independent regions in one type (`Parser<'src, 'arena>`);
  - results that borrow a subset of the arguments (`longest<'a>(x: &'a str, y: &str)`);
  - long-lived reference graphs in heaps (`&'arena Node`).

  Their cost is annotations, variance, higher-ranked bounds, error messages agents misread, and region inference. With one region per signature and inferred origins inside bodies, the loss shows up as occasional false conflicts. The fixes are a clone or an index, or else indices and raw pointers for reference graphs. A narrowing attribute (`#[views(a)]`) is kept in reserve, to add only if the corpus asks for it.
- **Swift (CoW + ARC + exclusivity).** Its copies are implicit and cheap, but cost reference counting and uniqueness checks on every mutation. That is rejected: copies stay explicit. Swift's exclusivity, and its `~Escapable` copy/borrow dependence, are adopted.
- **Hylo (pure MVS: `let`/`inout`/`sink`/`set`, subscripts).** The semantics are adopted: second-class references and projections. The spelling is U1's alternative. Hylo's `let` bindings, which are borrows rather than moves, were rejected as surprising next to Rust habits.
- **Mojo.** Its origins are close to ours, but parametric. ASAP destruction (drop at last use) was rejected: destructor timing must be readable in the text, and scope-end drop with NLL liveness for *views* gives the same freedom where it matters.
- **Vale's generational references.** They make every dereference a run-time check plus a 64-bit generation per allocation. They violate "zero-cost", but they remain the model for `--check-alloc`.
- **Austral linear types.** "Must consume" would make every early return name every value. Affine types with automatic drop are kept.
- **Tachyon-specific relaxations.**
  - Shape-versus-content writes: plain element writes allowed while views are live. Rejected: two notions of "write", weaker optimizer facts, and agents already know aliasing XOR mutation.
  - Inferring each pointer parameter's mutability from the body: changing a callee body would break its callers silently. Rejected.

## 3. Before and after

**1. wordcount (bench/wordcount.tach): views into the text, no frees.**

```tach
// before (0.15)
fn next(state: *u64) -> u64 { *state = *state * 6364136223846793005u64 + 1442695040888963407u64; *state >> 33 }
...
let s = text.as_slice();
let mut counts: HashMap<[u8], i64> = HashMap::new();
... counts.insert(s[start..i], c + 1); ...
counts.free();
text.free();
```

```tach
// after (0.17)
fn next(state: &mut u64) -> u64 { *state = *state * 6364136223846793005u64 + 1442695040888963407u64; *state >> 33 }
...
let a = next(&mut state) % 4096u64;
let s = text.as_slice();                          // a view of text
let mut counts: HashMap<[u8], i64> = HashMap::new();
... counts.insert(s[start..i], c + 1); ...        // counts now views text
0
}   // counts dropped, then text: reverse order, so the view goes before its owner
// text.push(b' ') after the counting loop, while counts is used later:
// wc.tach:52:5: error[own] 'text.push' may move text's bytes while 'counts' (keys from s[start..i] at 44:27) views them; used at 60:9
// help: finish with 'counts' first, or keep owned keys: 'HashMap<Buf, i64>' with 'Buf::from(w)'
```

The generated code is the same as today's. The `free` calls come from drop glue, inlined.

**2. A struct owning containers: G4 closed.**

```tach
// before
struct Item { name: Buf, qty: i64 }
struct Inventory { items: Vec<Item> }
impl Inventory {
    fn add(self: *Inventory, name: [u8], qty: i64) { let mut b = Buf::new(); b.push_str(name); self.items.push(Item { name: b, qty: qty }); }
    fn total(self: *Inventory) -> i64 { self.items.iter().map(|it| it.qty).sum() }
    fn free(self: *Inventory) { for it in self.items.iter() { let mut n = it.name; n.free(); } self.items.free(); }
}
let mut inv = Inventory { items: Vec::new() };
defer inv.free();
let snap = inv;          // shares the memory: a later push to inv is lost to snap, and freeing both is a double free
```

```tach
// after
#[derive(Clone)] struct Item { name: Buf, qty: i64 }
#[derive(Clone)] struct Inventory { items: Vec<Item> }       // owned; drop glue, no code written
impl Inventory {
    fn add(self: &mut Inventory, name: [u8], qty: i64) { self.items.push(Item { name: Buf::from(name), qty }); }
    fn total(self: &Inventory) -> i64 { self.items.iter().map(|it| it.qty).sum() }   // it: &Item
}
let mut inv = Inventory { items: Vec::new() };
let snap = inv.clone();  // explicit deep copy; 'let snap = inv;' would move inv
inv.add("nut", 10);
println(f"{snap.total()} {inv.total()}");
```

**3. Iterator invalidation and unnamed views (G1–G3).**

```tach
for x in v { if x % 2 == 0 { v.push(x / 2); } }
// e.tach:2:30: error[own] 'v.push' may move v's elements while the 'for' at 2:1 iterates over them
// help: collect first: 'let extra: Vec<i64> = v.iter().filter(|x| x % 2 == 0).map(|x| x / 2).collect();' then 'v.extend_from_slice(extra.as_slice())'
take(v.as_slice(), grow(&mut v));
// e.tach:5:20: error[own] 'grow(&mut v)' changes v while the view 'v.as_slice()' (5:6) waits for 'take'
// try: let k = grow(&mut v); take(v.as_slice(), k);
fn bad(xs: &mut Vec<i64>, first: &i64) { xs.push(1); println(f"{*first}"); }
bad(&mut v, &v[0]);
// e.tach:9:13: error[own] 'v' is borrowed mutably by argument 1 and read by argument 2
```

**4. Arenas (0.16 to 0.17.1, with U3).**

```tach
// 0.16
fn round(d: i64) -> i64 {
    arena_scope(|s: ScopedArena| { let mut t: Vec<Node, ScopedArena> = Vec::new_in(s); build(&t, d); check(t.as_slice()) })
}
// 0.17.1
let mut arena = Arena::new();
for d in 4..17 {
    let mut t: Vec<Node, &Arena> = Vec::new_in(&arena);
    build(&mut t, d);
    total += check(t.as_slice());
    arena.reset();         // safe: t's last use is above; its drop is a no-op
}
// with 'let keep = t.as_slice();' used after the reset:
// error[own] 'arena.reset()' frees memory that 'keep' (12:9) views; used at 15:5
```

**5. The compiler's table style.** It stays legal as unsafe raw code; the 0.18 safe form is below.

```tach
// today
static mut TYPES: *Type = 0 as *Type;  static mut TYPE_COUNT: i64 = 0;  static mut TYPE_CAP: i64 = 0;
fn add_type(t: Type) -> i64 { unsafe { TYPES = grow(TYPES, TYPE_COUNT, &TYPE_CAP); TYPES[TYPE_COUNT] = t; } TYPE_COUNT += 1; TYPE_COUNT - 1 }
let a = unsafe { TYPES[template_instance(s, args)].a };   // the 0.14 bug: TYPES was read before the call grew it
```

```tach
// 0.17 rules (0.18 compiler)
static mut TYPES: Vec<Type> = Vec::new();               // 0.16 constant constructor
fn add_type(t: Type) -> i64 { TYPES.push(t); TYPES.len() - 1 }    // safe
let a = TYPES[template_instance(s, args)].a;            // defined: the index first, then the place (0.14 order)
let t = &TYPES[i];
let j = template_instance(s, args);
// types.tach:41:9: error[own] 'template_instance' writes statics (global) while 't' (40:9) views TYPES; used at 42:13
// help: copy the plain value first: 'let t = TYPES[i];' (Type is plain)
```

In 0.17 the static check is coarse (any `global`). 0.17.1's written-static sets make it exact (`intern`, which writes only SYMS, stops conflicting). Index handles plus plain copies stay the recommended table style. After inlining, SROA reduces `TYPES[i].a` to one load.

## 4. Checker algorithm, cost, optimizer

**Where: on the typed AST, not a MIR.**
- `check` is front-end only (79 ms on the compiler, about 45 ms of it in the checker; 7 ms warm), and the tools need these errors without lowering.
- Errors need source spans and the "used at" secondary positions.
- Tachyon's control flow is structured: blocks, if, match, loop/while/for, labeled break/continue, return, `?` (a desugared return), defer.
- 0.16's effects pass made the same choice. A MIR would duplicate middle/lower and cost compile time.
- Expressions are linearized per statement in the grammar's documented evaluation order: left to right, the right-hand side before the place, the index before the base is read, two-phase receivers. That gives an exact access sequence.

**Pass `front/own/` (per checked body: items, generic instances, closures).**
1. *Kinds.* `KIND[type]` bits (PLAIN, OWNED, VIEW, PURE_VIEW, NEEDS_DROP), memoized. The model is `closures::escape::type_borrow`.
2. *Places.* Interned per function: a local or static plus a field path; indexes collapse; usually fewer than 64. *Loans*: one per borrow site (`&`, `&mut`, auto-ref, a call result by the signature rule).
3. *Backward liveness* of view-holding locals, a structured walk with loops iterated to a fixpoint. It records each local's next use for diagnostics.
4. *Forward walk.* The state is `init`/`maybe` bitsets over places, plus an origin bitset per view local.
   - if/match joins: `init` by AND; `maybe` and origins by OR.
   - Loops iterate until the head state is stable (monotone bitsets, at most 3 rounds in practice).
   - break, continue and return feed their target's accumulator.
   - Every access is checked against the live loans; every move against `init`; every exit records which owned places are definitely, maybe or not initialized.
   - At most one error per place, so there is no cascade.
5. *Drop elaboration, as AST desugaring.* At each owned `let` (and each owned temporary, hoisted into a hidden `__tN` let in a statement block), insert an implicit `Defer` node:
   - `drop_in_place(&mut x)` when x is initialized at every exit;
   - nothing when x is moved at every exit;
   - otherwise guarded by a hidden `bool` flag, cleared at each move.

   Assigning an owned place becomes `{ let __n = rhs; drop_in_place(&mut p); p = __n }`. Because both back ends already lower `defer` on every exit path (middle/lower/control.tach `lower_defers`, gen0), **no back-end change is needed**.
6. *Ordering with 0.16.* Steps 1–5, then `infer_effects()` (it sees the drop calls, so a function that drops a moved-in Vec has `alloc(Gpa)`), then a small post-pass. The post-pass checks the recorded "view of static S live across call c" pairs against c's effects.

**Cost.** Linear in nodes, times bitset words; no region variables and no constraint solving. Budget: 4 ms on the compiler's check (5%); the prototype measures it. Templates and unused lazy std functions cost nothing.

**Tools.**
- `query own FILE:LINE:COL` gives each local's state ("moved at 12:9 by `consume(v)`") and the live views with their origins and next uses.
- `query def` and `show` print the kind and, from 0.17.1, "views".
- Diagnostics use the codes `own.moved`, `own.conflict`, `own.escape`, `own.static`, `own.drop_view`, `own.partial` with `explain` entries, one line plus `help:`/`try:`. The query cache stores kinds per Def.

**Optimizer work for zero cost.**
1. *Moves.* Move copies are flagged `COPY_MOVE`. copies.tach's "source used only before the copy" then holds by construction, so it skips the use scan and also elides copies inside loops. NRVO: a returned local is merged with the sret slot.
2. *Passing.* A large plain by-value parameter, and a moved-in owned parameter, are passed by the caller's slot address with no copy: exclusivity guarantees nothing writes the slot during the call.
3. *Drops.* std's `drop` impls are `#[inline]`, and drop glue is a generated `#[inline]` function per type. `needs_drop::<T>()` folds at type-check time. Drop flags are SROA'd and constant-folded away. At -O0, gen0 emits flags only for maybe-moved locals.
4. *Aliasing (U2).*
   - A `&mut T` or `&mut [T]` parameter is its own memory object in gvn's `may_alias`: distinct from every other parameter, static and heap pointer.
   - `&T` and `[T]` parameters are read-only for the call, so their loads are hoisted across stores and calls without `global`.
   - The vectorizer drops its run-time overlap checks between a `&mut [T]` and other slices (stencil, matmul, sort).
5. *heap_to_stack.* It keeps working, because Gpa's free inlines to `free`.

**Gate.** bench/ within noise at -O2 (wordcount, json, sort, binarytrees, iterchain, fmtloop); -O0 within +3%; self-compile within +2%.

## 5. Migration: `tachyonc fix --values`

**Rules, each typed and checked like any edit:**
1. Delete `defer X.free();` when X is an owned local of the same block. Mid-scope, `X.free();` becomes `drop(X);` when X is not used later, else `X = Vec::new();` (the old meaning: an empty, reusable handle).
2. `p: *T` or `self: *T` in safe functions becomes `&mut T` when the function writes through p (transitively, through the callees' rewritten signatures, computed as a fixpoint over SCCs), else `&T`. Call sites `&x` become `&mut x` for `&mut` parameters.
3. Slice parameters that are written become `&mut [T]`. Call sites: `v.as_slice()` becomes `v.as_mut_slice()`, `a[..]` becomes `&mut a[..]` (U2).
4. Handle copies:
   - `let w = v;` with v used later becomes `let w = &v;` when w is only read, else `v.clone()`. A clone is reported for review, because the old shared-buffer meaning cannot be preserved.
   - By-value owned parameters that the callee only reads become `&T`, with the call sites changed to `&v`.
5. `Vec::filled(n, x)` with an owned x gets `#[derive(Clone)]` on the element type.
6. A struct holding slices that must outlive its source (returned without view parameters, stored in a static): the field becomes `Buf`/`Vec<T>` with `Buf::from(s)` or `.to_vec()` at the literals, when every value assigned to it is a slice. Literal-only (∅) fields stay as they are.
7. No auto-fix (exact diagnostics instead): conflicts and invalidation (an index loop or collect-then-extend is suggested), views of statics, partial moves out of Drop types.

**Expected volume** (grep counts over tests/, `query grep --count` elsewhere):

| corpus | mechanical | likely by hand |
|---|---|---|
| tests (666 files, 61 of them agent-eval) | 131 `defer x.free()` and 25 other frees (62 files); 268 `self: *` receivers (87 files) and 412 `*T` parameters (127 files), optional in 0.17 because of the legacy rule; 228 `as_slice()`, mostly unchanged | 15–30 cases: handle-sharing tests and guide memory's `lost()`, `index_order` (static views re-taken after growth become errors or unsafe), 17 structs with slice fields (most stay local views), the 59 `.iter()` loops that push; plus about 40 err-test outputs regenerated |
| bench + examples (26 files) | 34 frees (httpd 10, iterloop 3, iterchain 3), 33 `self: *` | about 2 (httpd's buffers) |
| agent-eval reference solutions | 81 frees | a few, re-run under the eval |
| compiler/src (95k lines) | 16 `self: *`; 56/32/34 refs to Vec/Buf/HashMap | a handful of Vec handle copies, fixed with 0.16-compatible code (`.clone()`, restructuring). The raw `static mut` tables (1120 statics, 3031 `unsafe`, 248 `*IntVec`, 164 raw `free(`) are untouched; the compiler moves to MVS in 0.18 as the roadmap says |

## 6. Prototype first, then the phases

**Prototype** (one engineer, an unmerged branch on the 0.16 compiler, flag `--values=report`). Each step de-risks one assumption:
1. **Kinds plus move/init only.** Run over tests, examples, bench, eval solutions and compiler/src. Measure use-after-move counts, true versus false positives, and ms per check.
2. **Drops through implicit defers.** `Drop` on std's Vec/Buf/HashMap, `free` removed in a copy of bench/. Check bench parity at -O2, -O0 overhead and gen0 correctness (drop order, `?`, break out of a loop with defers).
3. **Views and exclusivity** with the one-region rule and the pure-view exception. Classify every error in the corpus: G1–G8 bugs found, conflicts that would need a narrowing annotation (target under 1% of functions), two-phase cases. *Go/no-go gate:* if one-region false positives exceed about 2% of functions, add `#[views(a)]` before 0.17.
4. **noalias for `&mut`** on stencil, matmul and sort: measure the vectorizer's run-time checks removed. This sizes U2's payoff.

**0.17: every gap closed.**

Phase 0, serial (the lead):
- syntax: `&T`, `&mut T`, `&mut x`, `&mut [T]`;
- `Drop`, `drop`, `forget`, `needs_drop`, the `Copy` bound;
- the kind table;
- front/own/ stubs and the `check_program` hook;
- `--values=report|error`;
- the legacy `*T` rule;
- the compiler source made `report`-clean.

Then in parallel:

| task | owns | provides |
|---|---|---|
| T1 Moves and drops | front/own/{kinds,moves,drops}.tach, the desugaring | init/move analysis, drop flags, temporaries, partial moves, the `own.moved`/`own.partial` diagnostics |
| T2 Views and exclusivity | front/own/{loans,live,calls}.tach, closures/escape.tach (subsumed) | origins, liveness, the signature rule, two-phase receivers, `for` loans, statics with coarse `global`, `own.conflict`/`escape`/`static` |
| T3 std on values | compiler/std/*.tach | Drop impls; consuming `free`; `v[i]`; `as_mut_slice`, `iter_ref`, `swap`/`take`/`replace`; `sort(&mut [T])`; Scanner, SliceIter, split and Fmt (`&mut Buf`) as views; `Clone` bounds |
| T4 Optimizer | middle/{copies,gvn,licm,vectorize,inline}.tach | COPY_MOVE elision, NRVO, noalias/readonly, drop inlining, the bench gate |
| T5 Tools and guide | tools/*, compiler/guide/{memory,unsafe,rust,errors,core}.md, docs | `query own`, explain codes, `fix --values`, fmt, refactor signature with `&`/`&mut`, the guide rewritten (memory and unsafe lose "the one gap") |
| T6 Migration | tests/, examples/, bench/, tests/agent-eval | `fix --values` applied; the hand cases; eval solutions re-run |

Merge order: Phase 0, T1, T3 (they change what programs mean), T2, T4, T5 throughout, then T6. Gate: `gate.sh --quick` plus a `--check-alloc` run of the suite.

**0.17.1: expressiveness.**
- Projections (`-> &T`, `-> &mut T`, reference type arguments, `HashMap::get_mut -> Option<&mut V>`, `iter_mut`).
- Written-static sets in effects, with results viewing statics.
- `&Arena` containers with safe `reset`/`free_all` (U3), `FixedBuf` views.
- Value-level allocator naming (0.16 U2).
- `*T` parameters deprecated (warning), ahead of 0.18 making them raw.

## 7. Open questions

**For the user (U1–U4):**
- **U1. Surface spelling.**
  - (A) Rust's: `x: T` moves, `&T`/`&mut T`, `&mut x` at calls.
  - (B) Hylo/Swift's: `x: T` borrowed read-only, `inout T` with `&x`, `sink T`.

  The semantics are identical (second-class, one region). *Recommendation: A.* Agents write it already, call sites show mutation, and B's default-borrow advantage (no `&` on read-only arguments) does not outweigh a second vocabulary. The roadmap's `inout` is spelled `&mut`.
- **U2. Slices.**
  - Split into read-only `[T]` and exclusive `&mut [T]`.
  - Or keep today's writable, aliasable `[T]`.

  *Recommendation: split.* It gives the optimizer noalias/readonly facts (vectorizer run-time checks go away), it is Rust's rule agents know, and it is one aliasing rule instead of two. The cost is rewriting written slice parameters, which `fix` handles.
- **U3. Arena handles as references** (`Vec<T, &Arena>`). This breaks 0.16's `Vec<T, Arena>` spelling one release after it shipped. In exchange, `reset`/`free_all` become safe and `#[scoped]`'s special rules fold into views. *Recommendation: yes, in 0.17.1, with `fix --only alloc017`.*
- **U4. Enforcement in 0.17.0.**
  - Errors, with `--values=warn` as a one-release opt-out.
  - Or warnings in 0.17 and errors in 0.17.1.

  *Recommendation: errors, with the opt-out.* The no-UB principle, and `fix --values` covers the bulk.

**Decided here** (each can be revisited):
- drops at scope end in reverse order (not at last use);
- plain/owned is structural, with no Copy derive;
- view types cannot implement Drop;
- one region per signature, plus the pure-view exception;
- two-phase receivers;
- `for x in v` borrows (`into_iter` consumes);
- `free` stays as a consuming, deprecated alias;
- legacy `*T` parameters are `&mut T` until 0.18;
- the checker runs on the AST, and drops become implicit defers;
- statics are never dropped, and hold only ∅ views;
- leaks are safe.

### Critical Files for Implementation
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/check/mod.tach (`check_program`, where the own pass and the effects ordering hook in), with /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/check/unsafety.tach (`is_borrow`, `is_borrow_param`: today's borrow rule, which becomes the legacy `*T` rule)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/closures/escape.tach (`type_borrow`, `check_scope_exit`: the model for the kind table, subsumed by origins) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/check/iterate.tach (`for` desugaring: loop loans, `iter_ref`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/check/body.tach (`check_defer`) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/lower/control.tach (`lower_defers`, `lower_break`): drops lowered as implicit defers
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/std/std.tach (Vec/Buf/HashMap: Drop, consuming `free`, views), with compiler/std/iter.tach, io.tach (Scanner, split) and fmt.tach (Fmt as a view)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/copies.tach and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/gvn.tach (`may_alias`): move elision, NRVO, noalias for `&mut`

## Decisions taken for now (to confirm with the user)

U1–U4 taken as recommended on 2026-10-15 (the user said to proceed):
- U1: Rust's spelling (`x: T` moves, `&T` / `&mut T`, `&mut x` at calls);
  the roadmap's `inout` is spelled `&mut`.
- U2: slices split into read-only `[T]` and exclusive `&mut [T]`.
- U3: arena handles become references (`Vec<T, &Arena>`) in 0.17.1, with
  `fix --only alloc017`.
- U4: errors in 0.17.0, with `--values=warn` as a one-release opt-out.


## 8. Prototype results (§6, branch c17-proto, 2026-10-15)

The four prototype steps were built on 0.16 (b3975e1) behind flags that are off by default; the suite is unchanged without them (859 passed). The branch is for measurement and will not be merged as is.

| flag | what it does | code |
|---|---|---|
| `--values=report` (`report-std`: std's own functions) | kinds, moves, views, exclusivity; one line per report, then an `own-summary:` line | front/own/mod.tach (≈3,100 lines), a hook after the effects in `check_program` |
| `--values=drops` | `Drop`, drop glue, drops as implicit defers | front/own/drops.tach, hooks in `check_block`, `check_function` and `check_defer`; std's `Drop` section is appended to std's source only under the flag |
| `--noalias-params`, `--vec-stats` | the optimizer facts of `&mut`/`&`/`[T]` parameters | middle/gvn.tach, middle/vectorize/checks.tach (merged from c17-noalias) |

tests/values-proto/ holds the drop-order program, two report examples, the corpus script (`corpus.sh`) and the bench script (`bench-drops.sh`). bench/drops/ is bench/ with its 13 frees removed.

**The corpus.** It has 7,413 distinct functions that the checker reports on:

| corpus | functions |
|---|---|
| tests/run (301 programs check cleanly; the rest are error tests) | 1,926 |
| examples | 843 |
| the 20 agent-eval reference solutions | 379 |
| bench | 75 |
| compiler/src | 4,190 |

std was reported separately, over every program in tests/run.

### 8.1 How the prototype works

- **Kinds.** They are memoized per type, as in §2.1. Owned is std's Vec, Buf, HashMap and Arena, or any type with a `Drop` impl.
- **The walk.** It is a forward abstract interpretation of each checked body, in evaluation order, as in §4. Its state:
  - per owned place: maybe-moved and definitely-moved bits;
  - per view-holding local (a "slot"): its origins, and whether a write, move or drop has since touched a place it views.
- **Liveness is implicit.** An error is reported where an invalidated view is *used*, so a view that is never used again is not a conflict (NLL).
- **Control flow.** Loops iterate to a fixpoint (4,336 rounds over 326,800 node visits on the compiler); if and match join.
- **Pending arguments.** These give unnamed views (G2), conflicts between the arguments of one call, and two-phase receivers.
- **Two pieces of measurement apparatus** stand in for things 0.17 does not have yet:
  - **Parameter mutability.** It is inferred from the bodies (a fixpoint over calls), as `fix --values` would infer it. A `*T` or `[T]` parameter that the function writes through becomes `&mut`, and every other one `&`.
  - **Two origins per view.** One follows the one-region rule as §2.4 specifies it. The other is *precise*: it comes from inferred callee summaries, which record which parameter, and which level of it, the result views. **A report under the first origin but not the second is exactly a case a narrowing annotation would fix**, which is the go/no-go measure.

### 8.2 Step 1: kinds, moves and initialization — **go**

**Reports.** These are unique positions under the design's rules, after the fixes in "Prototype false positives" below:

| corpus | use after move | move out of index, `*p` or static | read-only by-value argument (`mig.borrow`) |
|---|---|---|---|
| tests | 4 | 3 | 12 |
| examples | 2 | 5 | 11 |
| evals | 1 | 8 | 4 |
| bench | 0 | 0 | 0 |
| compiler | 0 | 0 | 0 |

**How the reports classify.** Every report of a first run (214 unique) was read and classified; the run was repeated after the fixes.

- **Use after move: 7.**
  - The 2 intended `--check-alloc` tests (G4: a double free, and a use after free through a copied handle).
  - 3 handle copies that 0.17 forbids. Two are mechanical: a `defer tokens.free()` of a Vec passed to `parse`, which the migration deletes, and a `.clone()` that comes too late. One needs a hand change: bigint's `a = odd`, after which both share a buffer.
  - 2 false positives: a `{v:?}` f-string hole lowered as a move.
- **Move-outs: 16.** Most are handle copies out of `*self` (`let keys = self.keys`, in life and in eval 17), which become `std::take`/`swap` or `&`. Also:
  - std's `OLD.push(V)`, a move out of a static in tests' index_order;
  - 4 false positives: a `match` through a pointer, which needs binding modes.
- **`mig.borrow`: 27.** An owned value passed by value to a callee that only reads it. This is fix rule 4 (`&T`). Once those 27 are borrows, the moves the corpus would otherwise report as uses after move disappear.
  - One subgroup is not mechanical. bigint's operator traits take `self: BigUint`, and `fix` cannot change a trait's signature, so these are hand changes.
- **Reuse after `free()`.** No program reuses a Vec after freeing it, so it is 0 outside the prototype's own tests.

**Cost.** The reporting pass (pass 1) on the self-check of compiler/src takes 15–18 ms CPU. The type checker took 110–125 ms in the same runs: the machine had a load average of 10–17, against the 45 ms the design assumed. So the pass is about 14% of the checker.

- Of that, an earlier single-level version took 9.4 ms; the precise second origin, which is apparatus, roughly doubles the bitset work.
- The pass makes 326,800 node visits, about 50 ns each.
- The prototype makes a separate pass to find the slots, and its bitset code makes a function call per operation.
- **The 4 ms (5%) budget is not met by the prototype.** A one-origin implementation with inlined bitset operations should land around 6–8 ms (≈8% of an unloaded check). *Adjustment: budget 8%, or plan the optimization work in T1/T2.*

The apparatus passes are not part of 0.17: inferring mutability takes 3–9 ms, and two rounds of summaries take 26–35 ms.

### 8.3 Step 2: drops as implicit defers — **go**

**How it is built.**

- Before a block is checked, an implicit `defer` follows each plain `let`, and a function body starts with one per by-value parameter.
- At `check_defer`, the implicit defer becomes the drop of the local's type:
  - `x.drop()` for a type with a `Drop` impl;
  - a block of its owned fields' drops for a struct or tuple without one (glue, in declaration order);
  - nothing for a plain type.

  This step is checked where the local is in scope.
- After every body is checked, the move analysis (pass 2) empties the implicit defer of a local that is moved away at every exit.
- **No back-end change was needed**: both back ends already lower `defer` on every exit.

**Correctness (gen0 and -O2).** tests/values-proto/drop_order.tach gives identical output at -O0 and -O2, and it matches the expected order. It covers:

- reverse order at scope end;
- a nested block;
- `break` and `continue` out of a loop body holding drops;
- `?` (an early `Err` drops both locals);
- a value moved into a callee, which the callee drops and the caller does not;
- the drop of a by-value parameter;
- struct glue, with fields in declaration order.

**Bench.** This compares bench/X.tach with its frees against bench/drops/X.tach under `--values=drops`. Times are the best of 9; the machine was loaded, and the noise is about ±10% (fmtloop at -O2 read 1.10 with byte-identical code).

| program | -O2 code | -O2 time | -O0 time |
|---|---|---|---|
| fmtints, fmtloop, iterchain, iterloop, wordcount | byte-identical assembly | 0.98–1.01 (one noisy 1.10) | 0.999–1.08 |
| json | +8 instructions: `g.out` is now also freed on an early-error exit, a leak fixed | 1.00 | 0.98 |
| sort | the two frees swap order (reverse declaration order) | 0.98 | 1.005 |

- **-O2 parity holds by construction.** `Drop::drop` is `#[inline]` and calls `free`, which is exactly the hand-written code.
- **-O0.** Each drop is one extra call (`Buf.drop` → `Buf.free`), and fmtloop now frees a Vec it used to leak. That is within the +3% gate on most programs and within noise on the rest.

**Over the whole corpus** (with std's instances, which every program counts again):

- only 8 implicit defers would need a drop flag (moved on some exits, not all);
- 48 assignments to an owned place need the drop-the-old-value desugaring of §4 step 5, which the prototype does not do;
- 58 `match`es move owned bindings;
- 75 `let`s destructure tuples or enums;
- 39 enum, array or closure types hold owned parts, which need generated glue;
- 4 owned temporaries are dropped on the floor.

**Adjustments:**

- Drop glue has to be generated functions (match for enums, a loop for arrays guarded by `needs_drop`), not the prototype's inline AST.
- The assignment desugaring is needed from day one: 48 sites.
- `Drop` must be in the prelude; the prototype needed `use std::Drop`.

### 8.4 Step 3: views and exclusivity — **go overall, no-go for agent-written parsers without one more rule**

**Analysis rules the design needs that it does not state.** Each one was found by a class of false conflicts in the corpus, and none needs an annotation.

- **R1. Two-level origins.** A view value's origin must say separately:
  - what the value *points into* (its loans), and
  - what the views it *holds* point into.

  With one set, `let t = tokens.as_slice(); ... t[1]` "views `tokens`", and every element read out of a container of views (`Vec<[u8]>`, `[[u8]]`, `HashMap<[u8], V>`) looked like it escaped or was invalidated by pushes. An element read out of a view gets the outer value's inner level. This costs two bitsets per origin instead of one.
- **R2. Parametricity.** A generic function whose result type is built from its type parameters carries the T values its arguments hold, not loans on the arguments: `T`, `Option<T>`, `(K, V)`, and level by level for `[T]`. This covers `Vec::get`, `HashMap::get`, `key_at`, `unwrap` and `Iterator::next`.

  It is free (a generic body cannot make a T that points into its arguments) and removes the bulk of the false conflicts around `Vec<[u8]>`.
- **R3. Reborrows.** A view taken from a view local (`let out = acc[..]`) does not invalidate its parent when written through.
- **R4 (experiment, `OWN_TYPEFILTER=1`). Type-directed loans.** A view of `[E]` points only into storage of E (`Vec<E>`, `[E; N]`, `Buf` for u8). A loan on an argument whose referent stores no E, such as a sibling `&mut HashMap<[u8], i64>`, is not in its origin.

**Bugs found.**

- **G5: 1 real, unintended.** In examples/errors-and-results:166, `main -> Result` returns a `ConfigError` whose key views `input`. `defer input.free()` runs before the wrapper prints the error, so a bad config prints freed memory.
- **G1, G4: 3 intended `--check-alloc` tests.**
- **G7: tests' index_order.** It reports 35 times, as §5 expected: static views across calls that grow the tables.
- **G2: std_self_append, 2.** `b.push_str(b.as_slice())`.
- **G8 is not detected.** It is not a view or move rule, and needs §2.6's lint.

**Rule conflicts that are not bugs:**

- the 9 deliberate aliasing tests (opt_vectorize, opt_gvn, opt_slp, opt_promote), which split slices forbid;
- ledger's two `get_mut` views of one map;
- 15-multi-module returning views of deliberately leaked Bufs (14 reports; return a `Buf` instead);
- std's stable sort, whose ping-pong `from`/`to` buffers need raw pointers or indices;
- std's `sort_by` closures, which take `*T` (legacy `&mut`) and should take `&T`.

**Two-phase receivers are essential.**

- 422 call sites read the receiver in their arguments and are legal only because a `&mut self` receiver is two-phase (`v.push(v.len())`): tests 94, examples 155, evals 144, bench 13, compiler 16.
- 2 genuine violations remain: bigint's `rng.big(1 + rng.next() % 600)`, which Rust also rejects; hoist `rng.next()`.
- Explicit `&mut` arguments read later in the same call: 5, all of them std's `sort_by` and the aliasing tests above.

**The go/no-go gate.** It counts the functions with a conflict that only the one-region rule makes (`own.region`; the threshold was about 2% of functions):

| corpus | functions | one-region, as specified (with R1–R3) | with R4 too |
|---|---|---|---|
| tests | 1,926 | 0 | 0 |
| examples | 843 | 4 (0.47%) | 1 |
| evals | 379 | **13 (3.4%)** | **11 (2.9%)** |
| bench | 75 | 0 | 0 |
| compiler | 4,190 | 1 (0.02%) | 1 |
| total | 7,413 | 18 (0.24%) | 13 (0.18%) |

The two patterns behind the evals' 13 functions:

- **A struct that holds views of a source text (a lexer, a parser, a table) returns a view of that text from a `&mut self` method, then mutates itself.** For example: `let col = self.name(); self.accept(..); use col`. The one-region result views `self`; the precise summary says it views only what `self`'s views view. Rust needs `Parser<'src>` for the same code.
- **A call stores a view into one `&mut` argument while another `&mut` argument is passed.** For example `intern(&ids, &names, word)`: the store rule unions the loan on the sibling into the stored-to referent. R4 removes the cases where the sibling cannot hold the view's element type.

The compiler's single case is the second pattern (`elements(old, what, &old_name, &on, &ot)`).

**Verdict and adjustment.** The rule passes on the code humans wrote here: the compiler, std, tests and examples are all at or under 0.5%. It fails on the code agents write: eval solutions at 3.4%, which are parsers that keep views of their input. Two ways to handle this:

- **(a) What the design reserved.** Add `#[views(p)]` to narrow a function's result or stores to named parameters, or to a parameter's held views (`views(*self)`).
- **(b) Infer the precise, level-aware summaries, like 0.16's effects.** Run them per SCC, callees first; show them in `query` and `explain`; let `#[views(...)]` pin them on functions that must not change.

  The prototype's precise origins are exactly this inference, and they remove all 18 functions by construction. The objection §2.8 raised against inferring mutability (a callee's body change silently breaks callers) applies equally to inferred effects, which 0.16 accepted with declarations as the pin.

*Recommendation: (b), with `#[views]` as the declaration form. Ship R1–R3 in 0.17.0 regardless, and R4 too, because it is cheap and sound.*

**Prototype false positives.** These were fixed, so they are not in the numbers above:

- structural equality's `let ==l = a` read as a move (8);
- a `for` over owned elements bound by move instead of `&T` (6);
- a tuple `let` binding every element with the whole tuple's origin (3);
- no reborrows (2);
- pointer parameters getting no pseudo origin, which made G1 cases look like region conflicts (1).

Two remain: a `match` through a pointer (binding modes, 4) and `{v:?}` holes (2).

### 8.5 Step 4: noalias for `&mut` and read-only `&` parameters — **go, for safety more than speed**

`--noalias-params` asserts the post-migration facts for the optimizer:

- two different pointer or slice parameters never overlap each other, nor a static (in `may_alias`, so gvn, licm, slp and the vectorizer all get it);
- a parameter the function never writes through is not written by its calls.

| program | vectorizer overlap tests (pairs) | -O2 time |
|---|---|---|
| stencil | 4 → 0 (assembly 329 → 266 lines) | 8.00 → 7.95 ms (noise) |
| matmul | 8 → 0 (assembly 301 → 183 lines) | 20.5 → 21.5 ms (noise) |
| sort | no vector loops either way | 64.6 → 64.8 ms |
| micro: 8 slices, 3 stores (18 pairs, over the limit of 16) | not vectorized → vectorized | 17.8 → 11.5 ms (**1.56×**) |
| micro: 24-element axpy, 400k calls | 2 → 0 | 2.41 → 2.26 ms (6%) |

- **bench/ does not move.** The overlap tests run once per outer iteration, and no bench loop vectorizes newly.
- **Where it pays.** Kernels with many streams (past the vectorizer's pair limit) and short trip counts.
- **Outputs** are identical with and without the flag.
- **It is only sound under 0.17's rules.** With today's aliasable slices, `sweep(sa, sa)` would miscompile. So the flag can ship only with split slices (U2) and exclusivity, and "a parameter never overlaps a static" also needs the rule that `&S` cannot be passed to a function with `global`.
- **Inlining loses the facts.** The optimizer must keep them as noalias scopes on the inlined body.

*U2's payoff is mostly in correctness and in the occasional kernel, not in bench numbers.*

### 8.6 Design changes the prototype implies

1. **Origins have two levels (R1)**, what a value points into and what its views point into. Parametric results (R2) and reborrows (R3) are part of the rules.
2. **Infer level-aware view summaries like effects**, with `#[views(...)]` to declare and pin them. The alternative is the narrowing attribute alone, which agent-written parsers would need in about 3% of functions. Add the type-directed loan filter (R4).
3. **Two-phase receivers are not optional:** 422 call sites in this corpus depend on them.
4. **Drops:**
   - generated glue functions for enums and arrays;
   - the owned-assignment desugaring;
   - `Drop` in the prelude;
   - drop flags are rare (8 sites).
5. **`fix --values` rule 4** (read-only by-value parameters → `&T`) carries most of the move migration. Trait signatures with `self: Self` operators (bigint) need hand changes or `&Self` operator impls.
6. **Check-time budget.** The pass costs about 14% of the checker in the prototype (two origin levels, unoptimized). Budget about 8% for 0.17, or plan the work to reach 5%.
7. **`--noalias-params` ships only after exclusivity and split slices are enforced.** It must survive inlining to matter.
