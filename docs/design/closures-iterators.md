# tachyon 0.14 design: closures and iterators, split for parallel work

## 1. Current state (release-0.13)

- **Parser.** Expressions use a Pratt parser in `front/parser/exprs.tach` (`parse_prefix`, `parse_primary`, `parse_postfix`). A `|` in prefix position is currently the error "expected expression". `move` is reserved (`front/lexer.tach::init_lexer`, `add_reserved`). Types are parsed by `front/parser/types.tach::parse_type`. A path type `I::Item` becomes a `TyName` whose `list` holds the prefix segments. `parse_fn_type` builds a `TyFn` node, with `d=1` meaning extern C. Bounds are parsed by `items::parse_generic_params` with `parse_type` and stored in the param's `h`. `parse_trait` rejects `trait X<T>` and accepts only `fn` items.
- **AST.** `front/ast.tach`: `NodeKind`, uniform `Node {a,b,c,d,list,count,ty,x,y,z,g,h,p}`. The checker desugars by building or rewriting nodes in place: `check_for_each`, `MethodCall` turning into `Call`, `VecOp`.
- **Monomorphization.** `front/generics/instantiate.tach`. `fn_instance` clones the template AST (`clone_node`) and queues it on `INST_QUEUE`. `instantiate_call` → `infer_from`, which makes 2 passes and leaves untyped literals for last; `unify` matches AST type nodes against `TYPES`. Bodies are checked per instance (C++-template style), so unbounded generics are duck-typed. `check::finish_program` appends the instances to the program list that both back ends walk.
- **Traits.** `front/traits.tach`: `TraitInfo`, `ImplInfo`, at most one impl per (trait, type). A generic impl must be for a generic struct or enum, with the impl's params as its arguments. `collect_impl` copies missing defaults into each impl, and they are checked eagerly in non-generic impls. Bounds are checked by `check_bounds`/`satisfies`; `require_in_bounds` limits which methods may be called. There are no generic traits, associated types, `dyn` or `impl Trait`.
- **Method dispatch.** `check/calls.tach::synth_method` does a linear `find_method`, auto-`&`/`*` of the receiver (a compound temporary may be passed by address), and rewrites to `Call` with `x=f+1`.
- **fn pointers.** `TyKind::Fn` (`a`=result, `b`=extern C). Calls through a value go through the tail of `synth_call`. Making a function with pointer parameters into a value is unsafe, and so is passing a non-borrow pointer through a fn pointer.
- **Locals.** `check/mod.tach`: `LOCALS` are global ids; `Ident` nodes get `res=Local, y=id`. Neither back end ever reuses a slot: gen0's `bind` grows `FRAME_SIZE`, and `middle/lower::new_slot_for` makes a new slot per binding. A local whose address is taken (`&x`) is not promoted (`lower_program`, `PROMOTE`).
- **for loops.** `check/body.tach::check_for` turns a `Range` into a counted loop, and `check_for_each` turns slices and arrays into an index loop. Anything else is an error. `synth_expr_inner` rejects a `Range` outside `for`.
- **std.** One file, `compiler/std/std.tach` (680 lines). `embed.sh` turns it into `front/stdsrc.tach`, and it is loaded by a token scan (`modules::load_std_if_named`). The prelude list is `modules/lookup::prelude_name`. `Option`, `Vec` (`as_slice`) and `HashMap` (iterated by slot: `slots`/`key_at`/`value_at`) are there, plus `sort<T: Ord>`.
- **Optimizer** (`middle/`, see optimizer.md):
  - inlining bottom-up over SCCs: up to 30 instructions, or a single call site up to 400; `#[inline]` ignores the budget; devirtualization of constant fn addresses, iterated over 3 rounds;
  - SROA of structs, tuples, enums and slices, including the values of `if`/`match`/`loop`;
  - SSA at construction, store-to-load forwarding, dead stores;
  - range-based jump threading and bounds-check removal;
  - SCEV and unrolling;
  - a loop vectorizer for innermost counted loops (unit stride, integer reductions);
  - LICM and scalar promotion.

## 2. Surface syntax and semantics

