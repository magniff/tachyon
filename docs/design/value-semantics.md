# tachyon 0.17 design: memory safety by mutable value semantics

I read the language from `/Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15` (release-0.15) using `tachyonc guide memory|unsafe|types`, `query show/items/grep/refs`, `try`, docs/grammar.md ("Indexing", "Undefined behaviour", "Additions of 0.9", "Escape"), docs/optimizer.md, the commits c51304d/7229534 (the index-order fix), docs/design/closures-iterators.md and errors-formatting.md. The decided 0.16 design comes from `/Users/magniff/workspace/tachyon/.claude/worktrees/design-016/docs/design/effects-allocation.md`. I modified nothing.

## Revision 1 (2026-10-15): after the prototype

The prototype (§8, branch c17-proto) measured every assumption of the first version on 7,413 functions. Steps 1, 2 and 4 passed; step 3 passed on human-written code and failed on agent-written code. What changed, and why:

| # | change | where | why (§8) |
|---|---|---|---|
| 1 | **The one-region signature rule is replaced by inferred, level-aware view summaries** (`views(self)`, `views(*self)`, `stores(word)`), computed callees first over 0.16 effects' SCCs, shown by `query views`, pinned by `#[views(...)]`. The pure-view exception becomes the inferred `views(*self)`, for any type. | §2.4, §4 | One region rejected 13 of the eval solutions' 379 functions (**3.4%**, over the 2% gate): parsers and lexers that hold views of their input. Precise summaries rejected none of the 18 one-region functions in any corpus (§8.4). |
| 2 | **Origins have two levels**: what a value points into, and what the views it points to point into. | §2.4 | Containers of views (`Vec<[u8]>`, `HashMap<[u8], V>`) otherwise make every element read look like a view of the container (R1). |
| 3 | **Generic results are parametric**: a result built from type parameters carries the T values its arguments hold, never loans on them. | §2.4, §2.7 | `Vec::get`, `HashMap::get`, `unwrap`, `next` caused the bulk of the false conflicts around `Vec<[u8]>` (R2). It also covers std's raw bodies. |
| 4 | **Reborrows** and a **type-directed loan filter** are in the rules. | §2.4 | Reborrows: 2 false positives (R3). The filter: one-region cases 18 → 13 (R4); it stays because it is sound and cheap, and it narrows the conservative cases (indirect calls, the fallback). |
| 5 | **Two-phase receivers are stated as essential.** | §2.4 | 422 call sites depend on them (`v.push(v.len())`). |
| 6 | **Drops**: glue is generated functions (match for enums, a guarded loop for arrays); the owned-assignment desugaring is in from day one; `Drop` is in the prelude; drop flags are rare. | §2.2, §4 | 39 types need enum/array/closure glue, 48 owned assignments, 8 flagged locals (§8.3). |
| 7 | **The checker**: liveness is implicit (an error at the use of an invalidated view), slots are found during the walk, functions run in SCC order and produce their summaries as they are checked. | §4 | The prototype's design; the backward pass of the first version is unnecessary. |
| 8 | **Cost budget 5% → 8%** of the type checker. | §4 | The prototype costs about 14% (15–18 ms against 110–125 ms), half of it apparatus; a lean two-level pass is estimated at 6–8% (§8.2). |
| 9 | **noalias** only when the own pass ran in `error` mode, and kept through inlining. | §4 | It is unsound without exclusivity and split slices, and inlining loses it (§8.5). |
| 10 | **New §2.9, "What agents see"**: the six commonest situations, their diagnostics, `query own`/`query views`, and a `try:` on every rejection that is run by a test. | §2.9 | The goal: agents are not wrongly rejected on what they naturally write. |
| 11 | **The tasks are re-split**: a new task T3 for summaries (std, optimizer, tools and migration become T4–T7); Phase 0 fixes the walk's skeleton, its state and its event interface so that moves, views and summaries can proceed in parallel. | §6 | The prototype is one walk doing moves and views; the summaries are a driver around it. |
| 12 | §3's diagnostics carry codes and `try:` lines; a sixth example shows a parser over a token slice, which the first version rejected. | §3 | The evals' pattern (§8.4). |
| 13 | `fix --values` rule 4 (read-only by-value → `&T`) is the main move migration; operator traits taking `self: Self` are hand changes. | §5 | 27 `mig.borrow` sites; bigint (§8.2). |

U1–U4 are kept: the prototype supports U2 and does not touch U1 or U3. **U4 now depends on change 1**: errors in 0.17.0 are right only if inferred summaries ship in 0.17.0. If T3 slips, view conflicts must be warnings until it lands. §7 lists this and the other new choices (V1–V3) for the user.

## Pending: eval findings

Tonight's agent-eval round may add requirements: code agents write that this design still rejects, `try:` lines they fail to apply, and how they use `query own`/`query views`. The findings go here, then into §2.9 and the T6 tests. Until then §2.9's six situations come from the prototype's corpus.

## 1. Current state and every known safety gap

