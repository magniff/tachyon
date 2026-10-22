# Parameter conventions: `let`, `inout`, `sink` (design)

Written 2026-10-21 on branch design-mvs (release-0.20: v0.19.1 plus the
0.20 std work). Nothing is implemented here.

The user's decision of 2026-10-18: "lets go full blown mvs + effect
system and explicit allocators as of rn and just face the music ... also
change the syntax to use the real deal let, inout and sink keywords,
lets not pretend we are rust, we are not."

What this design changes is the **surface**. The semantics stay what
0.17 built and 0.18.1 finished ([value-semantics.md](value-semantics.md)):
mutable value semantics, second-class references, views with inferred
summaries, `Drop`, moves, effects and explicit allocators. The Rust-like
spelling (`&T`, `&mut T`, `&mut x`, `let mut`, `*r` through a reference)
is replaced by spellings that say what vole means. Evals are off until
0.24, so each choice below is made on design merit and consistency, not
on Rust familiarity. The language becomes **vole** in 0.24 (`volec`,
`.vl`); this design keeps the name vole, and its diagnostics name no
language so that the rename changes none of them.

Sources: value-semantics.md (§2, the "as built" sections, V4),
docs/grammar.md (0.17 "familiar forms", 0.18.1), compiler/guide/{core,
memory, views, rust, allocators, effects}.md,
tests/agent-eval/prompts/guide-mini.md, front/parser/items/params.vl,
front/own/kinds.vl (`param_mode`), and probes run with this branch's
compiler.

## 0. Summary

```tach
fn total(v: Vec<i64>) -> i64 { ... }            // let (the default): borrowed, read-only
fn fill(v: inout Vec<i64>, n: i64) { ... }      // inout: exclusive, changes reach the caller
fn keep(store: inout Vec<Buf>, b: sink Buf) { store.push(b); }   // sink: the callee takes it

impl Counter {
    fn get(self) -> i64 { self.n }              // let self
    fn bump(inout self) { self.n += 1; }        // inout self
    fn finish(sink self) -> Report { ... }      // sink self
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);         // var: a mutable binding (was let mut)
    fill(&v, 4);                                // & marks the inout argument
    println(total(v));                          // a let argument: no marker
    inout r = &v;                               // an inout binding (was let r = &mut v)
    fill(&r, 1);
    r.push(9);                                  // an access is used as the value itself: no *r
}
```

- **Parameters** take a convention: `let` (the default, not written),
  `inout` or `sink`, written before the type as Hylo writes it: `x:
  inout T`. Receivers: `self`, `inout self`, `sink self`. No `set`.
- **Call sites:** `&x` marks an inout argument and only that; let and
  sink arguments are unmarked. A move into a sink parameter is visible
  because the parameter says sink and the source is dead after it.
- **Accesses are transparent.** A binding that holds an access (a let
  or inout parameter, an `inout` local, an access field) is used as the
  value it designates: `out = acc`, `n + 1`, `v.push(1)`. `*` is only
  for raw pointers.
- **Types.** `&T` and `&mut T` disappear. An access in a type is `let
  T` or `inout T` (a field, a result, a type argument). Slices are
  accesses already: `[T]` is `let [T]`, and `&mut [T]` becomes `inout
  [T]`. Raw `*T` is unchanged.
- **Locals.** `let` stays an owning binding, which moves from a local
  it owns, and *borrows* a part it cannot take (an element, a field
  through an access). That case was an `own.move_out` error, so no
  accepted program changes meaning. `var` replaces `let mut`. `inout x
  = &place;` is the exclusive local access. `static var` replaces `static
  mut`, so `mut` leaves the language.