**Grammar** (docs/grammar.md, "Additions of 0.14"):
```ebnf
prefix   += [ "move" ] ( "||" | "|" [ cparam { "," cparam } [","] ] "|" ) ( "->" type block | expr )
cparam    = single_pattern [ ":" type ]          (* no top-level or-pattern *)
tparam    = ident [ ":" bound { "+" bound } ]
bound     = path [ "<" ident "=" type { "," ident "=" type } ">" ]   (* Iterator<Item = i64> *)
          | ("Fn" | "FnMut") "(" [ type { "," type } ] ")" [ "->" type ]
trait_item += "type" ident ";"        impl_item += "type" ident "=" type ";"
type      += path "::" ident        (* T::Item, Self::Item, F::Output: projections *)
```
`move` becomes a keyword (`Tok::Move = 91`). The closure body has binding power 0, as in Rust.

**Typing.**
- Each closure expression, in each enclosing function instance, has its own anonymous type.
- Parameter types come from annotations, else from the expected signature: an `fn(...)` type, or the `Fn` bound of a type parameter at an argument position. Without either, the error is "cannot infer the type of closure parameter 'x'", with `try: |x: i64|`.
- The result is the annotated type, else the expected one, else the body's type.
- `return` returns from the closure. `break`/`continue` cannot cross it. An `unsafe` block around the closure covers its body.

**Captures.** The mode is decided per variable, so that the observable meaning never depends on an analysis:
- An immutable binding (`let x`, parameters, `for` variables) is captured by value. Nobody can change it, so a copy and a borrow are indistinguishable. Above 32 bytes it is captured by reference instead, which is still indistinguishable.
- A `let mut` binding is captured by reference. The closure sees changes and makes them, as a Rust non-`move` closure does.
- `move |..|` captures everything by value. Assignments inside then change the closure's own copy.

**Escape (soundness).**
- Closure types cannot be named, statics cannot hold them, and there is no `dyn` or `impl Trait`. So a closure value, and any value whose type contains one (`Map<I, C>`, `Vec<C>`), can only flow within its creating function's frame and down into callees.
- The only way out in safe code is leaving a *scope* as a value: a block tail, a `break` value, or a match or `if let` arm value.
- Rule: when a value leaves a scope and its type contains a closure that borrows a variable declared in that scope, it is an error, with `try:` "write `move`, or declare 'j' outside the block".
- Combined with the invariant that borrowed locals keep their own frame slot for the whole function (true today; document it in optimizer.md for any future stack colouring), borrows cannot dangle.

**Fn bounds.**
- `F: Fn(A..) -> R` and `F: FnMut(A..) -> R` are built-in bound forms. They are not trait items and are not in the trait table.
- A type satisfies `FnMut(A..)->R` if it is a closure with exactly that signature, or the plain `fn(A..)->R` type.
- It satisfies `Fn` if it is a fn pointer, or a closure that assigns no captured variable or part of one.
- There is no `FnOnce`.

**Calls.**
- `f(args)` where `f`'s type is a closure type becomes a direct `Call` of the closure's function. Arguments are `[&f]` (only when it captures), then `args`; the receiver is auto-referenced like a method's `self: *T`, temporaries included.
- Inside generic code, `F` is concrete per instance, so the same rule applies, or the existing fn-pointer call when `F` is a fn type. `(self.f)(x)` works.
- **Coercion:** a non-capturing closure, literal or value, coerces where a plain `fn(..)` is expected, becoming the closure's function as a value. A capturing one is an error, with help "make the parameter generic: `fn apply<F: Fn(i64) -> i64>(f: F)`". The existing unsafety rule for pointer parameters applies.

**Associated types (restricted).**
- `type Item;` in traits and `type Item = T;` in impls; every declared name must be defined.
- `X::Name` resolves only when `X` is concrete (always true per instance) or `Self`. Two traits giving `X` the same name is an ambiguity error.
- Built-in `F::Output` is the result type of a closure or fn type.
- Constraints `I: Iterator<Item = T>` are checked at instantiation, and they bind `T` during inference.
- No defaults or bounds on associated types, and no `<T as Tr>::N`.
- **Lazy defaults:** a trait default copied into a *non-generic* impl is checked (and emitted) only when first used. This is needed so that `sum` is not checked for `Item = [u8]`.
- **Slice impls:** `impl<T> [T] { ... }` and `impl<T> Tr for [T]` are allowed, so that `s.iter()` and `s.sort_by(..)` work.