**What exists.**
- Every `=`, argument and return copies bits; nothing moves.
- `Vec<T> {ptr,len,cap}`, `Buf` and `HashMap` are handles. `Vec::free` is safe: it frees, then nulls the handle.
- There are no destructors. `defer v.free()` is the idiom: 131 of the 156 `.free()` lines in tests are `defer x.free()`.
- Tachyon has one pointer type, `*T`. A *borrow* is `&place` written directly as an argument, or a non-`mut` pointer parameter, and dereferencing one is safe. A pointer held anywhere else (a local, a field, a call result) is raw and needs `unsafe`. So `*T` references are already second-class *across* calls.
- Slices `[T]` are first-class. They are writable and need no `mut`. They are stored freely: `Scanner { text: [u8] }`, `SliceIter { s: [T] }`, `split() -> Vec<[u8]>`, `HashMap<[u8], i64>`, `HashMap::get_mut -> Option<[V]>` (a one-element view).
- Closures that capture by reference are confined by 0.14's scope-escape check. Borrowed locals keep their frame slot for the whole function.
- 0.16 adds `Vec<T, A: Allocator = Gpa>`, `Arena`, `ScopedArena` (`#[scoped]`, rules S2/S3), `FixedBuf`, `#[sealed]` and `--check-alloc`. It makes `Arena::reset`/`free_all` `unsafe fn`, and lists four gaps under "waits for 0.17".
- 0.16's effects are inferred per function over the call graph's SCCs, shown by `query effects`, and pinned by declarations. Revision 1 infers view summaries the same way (§2.4).

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
- **`Drop`.** `trait Drop { fn drop(self: &mut Self); }` is in the prelude. A type without an impl gets generated *drop glue*: field by field for structs and tuples, a `match` for enums, a loop for arrays (none when `needs_drop::<T>()` is false), and the owned captures of a closure. Calling `x.drop()` directly is an error (`try: drop(x)`). `std::drop(x: T)` consumes. `std::forget(x)` is safe: leaks are not UB, and `--check-alloc` lists them. **A view type may not implement `Drop`.** This removes Rust's dropck problem: no destructor can read a view whose owner died first.
- **When drops run.** At scope end, in reverse declaration order, interleaved with `defer`s as if each owned `let` registered one. They run on every exit: block end, `return`, `break`, `continue`, `?`.
  - They do not run on `exit` or a failed check (exit 101), which is today's defer rule.
  - Temporaries drop at the end of their statement.
  - Assigning an owned place evaluates the right side, drops the old value, then writes (the grammar's existing order). The corpus has 48 such assignments (§8.3), so this is in 0.17.0.
  - A conditionally moved local carries a drop flag (8 locals in the corpus).
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

### 2.4 Views: second-class, with two-level origins and inferred summaries

*Revised in Revision 1.* The first version gave every signature one region, with an exception for pure views. The prototype found that rule rejects 3.4% of the functions agents write (§8.4). Each function now has an inferred view summary, as each function has inferred effects in 0.16.

**Origins have two levels.** Every value that holds views has an *origin*, which is a pair of sets:

- **level 1**, what the value's own views point into:
  - for a slice, its storage;
  - for `Scanner { text: [u8] }`, the text;
  - for an owned `Vec<[u8]>`, what its elements point into (its buffer is owned, not viewed);
- **level 2**, what the views at level 1 point to hold, collapsed into one set. For `let t = tokens.as_slice()` with `tokens: Vec<[u8]>`, level 1 is `tokens` and level 2 is the text the tokens view.

Levels change in three ways:

- Reading an element *through a view* goes one level down: `t[1]` has level 1 = `t`'s level 2 (the text), not `tokens`.
- Copying a view *out of owned storage* keeps the levels: `tokens[1]` views the text, not `tokens`.
- `&x` has level 1 = a loan on `x`, and level 2 = everything `x` holds.

The members of a level are:

- **loans**: a place (a local or static plus a field path; indexes collapse to their base) and a kind (shared or mut);
- inside a function, each view-holding parameter's **two roots**:
  - `p` is what the argument points into: the referent of `p: &T`, the storage of `p: [T]`;
  - `*p` is what the views the argument holds point into.

The empty origin ∅ is for string literals, constant and static data, and slices made in unsafe code from a raw pointer that does not come from a parameter (the unsafe author vouches, as Rust's unbounded lifetimes do). A slice made in unsafe code from a pointer read out of a parameter's place has that parameter's root: this is how std's `as_slice` views `self`.

**Where views may go.**
- Locals, parameters, temporaries, and other view types, so containers of views are allowed: `Vec<[u8]>` and `HashMap<[u8], i64>` are views of their keys' text.
- Statics hold only ∅ views.
- A value whose origin includes a loan on local `x` cannot outlive `x`, and `x` cannot be moved, dropped or conflictingly accessed while that value is live. This subsumes 0.14's closure-escape rule and 0.16's S2/S3.

**View summaries.** No lifetime is ever written. Every function has a *summary*, which says for its result, and for what its `&mut` parameters' referents may newly hold, which parameter roots each level comes from. It is spelled as the parameters it views:

| summary | meaning | examples |
|---|---|---|
| `views(self)` | the result points into `self`'s referent, level by level | `Vec::as_slice`, `Buf::as_slice`, a `Lexer { src: Buf }` returning `self.src[a..b]` |
| `views(*self)` | the result carries views that `self` holds, without pointing into `self` | `Scanner::next_token`; a `Parser { toks: Vec<Tok> }` returning a token's `text` |
| `views(s, *t)`, `views()` | several sources; none | `first_word(s: [u8]) -> [u8]` is `views(s)` |
| `stores(word)` | what the `&mut` parameters may come to hold | `intern(ids: &mut HashMap<[u8], i64>, names: &mut Vec<[u8]>, word: [u8])` |

Internally a summary is four bits per parameter for the result and four for the stores: level 1 or level 2, from `p` or from `*p`. The text form rounds up to the two shapes above. That is an upper bound, so it is sound to pin.

- **Inferred.** A summary is computed from the body, callees first, over the SCCs of 0.16 effects' call graph. Within a recursive SCC it is iterated to a fixpoint (the masks only grow). A function whose result and `&mut` referents hold no views has `views()` by its type, with nothing to compute; that is most of the compiler. Generic functions get one summary per instance, as they get effects.
- **The caller's side.** A call's result gets the summary applied to the arguments' origins:
  - `p` passes the argument's levels on as they are (for `&x`, a loan on `x` at level 1);
  - `*p` passes the argument's level 2 on, as both levels.

  For the stores, each `&mut` argument's referent gains the summarized origins, minus loans on itself.

  So `let a = sc.next_token(); let b = sc.next_token();` works for any type whose method is `views(*self)`, which used to need the pure-view exception.
- **The callee's side.** The result and the stores may point only into parameter roots. Pointing into a local, or into an owned by-value parameter (which is dropped at the return), is the error `own.escape`: "returns a view of 'buf', which is dropped when 'make' returns".
- **Pinned.** `#[views(...)]` (with `stores(...)`) declares a summary.
  - The body is checked against the declaration (`own.views`: "'name' is #[views(*self)] but returns a view of 'self': 'self.src[a..b]' at 14:9").
  - Callers use the declaration, so a change to the body cannot silently break them.
  - On a trait's method, the declaration binds every impl.
  - std's public functions that return or store views are pinned (T4). This is the contract of std's API.

  It is 0.16's model for effects, unchanged: inferred, shown by `query`, declarable.
- **Generic results are parametric.** A generic function's result whose type is built from its type parameters (`T`, `Option<T>`, `(K, V)`, `[T]` level by level) carries the T values its arguments hold, never loans on the arguments. This covers `Vec::get -> T`, `HashMap::get`, `unwrap` and `Iterator::next`.
  - It holds by the type, whatever the body does; std's bodies read raw memory.
  - It is the floor that inference starts from.
- **Indirect calls.** A call through a `fn` value uses the join of the summaries of every function of that type whose address the program takes, as effects do. An `extern` function returns raw pointers and holds no loans.
- **The type filter.** A level whose views have element type E points only into storage that can hold an E: `Vec<E>`, `[E; N]`, `Buf` for u8, and structs and enums of those. A loan on an argument that stores no E is dropped from the result. So a sibling `&mut HashMap<[u8], i64>` never gets a `[Tok]` view's loan. The filter is sound by type and memoized per type.
- **Reborrows.** A view taken from a view local (`let out = acc[..]`, `&mut s[a..b]`, a slice parameter passed on) is a child of it. Writing through the child does not invalidate the parent. Using the parent ends a live `&mut` child.

*Why inferring is right here, when inferring mutability was rejected (§2.8):*
- Mutability shows at every call site (`&mut x`), and agents write it from Rust habit.
- View relations are what Rust says with lifetime elision and explicit lifetimes. Those are what agents get wrong most often, and tachyon never asks for them.
- One region per signature needs a narrowing annotation in 3.4% of the eval's functions; inferred summaries need none in any corpus (§8.4).
- The cost of inference, that a callee's body change can break its callers, is paid as 0.16 pays it for effects:
  - the caller's error names the callee's summary and the line that makes it (§2.9);
  - `#[views]` pins the summary.

**Returning views and projections (decided).**
- `fn first_word(s: [u8]) -> [u8]` (`views(s)`) and `fn as_slice(self: &Vec<T>) -> [T]` (`views(self)`) are allowed in 0.17.
- `fn first(v: &Vec<T>) -> &T` and `fn get_mut(self: &mut HashMap<K, V>, k: K) -> Option<&mut V>` (references as results and as type arguments: Hylo's projections, Rust's elided `&self -> &T`) have summaries the same way. They come in 0.17.1, because they need reference types as type arguments. Until then, std keeps its one-element `[V]` views, now checked.
- `Vec` and `Buf` get `v[i]` and `v[a..b]` as places (they are not indexable today), with the same two-phase rule as receivers.

**Slices (U2).** `[T]` (and `&[T]`, the same type) is a shared, read-only view. `&mut [T]` is the exclusive, writable one: `sort(s: &mut [T])`, `v.as_mut_slice()`, `&mut a[..]`.

**Exclusivity.** Aliasing XOR mutation, checked within one function, with live ranges ending at the last use (NLL-style, not lexical scopes):
- While a shared loan on P is live, nothing may write, move or drop P, or take `&mut` of any place overlapping P.
- While a mut loan is live, P is reachable only through it.
- Disjoint fields don't overlap; `v[i]` and `v[j]` do.
- A `&mut self` receiver is two-phase (§2.3). This is essential, not a convenience: 422 call sites in the corpus read the receiver in their arguments (§8.4).

Consequences:
- `f(&mut a, &a)` is an error ("'a' is borrowed mutably by argument 1 and read by argument 2"). `f(&mut a.x, &a.y)` is fine.
- `f(&mut v[i], &v[j])` is an error. The help names `v.swap(i, j)`, or copying a plain value out first.
- `rng.big(1 + rng.next() % 600)` is an error, as in Rust: a mutable receiver is changed by its own argument. `try:` hoists `rng.next()`.
- **Iterator invalidation.** `for x in v` holds a shared loan on `v` for the whole loop, so `v.push` inside it is an error. Over plain elements `x` is a copy, as today; over owned elements `x: &T`. `for x in &mut v` (`iter_mut`, 0.14's open question 4) yields `&mut T`. `for x in v.into_iter()` consumes.
- **Unnamed views.** G2's cases are errors at the growing call, which names the view and the use that keeps it alive.
- **Statics.** A view of a static S has the origin "static S". It is invalidated by writes to S and by any call whose 0.16 effects include `global`.
  - Passing `&S` or `&mut S` to a function with `global` is an error, because noalias would be a lie.
  - 0.17.1 refines `global` into written-static sets (a bitmask, like 0.16's `allocs`), which makes this precise. It also lets a summary name statics (`views(TYPES)`), so a function can return a view of statics.
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

- **Generics.** They are checked per instance, as now, so moves, drops and view summaries are decided per instance. A result built from type parameters is parametric (§2.4): it carries the T values of the arguments, not loans on them. Errors carry the "in instantiation of" note. `Copy`/`Clone` bounds let templates state intent, and `Vec::filled(n, x)` requires `T: Clone`.
- **Traits.** Trait methods declare receivers as `&Self`, `&mut Self` or `Self`. A `#[views(...)]` on a trait's method binds every impl, as an effect declaration does. Derived `Clone` (0.15) becomes the deep copy. `Eq`/`Ord`/`Hash` take `&Self`, as they already take `*Self`.
- **`?`.** It desugars to a `return` (0.15), so pending drops run. Moving the error into `From` is a move.
- **`defer`.** Defers and drops share one exit list. A `defer` body that uses a local is checked at every exit, against the join of the exit states.
- **f-strings.** The holes are shared borrows, never moves (`{v:?}` too; the prototype's two remaining false positives were holes lowered as moves): the `Interp` closure is a view. `println(f"{v}")` is free. `let m = f"{v}"; v.push(1); println(m)` is an error with "format(...) it to a Buf, or build it after the push".
- **`match`.** Matching an owned place moves the bindings out (a partial move). Matching `&x`, or a place reached through a reference (`match *self`, `match self.kind`), binds `&T` for owned parts and copies for plain ones, as Rust's default binding modes do (the prototype's other remaining false positive, 4 sites). Today's "bindings are copies" stays true for plain types.
- **`main -> Result`.** Its body closure drops before the error is printed.

### 2.8 Alternatives considered

- **Rust lifetimes.** They buy:
  - several independent regions in one type (`Parser<'src, 'arena>`);
  - results that borrow a subset of the arguments (`longest<'a>(x: &'a str, y: &str)`);
  - long-lived reference graphs in heaps (`&'arena Node`).

  Their cost is annotations, variance, higher-ranked bounds, error messages agents misread, and region inference. Inferred summaries (§2.4) recover the second: a result views exactly the parameters its body uses. What is still lost is the first, approximated by two levels, and the third. Its fixes are a clone or an index, or else indices and raw pointers for reference graphs.
- **One region per signature, with `#[views(a)]` to narrow it** (the first version of this design). Measured in §8.4: agents would need the attribute in 3.4% of their functions, almost all of them parsers and lexers, and an agent cannot be expected to see why. Rejected in Revision 1 for inferred summaries, with `#[views]` as the pin.
- **Swift (CoW + ARC + exclusivity).** Its copies are implicit and cheap, but cost reference counting and uniqueness checks on every mutation. That is rejected: copies stay explicit. Swift's exclusivity, and its `~Escapable` copy/borrow dependence, are adopted.
- **Hylo (pure MVS: `let`/`inout`/`sink`/`set`, subscripts).** The semantics are adopted: second-class references and projections. The spelling is U1's alternative. Hylo's `let` bindings, which are borrows rather than moves, were rejected as surprising next to Rust habits.
- **Mojo.** Its origins are close to ours, but parametric. ASAP destruction (drop at last use) was rejected: destructor timing must be readable in the text, and scope-end drop with NLL liveness for *views* gives the same freedom where it matters.
- **Vale's generational references.** They make every dereference a run-time check plus a 64-bit generation per allocation. They violate "zero-cost", but they remain the model for `--check-alloc`.
- **Austral linear types.** "Must consume" would make every early return name every value. Affine types with automatic drop are kept.
- **Tachyon-specific relaxations.**
  - Shape-versus-content writes: plain element writes allowed while views are live. Rejected: two notions of "write", weaker optimizer facts, and agents already know aliasing XOR mutation.
  - Inferring each pointer parameter's mutability from the body: changing a callee body would break its callers silently. Rejected. Mutability shows at every call site (`&mut x`) and agents write it; view summaries are inferred instead because nothing at the call site shows them and Rust's equivalent, lifetimes, is what agents get wrong (§2.4).

### 2.9 What agents see

*New in Revision 1.* The aim, above any other: an agent is not wrongly rejected on the code it naturally writes (parsers, lexers, iterators over input, builders), and every rejection says what to run.

**The contract of every `own.*` diagnostic:**
- **One line.** It gives the position and the code, then what happened and what still needed the value, with both positions.
- **`help:`** gives the idiomatic fix in words.
- **One or more `try:` lines** give commands that run as they are: `tachyonc edit patch`, `refactor ...`, `rewrite`. When the fix needs a choice, `try:` gives the query that shows the facts (`query own`, `query views --why`).
- **A conflict that comes through a callee** names the callee's summary and the line that makes it, so the agent does not have to read the callee.
- **The `try:` lines are tested.** tests/own-try (T6) runs every `try:` of the own error tests. After it, the program must check clean, or report a different, named next step: an `edit.breaks` at the callers counts.

`check` prints a diagnostic on one line, joined by ` | `; below, the parts are split for reading.

**The queries.**
- `query own FILE:LINE:COL` shows the state at that point. For each local it gives the kind, whether it is moved (where, and by what), and the views it holds, each with its origin, where it was taken and what invalidated it.
- `query views NAME` shows a function's summary, marked `inferred` or `declared`; `--why` adds the line that makes each source. On a MODULE it shows every function with a non-empty summary.
- `query def`, `show` and `context` print `views:` on the first line, after `effects:`.

The six situations below are the most frequent in the prototype's corpus (§8.2, §8.4).

**1. A value used after it moved into a call** (7 uses after move in the corpus, and 27 owned arguments passed by value to a callee that only reads them).

```tach
fn total(v: Vec<i64>) -> i64 { let mut s = 0; for x in v { s += x; } s }
fn main(gpa: Gpa) {
    let mut v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    let n = total(v);
    v.push(n);
}
```
```text
main.tach:6:5: error[own.moved] 'v' is used here after it moved into 'total(v)' at 5:19
  help: 'total' only reads its parameter 'v': take it by reference ('v: &Vec<i64>'), or pass a copy
  try: tachyonc refactor signature total --type v '&Vec<i64>' --default '&$v'
  try: tachyonc edit patch main.tach:5 --old 'total(v)' --new 'total(v.clone())'
```
When the callee keeps or consumes its parameter, the first `try:` is left out.
```text
$ tachyonc query own main.tach:6:5
main.tach:6:5 in crate::main
v  Vec<i64>  owned  moved at 5:19 into 'total(v)' (total takes 'v: Vec<i64>' and only reads it)
n  i64       plain
```

**2. Moving out of a borrowed place** (16 move-outs, most of them `let keys = self.keys`).

```tach
fn rehash(self: &mut Table) {
    let old = self.keys;
    for k in old { self.insert(k); }
}
```
```text
table.tach:2:15: error[own.move_out] cannot move 'self.keys' (Vec<Entry>) out of '*self': 'rehash' borrows 'self'
  help: take it out and leave an empty Vec in its place, or iterate over it by reference
  try: tachyonc edit patch table.tach:2 --old 'self.keys' --new 'std::take(&mut self.keys)'
```

**3. A view used after its owner changed** (G1: the 3 intended tests, the 35 reports of index_order, std_self_append).

```tach
let first = v.as_slice();
v.push(4);
println(f"{first[0]}");
```
```text
main.tach:5:5: error[own.conflict] 'v.push(4)' may move v's elements while 'first' (4:17) views them; 'first' is used at 6:16
  help: use 'first' before the push, keep an index instead of a view, or keep a copy
  try: tachyonc edit patch main.tach:4 --old 'v.as_slice()' --new 'v.clone()'
  try: tachyonc query own main.tach:6:16
```
```text
$ tachyonc query own main.tach:6:16
main.tach:6:16 in crate::main
v      Vec<i64>  owned  written at 5:5 by 'v.push(4)'
first  [i64]     view   views v (taken at 4:17); invalid since 5:5 'v.push(4)'
```
- Over plain elements, the help names the copy instead: `let x = v[0];`.
- The static form (G7) reads "'intern' writes statics (global) while 't' (40:9) views TYPES". Its help is "copy the plain value first: 'let t = TYPES[i];'".

**4. Changing a collection while iterating over it** (in tests alone, 59 `.iter()` loops push to some Vec, §5).

```tach
for x in v { if x % 2 == 0 { v.push(x / 2); } }
```
```text
main.tach:7:30: error[own.conflict] 'v.push' may move v's elements while the 'for' at 7:1 iterates over them
  help: loop over the indexes (the loop sees the elements present when it starts), or collect the new elements and append them after the loop
  try: tachyonc edit patch main.tach:7 --old 'for x in v {' --new 'for i in 0..v.len() { let x = v[i];'
```

**5. Returning a view of something the function owns** (G5; the one unintended bug the prototype found has this shape).

```tach
fn greet(name: [u8]) -> [u8] {
    let b = format(f"hello {name}");
    b.as_slice()
}
```
```text
greet.tach:3:5: error[own.escape] 'greet' returns a view of 'b', which is dropped when 'greet' returns
  help: return the Buf itself; a caller that wants a view takes '.as_slice()' of it
  try: tachyonc edit patch greet --old '-> [u8]' --new '-> Buf' --old 'b.as_slice()' --new 'b'
```
If a caller then breaks, the edit reports `edit.breaks` with that caller's own `try:` lines.

**6. Lexers and parsers that keep views of their input.** This is the evals' pattern: 13 functions were rejected under the first version, and none is now.

```tach
struct Tok { text: [u8], kind: i64 }
struct Parser { toks: Vec<Tok>, pos: i64, nodes: Vec<Node> }
impl Parser {
    fn name(self: &mut Parser) -> [u8] { let t = self.toks[self.pos]; self.pos += 1; t.text }
    fn item(self: &mut Parser) -> Result<[u8], [u8]> {
        let col = self.name();
        if !self.accept(COMMA) { return Err("expected ','"); }
        Ok(col)                  // accepted: 'col' views the source text, not the parser
    }
}
```
```text
$ tachyonc query views Parser --why
crate::Parser::name  views(*self)  inferred
  why: parse.tach:4:83 't.text': 't' is a Tok read out of 'self.toks' (4:46), so its text is a view 'self' holds
crate::Parser::item  views(*self)  inferred
  why: parse.tach:8:12 'col' comes from 'self.name()' (views(*self))
```
The rejection that remains is the real one: the lexer *owns* its text and hands out views of it while it is still mutated, which Rust rejects too.
```tach
struct Lexer { src: Buf, pos: i64 }
fn word(self: &mut Lexer) -> [u8] { ...; self.src.as_slice()[a..b] }
let a = lx.word();
let b = lx.word();
println(f"{a} {b}");
```
```text
main.tach:12:13: error[own.conflict] 'lx.word()' borrows 'lx' mutably while 'a' (11:13) views it; 'a' is used at 13:16
  help: 'Lexer::word' is views(self): it returns 'self.src.as_slice()[a..b]' (lex.tach:9:5), a view of the Buf the lexer owns. Let the lexer view text its caller owns ('src: [u8]'), or copy each word
  try: tachyonc refactor field Lexer --type src '[u8]' --default '$src.as_slice()'
  try: tachyonc edit patch main.tach:11 --old 'lx.word()' --new 'Buf::from(lx.word())'
```

The other rejections are rarer in the corpus and follow the same contract:
- an argument conflict, `f(&mut a, &a)`, whose `try:` lines name `v.swap(i, j)` or hoisting;
- a two-phase violation, `rng.big(1 + rng.next() % 600)`, whose `try:` hoists `rng.next()` into a `let`;
- two `get_mut` views of one map (`try:` take the first value out, or use `swap`);
- views of deliberately leaked Bufs (`try:` return the Buf).

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
... counts.insert(s[start..i], c + 1); ...        // counts now views text: insert is stores(k), parametric in K
0
}   // counts dropped, then text: reverse order, so the view goes before its owner
// text.push(b' ') after the counting loop, while counts is used later:
// wc.tach:52:5: error[own.conflict] 'text.push' may move text's bytes while 'counts' (keys from 's[start..i]' at 44:27) views them; 'counts' is used at 60:9
//   help: finish with 'counts' first, or keep owned keys: 'HashMap<Buf, i64>' with 'Buf::from(w)'
//   try: tachyonc query own wc.tach:60:9
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
// e.tach:2:30: error[own.conflict] 'v.push' may move v's elements while the 'for' at 2:1 iterates over them
//   help: loop over the indexes, or collect first: 'let extra: Vec<i64> = v.iter().filter(|x| x % 2 == 0).map(|x| x / 2).collect();' then 'v.extend_from_slice(extra.as_slice())'
//   try: tachyonc edit patch e.tach:2 --old 'for x in v {' --new 'for i in 0..v.len() { let x = v[i];'
take(v.as_slice(), grow(&mut v));
// e.tach:5:20: error[own.conflict] 'grow(&mut v)' changes v while the view 'v.as_slice()' (5:6) waits for 'take'
//   try: tachyonc edit patch e.tach:5 --old 'take(v.as_slice(), grow(&mut v));' --new 'let k = grow(&mut v); take(v.as_slice(), k);'
fn bad(xs: &mut Vec<i64>, first: &i64) { xs.push(1); println(f"{*first}"); }
bad(&mut v, &v[0]);
// e.tach:9:13: error[own.conflict] 'v' is borrowed mutably by argument 1 and read by argument 2
//   help: copy the plain value out first
//   try: tachyonc edit patch e.tach:9 --old 'bad(&mut v, &v[0]);' --new 'let f0 = v[0]; bad(&mut v, &f0);'
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
// error[own.conflict] 'arena.reset()' frees memory that 'keep' (12:9) views; 'keep' is used at 15:5
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
// types.tach:41:9: error[own.static] 'template_instance' writes statics (global) while 't' (40:9) views TYPES; 't' is used at 42:13
//   help: copy the plain value first: 'let t = TYPES[i];' (Type is plain)
//   try: tachyonc edit patch types.tach:40 --old '&TYPES[i]' --new 'TYPES[i]'
```

In 0.17 the static check is coarse (any `global`). 0.17.1's written-static sets make it exact (`intern`, which writes only SYMS, stops conflicting). Index handles plus plain copies stay the recommended table style. After inlining, SROA reduces `TYPES[i].a` to one load.

**6. A parser over a token slice (the evals' pattern; changed in Revision 1).** This is eval 15's shape: the parser *views* its tokens and *owns* its nodes, so it is not a pure view, and the first version's exception did not apply.

```tach
struct Parser { toks: [Token], pos: i64, nodes: Vec<Node> }      // Token { text: [u8], .. }
fn ident(self: &mut Parser) -> [u8] { let t = self.toks[self.pos]; self.pos += 1; t.text }
fn decl(self: &mut Parser) -> i64 {
    let name = self.ident();
    self.nodes.push(Node::Decl(0));      // first version: error, 'name' views 'self' (one region)
    self.intern(name)                    // Revision 1: fine, ident is views(*self)
}
```

- Under one region, `ident`'s result viewed its argument `self`, so the push to `self.nodes` invalidated `name`. Rust needs `Parser<'src>` for this code.
- The inferred summary says the result views only what `self` holds (the token text), and `nodes` holds nothing it views.
- No annotation is written. `query views Parser::ident` shows `views(*self)`.

## 4. Checker algorithm, cost, optimizer

*Revised in Revision 1, after the prototype (§8.1).*

**Where: on the typed AST, not a MIR.**
- `check` is front-end only (79 ms on the compiler, about 45 ms of it in the checker; 7 ms warm), and the tools need these errors without lowering.
- Errors need source spans and the "used at" secondary positions.
- Tachyon's control flow is structured: blocks, if, match, loop/while/for, labeled break/continue, return, `?` (a desugared return), defer.
- 0.16's effects pass made the same choice. A MIR would duplicate middle/lower and cost compile time.
- Expressions are walked per statement in the grammar's documented evaluation order: left to right, the right-hand side before the place, the index before the base is read, two-phase receivers. That gives an exact access sequence.
- The prototype confirmed the choice. Its walk is about 3,100 lines on the typed AST, it needed no back-end change, and it found every gap it was meant to find except G8, which is a lint (§2.6).

**The pass `front/own/`.** It runs in `check_program` after `infer_effects()`, whose call graph and SCC numbering (`COMPONENT`) it reuses, and before `exit_if_errors`.

0. **Drop placeholders, during type checking.**
   - Before a block is checked, an implicit `defer` is placed after each `let` whose type may need a drop, and a body starts with one per owned by-value parameter.
   - `check_defer` fills each placeholder with the drop of the local's type: `x.drop()` for a `Drop` impl, else a call of the type's generated glue `__drop_T(&mut x)`, else nothing.
   - Glue is one generated `#[inline]` function per type: field by field for structs and tuples, a `match` for enums, a loop for arrays guarded by `needs_drop::<T>()`.
   - Owned temporaries are hoisted into a hidden `let __tN` in a statement block.
   - Assigning an owned place becomes `{ let __n = rhs; drop_in_place(&mut p); p = __n }`.
   - Because the drops exist before effects are inferred, effects see them: a function that drops a moved-in Vec has `alloc(Gpa)`.
1. **Kinds.** `KIND[type]` holds the bits PLAIN, OWNED, VIEW, NEEDS_DROP and LEVEL2 (the type holds views of views), plus `VIEW_ELEM[type]` (the element type of the views it holds, or "several", for the type filter). They are memoized, cached per Def, and modelled on `closures::escape::type_borrow`.
2. **Order.** Functions run in reverse topological order of the effects SCCs.
   - A function whose result and `&mut` referents hold no views has the summary `views()` by type. It is walked once, in any order; this is the bulk of every corpus.
   - A recursive SCC with view-carrying summaries starts every member from its parametric floor and walks them all until no summary grows (the masks are monotone, at most 8 bits per parameter). Errors are reported only from the final round.
   - A `#[views]` declaration is used as it is, and the body is checked against it.
3. **Places and slots.**
   - Places are interned per function. A place is a root (a local, a static, or a parameter's root `p` or `*p`) plus a field path; indexes collapse.
   - Most functions have at most 64 places: one word per bitset. Larger ones use 8 words, adaptively, as in the prototype.
   - A *slot* is a view-holding local. Slots are made when first bound during the walk; there is no pre-pass.
4. **The forward walk**, in evaluation order. Its state:
   - per owned place, maybe-moved and definitely-moved bits;
   - per slot, its origin (2 levels × NW words) and an *invalidated* mark with the node that invalidated it and how (write, move, drop, `&mut`, a `global` call).

   The rules:
   - **Liveness is implicit (NLL).** Using an invalidated slot is the error, and both positions are known there. A view that is never used again is no conflict, and no backward pass is needed.
   - **Calls.** The arguments are evaluated left to right as *pending* entries: their loans and their views' origins. Then, in order:
     1. an argument changes the views of earlier pending arguments (G2);
     2. overlaps between a written argument and the others are conflicts;
     3. a `&mut self` receiver is reserved during the arguments and activated at the call (two-phase);
     4. the callee's summary gives the result's origin and the stores into `&mut` referents, through the type filter;
     5. a callee with `global` invalidates the views of statics.
   - **Control flow.** At if and match joins, the origins and maybe bits are ORed and the definite bits ANDed. Loops iterate until the head state is stable; the prototype made 4,336 rounds over 326,800 node visits on the compiler. `break`, `continue` and `return` feed their targets, and defers and drops share one exit list.
   - **One error per place or slot**, so errors do not cascade.
   - **Outputs:**
     - the errors;
     - the function's summary, from the origins of its returns and tail and of its `&mut` parameters' slots at the exits;
     - the exit states of each drop placeholder.
5. **Finishing the drops.**
   - A placeholder whose local is moved away at every exit is emptied.
   - One that is moved on some exits gets a hidden `bool` flag, cleared at each move (8 locals in the corpus).
   - Both back ends already lower `defer` on every exit (middle/lower/control.tach `lower_defers`, gen0), so **no back-end change is needed**.
6. **Statics.** A small post-pass checks the recorded "view of static S live across call c" pairs against c's effects.
7. **Cache.** Kinds and summaries are stored per Def in the query cache, as effects are. `query views` reads them; `query own` walks one function using its callees' cached summaries.

**Cost.**
- **Measured (§8.2).** The prototype's pass costs 15–18 ms CPU on the self-check of compiler/src. The type checker took 110–125 ms in the same runs on a loaded machine, so the pass was about **14%**: 326,800 node visits at about 50 ns each. An earlier version with one level and one origin took 9.4 ms.
- **What is surplus in the prototype:**
  - the second (one-region) origin, which is apparatus and about doubles the bitset work;
  - the pre-pass that finds slots;
  - a function call for every bitset operation;
  - a pool allocation for every temporary origin.

  The apparatus passes do not ship either: mutability inference took 3–9 ms, and two whole-program summary rounds took 26–35 ms.
- **0.17's pass** has one origin of two levels, a one-word bitset fast path inlined, and slots made on the fly. The walk that checks a function also produces its summary. Only the members of recursive SCCs with view-carrying summaries are walked again, and in the compiler, whose functions return integers and raw pointers, those are a handful.
- **Estimate.** 9.4 ms for one level becomes about 11 ms with level 2 at the prototype's quality, and 6–8 ms with the fast paths: about 6–7% of the checker on the prototype's machine.
- **Budget: at most 8% of the type checker's time** on compiler/src, measured by `check --time` in the same run (reported as `own`), with a ceiling of 10% at the gate. The first version's 5% (4 ms of 45 ms) assumed one level; the prototype shows two levels are needed. *Reaching 5% means more work, which T2 can take on if the user holds to it.*
- **Drops** add one placeholder node per owned `let`. T1 measures them and expects under 1% of the checker (the counts of §8.3).
- **Agent-sized programs** are under 1,000 lines, where the pass is noise.
- The self-compile gate is unchanged (+2%).

**Tools.**
- `query own FILE:LINE:COL` and `query views NAME [--why]` (§2.9).
- `query def`, `show` and `context` print `views:` after `effects:`; `--print-views` prints every function's summary, like `--print-effects`.
- **Diagnostic codes.** Each has an `explain` entry and follows the contract of §2.9. They are the compiler's first dotted codes, so that `explain own.escape` is specific.

  | code | what it reports |
  |---|---|
  | `own.moved` | a use after a move |
  | `own.move_out` | a move out of an index, `*r`, a static or a borrowed parameter |
  | `own.partial` | a partial move out of a `Drop` type |
  | `own.conflict` | a write, move, drop or `&mut` while a view or loan is live, which covers `for`, arguments and two-phase receivers |
  | `own.escape` | a view that outlives what it points into |
  | `own.static` | statics against `global` calls |
  | `own.views` | a body that exceeds its `#[views]` declaration |
  | `own.drop_view` | `Drop` on a view type |

**Optimizer work for zero cost.**
1. **Moves.** Move copies are flagged `COPY_MOVE`. copies.tach's "source used only before the copy" then holds by construction, so it skips the use scan and also elides copies inside loops. NRVO: a returned local is merged with the sret slot.
2. **Passing.** A large plain by-value parameter, and a moved-in owned parameter, are passed by the caller's slot address with no copy: exclusivity guarantees nothing writes the slot during the call.
3. **Drops.** std's `drop` impls and the generated glue are `#[inline]`. `needs_drop::<T>()` folds at type-check time. Drop flags are SROA'd and constant-folded away. At -O0, gen0 emits flags only for maybe-moved locals. The prototype measured byte-identical -O2 code on 5 of 7 benchmarks, and the other two differ only by a fixed leak and a reversed free order (§8.3).
4. **Aliasing (U2).**
   - A `&mut T` or `&mut [T]` parameter is its own memory object in gvn's `may_alias`: distinct from every other parameter, static and heap pointer.
   - `&T` and `[T]` parameters are read-only for the call, so their loads are hoisted across stores and calls without `global`.
   - The vectorizer drops its run-time overlap checks between a `&mut [T]` and other slices: stencil 4 → 0, matmul 8 → 0, and 1.56× on a kernel past the pair limit (§8.5).
   - **These facts are used only when the own pass ran in `error` mode** (the 0.17 default) and found no errors. Under `--values=warn` or `report` they are unsound (`sweep(sa, sa)`), and the optimizer must not assume them.
   - **Inlining keeps them** as noalias scopes on the inlined body; otherwise they are lost exactly where they would pay.
5. **heap_to_stack** keeps working, because Gpa's free inlines to `free`.

**Gate.** bench/ within noise at -O2 (wordcount, json, sort, binarytrees, iterchain, fmtloop); -O0 within +3%; self-compile within +2%; the own pass at most 8% of the checker.

## 5. Migration: `tachyonc fix --values`

**Rules, each typed and checked like any edit:**
1. Delete `defer X.free();` when X is an owned local of the same block. Mid-scope, `X.free();` becomes `drop(X);` when X is not used later, else `X = Vec::new();` (the old meaning: an empty, reusable handle).
2. `p: *T` or `self: *T` in safe functions becomes `&mut T` when the function writes through p (transitively, through the callees' rewritten signatures, computed as a fixpoint over SCCs), else `&T`. Call sites `&x` become `&mut x` for `&mut` parameters.
3. Slice parameters that are written become `&mut [T]`. Call sites: `v.as_slice()` becomes `v.as_mut_slice()`, `a[..]` becomes `&mut a[..]` (U2).
4. Handle copies:
   - `let w = v;` with v used later becomes `let w = &v;` when w is only read, else `v.clone()`. A clone is reported for review, because the old shared-buffer meaning cannot be preserved.
   - By-value owned parameters that the callee only reads become `&T`, with the call sites changed to `&v`. This carries most of the move migration: 27 sites in the corpus (§8.2). Trait methods taking `self: Self` (bigint's operators) are not rewritten, because `fix` cannot change a trait's signature; they are hand changes, or `&Self` operator impls.
5. `Vec::filled(n, x)` with an owned x gets `#[derive(Clone)]` on the element type.
6. A struct holding slices that must outlive its source (an `own.escape` that no summary can fix, or a value stored in a static): the field becomes `Buf`/`Vec<T>` with `Buf::from(s)` or `.to_vec()` at the literals, when every value assigned to it is a slice. Literal-only (∅) fields stay as they are.
7. No auto-fix (exact diagnostics instead): conflicts and invalidation (an index loop or collect-then-extend is suggested), views of statics, partial moves out of Drop types.

**Expected volume** (grep counts over tests/, `query grep --count` elsewhere):

| corpus | mechanical | likely by hand |
|---|---|---|
| tests (666 files, 61 of them agent-eval) | 131 `defer x.free()` and 25 other frees (62 files); 268 `self: *` receivers (87 files) and 412 `*T` parameters (127 files), optional in 0.17 because of the legacy rule; 228 `as_slice()`, mostly unchanged | 15–30 cases: handle-sharing tests and guide memory's `lost()`, `index_order` (static views re-taken after growth become errors or unsafe), 17 structs with slice fields (most stay local views), the 59 `.iter()` loops that push; plus about 40 err-test outputs regenerated |
| bench + examples (26 files) | 34 frees (httpd 10, iterloop 3, iterchain 3), 33 `self: *` | about 2 (httpd's buffers) |
| agent-eval reference solutions | 81 frees | a few, re-run under the eval |
| compiler/src (95k lines) | 16 `self: *`; 56/32/34 refs to Vec/Buf/HashMap | a handful of Vec handle copies, fixed with 0.16-compatible code (`.clone()`, restructuring). The raw `static mut` tables (1120 statics, 3031 `unsafe`, 248 `*IntVec`, 164 raw `free(`) are untouched; the compiler moves to MVS in 0.18 as the roadmap says |

## 6. Prototype, then the phases

*Revised in Revision 1.*

**The prototype is done** (§8; research branch c17-proto, not to be merged as is). It ran the four steps planned here:
1. kinds plus move/init;
2. drops through implicit defers;
3. views and exclusivity under the one-region rule, with the go/no-go gate at 2% of functions;
4. noalias for `&mut`.

Steps 1, 2 and 4 passed. Step 3 failed the gate on the eval solutions (3.4%), which is why §2.4 changed. Its walk, place and bitset machinery and drop hooks are the starting code for Phase 0, T1 and T2. They are copied, then stripped of the apparatus: the one-region origin, mutability inference, the report classes and the two-round summary passes.

**0.17.0: every gap closed, with inferred summaries.**

**Phase 0: the interface commit** (serial, the lead). After it, each task builds against fixed signatures and stubs. It contains:

- **Syntax.**
  - `&T`, `&mut T` and `&mut [T]`; `&x` and `&mut x` as tracked references.
  - `#[views(...)]` with `stores(...)`, parsed, validated against the parameter names, and stored on the Def. It is not checked yet.
- **The prelude:** the `Drop` trait (no `use std::Drop`), `drop`, `forget`, `needs_drop`, `std::take`, `std::replace`, and the `Copy` bound.
- **front/own/**, with these signatures fixed:

  | file | contents | in Phase 0 |
  |---|---|---|
  | `mod.tach` | `pub fn check_own()`, hooked into `check_program` after `infer_effects()`; `--values=off\|report\|warn\|error` (`OWN_MODE`) | done; the default is `report` until T7, then `error` |
  | `kinds.tach` | `type_kind(t) -> i64` (PLAIN, OWNED, VIEW, NEEDS_DROP, LEVEL2), `view_elem(t) -> i64` | done (small, and every task uses it) |
  | `state.tach` | the walk's state layout: owned bits, slots, two-level origins, the invalidation marks, pending arguments, the pool, the bitset fast path | done |
  | `walk.tach` | the evaluation-order walk from the prototype: expressions, blocks, `let`, `match`, loops to a fixpoint, joins, exits and defers. It calls the event hooks `ev_read`, `ev_write`, `ev_move`, `ev_init`, `ev_drop`, `ev_call` and `ev_result`, and `pub fn walk_fn(f: i64, round: i64) -> ViewSummary` | the skeleton, with the events as stubs |
  | `summary.tach` | `pub struct ViewSummary { ret: [i64; 4], sto: [i64; 4], top: bool, declared: bool }`, `summary_of(f) -> ViewSummary`, `summary_text(out, s)`, `parse_views_attr` | `summary_of` returns the parametric floor for a generic result, else `top` (one region) |
  | `diag.tach` | the codes of §4, `own_error(node, code, msg, other)`, `own_help`, `own_try`, and the `explain` entries | the codes and helpers, with stub entries |
  | `observe.tach` | `own_state_at(file, line, col)` for `query own` | a stub |
- **The query cache** gets slots for kinds and summaries (a cache format bump).
- **The legacy `*T` rule.**
- **compiler/src stays clean under `report`.** §8 found nothing to fix: 0 moves, and its 1 one-region case disappears with summaries.
- **The tests.** tests/values-proto becomes `own_*` cases in tests/run, with expected outputs that the tasks update.

**Then, in parallel:**

| task | owns | provides |
|---|---|---|
| T1 Moves and drops | front/own/{moves,drops,glue}.tach; the hooks in `check_block`, `check_function` and `check_defer` | the move events (init/move bits, partial moves, binding modes for `match` through references); drop placeholders and their filling; generated glue (struct, tuple, enum, array, closure); drop flags; owned temporaries; the assignment desugaring; `own.moved`, `own.move_out`, `own.partial`, `own.drop_view` |
| T2 Views and exclusivity | front/own/{views,calls}.tach; closures/escape.tach (subsumed) | the view events (two-level origins, slots, invalidation, implicit liveness); pending arguments, two-phase receivers, reborrows, `for` loans, f-string holes as borrows; exclusivity; escapes; coarse statics; `own.conflict`, `own.escape`, `own.static`; `observe.tach`; **the cost budget** |
| T3 View summaries | front/own/{summary,infer}.tach; `query views`, `--print-views` | the driver: SCC order over the effects graph, the fixpoint for recursive SCCs, errors only from the final round; the parametric floor; the type filter; indirect calls through address-taken functions; `#[views]`/`stores` checked (`own.views`); the why-chains; the cache |
| T4 std on values | compiler/std/*.tach | Drop impls; a consuming `free`; `v[i]`; `as_mut_slice`, `iter_ref`, `swap`/`take`/`replace`; `sort(&mut [T])` (the stable sort's ping-pong buffers on indices or raw pointers, §8.4); `sort_by` closures taking `&T`; Scanner, SliceIter, split and Fmt (`&mut Buf`) as views; `Clone` bounds; `Buf::from`; **`#[views]` pins on every public std function that returns or stores views** |
| T5 Optimizer | middle/{copies,gvn,licm,vectorize,inline}.tach | COPY_MOVE elision, NRVO, noalias/readonly gated on `error` mode, noalias scopes through inlining, drop inlining, the bench gate |
| T6 Tools and guide | tools/*, compiler/guide/{memory,unsafe,rust,errors,core}.md and a new topic `views`, docs | `query own`; the `explain own.*` entries; `fix --values`; fmt; `refactor signature` with `&`/`&mut`; `refactor field --type` with `--default`; **tests/own-try, which runs every `try:` of §2.9**; the guide rewritten (memory and unsafe lose "the one gap") |
| T7 Migration | tests/, examples/, bench/, tests/agent-eval | `fix --values` applied; the hand cases (bigint's operators, ledger's two `get_mut`, 15-multi-module's leaked Bufs, the aliasing opt tests); the eval solutions re-run |

**Where the tasks meet:**
- **T1 and T2** share one walk: they implement disjoint event hooks over Phase 0's `state.tach` layout, and neither changes `walk.tach`'s traversal without the lead.
- **T2 and T3** meet at `walk_fn` and `summary_of`.
  - T2 develops against `summary_of`'s fallback, which is one region, so T2's own tests use only non-generic callees or `#[views]`-declared ones.
  - T3 develops its driver against declared summaries and the parametric floor; tests/own_views_* declare what they need.
  - Real inference appears when both have landed. One integration commit (T3's) switches the fallback off.
- **T4's pins** are checked once T3 lands. Until then they are trusted, as declarations are.
- **T5** rebases on the compile-speed track's per-function pipeline (the roadmap's 0.17 speed track), which also touches middle/.

**Merge order:** Phase 0; T1 and T4 (they change what programs mean); T2; T3; T5; T6 throughout; T7 last. Gate: `gate.sh --quick` plus a `--check-alloc` run of the suite, and the own-pass budget (§4).

**The split between 0.17.0 and 0.17.1, re-checked.**
- **Into 0.17.0:**
  - inferred summaries with `#[views]` (new; in the first version they were only an attribute held in reserve). They are what keeps agents' parsers from being rejected, and U4's errors depend on them;
  - the type filter;
  - the owned-assignment desugaring and the enum/array glue (the corpus needs them, §8.3).
- **Stays in 0.17.1:**
  - projections (`-> &T`, `-> &mut T`, reference type arguments, `HashMap::get_mut -> Option<&mut V>`, `iter_mut`), because they need reference types as type arguments. Until then, agents' two-`get_mut` code (ledger) is a real conflict with a `try:`, as in Rust;
  - written-static sets in effects, and summaries naming statics (`views(TYPES)`); the summary format reserves static names;
  - `&Arena` containers with safe `reset`/`free_all` (U3), and `FixedBuf` views;
  - value-level allocator naming (0.16 U2);
  - `*T` parameters deprecated (a warning), ahead of 0.18 making them raw;
  - per-target `stores` (`names <- word` rather than one set for all `&mut` parameters), if the evals ask for it: the prototype needed no more than one set.
- **The fallback.** If T3 is not ready for 0.17.0, 0.17.0 ships with one region plus the parametric floor and the type filter, and `own.conflict` errors that come only from a non-inferred summary are *warnings* until 0.17.1 (see U4). That keeps the no-UB promise for everything else without rejecting 3% of agents' code.

## 7. Open questions

**For the user (U1–U4):**
- **U1. Surface spelling.**
  - (A) Rust's: `x: T` moves, `&T`/`&mut T`, `&mut x` at calls.
  - (B) Hylo/Swift's: `x: T` borrowed read-only, `inout T` with `&x`, `sink T`.

  The semantics are identical (second-class, inferred view summaries). *Recommendation: A.* Agents write it already, call sites show mutation, and B's default-borrow advantage (no `&` on read-only arguments) does not outweigh a second vocabulary. The roadmap's `inout` is spelled `&mut`.
- **U2. Slices.**
  - Split into read-only `[T]` and exclusive `&mut [T]`.
  - Or keep today's writable, aliasable `[T]`.

  *Recommendation: split.* It gives the optimizer noalias/readonly facts (vectorizer run-time checks go away), it is Rust's rule agents know, and it is one aliasing rule instead of two. The cost is rewriting written slice parameters, which `fix` handles.
- **U3. Arena handles as references** (`Vec<T, &Arena>`). This breaks 0.16's `Vec<T, Arena>` spelling one release after it shipped. In exchange, `reset`/`free_all` become safe and `#[scoped]`'s special rules fold into views. *Recommendation: yes, in 0.17.1, with `fix --only alloc017`.*
- **U4. Enforcement in 0.17.0.**
  - Errors, with `--values=warn` as a one-release opt-out.
  - Or warnings in 0.17 and errors in 0.17.1.

  *Recommendation: errors, with the opt-out.* The no-UB principle, and `fix --values` covers the bulk. *Revision 1:* this holds only with inferred summaries in 0.17.0, which keep agents' parsers from false errors; see §6, "The fallback".

**For the user, new in Revision 1 (taken as recommended, like U1–U4):**
- **V1. Infer view summaries** (`views(...)`, `stores(...)`, pinned by `#[views]`), instead of one region per signature plus a narrowing attribute. This reverses the first version's "kept in reserve" (§2.8) on the prototype's evidence: 3.4% of the eval's functions against a 2% gate. The price is 0.16's price for effects: a callee's body can change what its callers may do, unless it is pinned.
- **V2. The check-time budget is 8% of the type checker, not 5%** (§4). 5% needs further work beyond the lean two-level pass, and T2 can do it if compile speed must win here.
- **V3. The fallback if summaries slip:** view conflicts that come only from a non-inferred summary become warnings in 0.17.0 (§6). The alternative is to hold 0.17.0 for T3.

**Decided here** (each can be revisited):
- drops at scope end in reverse order (not at last use);
- plain/owned is structural, with no Copy derive;
- view types cannot implement Drop;
- ~~one region per signature, plus the pure-view exception~~ (replaced in Revision 1): two-level origins and inferred, pinnable view summaries, with parametric generic results, reborrows and the type filter;
- two-phase receivers (essential: 422 call sites);
- liveness is implicit: an error is reported where an invalidated view is used;
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
- compiler/src/front/effects/infer.tach (`infer_effects`, `components`, `COMPONENT`, `ADDRESS_TAKEN`): the call graph and SCC order the summaries reuse
- branch c17-proto: compiler/src/front/own/mod.tach (the walk, places, bitsets, two-level origins, `eval_call`, `check_result`, the level summaries) and drops.tach (the implicit defers): the starting code for Phase 0, T1 and T2; tests/values-proto
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/copies.tach and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/gvn.tach (`may_alias`): move elision, NRVO, noalias for `&mut`

## Decisions taken for now (to confirm with the user)

U1–U4 taken as recommended on 2026-10-15 (the user said to proceed):
- U1: Rust's spelling (`x: T` moves, `&T` / `&mut T`, `&mut x` at calls);
  the roadmap's `inout` is spelled `&mut`.
- U2: slices split into read-only `[T]` and exclusive `&mut [T]`.
- U3: arena handles become references (`Vec<T, &Arena>`) in 0.17.1, with
  `fix --only alloc017`.
- U4: errors in 0.17.0, with `--values=warn` as a one-release opt-out.

Checked against the prototype (Revision 1):
- U1: not touched by the measurements.
- U2: supported. Split slices make the 9 deliberate aliasing tests and std's stable sort errors, which is the intent. noalias pays off mainly in safety, plus the occasional kernel (§8.5).
- U3: not measured (0.17.1).
- **U4: kept, with a condition for the user.** Errors in 0.17.0 are right only if inferred summaries (V1) ship in 0.17.0. Under the first version's one-region rule, 3.4% of agent-written functions would have been rejected wrongly. If T3 slips, apply V3, warnings for summary-only conflicts, or hold the release.


## 8. Prototype results (§6, branch c17-proto, 2026-10-15)

*This section records the measurements against the first version of the design: "§2.4" and "the one-region rule" here mean that version. R1–R4 are its names for the analysis rules that Revision 1 adopted.*

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