- **Returned parts** (0.17.1's "references as results"): a function may
  return `let T`, `inout T` or `Option` of one. Its view summary is
  inferred as any other. There are no `yield` subscripts yet.
- **Rust spellings** are errors that are recognized and fixed: `&T`,
  `&mut x`, `&self`, `let mut`, `*r` on an access, `move ||` and
  `static mut` each get a code and a `try:` line with the new form.
- **Bootstrap.** 0.20 brings the new syntax. compiler/src keeps the 0.19
  spelling under a root pragma that only it may carry. In 0.21's first
  commit, `fix --only conventions` migrates compiler/src, and the old
  syntax is removed (§9).

## 1. What Hylo does, and what I am unsure of

Hylo, which this design takes the words from, as far as I know it:

- **Parameter conventions:** `let` (the default: an immutable borrow),
  `inout` (exclusive mutable access), `sink` (ownership passes to the
  callee), `set` (the callee initializes uninitialized storage). They
  are written before the type: `fun f(_ x: inout Int)`. *Sure.*
- **`&x` marks an inout argument** at the call site. *Sure.* As I
  understand it, Hylo also marks the receiver of a mutating method call
  (`&a.append(x)`), unlike Swift. *Fairly sure, not certain.*
- **Bindings:** `let x = e` is an immutable projection (a borrow) of e,
  `var x = e` owns a mutable value, `inout x = &y` is a mutable
  projection, and `sink let x = e` owns an immutable one. *Fairly sure*
  of all four; I do not know every rule for when `let` of a temporary
  owns it.
- **Subscripts** project parts with `yield`, as `let`, `inout`, `sink`
  and `set` variants of one subscript (a *bundle*); methods can be
  bundles too, as in `fun f() { let { .. } inout { .. } sink { .. } }`.
  *Sure* of the concept; I would not vouch for the exact syntax.
- `fun` declares functions. Parameters have argument labels (`_ x`). Hylo
  has no stored references in types. I believe there was work on
  *remote parts* (a projection stored in a type), but I do not know its
  state, so this design does not rely on it.
- I am *not sure* whether a `sink` parameter is mutable in the callee.
  This design makes it mutable (§2.4), for vole's own reasons.

Swift is the other precedent. It has `inout` with `&x` at the call,
mutating methods called without a marker (`a.append(x)`), and
`borrowing`/`consuming` parameter modifiers (SE-0377), also written
before the type. *Sure.*

## 2. Parameter conventions (question 1)

### 2.1 The three conventions

| convention | written | what the callee gets | the caller passes |
|---|---|---|---|
| **let** (default) | `x: T` (`x: let T` is accepted; `fmt` drops the `let`) | read-only access for the call; the caller keeps the value | a place (borrowed), or any value (a temporary for the call) |
| **inout** | `x: inout T` | exclusive access; writes reach the caller | `&place` |
| **sink** | `x: sink T` | ownership; the binding is the callee's, mutable | a value: a temporary, or a local it owns (which moves) |

**D1. `let` is the implicit default.** It is Hylo's default and Swift's.
It is also the commonest case: in std, read-only receivers outnumber
mutating ones about 2.5 to 1 (`self: &` against `self: &mut`). It makes
the *harmless* call the unmarked one: under `let` a function cannot
change or keep what it is given, so it needs no marker at the call. The
two that matter, mutation and giving up ownership, are visible: `inout`
at the call through `&`, and `sink` through the parameter and the dead
source. 0.17's rule 4 of `fix --values` existed only because by-value
owned parameters moved by default; with `let` as the default, a reader
of a `Vec` is right without thinking.

**D2. Spelling: the convention goes before the type, `x: inout T`
(Hylo's and Swift's placement), not before the name.** The convention
belongs with the type because vole also needs accesses in places
that have no parameter name: fields (`q: inout Query`), results (`->
inout V`), type arguments (`Option<inout V>`) and function types (`fn(inout
Sum, i64)`). So one form serves everywhere. A prefix spelling (`inout
x: T`) would need the type form anyway, making two spellings of one
idea. Receivers are the exception, because they have no type to put it
before (§4).

**D3. No `set`.** Hylo's `set` initializes storage the caller has not
initialized. Vole has no uninitialized locals (`let x;` is not
allowed, and that stays), so a `set` argument could only be a place
whose old value is dropped first, which is `inout` plus an assignment.
Out-parameters are results: a function returns its values (a tuple or a
struct), and NRVO (0.17, optimizer item 1) makes that free. `set` is not
reserved: there are 132 identifiers named `set` in tests/examples/bench.
`x: set T` in a parameter list is the error `conv.set` ("there is no
`set` convention: return the value"). It can be added later if
uninitialized locals ever come.

**D4. `sink` bindings are mutable.** The callee owns the value, so no
one else can see it change. This takes over the `mut x: T` parameter,
which 0.19 has 1,442 times in compiler/src (cursor loops) and as `mut
self: T` in builders. `let` parameters are immutable. `inout` ones are
written through. There is no `var` convention: Swift removed `var`
parameters (SE-0003) because a local copy's mutability is an
implementation detail, and here `sink` is that copy.

### 2.2 Plain, view and owned types under each convention

The three kinds of 0.17 (§2.1 there) decide what each convention costs:

| | plain (`i64`, `Point`) | copyable view (`[u8]`, `Tok { text: [u8] }`, `Scanner`) | owned (`Vec`, `Buf`, a struct with one) or a move-only view (holds an `inout`) |
|---|---|---|---|
| `let` | a **copy**, immutable; no loan on the source | a copy of the view, immutable | **borrowed**: an address, read-only for the call, no copy, no drop |
| `inout` | an address; `&n` at the call | an address of the view (its fields may be changed: `pos`, `text`) | an address, exclusive |
| `sink` | a copy the callee may change | a copy (a move-only view moves) | **moved**: the caller's binding is dead until reassigned; the callee drops it |

- **For plain types `let` is a copy, not a borrow (D5).** It is
  observably the same as a borrow, except that a copy takes no loan.
  So `f(s.n, &s)` is legal, as Rust's `Copy` makes it, where a borrow
  would conflict. The ABI is the compiler's choice: registers, or the
  caller's slot address for a large struct (0.17's optimizer item 2:
  exclusivity guarantees that nothing writes it during the call). In a
  generic function the instance decides: `x: T` is a copy where T is
  plain and an address where it is owned. That is decided per instance,
  as moves and drops already are.
- **For copyable types `let` and `sink` differ only in mutability.** So
  the convention a program must get right is `inout`, plus `sink` on
  owned types. `fn add(v: inout Vec<Item>, it: Item)` is right for a
  view-holding `Item`: `push` takes `x: sink T`, and a copyable value
  passes from a let binding to a sink by copy.
- A `let` argument of an owned type that is a temporary (`total(make())`)
  is dropped after the call, at the end of the statement, as
  temporaries are today.

### 2.3 What a convention means to the own pass

Nothing new. Each convention maps onto 0.17's parameter modes
(kinds.vl `param_mode`), so the walk, the loans, the summaries and
exclusivity stay as built:

| convention | type kind | `param_mode` | internal parameter type |
|---|---|---|---|
| let | plain, or a copyable view | `P_VALUE` / `P_VIEW` | T (immutable binding) |
| let | owned, or a move-only view | `P_SHARED` | `&T` (`REF_SHARED`), transparent |
| inout | any (not a slice) | `P_MUT` | `&mut T` (`REF_MUT`), transparent |
| inout | `[T]` | `P_MUT_VIEW` | `&mut [T]` |
| sink | any | `P_VALUE` / `P_VIEW` | T (mutable binding) |
| raw | `*T` | `P_RAW` | `*T` |

"Transparent" (§5.1) is a flag on the binding. The optimizer's noalias
and read-only facts come from the same modes, so they are unchanged.

### 2.4 Effects and allocators (question 6)

```tach
#[effects(alloc(Gpa), panic)]
fn grow(v: inout Vec<i64>) { v.push(1); }

fn squares(n: i64, gpa: Gpa) -> Vec<i64> { ... }      // the allocator: let (a copy: Gpa is plain, zero-sized)

fn keep_words(text: [u8], into: inout Vec<[u8]>) { ... }   // stores(text): inferred as before

fn build(t: inout Vec<Node, let Arena>, d: i64) { ... }    // U3's arena containers, when they land
```

- **D6. Allocators are passed `let`, so no word is written.** `Gpa` is
  plain and zero-sized, so `let` copies it. An arena is shared by every
  container that allocates from it, so it can only be shared: an
  `inout gpa` or `inout arena` would allow one container per allocator
  at a time. This is why the `Allocator` trait's methods take `self`
  (let), with interior mutation in the arena's unsafe body, as Rust's
  `Allocator` takes `&self`. U3 (value-semantics.md §2.5), not yet built,
  is spelled `Vec<T, let Arena>`: a container on an arena holds a let
  access to it, so it is a view of the arena and cannot outlive it.
  `arena.reset()` takes `inout self`, legal only while nothing views
  the arena. The words now say what U3 meant.
- **Effects are unchanged, and the two parts of a signature now say
  different things.** The conventions say what a call may change of
  its arguments (`inout`) and keep (`sink`). The effects say what it
  may do beyond them (allocate, io, statics, panic). `#[pure]` (no
  alloc, io or global) still permits writes through `inout` parameters,
  because they are in the signature. The pins read naturally:
  `#[effects(alloc(Gpa))] fn grow(v: inout Vec<i64>)`.
- `#[views(self)]`, `#[views(*self)]` and `#[stores(word)]` keep their
  spelling. `*self` there is summary notation ("the views `self`
  holds"), not a dereference, and it is rarely written.

### 2.5 Other positions

- **Defaults and named arguments.** `let` and `sink` parameters take
  defaults (`b: i64 = 2`). An `inout` parameter cannot, because it needs
  a caller's place. Named: `f(1, out: &acc)`.
- **Function types and closures.** Conventions are part of a function's
  type: `fn(inout Sum, i64)`, `F: Fn(inout Sum, i64) -> bool`. Closure
  parameters are `let` unless annotated (`|a, b| a.qty < b.qty`, `|s:
  inout Sum, x| s.total += x`).
- **`extern "C"`.** C has only values and pointers. An extern function's
  parameters are by value (`let`, the default, a C value). `inout` and
  `sink` there are the error `conv.extern` ("C takes a pointer: `p:
  *T`, pass `&x`"). A vole function exported to C follows the same
  rule.
- **`sink` outside parameters** is the error `conv.sink_type`: a field
  or a result of type T already owns its value.

## 3. Call sites (question 2)

**D7. `&place` marks an inout argument, and nothing else.** Writing
`&x` hands an exclusive access to x to someone: an inout parameter, an
`inout` binding, an `inout` field of a struct literal, the scrutinee of
a mutating `match`, a mutating `for`, or a `-> inout T` result.

| argument for | write | missing or extra marker |
|---|---|---|
| `x: T` (let) | `f(v)`, `f(v.len())`, `f(make())` | `f(&v)`: `conv.marker_extra` |
| `x: inout T` | `f(&v)`, `f(&v[i])`, `f(&self.items)`, `f(&r)` for an inout binding r | `f(v)`: `conv.marker` |
| `x: inout [T]` | `sort(&v)` (a Vec, Buf or array place gives its elements), `sort(&v[a..b])` | |
| `x: sink T` | `f(v)` (moves an owned local), `f(make())`, `f(v.clone())` | `f(&v)`: `conv.marker_extra` |
| `p: *T` (raw) | `f(&x)`: converts to the raw pointer (the call takes an exclusive loan), or a raw pointer | |

- **An argument that already is an inout access needs no `&`.** This is
  a call returning `-> inout T` (`sort(v.as_mut_slice())`), or an
  `Option<inout V>` unwrapped. `&` turns a *place* into an access, so
  `&` on an access is `conv.marker_extra`. A *named* access (an `inout`
  binding or parameter) is used as the place it designates, so passing
  it on is `f(&r)`, a reborrow.
- **`&` of something that is not a place** (a call's value, a literal)
  is `conv.place`: "'&' lends a place; 'make()' is a temporary". The
  `try:` is `var t = make(); f(&t);`. 0.18.1's `&f(x)` temporaries are
  no longer needed, because a let parameter takes a temporary as it is.
- **D8. Sink arguments are unmarked.** The move is visible in three
  ways: the parameter says sink, the source is dead afterwards, and any
  later use is `own.moved`, whose message names the sink parameter.
  Swift's `consume x` and Rust's implicit moves are the precedents. A
  marker on every sink argument (every `push(x)`, every struct literal
  field) would be noise on the commonest calls. For plain and copyable
  types a sink argument is a copy, and nothing is dead.
- **Exclusivity and evaluation order are unchanged** (left to right,
  two-phase receivers): `f(&a, a.len())` conflicts, as `f(&mut a,
  a.len())` did. `v.push(v.len())` is fine.

The diagnostics, each one line with `try:` lines that run as they are:

```text
main.vl:7:10: error[conv.marker] 'fill' takes 'v' inout (it may change 'v'): mark the argument | try: volec edit patch main.vl:7 --old 'fill(v, 3)' --new 'fill(&v, 3)'
main.vl:8:15: error[conv.marker_extra] '&' marks an argument the callee may change; 'total' takes 'v' let (it only reads) | try: volec edit patch main.vl:8 --old 'total(&v)' --new 'total(v)'
main.vl:9:11: error[conv.place] '&' lends a place, and 'make()' is a temporary | help: bind it first | try: volec edit patch main.vl:9 --old 'grow(&make())' --new 'var t = make(); grow(&t)'
```

When the callee declares `inout` but never writes the parameter (the
own pass knows: no write, no inout call, no inout store reaches it), a
second `try:` changes the callee instead, with every call:

```text
main.vl:7:10: error[conv.marker] 'show' takes 'v' inout (it may change 'v'): mark the argument | help: 'show' never changes 'v': it could take it let | try: volec edit patch main.vl:7 --old 'show(v)' --new 'show(&v)' | try: volec refactor signature show --convention v let
```

## 4. Receivers (question 3)

**D9. `self`, `inout self` and `sink self`, with the long form `self:
inout Self` also accepted. `fmt` writes the short form.**

```tach
impl Vec<T, A> {
    fn len(self) -> i64 { self.len }               // let self
    fn push(inout self, x: sink T) { ... }
    fn into_buf(sink self) -> Buf { ... }
    fn as_mut_slice(inout self) -> inout [T] { ... }
}
impl [T] { fn swap(inout self, i: i64, j: i64) { ... } }   // Self = [T]: inout self is today's self: &mut [T]
```

- A receiver has no type to put the convention before, so its prefix
  form is the natural short form. It needs no new rule beyond "a
  receiver is named self". `self` alone (`fn get(self)`) is legal from
  now on; 0.14–0.19 rejected it with a help line. `self: *Self` stays
  the raw receiver.
- **D10. Receivers are borrowed automatically, without `&`**, as Swift
  does and as 0.17 did: `v.push(1)` takes `&v`, `p.get()` lends p, and
  `r.finish()` with `sink self` moves r. Hylo marks a mutating receiver
  (`&v.push(1)`, as I understand it), and that is rejected here. A
  method name says what the call does far more often than an argument's
  position does (push, insert, sort, clear). The receiver is the
  commonest call there is, and the two-phase rule makes it safe (422
  call sites in the 0.17 corpus read the receiver in their arguments).
  Mutation of a local through a method is visible at its declaration,
  which must be `var`.
- A method that needs a receiver it cannot have is an error naming the
  convention. On a `let` binding or parameter: `own.readonly` "'v' is
  let here: 'v.push(1)' changes it" (§10). On a part it cannot give up,
  with `sink self`: `own.move_out`.
- In the `T::f(args)` form the receiver is an ordinary first argument:
  `Vec::push(&v, 1)`.
- Traits declare receivers the same way: `fn eq(self, other: Self) ->
  bool`, `fn next(inout self) -> Option<Self::Item>`, `fn drop(inout
  self)`, `fn fmt(self, f: inout Fmt)`, `fn clone(self) -> Self`.
  - **D11. The operator traits (`Add`, `Sub`, `Mul`, ...) take both
    operands `let`**: `fn add(self, rhs: Self) -> Self`. For plain types
    nothing changes. For an owned type (bigint) `a + b` stops consuming
    its operands. That is what bigint's hand change in 0.17 T7 had to
    build around: borrowing `plus`/`minus`/`times` that did the work
    behind consuming operators.

## 5. Local bindings (question 4)

### 5.1 Accesses are transparent

**D12. A binding that holds an access is used as the value it
designates.** This covers a let or inout parameter of an owned type, an
`inout` local, an access field (`self.q`) and a binding made through an
access pattern. Reading it reads the value, assigning to it writes the
value (`out = acc`, `n += 1`), and methods and fields reach it. `*r`
exists only for raw pointers. For the 0.17 own pass this is an
implicit dereference at each use of the binding: the reborrow machinery
already exists, and `&r` is a reborrow. It removes a whole class:

- the 0.17 eval's `a[0]` on a `&T` parameter, and `out[0] = acc`, which
  needed `try: *out = acc`;
- 0.18.1's rules for "references where values are expected" (an
  operand, an index, an argument), which become one rule with no
  exceptions.

Consequence: an access binding cannot be *rebound*. Today `let mut q =
&a; q = &b;` re-points q (probed: it prints the new referent). Under the
new syntax `q = x` writes through. Re-pointing an access is rare. The
alternatives are a new binding, an index, or a struct rebuilt; a cursor
over a linked structure uses indices or raw pointers. `fix` reports each
re-pointed reference local for a hand change (§9.2).

### 5.2 The four binding forms

| form | meaning | replaces |
|---|---|---|
| `let x = e` | immutable. **Owns** e when e is a temporary or a whole local (or `sink` parameter) this function owns, which then moves. **Borrows** e (a let access) when e is a part it cannot take: an element (`v[i]`), a field reached through an access, a let parameter, a std accessor's result. **Copies** a plain or copyable value. | `let x = e` |
| `var x = e` | mutable, always owns: moves from what it owns, copies a copyable value. A part it cannot take is `own.move_out` (`try:` `.clone()`, `std::take(&v[i])`, `let` to borrow it). | `let mut x = e` |
| `inout x = &place` | an exclusive access to `place`, transparent: `x.push(1)`, `x = y` writes the place | `let x = &mut place` |
| `inout x = e` | the same, with e already an inout access (`m.get_or_insert(k, 0)`, `opt.unwrap()` on an `Option<inout V>`) | `let x = m.get_mut(k)...` |

**D13. `let` stays an owning binding; it is not Hylo's borrow binding,
except where it can only borrow.** The brief's warning is the reason.
Hylo's `let x = v` would borrow v even where v is a local the function
owns, and that changes accepted programs:

- `let it = Item { .. }; items.push(it);` would no longer move `it`:
  a sink of a let binding is an error in Hylo's model, which wants
  `var` or `sink let` there. That pattern is everywhere.
- Drops would move: the value would stay in v and be dropped at v's
  scope end, not at x's.
- `let a = v; v.push(1)` would turn from `own.moved` into
  `own.conflict`.

What this design takes from Hylo is the part that loses nothing: `let x
= v[i]` on an owned element is `own.move_out` today (probed: `let row =
vs[0];` with `vs: Vec<Vec<i64>>` is rejected with `try: .clone()`). Here
it borrows instead, as `for x in v` already binds owned elements and as
std's accessors (`get`, `last`, `unwrap`) already give borrowed copies
(0.17 T7). So:

- **no program that compiles today changes meaning**: moves stay moves,
  copies stay copies, and only an error becomes a borrow;
- the user can name a part without a copy or an index.

The rule a reader keeps is "let gives the binding the value: it takes
it from what this function owns, and borrows it from anything else".

**D14. `var` replaces `let mut`.** `let mut` is Rust's two-word form of
one idea. `var` is Swift's and Hylo's, and it pairs with `let`.
Everywhere a binding is made mutable, `var` is written:

- `var x = e;`
- `var (a, b) = t;` makes both mutable; `let (a, var b) = t;` only b;
- `Some(var n) =>` in a match arm;
- `static var X: T = ...` for `static mut`;
- `extern "C" { static var errno: i32; }`.

**D15. `mut` leaves the language.** It was `let mut`, `mut x:`
parameters (now `sink`, §2.1), `static mut`, patterns and `&mut`. After
0.21 it is reserved: every use is `conv.rust` with the new form.

**D16. `inout` locals exist** (Hylo has them, I believe). They replace
`let r = &mut ps;` passed to several helpers. That pattern is the 0.17
eval's "situation 7", 134 errors in 8 runs before 0.17 made it legal,
and it stays legal: `inout p = &ps; expect_kw(&p, ..)?; bump(&p);`.
There is no shared-access local of a whole owned local: a `let`
argument borrows the place directly, so `let r = &x; f(r); g(r)` is
`f(x); g(x)`.

**D17. No `sink let`.** `let` already owns what it can take.

### 5.3 Loops and patterns

- `for x in v` binds each element `let`, as today: a copy of a plain
  element, a borrow of an owned one. **`for inout x in &v { x += 1 }`**
  (D18, with the projections, §6.3) binds each element inout, which is
  Rust's `iter_mut`; the guide's workaround today is `for i in
  0..s.len() { s[i] += 1 }`. `&v` marks that the loop changes v.
  `v.into_iter()` consumes, as before.
- **Patterns through accesses** keep 0.18.1's default binding modes,
  now transparent. Matching through a let access binds let accesses,
  and matching `&place` (a mutating match, D7) binds inout accesses:
  `match e { E::A(n) => n + 1 }` with `e: E` a let parameter (was `*n`),
  and `match &self.state { S::Run(n) => n += 1, _ => {} }`. Matching an
  owned local by value still moves its parts out.
- `if let`, `while let` and `let ... else` follow `let` (D13).

### 5.4 Closures

**D19. `sink |..| body` replaces `move |..| body`.** One word means
"takes ownership" in parameters, receivers and captures. Capture modes
are otherwise 0.14's, in the new words: a `var` is captured inout, an
owned `let` by let access, a plain `let` by copy. `sink` and `inout`
become keywords in new code (D27), so `sink |x|` cannot be read as `sink
| x | ...`.

## 6. Types (question 5)

### 6.1 `&T` and `&mut T` disappear

**D20. An access in a type is `let T` or `inout T`.** Parameters are §2.
Elsewhere:

| position | example | meaning |
|---|---|---|
| a field | `struct Parser { toks: [Tok], q: inout Query, cfg: let Config }` | the struct is a view (0.17 kinds); with an `inout` field it is move-only |
| a result | `fn first(self) -> let T`, `fn top(inout self) -> inout T` | a projection (§6.3) |
| a type argument | `Option<let T>`, `Option<inout V>` | a view value (minimal version: `Option` only, §6.3) |
| a function type | `fn(inout Sum, i64)` | a parameter's convention |
| a local's annotation | `let x: let T = ...` (rare) | |

- A struct literal's access field takes what a parameter of that
  convention takes: `Parser { toks: toks, pos: 0, q: &query, cfg: cfg
  }`.
- `[T]` **is** `let [T]`: a slice is an access to elements, never an
  owned value, so its default is `let` in every position, a field
  included. `inout [T]` is 0.17's `&mut [T]`, the exclusive writable
  view. It is not "a slice variable the callee may re-point": to
  advance a slice for a caller, return the rest, or keep it in a struct
  with an `inout self` method (`self.rest = self.rest[n..]`). That is
  what 0.19 offers as well, since `&mut [T]` means the same.
- Coercions keep 0.17's, in the new words. A place of type `Vec<T>`,
  `Buf` or `[T; N]` passed where `[T]` is wanted gives its elements:
  `sum(v)` for `sum(s: [i64])`, a let borrow of `v.as_slice()`. Passed
  as `&v` where `inout [T]` is wanted, it gives `&v[..]`. An `inout T`
  converts where `let T` is wanted, and `inout [T]` where `[T]` is.
- `let T` and `inout T` of a plain T are legal (a field `n: inout i64`
  that a parser counts with). Such a struct is a view.

### 6.2 Views

Nothing changes but the words. The kinds of 0.17 are computed as
before:

- *plain*;
- *owned*;
- *view*: holds a slice, an access, a by-access closure, or a part that
  is one;
- *move-only view*: holds an `inout` access or an `inout [T]`, which 0.17
  called the views with `&mut`.

Views are second-class: they live in locals, parameters, fields and
containers, and the own pass keeps each inside what it views, with
inferred summaries (`views(self)`, `views(*self)`, `stores(word)`). The
parser of §11.2 is the evals' pattern, and it checks clean as today.

### 6.3 Returned parts: projections, minimal version

0.17 deferred `-> &T` and `Option<&mut V>` to "0.17.1" because they need
references as type arguments (`decay_ref` in `unify`). This is that
item, in the new spelling:

**D21. A function may return an access: `-> let T`, `-> inout T`,
`-> Option<let T>`, `-> Option<inout T>`.** This is a *projection*.

```tach
impl<K, V, A> HashMap<K, V, A> {
    fn get_mut(inout self, k: K) -> Option<inout V> { ... }
    fn get_or_insert(inout self, k: sink K, v: sink V) -> inout V { ... }
}
impl<T, A> Vec<T, A> {
    fn last_mut(inout self) -> Option<inout T> { ... }
    fn as_mut_slice(inout self) -> inout [T] { ... }
}
fn largest(v: Vec<Big>) -> let Big { var i = 0; ...; v[i] }   // a let result: the tail is a place

m.get_or_insert("k", 0) += 1;                    // was: m.get_or_insert("k", 0)[0] += 1
if let Some(c) = m.get_mut(word) { c += 1; }     // c: an inout binding
inout top = m.get_or_insert(k, 0);              // already an access: no &
sort(v.as_mut_slice());                          // likewise
```

- **The body** returns a place: plainly for `let T`, as `&place` for
  `inout T`, the way Hylo's inout subscript writes `yield &x`.
  `Some(&self.buf[i])` for an `Option<inout T>`. The place must be
  reachable from a parameter: through an `inout` parameter for an
  `inout` result, otherwise `own.readonly`; not from a local, otherwise
  `own.escape`. The summary is inferred as for any view-returning
  function (`views(self)` for `get_mut`) and is pinned in std
  (`#[views(self)]`).
- **The caller** treats the result as a view of what the summary says
  (a loan on `m` for `get_mut`), with NLL liveness. A second `get_mut`
  of the same map while the first result is used is `own.conflict`, as
  in Rust. A let result is a shared loan.
- **Lowering:** an address, as `&mut T` results would have been. A
  projection costs a pointer return, with no coroutine.
- **Why not Hylo's `subscript` with `yield`?** Hylo yields so that code
  can run after the access: write-back, invariants, computed
  properties. Vole's accesses are addresses, so every projection
  that points at storage is a function returning one. A `yield` form
  would need coroutine lowering or forced inlining for the case of a
  part that is computed rather than stored (a bit field, a proxy), and
  nothing in std or the corpus needs that now. It is kept as a later
  extension (`subscript` items whose `let`/`inout` bodies yield), and
  the result spelling `-> inout T` is the one it would use.
- **Minimal scope.** The minimal version covers bare accesses and
  `Option` of one as results and type arguments. Others (`Vec<let
  Node>`, tuples of accesses for `split_at_mut`-like pairs) come when a
  program needs them: their summaries already have the shape (two-level
  origins).
- **Index projections are unchanged.** `v[i]` and `v[a..b]` on Vec and
  Buf are places, as 0.17 made them. A user `Index` trait with `-> let
  T` / `-> inout T` methods would be the next step, and is not in this
  design.
- Today's one-element views (`get_mut -> Option<[V]>`, `get_or_insert
  -> [V]`, idiom `[0] += 1`) stay for one release as deprecated
  aliases, so that 0.20's migration can rewrite their users (§9.2,
  rule 9).

## 7. The familiar forms of the night of 10-15 and of 0.17/0.18.1 (question 7)

The principle: **a Rust form that conflicts with the new vocabulary is
not accepted, but it is recognized**, and its diagnostic gives the new
form in a `try:` line (cheap, and it helps anyone who comes from Rust).
A form that does not conflict and is good on its own merits stays as
vole's own.

| form (where it came from) | decision | why |
|---|---|---|
| `&mut x` read as `&x` (night), then tracked `&mut x` (0.17) | **removed**: `conv.rust` "'&mut x' is Rust's spelling; an inout argument is '&x'" | `&x` now means exactly what `&mut x` meant |
| `&x` to a shared `&T` parameter | **removed**: `conv.marker_extra`, `try:` drops the `&` | `&` marks mutation; a let argument is unmarked |
| `&T`, `&mut T`, `&[T]`, `&mut [T]` in types | **removed**: `conv.rust`, `try:` the parameter as `x: T` / `x: inout T`, a field as `let T` / `inout T`, `[T]` / `inout [T]` | §6 |
| `&self`, `&mut self`, `self: &Self`, `self: &mut Self` | **removed**: `conv.rust`, `try:` `self` / `inout self` | §4 |
| `let mut`, `mut x` in patterns, `static mut`, `mut x: T` parameters | **removed** after migration: `conv.rust`, `try:` `var` / `static var` / `x: sink T` | D14, D15 |
| `*r` on an access, `*out = acc` | **removed**: `conv.rust` "'out' is an access, used as its value: 'out = acc'" | D12 |
| `move \|..\|` | **removed**: `conv.rust`, `try:` `sink \|..\|` | D19 |
| `&f(x)` temporaries (0.18.1) | **removed**: a let parameter takes `f(x)` as it is; to an inout one, `conv.place` | §3 |
| references read through where values are expected; an index that is `&i64` (0.18.1) | **subsumed** by transparency | D12 |
| patterns on references: default binding modes (0.18.1) | **kept**, transparent (no `*n`); `match &p` for inout bindings | §5.3 |
| `p.0`, `p.x` through a reference (night) | **kept**, subsumed by transparency; on a raw pointer still `unsafe` | |
| `v[i]`, `v[a..b]` on Vec and Buf (night) | **kept**: built-in index projections | §6.3 |
| `p[i]` on a pointer to a Vec, Buf or slice (0.17) | **kept for raw pointers** (unsafe), as now; on accesses subsumed | |
| `.len()` on slices and arrays, `v.len` on Vec/Buf/HashMap (night, 0.17) | **kept** | no conflict, not a Rust form, harmless |
| struct-like variants `V { a: A }` (0.17) | **kept** | labeled payloads are a feature on their own merit (Swift and Hylo have them) |
| the larger prelude, safe `panic`/`unreachable` (night) | **kept** | names, not syntax |
| `use sibling::X` resolving beside the module (night) | **kept** | not a Rust form (Rust rejects it) |
| `let ... else`, `x?`, closures, `impl Trait for T`, `#[derive]`, `if let` | **kept** | vole's own now; no conflict |
| Display's `fmt(&self, f: &mut Formatter)` help (0.15) | **reworded**: `fn fmt(self, f: inout Fmt)` | |

`conv.rust` is one code with one message per spelling, since a user
asks `explain conv.rust` about the family. It is permanent: after 0.21
the parser still recognizes every spelling in the table, because the
cost is a few tokens of lookahead.

## 8. Raw pointers (question 8)

V4 stands: every `*T` is raw, and dereferencing, indexing, a field or a
method through one needs `unsafe`. The new syntax makes the split
cleaner:

- `*` now means only raw pointers, in types and in expressions, because
  accesses are transparent;
- `&place` gives an inout access, which converts to `*T` where a raw
  pointer is wanted (an extern call, `&x as *u8`); the call takes an
  exclusive loan for its duration, which is sound and conservative for
  C's `const T*` too;
- a raw pointer never becomes an access implicitly. `&*p` (unsafe)
  gives an inout access of the pointee, as `&*p` gives a reference today.

The unsafe contract does not change: no second live alias of a place
under `inout`.

## 9. Migration and the bootstrap (question 9)

### 9.1 The constraint

compiler/src of release N is compiled twice:

- by release N-1, with N-1's std (the compiler that runs supplies std);
- by N itself (build2, build3), with N's std, which stdsrc.vl embeds.

std of release N is only ever compiled by compilers of release N, so
std may use the new syntax in the release that introduces it.
compiler/src may not. With R the release that brings conventions (0.20,
if this lands in 0.20 as planned; otherwise shift every number by one):

### 9.2 `fix --only conventions`

A `fix` group, like `alloc016`. It is typed: it reads the program as
0.19 meant it. Each rewrite is checked like any edit, and the result is
proven by same-output. The rules:

1. **Parameter types:**
   - `x: &T` → `x: T`; `x: &mut T` → `x: inout T`;
   - `x: &mut [T]` → `x: inout [T]`; `x: &[T]` → `x: [T]`.
2. **Receivers:**
   - `self: &Self` (or `&T`) → `self`; `self: &mut Self` → `inout self`;
   - `self: Self` → `sink self` for an owned Self, `self` for a plain one;
   - `mut self: T` → `sink self`.
3. **By-value parameters:**
   - an owned or move-only `x: T` → `x: sink T`, except where the body
     only reads x: then it is left as `x: T`, now a let. Callers then
     drop the value at their own scope end instead of the callee's.
     Same-output catches any difference in output (a `Drop` that
     prints), and where it finds one the rule keeps `sink`.
   - `mut x: T` → `x: sink T`.
   - plain and copyable `x: T` stay as they are.
4. **Call sites:**
   - `&mut e` → `&e`;
   - `&e` to a let parameter → `e`;
   - `&e` to a raw `*T` parameter is left as it is;
   - `&f(x)` temporaries → `f(x)`;
   - `v.as_mut_slice()` and `&mut a[..]` as inout arguments →
     `v.as_mut_slice()` (an access already) and `&a[..]`.
   - Where rule 3 left `x: T` on a by-value owned parameter, an argument
     `v.clone()` that existed only to survive the old move is reported,
     not removed.
5. **Dereferences of accesses:** `*r` → `r`, `*out = acc` → `out = acc`,
   `(*p).f` → `p.f`.
6. **Locals:**
   - `let mut` → `var`;
   - `let r = &mut e;` → `inout r = &e;`;
   - `let r = &e;` → its uses replaced by `e` when e is a place that is
     not reassigned while r is used, and otherwise reported;
   - a re-pointed reference local (`q = &b`) is reported for a hand
     change (§5.1).
7. **Other spellings:**
   - `static mut` → `static var`;
   - `mut x` in patterns → `var x`;
   - `move |..|` → `sink |..|`;
   - fields `&T` / `&mut T` → `let T` / `inout T`;
   - `Option<&T>` style type arguments and function types the same way;
   - closure annotations `|a: &T|` → `|a: T|`.
8. **Names:** a local, parameter or field named `var`, `inout` or `sink`
   is renamed (`var_`; a `pub` item or field `r#var`). The corpus has 49
   `var` identifiers in tests and 56 in compiler/src.
9. **The one-element views** `m.get_mut(k)` / `get_or_insert(k, v)`
   with the `[0]` idiom → the projections (§6.3). This runs only once
   T3 has landed.
10. **`fix --values`** (0.16 → 0.17 code) emits the new spelling
    directly, so old programs reach the new syntax in one run.

Volume (spelling counts; each line changes about once):

| corpus | `let mut` | `&mut ` | `: &...` types | `self: &` | `static mut` |
|---|---|---|---|---|---|
| tests/run (817 files) | 1,711 | 609 | 679 | 223 | 66 |
| tests/agent-eval (165) | 608 | 402 | 481 | 188 | 0 |
| examples (127) | 638 | 432 | 446 | 183 | 4 |
| bench (36) | 214 | 77 | 72 | 17 | 0 |
| compiler/guide (27 .md) | 108 | 169 | 129 | 65 | 3 |
| std (query grep) | about 530 | about 440 | about 770 | 466 | 27 |
| compiler/src (query grep) | 4,956 | 1,275 | 594 | 25 | 1,480 (plus 1,442 `mut` parameters) |

The proof:

- tests/run and tests/examples print what they printed, with expected
  outputs unchanged except the err-tests whose messages name the old
  spelling, which are regenerated and reviewed;
- every bench program gives the same output;
- check-tasks passes every eval solution and fails each starter as
  before;
- `tests/run.sh guide` compiles the rewritten guide;
- for std, tools/std020/same-code.sh: the same code before and after,
  since the spelling changes and the instructions do not;
- for compiler/src (R+1), `volec same-output OLD_VOLEC` plus the
  fixpoint.

### 9.3 The bootstrap transition, exactly

**Release R (0.20): the new syntax, with compiler/src on the old one.**

1. **The pragma.** compiler/src/main.vl gets, as its first line:

       // vole-syntax: 0.19 (vole's own source until 0.21; docs/design/conventions.md §9.3)

   v0.19.1 sees a comment. R's driver reads the root file's leading
   comment lines and, on exactly this line, parses the whole crate in
   **legacy mode**: the 0.19 spelling, with its meaning. std is a crate
   of its own (0.20) and is never legacy.
2. **Only the bootstrap may use it.** tests/run.sh (and so the gate)
   fails if any file other than compiler/src/main.vl carries the line.
   It is not documented in the guide or in `--help`. `explain
   syntax.legacy` says what it is for and that 0.21 removes it. A user
   program in legacy syntax gets the `conv.rust` errors and `try:
   volec fix --only conventions`. A command-line flag was the
   alternative, but every tool would have to pass it: bootstrap.sh,
   gate.sh, the hooks, query, edit, refactor, same-output and the
   refactor tests. A pragma reaches all of them, because they all parse
   the root.
3. **Legacy mode is a parser and checker front, not a second
   language.** Both surfaces produce one internal form (§2.3): a legacy
   `&T` parameter is a let parameter; `&mut T` is inout; a by-value
   owned `T` is sink (a plain one let, and `mut x: T` sink); `&mut x` is
   the inout marker; `let mut` is var. Legacy code keeps 0.18.1's
   non-transparent rules (explicit `*r`, re-pointable reference locals)
   per function, which is the `LEGACY` bit of its crate.
4. **Legacy code calling new std** (build2 and build3 compile
   compiler/src against R's std) follows these rules:

   | legacy call | new callee | accepted as |
   |---|---|---|
   | `f(&x)` | `x: T` (let) | a shared loan, the 0.19 meaning |
   | `f(x)` | `x: T` (let) | a borrow (in both modes) |
   | `f(&mut x)` | `x: inout T` | the inout marker |
   | `f(&x)` | `x: inout T` | an error, as in 0.19 (`try: &mut x`) |
   | `f(x)` | `x: sink T` | a move, the 0.19 meaning |
   | an impl `fn eq(self: &Self, o: &Self)` | trait `fn eq(self, other: Self)` | matching (legacy `&Self` is let) |
   | an impl `self: Self`, plain Self | trait `self` (let) | matching (a plain by-value parameter is let) |

   std's API changes in R are conventions only (the 0.20 std rework adds
   new items and leaves old signatures' types alone), so every legacy
   call into it resolves by this table. A std signature change that
   compiler/src cannot meet this way waits for R+1.
5. **Traits compiler/src implements and std declares raw** (the
   `Allocator` trait's `self: *Self`, value-semantics.md V4): in R the
   trait keeps `self: *Self`, and R accepts an impl that writes `self`
   (let) for it. That is sound: a stricter promise, and the same
   address. R+1 then changes the trait and the impls together.
6. **The tools are mode-aware.** query, edit, refactor and fix print
   signatures and generate text (`extract-function`'s parameters,
   `refactor signature --type`) in the crate's spelling. An agent
   editing compiler/src during R writes the 0.19 spelling, which is
   already the rule ("compiler/src uses only what the previous release
   supports").
7. **The rehearsal, in R's gate.** On a scratch copy of the tree, run
   `volec fix --only conventions` over compiler/src, delete the
   pragma, build the result with R's build2 (as R+1's build1 will be),
   run the suite with it, and run `same-output`. R does not ship unless
   the rehearsal passes, so that R+1's first step is known to work.
8. **The other 0.20 branches.** The migration of std (Phase M below)
   runs after the d20-* std branches have merged into release-0.20. A std
   branch that lands later runs `fix --only conventions` over its files
   first. After Phase M the old syntax is an error outside the pragma,
   so such a branch cannot merge unmigrated by accident.

**Release R+1 (0.21): compiler/src migrated, the old syntax removed.**
These are the first commits of 0.21, before its other work branches off:

1. **C1.** Run `volec fix --only conventions` (v0.20.0's) over
   compiler/src and delete the pragma. The bootstrap builds it with
   v0.20.0 (which accepts the new syntax) and then with itself. The
   fixpoint must hold, the suite must pass, and `same-output` must hold
   against the compiler built from the tree before C1.
2. **C2.** Delete legacy mode: the parser's old branches, the checker's
   `LEGACY` bit, the tools' legacy printer and the cross-mode table.
   `mut` becomes reserved, with its `conv.rust` messages kept. The
   pragma line becomes the error `syntax.legacy_removed`: "this
   compiler reads only the new syntax; volec 0.20's `fix --only
   conventions` migrates it".
3. **C3.** The `Allocator` trait's receivers become `self`, together
   with compiler/src's impls (step 5 above).
4. Branches of 0.21 start from C1, or rebase onto it and run `fix --only
   conventions` over their own changes.

## 10. Diagnostics and the guide (question 10)

### 10.1 The own pass in the new vocabulary

The codes stay (`own.moved`, `own.move_out`, `own.conflict`,
`own.escape`, `own.readonly`, ...); their words change from
references to conventions. Each keeps 0.17's contract: one line, a
`help:` that carries the replacement, and `try:` lines that run as they
are, tested by tests/own-try.

```text
fill.vl:2:5: error[own.readonly] 'v' is let here (borrowed, read-only): 'v.push(1)' changes it | help: to change it, take it inout | try: volec refactor signature fill --convention v inout
main.vl:6:5: error[own.moved] 'v' is used here after it moved into 'consume(v)' at 5:13 ('consume' takes 'v' sink) | help: 'consume' only reads 'v': take it let, or pass a copy | try: volec refactor signature consume --convention v let | try: volec edit patch main.vl:5 --old 'consume(v)' --new 'consume(v.clone())'
table.vl:2:15: error[own.move_out] cannot take 'self.keys' (Vec<Entry>) out of 'self': 'rehash' has self inout | help: take it and leave an empty one, or borrow it with 'let' | try: volec edit patch table.vl:2 --old 'var old = self.keys' --new 'var old = self.keys.take()'
main.vl:9:13: error[own.conflict] 'a' is lent inout to argument 1 and to argument 2 of 'transfer' | help: two inout accesses of one value cannot be live at once
main.vl:5:5: error[own.conflict] 'v.push(4)' may move v's elements while 'first' (4:17) views them; 'first' is used at 6:16 | help: use 'first' before the push, keep an index, or keep a copy | try: volec edit patch main.vl:4 --old 'v.as_slice()' --new 'v.clone()'
```

- **`refactor signature F --convention x let|inout|sink`** (new) changes
  a parameter's convention and every call's marker: `&` added for
  inout, removed for let and sink. A sink that would move a caller's
  local still used later is `edit.breaks` at that caller, with its own
  `try:`.
- `query own` speaks the same words:

  ```text
  v      Vec<i64>  owned  let-borrowed by 'total(v)' at 5:11
  first  [i64]     view   views v (4:17); invalid since 5:5 'v.push(4)'
  r      inout Query  access  of 'q' (3:5)
  ```

- The new codes:

  | code | when |
  |---|---|
  | `conv.marker` | an inout argument without `&` |
  | `conv.marker_extra` | `&` on a let or sink argument, or on an access |
  | `conv.place` | `&` of a temporary |
  | `conv.rust` | a Rust spelling (§7's table), one message per spelling |
  | `conv.set` | `x: set T` |
  | `conv.sink_type` | `sink T` outside a parameter |
  | `conv.extern` | `inout`/`sink` in an `extern "C"` signature |
  | `syntax.legacy` | the bootstrap pragma (explain only); `syntax.legacy_removed` from 0.21 |

  Each gets an `explain` entry with a compiled example.

### 10.2 The guide

Rewritten in the new syntax, and compiled by `tests/run.sh guide`:

- **core.md**: the "Looks like Rust, means something else" block and
  the std example (§11.1); the first-errors table (`conv.marker`,
  `own.readonly`);
- **memory.md**: "References" becomes "Conventions" (the table of §2.2)
  and "Accesses";
- **views.md**: projections, `inout [T]`;
- **syntax.md**, **closures.md** (`sink ||`), **traits.md** (receivers,
  operators), **iterators.md** (`for inout`), **allocators.md** and
  **effects.md** (their examples), **errors.md** (the new codes),
  **unsafe.md** (`*` is raw only, `&x` to `*T`);
- **tests/agent-eval/prompts/guide-mini.md** and **guide-core.md** in the
  new words, ready for 0.24's evals. Its "Rust syntax and value
  semantics" opening becomes "value semantics with `let`/`inout`/`sink`
  conventions".

**rust.md's mapping table**, which replaces "References, ownership,
memory":

| Rust | vole |
|---|---|
| `x: &T`, `f(&x)` | `x: T` (let, the default), `f(x)` |
| `x: &mut T`, `f(&mut x)` | `x: inout T`, `f(&x)` |
| `x: T` (moves) | `x: sink T` (a copy for plain types) |
| `&self`, `&mut self`, `self` | `self`, `inout self`, `sink self` |
| `let mut x` | `var x` |
| `let r = &mut x;` | `inout r = &x;` |
| `*r = v`, `*n + 1` | `r = v`, `n + 1` (an access is used as its value) |
| `&T` / `&mut T` fields | `let T` / `inout T` fields |
| `&[T]`, `&mut [T]` | `[T]`, `inout [T]` |
| `fn f(&self) -> &T`, `-> &mut T` | `fn f(self) -> let T`, `fn f(inout self) -> inout T` |
| `Option<&mut V>`, `m.get_mut(&k)` | `Option<inout V>`, `m.get_mut(k)` |
| `*m.entry(k).or_insert(0) += 1` | `m.get_or_insert(k, 0) += 1` |
| `for x in v.iter_mut()` | `for inout x in &v` |
| `match &mut x` | `match &x` |
| `std::mem::take(&mut x)`, `swap(&mut a, &mut b)` | `std::take(&x)`, `std::swap(&a, &b)` |
| `move \|\| ..` | `sink \|\| ..` |
| `static mut` | `static var` |
| lifetimes | none: inferred view summaries (`query views`) |

## 11. Before and after

### 11.1 The core guide's std example (the inventory)

Before (compiler/guide/core.md, "std: what programs use most"):

```tach
struct Item { name: [u8], qty: i64 }

fn add(v: &mut Vec<Item>, it: Item) { v.push(it); }   // called as add(&mut items, ..)

fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();
    let mut sc = Scanner::new(input.as_slice());
    let n = sc.next_int().unwrap();
    let mut items: Vec<Item> = Vec::new_in(gpa);
    let mut seen: HashMap<[u8], i64> = HashMap::new_in(gpa);
    for _ in 0..n {
        let name = sc.next_token().unwrap();
        let qty = sc.next_int().unwrap_or(0);
        add(&mut items, Item { name: name, qty: qty });
        seen.insert(name, qty);
    }
    items.sort_by(|a, b| b.qty - a.qty);       // a, b: &Item
    for (i, it) in items.iter().enumerate() { print(f"{i}:{it.name} "); }
    let line = trim(sc.next_line().unwrap());
    let total = split_in(line, ',', gpa).iter()
        .map(|w| parse_int(trim(w)).unwrap_or(0)).sum();
    match seen.get("pen") {
        Some(q) => println(f"pen={q} total={total}"),
        None => println("no pen"),
    }
    let text = format_in(f"{items.len()} {seen.len()}", gpa);
    println(text.as_slice());
    0
}
```

After:

```tach
struct Item { name: [u8], qty: i64 }

fn add(v: inout Vec<Item>, it: Item) { v.push(it); }   // called as add(&items, ..); Item copies, so let is enough

fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();
    var sc = Scanner::new(input.as_slice());
    let n = sc.next_int().unwrap();
    var items: Vec<Item> = Vec::new_in(gpa);
    var seen: HashMap<[u8], i64> = HashMap::new_in(gpa);
    for _ in 0..n {
        let name = sc.next_token().unwrap();
        let qty = sc.next_int().unwrap_or(0);
        add(&items, Item { name: name, qty: qty });
        seen.insert(name, qty);
    }
    items.sort_by(|a, b| b.qty - a.qty);       // a, b: let Item
    for (i, it) in items.iter().enumerate() { print(f"{i}:{it.name} "); }
    let line = trim(sc.next_line().unwrap());
    let total = split_in(line, ',', gpa).iter()
        .map(|w| parse_int(trim(w)).unwrap_or(0)).sum();
    match seen.get("pen") {
        Some(q) => println(f"pen={q} total={total}"),
        None => println("no pen"),
    }
    let text = format_in(f"{items.len()} {seen.len()}", gpa);
    println(text.as_slice());
    0
}
```

The core block's methods become `fn bump(inout self) { self.x += 1; }`
and `fn get(self) -> i64 { self.x }`. Its comment "passes &mut p"
becomes "lends p inout". Lines one at a time become `var b =
Buf::new_in(gpa); while read_line(&b).unwrap() { ... }`.

### 11.2 A parser holding views (with a sink for its output)

Before (0.19; the eval's "situation 7" plus guide views' parser):

```tach
struct Tok { text: [u8], kind: i64 }
struct Query { names: Vec<[u8]> }
struct Parser { toks: [Tok], pos: i64, q: &mut Query }

impl Parser {
    fn at_end(self: &Parser) -> bool { self.pos >= self.toks.len() }
    fn name(self: &mut Parser) -> [u8] {
        let t = self.toks[self.pos];
        self.pos += 1;
        t.text                              // views the input, not the parser: views(*self)
    }
    fn item(self: &mut Parser) {
        let n = self.name();
        self.q.names.push(n);               // fine: n views the text, not self
    }
}

fn parse(toks: [Tok], q: &mut Query) {
    let mut p = Parser { toks: toks, pos: 0, q: q };
    while !p.at_end() { p.item(); }
}

fn count(q: &Query) -> i64 { q.names.len() }

fn main(gpa: Gpa) {
    let mut q = Query { names: Vec::new_in(gpa) };
    let toks = [Tok { text: "let", kind: 0 }, Tok { text: "x", kind: 1 }];
    parse(toks[..], &mut q);
    let r = &mut q;
    r.names.push("y");
    println(f"{count(&q)}");
}
```

After:

```tach
struct Tok { text: [u8], kind: i64 }
struct Query { names: Vec<[u8]> }
struct Parser { toks: [Tok], pos: i64, q: inout Query }

impl Parser {
    fn at_end(self) -> bool { self.pos >= self.toks.len() }
    fn name(inout self) -> [u8] {
        let t = self.toks[self.pos];
        self.pos += 1;
        t.text                              // views(*self), inferred as before
    }
    fn item(inout self) {
        let n = self.name();
        self.q.names.push(n);
    }
}

fn parse(toks: [Tok], q: inout Query) {
    var p = Parser { toks: toks, pos: 0, q: &q };   // lends the inout parameter on
    while !p.at_end() { p.item(); }
}

fn count(q: Query) -> i64 { q.names.len() }

fn main(gpa: Gpa) {
    var q = Query { names: Vec::new_in(gpa) };
    let toks = [Tok { text: "let", kind: 0 }, Tok { text: "x", kind: 1 }];
    parse(toks[..], &q);
    inout r = &q;
    r.names.push("y");
    println(f"{count(q)}");
}
```

What changed: the receivers, the inout field and its `&q`, `var`, and
an `inout` local in place of `let r = &mut q`. What did not: the views,
the summaries, and that both programs check clean.

### 11.3 A function that changes two things

Before:

```tach
struct Account { balance: i64, log: Vec<i64> }

fn transfer(from: &mut Account, to: &mut Account, amount: i64) -> bool {
    if from.balance < amount { return false; }
    from.balance -= amount;
    to.balance += amount;
    from.log.push(-amount);
    to.log.push(amount);
    true
}

fn report(a: &Account, out: &mut i64) { *out += a.balance; }

fn main(gpa: Gpa) {
    let mut a = Account { balance: 100, log: Vec::new_in(gpa) };
    let mut b = Account { balance: 5, log: Vec::new_in(gpa) };
    transfer(&mut a, &mut b, 30);
    let mut sum = 0;
    report(&a, &mut sum);
    report(&b, &mut sum);
    println(f"{sum} {a.log.len()}");
}
```

After:

```tach
struct Account { balance: i64, log: Vec<i64> }

fn transfer(from: inout Account, to: inout Account, amount: i64) -> bool {
    if from.balance < amount { return false; }
    from.balance -= amount;
    to.balance += amount;
    from.log.push(-amount);
    to.log.push(amount);
    true
}

fn report(a: Account, out: inout i64) { out += a.balance; }   // no *out

fn main(gpa: Gpa) {
    var a = Account { balance: 100, log: Vec::new_in(gpa) };
    var b = Account { balance: 5, log: Vec::new_in(gpa) };
    transfer(&a, &b, 30);
    var sum = 0;
    report(a, &sum);
    report(b, &sum);
    println(f"{sum} {a.log.len()}");
}
```

The call says which arguments change: `transfer(&a, &b, 30)`,
`report(a, &sum)`. The errors are 0.17's, in the new words:

```text
transfer(&a, &a, 1);
main.vl:14:5: error[own.conflict] 'a' is lent inout to argument 1 and to argument 2 of 'transfer' | help: two inout accesses of one value cannot be live at once
transfer(&accts[i], &accts[j], 5);
main.vl:15:5: error[own.conflict] 'accts[i]' and 'accts[j]' may be the same element: both are lent inout to 'transfer' | help: work by index in a function that takes 'accts: inout Vec<Account>', or take one out first ('std::take(&accts[j])', then put it back)
report(a, sum);
main.vl:16:15: error[conv.marker] 'report' takes 'out' inout (it may change 'sum'): mark the argument | try: volec edit patch main.vl:16 --old 'report(a, sum)' --new 'report(a, &sum)'
```

### 11.4 A consuming builder

Before (probed: compiles on this branch):

```tach
struct Request { url: Buf, headers: Vec<Buf>, gpa: Gpa }

impl Request {
    fn new(url: [u8], gpa: Gpa) -> Request {
        Request { url: Buf::from_in(url, gpa), headers: Vec::new_in(gpa), gpa: gpa }
    }
    fn header(mut self: Request, h: [u8]) -> Request {
        self.headers.push(Buf::from_in(h, self.gpa));
        self
    }
    fn send(self: Request) -> i64 { self.headers.len() }   // consumes the request
}

fn main(gpa: Gpa) {
    let r = Request::new("http://x", gpa).header("a: 1").header("b: 2");
    println(r.send());
}
```

After:

```tach
struct Request { url: Buf, headers: Vec<Buf>, gpa: Gpa }

impl Request {
    fn new(url: [u8], gpa: Gpa) -> Request {
        Request { url: Buf::from_in(url, gpa), headers: Vec::new_in(gpa), gpa: gpa }
    }
    fn header(sink self, h: [u8]) -> Request {      // owned, so mutable
        self.headers.push(Buf::from_in(h, self.gpa));
        self
    }
    fn send(sink self) -> i64 { self.headers.len() }
}

fn main(gpa: Gpa) {
    let r = Request::new("http://x", gpa).header("a: 1").header("b: 2");
    println(r.send());
}
```

`sink self` says what the old signature's by-value `self: Request` and
its `mut` said separately. A second `r.send()`:

```text
main.vl:16:13: error[own.moved] 'r' is used here after it moved into 'r.send()' at 15:13 ('send' takes self sink) | help: 'send' only reads self: take it let | try: volec refactor signature Request::send --convention self let
```

## 12. Implementation plan

The internal form exists already (§2.3: references, param modes, the
own pass). The work is a second front end over it, the tools, std and
corpus migration, and the projections. Release R = 0.20.

### Phase 0: the interface (serial, the lead; about 5 commits)

| chunk | contents | files |
|---|---|---|
| P0.1 | lexer: `var`, `inout`, `sink` as keywords of new-mode files (none of them is an identifier in std; 49 `var` in tests are renamed by M) | front/lexer/mod.vl |
| P0.2 | parser, new mode: `x: [let\|inout\|sink] T`; receivers `self`, `inout self`, `sink self`, `self: inout Self`; access types `let T`/`inout T` in fields, results, type arguments, fn types; `var` bindings and `var` in patterns; `inout x = e;`; `static var`; `sink \|..\|`; `for inout x in &e`; `&e` as the inout marker (the node that legacy `&mut e` makes, `NODE_REF_MUT`); the recognizer of §7's Rust spellings (`conv.rust`), as parse errors with the try text; legacy mode: today's parser, unchanged | front/parser/{items/params, types, stmts, exprs}.vl, front/patterns |
| P0.3 | the mode: the pragma (§9.3), `CRATE_LEGACY`, per-file mode for std; the tests/run.sh lint; compiler/src/main.vl gets the pragma | driver (front/mod.vl, front/modules), tests/run.sh |
| P0.4 | the fixed interface: AST fields (a parameter's `PARAM_CONV`: LET, INOUT, SINK, LEGACY_VALUE; a binding's `BIND_VAR`, `BIND_INOUT`; the type node's access flag); `front/conv.vl`: `param_conv(f, i)`, `binding_is_access(l)`, `is_transparent(l)`, `let_of(t)` (copy or `&T` by kind, per instance), `conv_text(c)` for every printer; `param_mode` (kinds.vl) mapping conventions per §2.3, with stubs where T1 fills the rules | front/ast.vl, front/conv.vl (new), front/own/kinds.vl |
| P0.5 | the codes (`conv.*`, `syntax.legacy`) with stub explain entries; tests: `conv_*` cases (XFAIL until their task), `err_conv_rust_*` (passing: the parser's errors), `conv_legacy_bridge` (a legacy crate calling a new-syntax module: §9.3 table) | front/own/diag.vl, tools/explain/, tests/run |

Rule: after P0, tasks change only the files they own. A change to the
AST fields, to `front/conv.vl`'s signatures or to `param_mode`'s
contract goes through the lead.

### The parallel tasks

| task | owns | chunks (one commit each) |
|---|---|---|
| **T1 checking** | front/check/** (calls, check_mode, assign, body, names, iterate), front/patterns, front/closures, front/traits.vl; front/own/{moves, views, calls, diag text} | T1.a transparency: implicit dereference of access bindings, writes through, `&r` reborrows, `*` on an access is `conv.rust`; T1.b markers: `conv.marker`, `conv.marker_extra`, `conv.place`, the Vec/Buf/array → `[T]`/`inout [T]` conversions; T1.c bindings: let immutability as `own.readonly` in the new words, `let x = part` borrows (was `own.move_out`), `var x = part` stays `own.move_out`, `inout` locals, sink bindings mutable, plain let as a copy without a loan; T1.d receivers, trait/impl matching across modes (§9.3 rows 6–7, the Allocator rule), fn types with conventions, closures (`sink \|\|`, captures), `extern "C"` rules; T1.e patterns through accesses and `match &e`; T1.f the own diagnostics' words (§10.1), tests/own-try updated |
| **T2 tools** | tools/** (new tools/fixconv.vl; fixvalues, fix/, refactor_shape, edit, fmt/, query/, rewrite, explain tables) | T2.a one printer of conventions and access types, mode-aware, used by every tool; T2.b `fix --only conventions` rules 1–4; T2.c rules 5–8 and the reports; T2.d `refactor signature --convention`, `refactor field --type 'inout T'`, `extract-function` emitting `inout`, `fix --values` emitting the new syntax; T2.e fmt (the short receiver form, drops a written `let`), query def/show/context/own in the new words |
| **T3 projections** | front/types.vl (access type arguments without `decay_ref`), front/own/summary.vl and the result side of views.vl, front/check/iterate.vl's `for inout` (after T1.a), compiler/std's collection APIs | T3.a bare `-> let T` / `-> inout T` (body rules, summaries, calls as views); T3.b `Option<let T>`, `Option<inout T>` as type arguments, `?`/`unwrap`/patterns on them; T3.c `for inout x in &v` over Vec, Buf, arrays and slices; T3.d std: `get_mut`, `get_or_insert`, `last_mut`, `as_mut_slice -> inout [T]`, the one-element views deprecated; `fix` rule 9 |
| **T4 guide and docs** | compiler/guide/*.md, docs/grammar.md (a new section, "Additions of 0.20: conventions", with the EBNF of §13), tests/agent-eval/prompts/*.md, the explain entries' text and examples | one chunk per topic: core, memory, views, rust, syntax, closures/traits/iterators, allocators/effects/unsafe/errors, guide-mini and guide-core, grammar.md, explain `conv.*` |

### Phase M: the migration and the flip (serial, after T1 and T2; the lead or T2's owner)

| chunk | contents |
|---|---|
| M.1 | std: `fix --only conventions` over compiler/std/** (after the d20-* branches have merged), `compiler/std/embed.sh`, same-code.sh, the suite |
| M.2 | tests/run, tests/examples, tests/std, tests/refactor fixtures, tests/own-try: fix, the err-tests' outputs regenerated and reviewed |
| M.3 | examples/, bench/, tests/agent-eval (solutions and starters; check-tasks as before) |
| M.4 | the flip: the old syntax is an error everywhere outside the pragma, T4's guide lands (`tests/run.sh guide`), the rehearsal of §9.3 step 7 joins gate.sh |

### Merge order

1. P0.
2. T1 and T2 in parallel. T2 builds against P0's AST, takes T1's checks
   as they land and merges after T1.
3. T4 is drafted throughout and lands in M.4.
4. M.1–M.4.
5. T3. It starts in parallel on T3.a and T3.b against T1.a's
   transparency, merges after M (it is additive), and then runs `fix`
   rule 9 over the corpus.
6. The R gate: `bootstrap/gate.sh --quick`, the rehearsal, then
   `--release`.
7. R+1: C1, C2, C3 (§9.3), first in 0.21.

**Gate for each chunk:** `tests/run.sh FILTER` for the cases it
concerns. At P0, M.4 and T3: the whole suite and `gate.sh --quick`.
Compile speed: the second front costs one branch per construct in the
parser and nothing in the own pass. `check --time` must stay within
noise on compiler/src (legacy) and on std (new).

## 13. Grammar (for grammar.md)

```ebnf
param       = self_param | ident ":" [ convention ] type [ "=" expr ] ;
self_param  = [ "inout" | "sink" ] "self" | "self" ":" [ convention ] type ;
convention  = "let" | "inout" | "sink" ;               (* let is the default; fmt does not write it *)
type       += "let" type | "inout" type ;              (* an access: field, result, type argument, fn type *)
fn_type     = "fn" "(" [ [ convention ] type { "," [ convention ] type } ] ")" [ "->" type ] ;
stmt       += "var" pattern [ ":" type ] "=" expr ";"
            | "inout" ident [ ":" type ] "=" expr ";" ;  (* expr: "&" place, or an inout access *)
single     += "var" ident ;                             (* replaces "mut" ident *)
fpat        = [ "var" ] ident | ident ":" pattern ;
static_decl = "static" [ "var" ] ident ":" type "=" expr ";" ;
prefix     += "&" pratt(25) ;                           (* an inout access of a place; no "&" "mut" *)
closure     = [ "sink" ] "|" params "|" expr ;          (* replaces "move" *)
for_expr   += "for" "inout" pattern "in" "&" expr block ;
match_expr += "match" "&" expr "{" arms "}" ;           (* binds inout accesses *)
```

Keywords in new-syntax files: `var`, `inout` and `sink` are added. `mut`
and `move` are recognized for their diagnostics only, and reserved
after 0.21. `set` is not reserved.

## Decisions taken (for the user's review)

Each was decided here; the section that argues it is in brackets.

1. **D1** `let` is the implicit parameter default: a borrowed,
   read-only access [§2.1].
2. **D2** The convention is written before the type, `x: inout T`, and
   the same form is used in fields, results, type arguments and fn
   types [§2.1].
3. **D3** No `set`. It is not reserved; `x: set T` is `conv.set`
   [§2.1].
4. **D4** `sink` parameters are mutable in the callee and replace `mut
   x: T`. There is no `var` convention [§2.1].
5. **D5** For plain and copyable types `let` is a copy with no loan.
   The ABI chooses registers or an address, and a generic instance
   decides by its type [§2.2].
6. **D6** Allocators are passed `let`, so nothing is written. Arena
   containers become `Vec<T, let Arena>` when U3 lands, and
   `Allocator`'s methods take `self` [§2.4].
7. **D7** `&place` marks an inout argument, binding, field, `match`,
   `for` or result, and nothing else. `&` on a let or sink argument is
   an error. A call that already returns an access needs no `&`
   [§3].
8. **D8** Sink arguments are unmarked. The move shows through the
   signature and the dead source [§3].
9. **D9** Receivers are written `self` / `inout self` / `sink self`;
   `self: inout Self` is also accepted, and `fmt` writes the short form
   [§4].
10. **D10** Receivers are borrowed automatically, without `&` (Swift,
    not Hylo); two-phase as before [§4].
11. **D11** Operator traits take both operands `let` [§4].
12. **D12** Accesses are transparent: there is no `*r`, `*` is for raw
    pointers only, and access bindings cannot be re-pointed [§5.1].
13. **D13** `let` stays an owning binding. It borrows only a part it
    cannot take, which was `own.move_out`, so no accepted program
    changes meaning [§5.2].
14. **D14** `var` replaces `let mut` everywhere: bindings, patterns and
    `static var` [§5.2].
15. **D15** `mut` leaves the language, and is reserved with diagnostics
    after 0.21 [§5.2].
16. **D16** `inout x = &place;` locals exist. There is no shared-access
    local of a whole owned local [§5.2].
17. **D17** No `sink let` [§5.2].
18. **D18** `for inout x in &v` and `match &e`, with T3 [§5.3].
19. **D19** `sink |..|` replaces `move |..|` [§5.4].
20. **D20** `&T` and `&mut T` disappear as types. Accesses are `let T`
    / `inout T`. `[T]` is `let [T]`, and `inout [T]` is the exclusive
    slice [§6].
21. **D21** Projections, minimal: `-> let T`, `-> inout T` and an
    `Option` of one, returning addresses with inferred summaries. There
    are no `yield` subscripts yet. Index projections stay built in
    [§6.3].
22. **D22** The familiar forms: Rust reference spellings are removed
    but recognized (`conv.rust` with a `try:`). `.len` both ways,
    struct-like variants, `v[i]`, `p.0`, the prelude and sibling paths
    stay [§7].
23. **D23** Raw pointers: V4 unchanged. `&x` converts to `*T` with an
    exclusive loan for the call [§8].
24. **D24** Migration is `fix --only conventions` (10 rules), proven by
    same-output, same-code and the suites. `fix --values` emits the new
    syntax [§9.2].
25. **D25** The bootstrap: 0.20 parses compiler/src in legacy mode under
    a root pragma that only compiler/src/main.vl may carry (a lint).
    The tools are mode-aware. The rehearsal is in the gate. 0.21's first
    commits migrate compiler/src and delete legacy mode [§9.3].
26. **D26** Diagnostics keep the `own.*` codes in the new words and add
    `conv.*`. The new `refactor signature --convention` is what their
    `try:` lines run [§10].
27. **D27** `var`, `inout` and `sink` are keywords in new-syntax files.
    Identifiers with those names are renamed by `fix` [§9.2, §13].
28. **D28** No diagnostic names the language, so 0.24's rename to vole
    changes none of them [intro].

## Questions this design leaves for later

- `yield` subscripts for computed projections (§6.3), and a user `Index`
  trait.
- Tuples of accesses (`split_at_mut`, two elements of one Vec inout at
  once). §11.3's error suggests the workarounds.
- Whether `inout` arguments to a C function should take a shared loan
  when the C type is `const T*`. The importer knows `const`, and this
  design takes an exclusive loan always.

## Phase 0 contract (2026-10-21, branch c20-conv0)

Phase 0 is the interface commit. T1 to T4 build against it in parallel.
A task changes only the files it owns. A change to a fixed signature, to
the AST flags below, or to the modes' rules goes through the lead.

### What Phase 0 contains

**The modes** (front/conv.vl). A file is read in one of three ways:

- **mixed**, the default until Phase M: both spellings, each with its
  meaning.
- **0.20**, set by `--syntax=0.20`, which every command takes (main's
  arguments, like `--values=`; the code cache keys on it). Rust's
  spellings are `conv.rust`, and `&x` is always exclusive. M makes this
  the default.
- **0.19 (legacy)**: the crate whose root starts with `LEGACY_MARKER`,
  `// vole-syntax: 0.19`. 0.20's forms are `syntax.legacy`, and
  `var`, `inout` and `sink` are plain identifiers.
  compiler/src/main.vl carries the line now. tests/run.sh fails when
  any other .vl under compiler/, tests/, examples/ or bench/ carries
  it, except tests/run/conv_legacy* (the mode's own tests).

std and the generated sources (`<check>`, `<profile>`, `<trace>`) are
always read mixed, until M migrates them. The helpers are
`conv_setup()` (called by `parse_program`), `legacy_at(pos)`,
`strict_at(pos)`, `syntax_option(arg)`, `word_at(i, word)` and
`starts_type(k)`.

**The parser** (front/parser/{items/params, types, stmts, exprs, mod,
foreign, items/mod}.vl) reads these forms:

| form | the AST it makes (until T1: what 0.19 would have made) |
|---|---|
| `x: inout T` | Param flagged CONV_NEW, CONV_INOUT; type TyPtr with NODE_REF, NODE_REF_MUT and CONV_NEW (`inout [T]`: TySlice with NODE_REF_MUT and CONV_NEW) |
| `x: let T` | Param flagged CONV_NEW; type TyPtr with NODE_REF and CONV_NEW (`let [T]`: the TySlice, CONV_NEW) |
| `x: sink T` | Param flagged CONV_NEW, CONV_SINK; type T as written; `c = 1` (mutable) |
| `self`, `inout self`, `sink self` | Param `self` typed `let Self` / `inout Self` (TyPtr over TyName `Self`) / `Self` with `c = 1`; flags as above |
| `x: T` in a 0.20 file | Param flagged CONV_NEW: let (still by value until T1's `let_of`) |
| `let T`, `inout T` in any type position (fields, results, type arguments, fn types, annotations) | the TyPtr / TySlice above (`parse_access_type`) |
| `fn(sink T)` | the parameter type T (the convention is dropped until T1) |
| `&e` | Unary `&` flagged CONV_NEW in mixed and 0.20 files, plus NODE_REF_MUT in 0.20 files; `check_expr` adds NODE_REF_MUT to a CONV_NEW `&` wherever `&mut T` or `&mut [T]` is expected (the inout marker, `inout_marker(n)`) |
| `var PAT = e;` | Let flagged CONV_NEW; every binding of PAT mutable (PatBind `b = 1`) |
| `inout x [: T] = e;` | Let flagged CONV_NEW, CONV_INOUT; an `&e` initializer gets NODE_REF_MUT; an annotation T becomes `inout T` |
| `var x` in a pattern | PatBind `b = 1` |
| `static var X` | Static `d = 1`, flagged CONV_NEW |
| `sink \|..\|` | Closure `c = CLOSURE_MOVE`, flagged CONV_NEW, CONV_SINK |

Rust's spellings in a 0.20 file each give one `conv.rust` error, soft,
with an `edit patch` try: line and a `fix --suggested` fix:

- `&T` / `&mut T` / `&[T]` / `&mut [T]`, written `T` in a parameter and
  `let T` elsewhere;
- `&mut e`;
- `let mut`, and `mut x` in a pattern;
- `mut x: T`;
- `static mut`;
- `move`.

The other errors: `x: set T` is `conv.set`, and `sink T` outside a
parameter is `conv.sink_type`. The receiver help (`&self` and
`fmt(&self, ..)`) now names `self`, `inout self` and `sink self`.

**The fixed interface** (front/conv.vl, front/ast.vl):

| name | contract |
|---|---|
| `CONV_NEW`, `CONV_INOUT`, `CONV_SINK` (ast.vl: bits 54, 55, 49 of `p`) | as in the table above; a node without CONV_NEW was written in 0.19's spelling |
| `param_conv(p)`, `fn_param_conv(f, i)`, `param_node(f, i)` | CONV_LEGACY (0.19's spelling: the type says how it is taken), CONV_LET, CONV_IN_OUT, CONV_SINK_K |
| `conv_word(c)` | "", "let", "inout", "sink" (for messages and printers) |
| `inout_marker(n)` | a CONV_NEW `&` that is not yet exclusive |
| `conv_error(code, start, end, message, help, new)`, `rust_spelling(start, end, what, new)`, `legacy_error(start, end, what)`, `try_patch(pos, old, new)` | the diagnostics' helpers: soft, coded, with try: and fix |
| `CODE_RUST`, `CODE_SET`, `CODE_SINK_TYPE`, `CODE_LEGACY` (reported); `CODE_MARKER`, `CODE_MARKER_EXTRA`, `CODE_PLACE`, `CODE_EXTERN` (T1's); `CODE_LEGACY_REMOVED` (0.21) | the codes; each has its `explain` entry in tools/explain/conv_table.vl, and tests/refactor's self_explain covers the `conv.` and `syntax.` prefixes |
| `PARAM_TYPE` (parser/items/params.vl) | true while a parameter's type is parsed |
| `mark_param_conv(n)` | a Param flagged from its type node |

**fmt** keeps a space after `inout` and `sink` before `[` or `(` in a
type position, and after a statement's `var` before `(`. It reads `sink
|x|` as a closure.

**Tests:**

- tests/run: `conv_params` (mixed: every form), `conv_strict`
  (`--syntax=0.20`), `conv_words` (the words as identifiers),
  `conv_legacy_ok` and `conv_legacy_errors` (the 0.19 mode),
  `err_conv_rust` (each Rust spelling, ERROR-COUNT 10), `err_conv_words`
  (`set`, `sink T`);
- changed for the marker: `err_own_refs` loses the `&x` to `&mut T`
  error, own-try `ref_mut_arg` now checks clean, and guide errors.md's
  two blocks are updated.

### The tasks

| task | owns | fills | must not change |
|---|---|---|---|
| **T1 checking** | front/check/** (calls, check_mode's coercions, assign, body, names, iterate), front/patterns, front/closures, front/traits.vl, front/own/{kinds `param_mode`, moves, views, calls}, the own diagnostics' words | `let_of`: a let parameter of a plain or copyable type is a copy, otherwise `&T`, per instance; transparency of access bindings (implicit `*`, writes through, `&r` reborrows; `*r` on an access is `conv.rust`); `conv.marker`, `conv.marker_extra`, `conv.place`, `conv.extern`; let parameters read-only (`own.readonly` in the new words); `let x = part` borrows; sink bindings; `fn(sink T)` / `fn(inout T)` in function types (conventions in `TyKind::Fn`); trait and impl matching across modes (§9.3 rows 6–7, the Allocator rule); `match &e`; the receiver of `sink self` moves; the own pass's messages in the new vocabulary (§10.1) and tests/own-try | the parser, front/conv.vl's signatures, the AST flags |
| **T2 tools** | tools/** (new tools/fixconv.vl; fixvalues, fix/, refactor_shape, edit, fmt/, query/, rewrite) | one mode-aware printer of conventions; `fix --only conventions` (§9.2 rules 1–8); `refactor signature --convention`; `refactor field --type 'inout T'`; extract-function and `fix --values` emitting 0.20's spelling in mixed and 0.20 crates and 0.19's in the legacy one; fmt writing `self` / `inout self` and dropping a written `let`; query def/show/context/own in the new words | front/**, explain's codes |
| **T3 returned parts** | front/types.vl (accesses as type arguments: no `decay_ref` for a CONV_NEW access), front/own/summary.vl and the result side of views.vl, front/check/iterate.vl's `for inout`, compiler/std's collection APIs, after M | `-> let T` and `-> inout T` (they parse now; the body's `&place` and the summaries are T3's), `Option<let T>` / `Option<inout T>`, `for inout x in &v` (parser: T3 adds it in stmts.vl's `for`, after asking the lead), `get_mut`, `get_or_insert`, `last_mut`, `as_mut_slice -> inout [T]`; `fix` rule 9 | the parser's other forms, `param_conv` |
| **T4 guide and docs** | compiler/guide/*.md (and `compiler/guide/embed.sh`), docs/grammar.md (the 0.20 section, then the EBNF of §13 at M), tests/agent-eval/prompts/*.md, the text of conv_table.vl's entries | the guide in 0.20's spelling, landing with M.4 (until then each example compiles mixed); rust.md's table (§10.2); guide-mini and guide-core | the code |

**Merge order:** Phase 0 → T1 and T2 (T2 merges after T1) → M.1–M.4,
where the default becomes `--syntax=0.20` and T4 lands → T3 → the R
gate with the rehearsal (§9.3 step 7).

### Found while building Phase 0

- **The marker changes one accepted error into acceptance.** In mixed
  files, `&x` where `&mut T` is wanted was "expected '&mut P', got
  '&P'" (`try: &mut x`); now it is the exclusive loan. This is D7. No
  accepted program changes meaning. compiler/src is legacy, so it is
  not affected.
- **`var`, `inout` and `sink` are contextual until 0.21.** The corpus
  has 49 `var` identifiers in tests and 56 in compiler/src. `var` starts
  a binding only before `IDENT =` / `IDENT :`, or before `( .. )`
  followed by `=` or `:`, so `var(a, b);` stays a call. `sink` starts a
  closure only before `|` or `||`. D27's keywords wait for M's renames.
- **Until T1 an access is a reference.** So `x: inout i64` needs `*x =
  v`, and `inout r = &v; f(&r)` is `&&mut`, both until transparency. The
  Phase 0 tests write only what holds either way.
- **The legacy crate is the whole root crate.** A test of the mode is a
  root of its own (tests/run/conv_legacy*): the pragma is read from
  file 0 only.

## T1 as built (branch c20-conv-t1)

- **Accesses** (Local.access). These are:
  - a let parameter that borrows;
  - an inout parameter, a receiver `self` / `inout self` that is a
    reference;
  - an `inout x = &e;` local;
  - a `let x = part;` that borrows;
  - in a 0.20 file, a pattern binding made through a reference (`match
    &x`).

  Each use is rewritten to `*x` in `synth_name`. So `x = v` writes
  through, `&x` reborrows, methods and fields reach the value, and `*x`
  written on one is conv.rust.
- **let parameters** (`conv::param_type`, applied in
  `resolve_signature`, so per instance) take a copy of a copyable value:
  no Drop, no Vec, Buf or HashMap, and no exclusive access in it.
  Anything else is taken as `&T`. In a 0.20 file an unwritten convention
  is let; in a mixed file it keeps 0.19's by-value meaning.
- **Temporaries.** A value passed to a let parameter that borrows
  (`total(make())`) becomes a temporary of the statement. temps.vl
  does this for calls of non-generic functions named by an identifier;
  method calls and generic callees do not get it yet.
- **`let x = part;`** in a 0.20 file borrows (D13) when the part is an
  element, a dereference, or a field reached through one. `var x =
  part` stays `own.move_out`.
- **Markers.** `conv.marker` (an inout argument without `&`) and
  `conv.marker_extra` (`&` where a let or sink parameter is wanted) are
  reported in 0.20 files only. Mixed files keep 0.19's messages, so
  nothing written in the old spelling changes until Phase M.
- **Traits.** A trait's let parameters go through `param_type` with the
  impl's Self. An impl's borrowing let parameter meets a trait's
  by-value one (`conv::let_for_value`). An arithmetic operator (and `-a`)
  whose impl takes its operands let reads them instead of moving them.
- **`conv.extern`** reports `inout` or `sink` in a C signature.
- **The diagnostics' words** in 0.20 files (own.readonly, own.moved,
  own.move_out, the immutable-assignment help) name let, inout and sink.
  Their `try:` lines use `refactor signature --type v 'inout T'`. T2's
  `--convention` replaces that once it lands.
- **Access fields** (`q: inout Query`, `cfg: let Config`, declared with
  CONV_NEW) are transparent too. `synth_field` makes `p.q` into `*p.q`,
  so `h.p.q = 10` and `h.n = 7` write the place the field designates.
  The owned-assignment desugaring (drops.vl `copy_place`) keeps the
  flag that marks the reference under an access's `*`. Before this,
  `x = v` in an instance with an owned T made `**x`. `star_on_access`
  reports only a `*` written in the source.
- **own.moved names the sink parameter** that took the value: "'v' is
  used here after it moved into 'keep(sink v)' at 16:18" (walk.vl
  records owned arguments, moves.vl `moved_into`). A by-value
  parameter in 0.19's spelling keeps the old message.
- **Not done:**
  - projections' bodies (T3);
  - a `try:` that changes a sink parameter to let (T2's `refactor
    signature --convention`).
- **The lost explain entries** (a T1 dev compiler, built from the
  working tree, listed 201 codes instead of 210) could not be
  reproduced:
  - from the committed tree at 6899a467, 3 builds with `--no-cache` and
    2 with the code cache gave 210 entries, and builds with the same
    output name are byte-identical;
  - a cache filled by the Phase 0 tree and then the T1 diff also gave
    210.

  The code cache keys a function on its IR hash, which includes the
  folded `CONV_COUNT`. The likeliest cause is a build made while the
  tree was mid-edit (one `edit patch --pairs` had failed just before),
  not the cache.

## T2: the tools (2026-10-21, branch c20-conv-t2)

**Built.** `fix --only conventions` (tools/fixconv.vl; §9.2 rules 1 to
8, rule 8 reported), in two stages: `--only conventions-spelling`
rewrites only what Phase 0's checker means as 0.19 did (`x: &T` → `x:
let T`, `&e` to it and `*r` kept), so its result checks and runs as
before; `--only conventions` finishes it (`x: T`, `&e` → `e`, `*r` → `r`,
`&r` for an access passed on) and checks the result with
`--syntax=0.20`. What needs a decision is `fix.conv_left` (`--list-left`
prints each place). `refactor signature --convention x let|inout|sink`,
`--type x 'inout T'`; extract-function in the crate's spelling
(fixconv::put_type_conv, the tools' one printer); fmt's short receivers
and, with `--syntax=0.20`, no written `let` in a parameter list.

**The migration, measured** (scratch copies, not committed):

| corpus | rewrites (spelling stage, then the rest) | left to hand |
|---|---|---|
| tests/run, tests/std, examples (816 roots) | 2,377 `var`, 596 `&mut e` → `&e`, 402 receivers, 305 inout / 296 let / 150 sink parameters, 65 `static var`, 15 inout locals, 12 access types, 4 `sink ||`; then 365 `&e` → `e`, 251 `*r` → `r` | 55 `let r = &e;`, 27 `&e`, 2 guessed, 1 `&&` |
| compiler/std | 589 `var`, 473 receivers, 180 inout / 160 let / 138 sink, 150 access types, 46 `&mut e`, 27 `static var`; then 254 `&e` → `e`, 300 `*r`, 129 `&mut e` (generic bodies) | 26 `let r = &e;`, 125 `&e` (mostly generic bodies no instance checks) |
| compiler/src (the 0.21 rehearsal, pragma removed) | 4,994 `var`, 1,501 `static var`, 1,446 sink, 898 `&mut e`, 357 inout, 223 let, 15 receivers; then 1,177 `*r`, 415 `&e` → `e`, 373 `&mut e` | 27 `let r = &e;`, 41 `&e`, 23 identifiers `var`/`inout`/`sink` |
| guide blocks (142; 71 are err blocks) | 87 `var`, 26 receivers, 12 inout, 9 sink, 9 `&mut e`; then 8, 6 `&e` → `e`, 2 `*r` | 1 `&e`; 3 multi-file blocks by hand |

- The spelling stage keeps every output: the suite passes on the
  migrated tests/examples but for the err-tests and walkthroughs whose
  text names the old spelling. compiler/src after it builds (mixed),
  reaches the fixpoint, and `same-output` against the compiler before
  it differs only in the compiler's path in try: lines.
- After the full stage nothing is `conv.rust` in tests and examples;
  83 of 512 checking roots, and compiler/src (45 `cannot assign to
  immutable variable`, 5 `expected '&T', got 'T'`), fail in 0.20 mode
  only for what T1 brings: writes through an access, a place given to a
  let parameter, impls of std's traits matching across modes.

**For T1 and the lead.**
- std's same-code after the spelling stage differs in 85 of 2,493
  compilations (HashMap insert, get_or_insert): a `sink` parameter is a
  mutable binding, so a closure captures it by reference where 0.19
  copied the immutable `key: K`. Outputs are the same; capturing a sink
  binding the body never writes by copy would make the code the same.
- `inout self` is `&mut Self`: for `impl [T]` that is not `&mut [T]`
  (`sort(self)` cannot infer), so fix keeps the long form `self: inout
  [T]` there; the parser's self_receiver could make the slice's form.
- In mixed files Phase 0 makes `&x` exclusive only where a `&mut` is
  expected of a non-generic callee: to a generic one (`read_line(&mut
  b)`, `std::take`) `&x` stays shared, so the spelling stage keeps
  `&mut x` there; the full stage (0.20 mode) rewrites it.
- `PARAM_TYPE` stays true inside a parameter's nested types, so the
  parser's conv.rust fix of `p: Option<&T>` is `Option<T>`, not
  `Option<let T>`.

## Phase M as built (branch c20-convM)

The migration and the flip, with helpers for the corpus (pm-tests,
pm-examples, pm-transcripts, merged in).

- **The flip.** User code is read in 0.20's spelling by default
  (`--syntax=0.20`); `--syntax=mixed` (and VOLE_SYNTAX=mixed, which a
  migration sets for the checks it runs) reads both; the root pragma
  `// vole-syntax: 0.19` is compiler/src's until 0.21. std is 0.20 code
  whatever the program's mode, except a std tree read from disk in a mixed
  run (`fix --only conventions --std-tree compiler/std`: std migrating).
- **fix --only conventions** works on the checked program, and in a merge
  on the files a branch brought: `--in A,B,...` limits it. Rules added
  while migrating: `let p = &e` used as a raw pointer (cast, indexed as an
  address, written through, its own address taken) is `let p = &e as *T`;
  a reference parameter cast or indexed as an address is `*T`; `for x in
  &v` is `for x in v`; `&v[a..b]` the checker reads as the slice is
  `v[a..b]` (`let s = &mut v[..]` is `inout s = &v[..]`); `&mut x` to a
  let parameter is `x`; `match &part`, `match &r`, `match &copy` drop the
  `&`; `(*p).f` whose node starts at the parenthesis; `let (a, b) = &e` of
  a copy; closure bodies of generic calls by the parameters' names.
  Generic std code that no instance reaches is not seen by it: an inout
  parameter passed on through a function value (`f(g)`) needed its `&` by
  hand.
- **Semantics settled while migrating.** `match e` of an access matches
  through it, and `match part` of a non-copyable part it cannot take
  borrows it (D13 for a match): the bindings are accesses. A view taken
  through an access (`&*r`: an inout local, a pattern's binding) is a view
  of what the access designates. A String or PathBuf place goes where its
  view goes, `f(s)` (as a Vec where its slice goes). A closure literal
  given to a let parameter that borrows it is lent from the caller's
  frame. `Iterator::at` takes `inout self` (its default advanced a copy).
  An assignment through an access drops the old value (its `let =o` is no
  D13 borrow). A let parameter of a plain type is a copy, so tests about
  the address or the aliasing of a `&T` parameter now use `*T`.
- **std::env::get / get_in** replace `var` / `var_in` (`var` is a word,
  a keyword from 0.21); `env::var(..)` is conv.rust with `try: env::get`.
- **Left for 0.20.1.** `fn(T)` and `fn(let T)` are different types in
  the checker (front/conv::fn_type_param: a plain `T` in a function type
  or an `Fn` bound is the value, as the migration wrote 0.19's by-value
  ones), while §2.5 makes `let` the default there; fmt keeps the `let` of
  a function type until they are one type (std's consuming bounds become
  `Fn(sink T)` then). A closure's by-value parameter is not dropped
  (0.19.1 leaks too); a generic let parameter given an rvalue of a
  non-copyable type other than a closure literal (`gl(make())`) errors;
  the own.move_out try for an operator impl suggests `std::take(&self)` of
  a let receiver.
  `fix --only conventions` (found migrating compiler/src, 0.21 C1): it
  drops the `&` of a raw address inside an f-string hole (`f"{cstr(if c
  { &sp[2] } else { sp })}"` became `sp[2]`), and it writes an impl's
  `self: &T` as `self` where std's trait now declares `inout self`
  (`Iterator::at`); both fixed by hand in compiler/src.

## 0.21 on c20-convM (branch c21-srcM)

- **C1** (09c21885): compiler/src in 0.20's spelling (`fix --only
  conventions` with VOLE_SYNTAX=mixed for the steps before it: the
  raw-pointer retypes of 13 parameters indexed as pointers; the 24
  `var`/`inout`/`sink` identifiers renamed; the two hand fixes above).
  c20-convM's compiler checks it clean, builds it, the fixpoint holds,
  and same-output against it differs only in argv[0].
- **C2** (df382ed2): the legacy mode removed (the pragma is
  `syntax.legacy_removed`), and the messages that spoke 0.19's spelling
  for the legacy crate. The mixed mode stays: `fix --only conventions`,
  `fix --values`, `--only std015|alloc016` and their tests read 0.19's
  spelling with it. Removing it means removing those migrations (they
  are 0.20's to run) and the tests and guide lines that name them: the
  step left before 0.24.
- **C3** (81575ae4): `var`, `inout`, `sink` keywords.
- **Mixed only in the migrations**: `--syntax=mixed` is refused
  (syntax.mixed_removed); `fix --only conventions`, `fix --values` and
  `--only std015|alloc016` set the mode themselves, and their children
  inherit it through VOLE_SYNTAX=mixed:PID (honored only by a child of
  PID). No build, check, run, try or query reads 0.19's spelling.
- **`.vl`** (for 0.24's name): sources are `.vl` or `.vl` everywhere,
  `x.vl` and `x.vl` both is an error, and every VOLE_X is read as
  VOLE_X too (VOLE_ wins); tests/refactor/vole021.
- Suite with C3's compiler: 1660 passed, 2 xfail, 0 failed. The
  bootstrap from v0.20.0 (releases.toml's 0.20.0 entry, then `bootstrap.sh
  --dev`) is the check left once the tag exists.

## 0.22 (branch c22-fixes), and what is left for 0.22.1

Done in 0.22: `fn(T)` is `fn(let T)` (a plain parameter of a function
type or an Fn bound is let; std's consuming bounds say `sink`: Option and
Result's map, and_then, map_err, unwrap_or_else, Iterator::map, for_each,
every fold's accumulator and item); `f(x?)` keeps the value `?` makes
through the call; std is own-checked (tests/std/own.sh, its known
patterns in tests/std/own.allowed).

### 0.22.1

- **The let-as-borrow rule** (decided, as recommended; the user may
  overrule it). Following Hylo, `let` is semantically a borrow; copying a
  copyable argument is an optimization, taken only when no view of the
  parameter escapes. A function that returns a view of a let parameter,
  or stores one (into an inout parameter or a field), takes it by
  reference. The plan: decide it from the signature before the body is
  checked (a result or an inout/sink parameter whose type can hold a view,
  and a let parameter whose type has storage a view can point into: an
  array, a struct holding one), in resolve_signature and fn_type_param
  alike, per instance; then restore `DirEntry::file_name(self)` and make
  voltty's `Text::as_slice(self) -> [u8]` legal. Not started.
- A closure's by-value parameter is not dropped (a leak, as in 0.19.1).
  Dropping it is a two-line change (front/own/drops, as param_drops does
  for a function), but iterators that yield bitwise copies of borrowed
  elements (HashMapIter, Keys, Values: `(*e).0`, `(*e).1`) pass them to
  `sink` fold and map closures, which would then free the map's elements:
  those items must become views first.
- A generic let parameter given an rvalue of a non-copyable type other
  than a closure literal (`gl(make())`) errors; an `x?` argument naming
  the receiver's variable, or after an impure argument, is not made a
  temporary.
- own.move_out's try for an operator impl suggests `std::take(&self)` of a
  let receiver.
- tests/std/own.allowed's eight patterns: fmt's rooms as `inout [u8]`
  results, `-> let T` results in the own pass (T3), the sort closures'
  summaries.

### 0.24 (branch c24-fixes)

Done: let is a borrow (conv::let_by_ref: a copyable let parameter with
storage is passed by reference when the result may hold a view;
`DirEntry::file_name(self)` again); distinct types (`str`, `Path`) are
views to the own pass; `gl(make())`; own.move_out through a let access
offers `.clone()` and `sink`, not `std::take(&self)`; a field moved out of
a temporary (`let x = make().v;`) moves out of the value (it was read
through the temporary's address and freed again with it), own.partial for
a type with Drop.

Left, for after 0.25 (soundness first):
- **Items of borrowing iterators are bitwise copies typed as owned
  values** (`Vec::iter`, `HashMap::iter`, `keys`, `values`: `SliceIter`'s
  and `HashMapIter`'s `next` return `T`): `w.iter().collect_in(gpa)` of a
  `Vec<Vec<i64>>` frees each element twice. The fix is items that are
  views of non-copyable elements (`let T`), which needs `-> let T` results
  and `let T` type arguments in the own pass (T3).
- Until then a closure's by-value parameter is not dropped (a leak, the
  safe default): dropping it would free those copies, the map's elements,
  in `m.iter().fold(..)` and `map`.
- A value given to a generic let parameter after an impure argument is
  not made a temporary ("this value has no place").

### 0.25: drop check and views across threads (branch fix25g)

Three soundness holes the poly red team found (tests/run/sem_poly_x15,
x14, x03, x02, th10), and one the exclusivity red team found, closed with
the simplest sound rules:

- **Drop check: a type with a Drop of its own holds no view, also
  through a type argument** (`own.drop_view`). 0.17 rejected `impl Drop`
  on a struct whose own fields hold views, but let `impl<T> Drop for
  G<T>` be instantiated with a view (`G<[i64]>`), as Rust's `may_dangle`.
  Nothing orders a drop before the drop of what its views point into
  (`var g = G { x: a[..] }; var v = ..; g = G { x: v.as_slice() };` drops v
  first, then g's drop reads the view: a use after free). Rust's answer,
  dropck, rejects the declaration order instead; the rule here is
  simpler and loses little: an instance of a user Drop type whose type
  arguments hold a view is `own.drop_view` at the impl (with a try: an
  owned argument, `.to_vec_in(gpa)`). std's generic containers keep the
  exemption (their drops read no element: `Vec<[u8]>`). So drop order
  never matters for soundness: no drop that runs reads a view. A type
  holding a view and a Drop field that holds none (`struct W { s: [i64],
  d: D }`) is fine.
- **No view in a channel, a Mutex, an atomic or a lock's result**
  (`sync.view_item`, front/threads::check_sync_items, whether or not the
  program starts threads). What `tx.send(x)` sends, `Mutex::new(x)` and
  `m.with(|d| d.push(x))` store and `Atomic::new(x)` holds is taken out
  elsewhere and later (another thread, or after the scope of what it
  views), and nothing ties it to what it views; what `m.with(|d| ..)`
  (`try_with`, a guard's `with`, `Condvar::wait_then`) returns would
  outlive the lock. The instances of `mpsc::channel_in::<T>`,
  `Mutex::new`, `Atomic::new` with T a view type, and of the lock
  functions with R one, are rejected; the try is an owned copy
  (`s.to_vec_in(gpa)`, new in std, or `s.to_string_in(gpa)`). Scoped
  threads still borrow views of data that outlives the scope (unchanged);
  `thread::spawn` already required Send without views. A thread-local of
  a view type (`#[thread_local] static var X: [u8]`) does not compile
  today (std's __tls_addr instance fails to check: a separate bug).
- **Scoped threads only read what they borrow, in every form**
  (`sync.scope_shared_write`). The check (front/threads::capture_write)
  missed an exclusive slicing that is no `&x` node after the checker:
  `&a[..]`, `&v[i..j]`, `&v` and `&a` coerced to `inout [T]`, `v[i] = x`
  on a Vec or a Buf (`v.as_mut_slice()[i]`), an inout method of an
  array's slicing (`a.sort()`) or of a captured shared slice. It now takes the
  root of any argument an inout parameter is given and of any access a
  call returns. Two threads cannot each write a disjoint part of one
  slice: std has no `split_at_mut` yet (OVERSTRICT, for later), and a
  thread may not capture an `inout [T]` at all.
- **An array's slicing as an inout method's receiver** (`a.sort()`,
  `a[1..].sort()`) is an exclusive slicing, as `&a[..]` (it was a shared
  one, which the own pass and the thread check took as a read). An inout
  method of a shared view (`s.sort()` of `let s = v.as_slice()`) stays
  legal, unlike `sort(s)` (own.readonly): the own pass takes it as a
  change of what s views, and a scoped thread's copy of s is a write of
  the view it copied (two threads sorting one shared slice raced).
- OVERSTRICT fixed: the scope's own closure may change a variable no
  thread of the scope borrows (`var n = 0; thread::scope(|s| { s.spawn(||
  1); n += 1; })`), unless a thread borrows a view, whose origin the check
  does not know.

Left: `let v: Vec<i64>; v.push(1)` and `let a = [..]; fill(&a)` change a
`let` binding (immutability, not memory safety).