**Iterator trait** (prelude gains `Iterator`; `compiler/std/iter.tach`, concatenated after std.tach by embed.sh, same module `std`):
```
pub trait Iterator {
    type Item;
    fn next(self: *Self) -> Option<Self::Item>;
    fn exact_len(self: *Self) -> i64 { -1 }                       // items left, or -1
    fn at(self: *Self, k: i64) -> Self::Item { self.next().unwrap() }  // k-th left; only when exact_len>k, k increasing
    fn map<B, F: FnMut(Self::Item) -> B>(self: Self, f: F) -> Map<Self, F>
    fn filter<F: FnMut(Self::Item) -> bool>(self: Self, f: F) -> Filter<Self, F>
    fn enumerate(self: Self) -> Enumerate<Self>          // Item = (i64, I::Item)
    fn zip<J: Iterator>(self: Self, other: J) -> Zip<Self, J>   // Item = (I::Item, J::Item)
    fn take(self: Self, n: i64) -> Take<Self>
    fn fold<B, F: FnMut(B, Self::Item) -> B>(self: Self, init: B, f: F) -> B
    fn for_each<F: FnMut(Self::Item)>(self: Self, f: F)
    fn count(self: Self) -> i64
    fn sum(self: Self) -> Self::Item                      // starts at `0 as Self::Item`
    fn min(self: Self) -> Option<Self::Item>
    fn max(self: Self) -> Option<Self::Item>
    fn collect(self: Self) -> Vec<Self::Item>
}
```
- Every consumer is written on top of `fold`.
- Sources and adapters override `fold` with a counted loop (internal iteration), so a chain becomes one `for k in lo..hi` loop after inlining.
- `Zip` and `Enumerate` use `exact_len`/`at` when both sides know their length; this works like Rust's TrustedRandomAccess, without specialization.
- Items are passed by value, as `for x in slice` is today.

**Sources and other std additions:**
- `SliceIter<T> {s: [T], pos: i64}`, from `Vec::iter(self: *Vec<T>)` and `impl<T> [T] { fn iter }`;
- `Range<T> {start, end}` and `RangeInclusive<T> {start, end, done: bool}`: `a..b` and `a..=b` outside `for` and slicing build these;
- `HashMapIter<K,V>` (copied handle fields plus `pos`, `Item = (K, V)`), plus `keys()` and `values()`;
- `pub fn sort_by<T, F: FnMut(*T, *T) -> i64>(s: [T], f: F)`, also as `Vec::sort_by` and the slice method, so `|a, b| a.cmp(b)` works. All std iterator methods are `#[inline]`.

**for desugaring** (`for PAT in E BODY`, where `E` is not a range literal and its type is not a slice or array):
- `I` is `E` if its type implements `Iterator`, else `E.iter()` (Vec, HashMap, slices, user types).
- If `I` is a `std::SliceIter`, `Range` or `RangeInclusive`, the existing counted forms are used: `for __k in it.pos..it.s.len { let PAT = it.s[__k]; BODY }`.
- Otherwise:
```
{ let mut __for_iter = I; LABEL: loop { let PAT = match __for_iter.next() { Some(__for_item) => __for_item, None => break }; BODY } }
```
- Otherwise the error is "'for' iterates over ranges, slices, arrays, iterators and types with an 'iter' method".

## 3. Representation

- **Type table:** a closure type is a `TyKind::Struct` of a synthesized struct. `StructInfo.closure = id+1`. Its fields are the captures: by value `T`, by reference `*T`; a non-capturing closure has zero fields. `buf_type` prints `closure(i64) -> i64 at f.tach:4:15`.
- **ClosureInfo** (front/closures.tach): `{node, f, env_struct, encl_fn, captures (TLISTS index of local,mode pairs), capture_count, writes: bool, borrow_depth}`.
- **Function:** a synthesized `Fn` node with `p |= FN_CLOSURE`. Its `list` is `[Param env: *Env]` (only when capturing; a hidden name, so a captured `self` still works) followed by the params; `c` is the shared body node. It gets an `add_fn` entry with the signature set directly and is pushed to `CLOSURE_FNS`, which `finish_program` appends after the instances. It is never put on `INST_QUEUE`: the body is checked inline, once.
- **Checked AST:**
  - The `Closure` node stays in place for the tools, with `x=id+1`, `ty`=the closure type, and `y`=the node the back ends lower: a `StructLit` of the env (inits `Ident` or `Unary(&, Ident)`), or an `Ident(Res::Fn)` when coerced.
  - Captured uses in the body are rewritten in place after the body is checked: to `FieldAccess(Ident env, field)` by value, or `Unary(*, FieldAccess(...))` by reference, with `p |= NODE_CAPTURE` and `d = local+1` kept for the tools.
  - **No new IR:** middle and gen0 each gain one line, `Closure => lower(NODES[n].y)`.
