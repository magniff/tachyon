# Semantics audit before 0.25: closures, generics, traits, threads

Branch `sem-poly`, from `release-0.25` at 2476e990. Each probe is a
regression case `tests/run/sem_poly_*.vl`: 205 cases, each built at -O0
and -O2 and run with `--check-alloc`. A finding's case carries `// XFAIL:
CLASS one line` and the directives of the right behaviour, so it turns into
an XPASS once fixed. A case without XFAIL records behaviour that is right
today. The suite (`tests/run.sh sem_poly_`, at -O2 and -O 0): 147 pass, 58
xfail, 0 fail.

Counts: **7 SOUNDNESS, 9 WRONG, 7 OVERSTRICT, 10 DIAG** distinct
findings. The known bug `let n = 1; bump(&n)` is not counted, but its
relatives are (W1 to W3, W7).

## Coverage: rule by context

`ok`: probed, holds. A finding id: probed, broken. `-`: not applicable.

| rule | locals and fields | let / inout / sink params, self | generics (plain, owned, view T) | traits, defaults, assoc types | closures | fn pointers | threads, Mutex, channels |
|---|---|---|---|---|---|---|---|
| capture mode (copy / let / inout / sink) | ok (c01–c06, c17, c27–c30) | W6 (sink of a borrowed binding), ok inout and sink params (c01, c02) | ok (g23) | - | W2, W4 | - | ok (y08) |
| a closure does not escape what it borrows | ok: block tail, break, struct, tuple, Some, generic id, match arm, if-let, scope result (c08–c16, y03) | - | ok (c12) | - | ok | - | ok (th04–th06, th23, x08b, x08c) |
| exclusivity: inout access vs other accesses | ok (c03, c20, c21, c29) | S4 (closure argument vs let argument) | ok (g18) | - | S4, W4 | ok (f10, f11) | ok (th19, y10, y11) |
| let is immutable | W1 (receivers), W2 | W1, W3 | W3 (plain T only) | W1, W3 (defaults) | W2, W7 | ok (f08) | ok (y10, y11) |
| each owned value dropped exactly once | ok (c23, c27) | ok (g10, g17, r01, r11) | ok (g19, g21, g22) | S3 (for and adapters over a user Iterator) | ok (c22, c23, x12) | ok (f07, f16) | ok (th14–th16, th18, th24, y04, y05) |
| moved-from values cannot be used | ok (c24) | ok (r03, y17) | ok (y17) | ok (r03, x22) | ok (c24, x16–x18) | ok (f06, f24) | ok (th20) |
| sink consumes; a sink closure called twice | - | ok (r01, x21) | ok (g10) | ok (r11) | ok (c22: exit 101; x12) | ok (f07) | ok (th14) |
| views do not outlive or survive a change of what they view | ok (x06, y01, y02) | ok (f00) | S1, S7 (ok: g04, g15, g16, g24, g25, y18) | ok (r13, r14, r16) | S1, S5 | ok (f12–f15, f17) | S1 (Mutex::with), S6 (channel), S2 (scope handle) |
| a trait's conventions bind its impls | - | ok (r06–r09) | ok (r04, r05b) | ok (r12, r17, r18, r23) | - | - | - |
| Fn means "changes no capture" | - | - | - | - | W5 | ok (f19, f23) | ok: Fn closures are not shared (th01, th02) |
| Send / Sync from types and effects | - | - | ok (th22, th23) | ok (th09) | ok (th06, x01) | ok (th08) | ok (th07, th21, y07, y09); W8, S2 |
| `fn(T)` == `fn(let T)`; conventions in fn types | - | - | ok (x27b) | - | ok (x27) | ok (f01–f05) | - |
| -O0 and -O2 print the same | every accepted case is run at both; only the cases of S1 to S5 differ (they read freed memory) | | | | | | |

## SOUNDNESS

**S1. A call of a generic `F` parameter loses the result's view summary,
and what it stores.** Inside `fn apply<T, R, F: Fn(T) -> R>(x: T, f: F) ->
R { f(x) }`, the result of `f(x)` is taken to view nothing, whatever the
instance. So a view comes back unchecked. The same happens with a plain fn
given as F (g06) and through std's generic callers: `Mutex::with`
(th10, th10b, th10c), `map(..).collect_in` (x05). Their "stores" are lost
too: `m.with(|d| d.push(s))` keeps a view of a dead local inside the Mutex
(x02). Direct calls of the same closure or fn pointer are checked (g03, g05,
f12, f13).

```vole
fn apply<T, R, F: Fn(T) -> R>(x: T, f: F) -> R { f(x) }
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    let s = apply(v, |d: Vec<i64>| d.as_slice());
    for i in 0..1000 { v.push(i); }
    println(f"{s[0]}");             // garbage, a different value at -O0 and -O2; check-alloc: use after free
}
```
Cases: `sem_poly_g07_closure_view_then_mutate`, g01, g02, g06, th10,
th10b, th10c, x02, x05.

**S2. A scoped thread's handle leaves `thread::scope`.**
`let h = thread::scope(|sc| sc.spawn(|| 7)); h.join()` is accepted. It
segfaults at -O0 and traps at -O2 (`sem_poly_th12b_scope_handle_escape_min`,
th12 with a view).

**S3. `for` over a user `Iterator`, and std's adapters over it, never drop
the owned items.** With `impl Iterator for Gen { type Item = R; ... }` and
`impl Drop for R`, `for r in Gen { n: 2 } { .. }` prints no drop, and
`--check-alloc` reports every item's Vec as not freed. `.map(|r| r.id).sum()`
and `.count()` drop none either. `while let Some(r) = g.next()` drops
correctly (r15c), and so does `collect_in` (y14). Cases: r15, r15f, r15g,
r15h.

**S4. A closure argument's inout capture is not checked against the same
call's let arguments.** `run(|| v.push(2), v)` is accepted, although `run(||
n += 1, &n)` is `own.conflict` (c20). So does a slice:

```vole
fn run<F: FnMut()>(f: sink F, s: [i64]) -> i64 { f(); s[0] }
// in main:
println(f"{run(|| { for i in 0..1000 { v.push(i); } }, v.as_slice())}");   // use after free
```
Cases: x07, x07b, x07c.

**S5. A closure calling an inout method on a captured owned `let` is not
a write.** The let binding changes (W2), and the own pass sees no write, so
a view of it is not invalidated:

```vole
let v = v0;
let s = v.as_slice();
let c = || { for i in 0..1000 { v.push(i); } };
c();
println(f"{s[0]}");                 // use after free
```
Case: x24b.

**S6. An mpsc channel of a view type.** `channel_in::<[i64]>(gpa)`,
`tx.send(v.as_slice())`, then v is dropped and `rx.recv().unwrap()[3]` reads
freed memory (x03). `send` takes `x: sink T`, and the view is stored in
the channel's buffer through raw pointers. Nothing ties it to `tx` or `rx`.

**S7. A generic `impl<T> Drop for G<T>` instantiated with a view.**
`var g = G { x: arr[..] }; var v = ...; g = G { x: v.as_slice() };`. At the
scope's end v (declared later) is freed first, then g's drop reads its view
(x15: check-alloc use after free). A non-generic type holding a view
cannot implement Drop (`own.drop_view`, x14b); a generic instance gets past
the rule (x14).

## WRONG

- **W1. An inout-self method on a let receiver is accepted**, inherent or
  trait, plain or owned: `let p = P { x: 1 }; p.bump();` prints 2 (r02,
  r02b, r02c, r02d). `P::bump(&p)` is the known bug's form (x23). A view
  held across it is caught (f00).
- **W2. A closure calling an inout method on a captured let changes the
  let.** With a plain `let p` (captured "by copy") `|| { p.bump(); p.x }`
  changes p itself: it prints `2 3 3` (x25, x25b). With an owned let,
  `|| v.push(1)` grows v (x24).
- **W3. A let parameter or let self of a plain type takes inout methods in
  generic and default bodies.** `fn use_it<T: B>(x: T) { x.bump(); }`
  and a default `fn twice(self) { self.bump(); }` are accepted for i64 and
  for a struct of i64 (they change a copy), and are `own.readonly` for owned
  types (r05 against r05b, r10 against r10b).
- **W4. A closure holding an inout capture can be copied.** `let a = || n
  += 1; let b = a;` gives two live exclusive accesses to n (c05). conventions.md
  §2.2 says a view holding an inout is move-only.
- **W5. `Fn` takes closures that change their captures through a call.**
  `apply_fn(|| v.push(1))` and `apply_fn(|| bump(&n))` satisfy `F: Fn()`
  (c25, c26). Only assignments are counted. Sharing such an Fn across
  threads is still refused (th01, th02), so this is not a race.
- **W6. A sink closure capturing a borrowed binding borrows it.** This
  covers a let or inout parameter of an owned type, a let self, and a `for`
  variable over owned elements. `sink || v.len()` is accepted without
  taking anything (x08, x09, x10, x11). Through an inout parameter, the sink
  closure's changes reach the caller: `sink || { v.push(9); v.len() }`
  prints `2 2`, not a snapshot (x09e). Moving such a capture out is refused
  (x08d to x11d), and so is a thread (x08b).
- **W7. An FnMut called through a let parameter changes the caller's let
  closure.** `let c = sink || { v.push(1); v.len() }; run(c); run(c)` with
  `fn run<F: FnMut() -> i64>(f: F)` prints `3 7` (x26c). The guide says to
  call an FnMut from a sink parameter or a var.
- **W8. The `Scope` can be returned out of `thread::scope`**:
  `thread::scope(|sc| sc)` is accepted (x20). Spawning on it later is
  refused (x20b: `sync.scope_spawn`), so W8 is not unsafe today.
- **W9.** A Drop impl on a view-holding type, through a generic instance
  (x14): see S7.

## OVERSTRICT

- **O1.** A non-capturing closure with an inout parameter, used as
  `fn(inout i64)`, needs `unsafe`: "using a closure with pointer
  parameters as a 'fn' value is unsafe". A named fn of the same type does
  not (f09).
- **O2.** A temporary passed to a let parameter through a fn pointer is
  refused: "this value has no place: name it first". A direct call accepts
  it (f18 against g10).
- **O3.** A closure parameter cannot be `sink`: `|r: sink R|` is
  `conv.sink_type`, so `F: FnMut(sink R)` cannot be met by a closure (x28).
  With a `F: FnMut(R)` bound, the refusal should name the bound instead
  (x30).
- **O4.** In a generic body, `var r = Vec::new_in(gpa); r.push(a); r` does
  not infer `Vec<T>` from the push or from the result type (g26).
- **O5.** `impl<T> Tr for Vec<T>` must also write the allocator parameter,
  `impl<T, A: Allocator>` (y13). The traits guide shows `Vec<T>`.
- **O6.** A sink closure may move a whole capture out, but not one field of
  it (x13).
- **O7.** `map(|r: R| r.id)` over owned items fails with "expected 'R',
  got 'let R'". Only the unannotated `|r|` works (r15e, r15h).
- Note, by design: a `fn` pointer is never Send ("may reach any static"),
  so `thread::spawn(sink || f())` with a `let f: fn() -> i64` is refused
  even for a pure function (th08).

## DIAG

- **D1.** The closure-escape help says "write `move`" (Rust's word; vole
  has `sink ||`). It is followed by a cascade error "cannot call
  non-function type '!'" (c08; c09 to c16 and y03 have the same help).
- **D2.** `sync.borrow_escapes` for a non-sink closure says "move it into
  the thread (`move ||`)", and its try: line rewrites to `spawn(move ||`.
  That is `conv.rust` (th04).
- **D3.** `sync.global` says "a static mut" and "without `mut`". The
  language has `static var` (th09).
- **D4.** `sync.not_sync` and `sync.not_send` describe a closure's inout
  capture as "holds a raw pointer at '.n' (*i64)" (th01, th02, th03, th06,
  th23, x01). The user wrote no pointer.
- **D5.** Fn types print a sink parameter as a bare type and a let one
  with `let`: "expected 'fn(let Vec<i64>) -> i64', got 'fn(Vec<i64>) ->
  i64'" for a `fn(sink Vec<i64>)`. The trait-signature errors say
  "expected 'fn(let R) -> i64'" (f04, f05, f19, r07, r09).
- **D6.** A let closure parameter given to `F: FnMut(inout i64, i64)` gets
  `conv.marker: 'i64' is lent inout here: mark it '&i64'`, with a try:
  that edits the parameter type to `&i64` (f21).
- **D7.** "expected 'R', got 'let R' | help: it is a reference: read
  through it with '*' | try: *R" for a closure parameter (r15e, x28, x29).
  vole has no `*` on accesses.
- **D8.** `own.moved` after `thread::spawn(sink || v.len())` suggests
  `sink || v.len().clone()` (th20).
- **D9.** Some try: lines pass a closure's printed type as NAME, unquoted:
  `volec query def closure() -> i64 at FILE:5:17` (th06, th23) and
  `volec edit patch closure(inout Scope) -> [i64] at ...` (th13).
- **D10.** A sink closure that moves out a capture it only borrows (a let
  parameter) is refused with "the closure may be called again". The cause
  is that the capture is a borrow (x08d).

## Method

Each probe was compiled with `volec check`, then built and run at -O0 and
-O2, each with and without `--check-alloc`. The outputs were compared, and
check-alloc's stderr (leaks, use after free) was read. A few accepted
programs were also compared between `-j1` and `-j8` (same output). The
Linux valgrind row was not run: every SOUNDNESS finding is a use after
free or leak reported by `--check-alloc`, or a crash.