- **Symbols:** closure k (in check order) of the function instance with symbol `S` is `S.k`, e.g. `main.0`, `Vec.Gl.sort_by.1`, nested `main.0.0`. A numeric segment cannot clash with any item. The env struct has the same symbol, so the mangling `N<len><sym>` is deterministic.

## 4. Work split

**Phase 0, serial (the lead, ~1 day): the interface commit.** Everything below compiles with stub bodies, and the suite passes unchanged.
- `ast.tach`:
  - `NodeKind::Closure` and `AssocType`, appended at the end;
  - flags `CLOSURE_MOVE=1` (in `c`), `NODE_CAPTURE=1<<26`, `FN_CLOSURE=1<<27`, `FN_LAZY=1<<28`;
  - `TyFn.d`: 2 for `Fn`, 3 for `FnMut`;
  - `Param.d`: the pattern (0 for a plain name);
  - `Trait.b` and `Impl.c`: a holder node whose list is the `AssocType` nodes (`a`=name, `b`=type);
  - a bound `TyName.h`: holder of the `Name = T` constraints.
- Lexer `move`; the parser for everything in §2; `clone_node` for the new kinds; `StructInfo.closure` (`refactor field StructInfo --add 'closure: i64 = 0'`).
- New modules with stubs:
  - `front/closures.tach`: `check_closure(n, expected)`, `check_closure_sig(n, mark, ret)`, `closure_of_type(t)`, `closure_sig(c)`, `note_local_use(n, local)`, `note_local_write(local)`, `closure_call(n, ty)`, `coerce_closure(n, expected) -> bool`, `fn_bound_satisfied(bound, t)`, `is_deferred_arg(arg)`, `infer_closure_arg(params, bound, tmod, arg, p)`, `check_scope_exit(ty, depth, pos)`, `CLOSURE_FNS`;
  - `front/assoc.tach`: `collect_trait_assoc(tr)`, `collect_impl_assoc(i)`, `projection(t, name, pos)`, `resolve_projection_node(n)`, `is_projection_node(n)`, `assoc_constraints_hold(bound, t)`, `infer_from_assoc(params, bound, tmod, k)`, `ensure_checked(f)`;
  - `front/check/iterate.tach`: `check_for_iter(n)`, `range_value(n, expected)`.
- The hooks calling those stubs: `synth_expr_inner`/`check_expr_inner`, `synth_name`, `synth_call`, the check-mode fn coercion, `satisfies`, `infer_from` (closures deferred to a third pass, then a bound-inference pass), `check_block` tail / arms / `break`, `check_assign`, `resolve_type_name`, `unify`, `collect_impl`, `check_program`, `finish_program`, `check_for`, Range.
- `embed.sh` concatenating `iter.tach`; `iter.tach` with the trait text; std loaded on `..`/`..=` tokens; `Iterator` in the prelude.
- A "0.14" skeleton in grammar.md. Verify that `lower_aggregate` and gen0 use `StructLit.ty` and `FieldInit.x`, not names.

| task | owns | consumes | provides |
|---|---|---|---|
| **T1 Closures** | `front/closures.tach`, the closure branch of `infer_from`, `tests/run/closure_*` | Phase 0 AST/hooks | closure types, Fn bounds, calls, coercion, escape check |
| **T2 Associated types** | `front/assoc.tach`, the projection lines in `traits.tach`/`instantiate.tach`, slice impls, lazy defaults, `tests/run/assoc_*` | Phase 0 | `projection`, `implements(Iterator)`, `Item =` constraints |
| **T3 Iterators** | `compiler/std/iter.tach`, `front/check/iterate.tach`, `tests/run/iter_*`, bench pair | T1, T2 (staged) | std API, for/range desugaring |
| **T4 Zero cost** | `compiler/src/middle/*`, `tests/run/opt_iter_*`, `docs/optimizer.md` | the IR shapes of §3 | the fused loops |
| **T5 Tools** | `compiler/src/tools/*`, `guide/`, `compiler/guide/*.md`, `tests/{query,refactor,fmt,guide}` | §3's AST shapes | fmt/query/refactor/guide |

**T1 items.**
1. Checking a closure body inline: save and restore `RETURN_TYPE`, the loop stack, defers and the wrap state. Record the env boundary as an ENV index; a stack of these handles nesting. Pattern params become `let`s. Record captures in `note_local_use` and the capture modes per §2.
2. After the body: make the env struct, the Fn and FnInfo, the rewrites, `y`, the symbol and display.
3. `closure_call`, `coerce_closure`, `fn_bound_satisfied` (resolving the bound under `env_enter`), and the deferred inference pass: the expected signature from `F`'s bound under the partial `bound[]`, then binding `F`, then unifying the bound's result to bind `B`. The same pass serves struct literals.
4. `check_scope_exit`, using a memoized "type holds a borrowing closure".

Tests use only generic functions with Fn bounds; no std iterators are needed. Acceptance cases:
- `apply(|x| x + k, 1)`; mut capture visible both ways; `move` snapshot; nested closures; a closure in a generic instance; `(h.f)(3)`; `|(a, b): (i64, i64)|`;
- errors: assignment under an `Fn` bound, a capturing closure to `fn`, a block-escape, an unannotated `let`;
- identical output at -O0/1/2;
- query mode (`TY_ERROR` instances) does not crash.

**T2 items.**
1. Assoc declarations and definitions, and `projection`, including `F::Output` and generic impls resolved under the instance's targs, with a cycle guard.
2. `Item = T` constraints: checked in `satisfies` and used in inference.
3. Lazy defaults: `FN_LAZY` on copies in non-generic impls; `ensure_checked` on first reference queues them; `finish_program` drops the unchecked ones.
4. `impl<T> [T]` inherent and trait impls.

Tests use user `impl Iterator for Counter` with `next`/`count`/`sum` (the default bodies come from Phase 0's trait text) and do not need closures. Acceptance cases:
- `fn first<I: Iterator>(it: I) -> Option<I::Item>`;
- the constraint mismatch error;
- a missing `type Item`;
- an `Item = [u8]` impl compiles until `sum()` is called;
- `impl<T> [T] { fn second(self: [T]) -> T }`.

**T3 items.**
1. `check_for_iter` and `range_value`. Start duck-typed, using the `next` method by lookup, so that inherent `next`s on Range/SliceIter test it before T2 lands.
2. Sources and `Vec`/`HashMap`/slice `iter`, then the switch to `impl Iterator` once T2 lands.
3. Adapters, consumers and the `fold` overrides, `exact_len`/`at`, and `sort_by`. This needs T1; until then, test with named functions as `F`.
4. `bench/iterchain.tach` and `bench/iterloop.tach` (below).

Acceptance cases:
- `for` over Vec, `&v`, HashMap, a user iterator, `(0..10)`, `0..=255u8` (no overflow);
- labels, `continue` and `defer` in bodies;
- each adapter and consumer, `collect`, `sort_by`;
- the error message for something not iterable.

**T4 items** (before T1–T3 land, test on *hand-desugared 0.13 programs*: env structs passed as `*Env`, structs with `next() -> Option<T>`, generic `fold<F: Call>` over a `trait Call { fn call(self: *Self, x: i64) -> i64; }`; these are exactly the shapes T1–T3 produce):
1. SROA to a fixpoint. When a scalarized slot's leaf held another slot's address, requeue that slot, so that by-reference captured counters get promoted.
2. Threading `match` on a phi of constant enum tags after `next()` is inlined, and canonicalizing the result into a counted loop that SCEV and the vectorizer accept.
3. The inliner: closure functions (`FN_CLOSURE`) and `#[inline]` std methods must not exhaust the 3000/growth budgets mid-chain (charge them only their post-simplification size). Elide copies of `self: Self` adapter structs.
4. Merging equal induction variables, `{0,+,1}` twice, for next-based zip/enumerate (a fallback if the `exact_len` route fails), and measuring compile time on a 200-chain program; hash `fn_instance`/`make_type` lookups if they turn quadratic.

Acceptance:
- `// CHECK-NOT: call` and vector ops (as in the hand-loop twin) for `v.iter().map(|x| x*3).sum()`;
- no env slot left in the IR;
- the bench pair within 5%;
- no `bench/` or self-compile regression.

**T5 items.**
1. fmt: `|x| e`, `||`, `move`, `-> T {}`, no spaces inside the bars, wrapping of `.map(..)` chains.
2. query:
   - `query type` on closures and closure params;
   - `refs`, `unused`, `stats` and `deps` skip `FN_CLOSURE` functions and closure structs but count item references inside closure bodies;
   - the walkers (`refactor_shape/body::kids`, `inline`, `extract`, `signature::calls_of`, `rewrite/parsed::expr_slots`, `rewrite/pattern`) descend into `Closure.a`;
   - `extract-function` maps `NODE_CAPTURE` uses back to locals and refuses ranges that cut a closure.
3. The `guide closures` and `guide iterators` topics, the core-guide table rows, the errors topic, explain codes.
4. docs/query.md, refactor.md, fmt.md.

Start on parse-only parts (fmt, rewrite patterns) right after Phase 0, and the guide last; its examples are compiled by `tests/guide/run.sh`. Acceptance: new `tests/query/closures.q`, `tests/refactor/closures.t` and fmt cases pass, and `fmt --all --check` is clean.

**Merging.** Each task edits mostly its own new files. Shared files get only Phase 0's one-line hooks. `stdsrc.tach` conflicts are resolved by rerunning `embed.sh`. Merge order: T2, then T1, then T3, with T4 and T5 at any time. After the merge: a `bootstrap/gate.sh --quick`.

## 5. Optimizer work for zero cost, and the benchmark

What already works: inlining, devirtualization, SROA, forwarding, threading, the vectorizer. What is missing is listed in T4 above.

The design avoids depending on the riskiest pieces:
- consumers use internal iteration (`fold` overrides that are already counted `for` loops);
- `for` over SliceIter, Range and Vec takes the counted form directly;
- zip and enumerate use `exact_len`/`at`.

The vectorizer then sees the same loop as the hand-written one.

**Bench pair.** `bench/iterchain.tach` (chains) and `bench/iterloop.tach` (hand loops), with identical output and C twins `iterchain.c`/`iterloop.c`. Kernels run over a `Vec<i64>` of 2^20 elements, 200 repetitions:
1. `filter(even).map(sq).sum()`;
2. a dot product via `zip`;
3. `enumerate().map(i*x).sum()`;
4. `map(x^k).max()` and `count`;
5. `for x in v.iter().take(n)` (the next-based path);
6. `collect` + `sort_by(|a, b| b.cmp(a))` against a hand-written heapsort.

`bench/run.sh` prints the iterchain/iterloop ratio, and the gate fails above 1.05.

**Risks:**
- SROA's leaf rules on `Option<(i64, T)>`;
- the inliner's budgets on deep chains;
- the next-based `for` over filter chains, which relies on threading (measured separately; the requirement is parity with the hand loop, which may not vectorize either);
- compile time from many monomorphized instances (linear scans in `fn_instance`, `make_type`, `find_method`);
- std now loading on any `..`.

## 6. Open questions, with recommendations

1. **`move`?** Yes. It is optional and only changes the meaning for `let mut` captures; agents write it out of Rust habit.
2. **Closure params with no context?** Make it an error with a `try:` annotation, not inference from later use.
3. **filter takes the item by value or by `*T`?** By value; give a targeted help for `|&x|` and `*x`.
4. **`iter_mut`?** Not in 0.14 (it needs raw pointers). Document `v.set(i, ..)`; revisit with 0.17's value semantics.
5. **`collect` targets?** Vec only; `collect::<Vec<_>>()` gets an error with help.
6. **`impl Fn` returns?** Defer to 0.15. Then the function body becomes one more scope exit, and returned closures must capture by value.
7. **Fn vs FnMut?** `Fn` means no assignment to captures; no `FnOnce`.
8. **Associated-type scope?** As restricted in §2. Lazy defaults are acceptable: `query`'s `check_unchecked` still checks them.
9. **std trigger on `..`?** Accept it, and measure compile time on programs without std. The fallback is a parser flag set only for value-position ranges.
10. **Should closure functions always be `#[inline]`?** No. Let T4 use `FN_CLOSURE` in the cost model; single-call-site instances already qualify.
11. **Closures in the random-program fuzzer?** Yes, after the merge, as a follow-up owned by T4.

### Critical files for implementation
- /Users/magniff/workspace/tachyon/compiler/src/front/check/calls.tach (`synth_call`, `synth_method`)
- /Users/magniff/workspace/tachyon/compiler/src/front/generics/instantiate.tach (`infer_from`, `unify`, `clone_node`, `fn_instance`)
- /Users/magniff/workspace/tachyon/compiler/src/front/traits.tach (`collect_impl`, `satisfies`, `has_impl`)
- /Users/magniff/workspace/tachyon/compiler/src/front/check/body.tach (`check_for`, `check_for_each`, `check_block`) and /Users/magniff/workspace/tachyon/compiler/src/front/check/mod.tach (`check_program`, `finish_program`, `lookup_local`)
- /Users/magniff/workspace/tachyon/compiler/std/std.tach (with /Users/magniff/workspace/tachyon/compiler/std/embed.sh) and /Users/magniff/workspace/tachyon/compiler/src/middle/sroa.tach, /Users/magniff/workspace/tachyon/compiler/src/middle/inline.tach

## Phase 0 notes (the interface commit, for T1–T5)

What Phase 0 made, where it differs from or adds to §3–§4:

- **AST.** `Closure`: list=params, a=body, b=written result type (0: none), c=flags (`CLOSURE_MOVE`). A closure parameter is a `Param`: a=name (0 when it is a pattern), b=type (0: inferred), c=mutable, d=the pattern (0 for a plain name, `mut x` included). `AssocType`: a=name, b=type (0 in a trait). The holders (`Trait.b`, `Impl.c`, a bound `TyName.h`) are `Generics` nodes whose list is the `AssocType` nodes; 0 when there are none. `Fn`/`FnMut` bounds are `TyFn` with d=2/3 (a=result, `TyUnit` when not written). `T::Item`/`Self::Item` are the existing path `TyName` (list = `[Ident T]`). `clone_node` copies `Closure.a/b`, `Param.d`, `AssocType.b` and (already) `TyName.h`.
- **Parser.** `parse_bound` (parser/types.tach) parses bounds; `Fn`/`FnMut` are recognized by name only there. `type` in an inherent impl is an error. `move`, `|`, `||` start an expression (also for `return`/`break` values).
- **Flags.** As designed: `CLOSURE_MOVE=1`, `NODE_CAPTURE=1<<26`, `FN_CLOSURE=1<<27`, `FN_LAZY=1<<28` (ast.tach). `StructInfo.closure` added.
- **Stubs.** front/closures.tach, front/assoc.tach, front/check/iterate.tach with the names of §4. Stubs that need checking report `error[type error] <what> are not implemented yet (check.unimplemented)` via `closures::unimplemented(pos, what)` (compiler errors have kinds, not codes, so the code is in the text; no `explain` entry: it disappears with the stubs). `check_for_iter` and `range_value` keep 0.13's messages (tests/run/err_for_over_non_range, err_range_outside_for depend on them). `closure_of_type` is real (reads `StructInfo.closure`); `is_projection_node` is a syntactic placeholder (one prefix segment that is `Self` in an impl or a type parameter in scope); `collect_trait_assoc` accepts (std's `Iterator` declares `type Item`); `collect_impl_assoc` reports unimplemented.
- **Signatures added where §4 named none.** `ClosureInfo` with `CLOSURES`/`CLOSURE_COUNT`; `CLOSURE_FNS` holds **Fn nodes** (not FNS indices). `check_closure_sig(n, mark, ret) -> i64` (the fn type; param types pushed on TSCRATCH from mark). `closure_sig(c) -> i64` (a fn type). `infer_closure_arg(params, bound: *i64, tmod, arg, p)` where p is the parameter's type node. `infer_from_assoc(params, bound: *i64, tmod, k)`. `collect_trait_assoc(tr)`: tr = TRAITS index, called from `add_trait` (the names phase, before types resolve). `collect_impl_assoc(i)`: i = IMPLS index, called in `collect_impl` after coherence; `ImplInfo`, `IMPLS`, `IMPL_COUNT` are now `pub` for assoc.tach.
- **check_scope_exit(ty, depth, pos)**: depth is a **LOCAL_COUNT mark** (locals with an id >= depth are declared in the scope left). Hooks: `check_block` tail, each `match` arm's value (patterns/mod.tach), `break` value (`check_loop` stores LOCAL_COUNT in the Loop's `d`, which was unused).
- **Hooks.** `synth_expr_inner`/`check_expr_inner`: `Closure => check_closure`, `Range => range_value`. `coerce_closure(n, expected)`: in `check_expr_inner` right before `mismatch_error` (`check_closure` also gets `expected` directly). `note_local_use`: `synth_name`, local branch. `note_local_write`: `check_mutable_name` (assign.tach), every assignment to a local or a part of one, before the mutability check. `closure_call`: `synth_call` after `synth_expr(callee)`. `fn_bound_satisfied` and `assoc_constraints_hold`: `satisfies` and also `check_bounds` (with a generic error, "the type 'T' does not satisfy the bound of 'F' of 'f'"; refine it); `bound_trait` returns -1 for a `TyFn` (so `collect_impls`, `require_in_bounds` pass it). `infer_from`: 3 passes; `is_deferred_arg` args are skipped in passes 0–1 and given to `infer_closure_arg` in pass 2; then `infer_from_assoc` for each parameter. `unify`: a projection node binds nothing (returns true). `resolve_type_name`: `is_projection_node` → `resolve_projection_node`. `ensure_checked(f)`: `check_direct_call`, `synth_method`, and a function as a value (`synth_name`, `synth_path`). Lazy defaults: `check_program` skips `FN_LAZY` items, `finish_program` drops those still `FN_LAZY` (so `ensure_checked` clears the flag and checks the body). `finish_program` appends `CLOSURE_FNS` after the instances (note: query mode's `check_unchecked` truncates `INST_QUEUE` afterwards; closures made there need the same).
- **Back ends.** `Closure => lower_expr(NODES[n].y)` (middle/lower/expr.tach) and `gen_expr(NODES[n].y)` (gen0) are in. Verified: `lower_aggregate` and gen0's `gen_aggregate` take the struct from `StructLit.ty` (`TYPES[ty].a`) and the field from `FieldInit.x`, never by name.
- **std.** `compiler/std/iter.tach` is appended by embed.sh. It has the full `Iterator` trait of §2 with real bodies, all `#[inline]`: `map`/`filter`/`enumerate`/`zip`/`take` build the adapter structs, `fold`/`for_each` call `f` (need T1), and `count`/`sum`/`min`/`max`/`collect` loop over `next()` directly (not over `fold`), so T2's `Counter` tests need no closures; T3 may move them onto `fold`. The adapters are declared as plain structs, `Map<I, F> { it, f }`, `Filter<I, F> { it, f }`, `Enumerate<I> { it, k }`, `Zip<I, J> { a, b }`, `Take<I> { it, n }`, without impls (T3's). `Iterator` is in the prelude.
- **Deviation: the std trigger.** std is loaded on a `..`/`..=` token only when it is a range used as a value (`modules::range_as_value`, a token heuristic: not a `for` head, a slicing or a pattern), the fallback of §6 Q9. Loading std on every `..` changed the assembly of every program with a `for` loop and no prelude name (std's non-generic functions are emitted), which `same-output` against 0.13 must not show.
- **Tests.** tests/run/err_014_closure_stub, err_014_fn_bound_stub, err_014_assoc_stub assert the stubs' errors: the owning task replaces its case. tests/query/syntax014 (a transcript) shows that query takes `|x|` closures, constraints and projections; update it with `tests/query/run.sh -u` when the error count changes. fmt still spaces bars as `| x |` (T5), so tests/run cases avoid `|x|` closures until then.
- **Guide.** compiler/guide/errors.md and core.md show the unimplemented message for closures; `move` is listed as a keyword (syntax.md, grammar.md); grammar.md has an "Additions of 0.14" skeleton.
