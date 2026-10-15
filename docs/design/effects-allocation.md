# tachyon 0.16 design: effects and explicit allocation, split for parallel work

Read from `/Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15` (release-0.15). Sources: `target/tachyonc query`, `guide memory|unsafe|types|tools`, docs/grammar.md, docs/roadmap.md (0.16–0.18), docs/optimizer.md, docs/agents.md §5–6, and both design docs with their notes.

## 1. Current state

- **std's allocation.** `compiler/std/std.tach` declares `malloc/realloc/free/write/read/exit` in one `extern "C"` block. `Vec<T> { ptr, len, cap }` grows with `realloc` (`Vec::reserve`, which uses a `while` loop). `Buf { bytes: Vec<u8> }`. `HashMap<K: Hash + Eq, V>` holds 3 raw arrays. All of these are handles: a copy shares the memory. `free` is a **safe** method. Fields are public: tachyon has no field privacy, `pub` on a field means nothing, and std's header says its safety depends on the fields being changed only by its own methods. `std::panic` is an `unsafe fn` that calls `write` and then `exit(101)`. The 0.15 `Fmt` writes to a static 4 KB buffer (fd targets) or to a `*Buf`.
- **Known UB in safe code ("the one gap", guide memory/unsafe).** Using a view (`as_slice`, `get_mut`) after the memory moves or is freed. The same applies, though the guide never says so, to freeing through a copied handle (double free). The one existing detector is `--check-unsafe`: it checks raw-pointer accesses in unsafe code against the heap blocks and remembers only the last 4096 freed blocks, so a use after free is caught only sometimes.
- **Compiler source.** It barely uses std containers: 41 refs to `Vec`. Its tables are statics grown with `base::grow`/`realloc`, and there are 198 calls of `base::free`. Nothing allocates in arenas.
- **Checker.** Generics are checked per instance (C++ style), so effects can only be computed on instances. `check_program` runs: collect phases, item bodies, `INST_QUEUE` (instances), `check_unchecked` (query mode), `exit_if_errors`, then `finish_program`, which appends instances and then `CLOSURE_FNS`. After checking, calls are `Call` nodes with `x = f+1`. A call through a fn value has `x = 0`. Closures are ordinary `FNS` entries (`FN_CLOSURE`). `Res::Static` resolves statics, and `Static.d` marks them `mut`.
- **Function attributes.** `parse_attributed_item`/`parse_fn_attribute` (parser/items.tach) handle `inline`, `inline(never)` and `cold` as `FN_*` bits, which reach `FnInfo.attrs`. Attributes inside extern blocks are parsed in parser/foreign.tach (`link_name` only). Generic parameters are `TyName` nodes with bounds in `h` (`parse_generic_params`), and `parse_bound` recognizes `Fn`/`FnMut` by name. **Default type parameters do not exist.**
- **Optimizer.** middle/ipo.tach infers `READNONE`, `READONLY`, `NORETURN`, `WILLRETURN` and `NOPANIC` over IR SCCs. `WILLRETURN` is lost on *any* CFG cycle. C functions are unknown, except a hard-coded `PURE_LIBM` list. Value numbering of calls is "left for the e-graph" and was never done. `heap_to_stack` matches the C symbol `malloc`.
- **Tools.** The query cache (tools/query/cache.tach) stores the front end's tables, so a new per-definition fact can be cached with the defs. Costs on the compiler: `check` takes 79 ms uncached (about 45 ms in the checker) and about 7 ms warm. Self-compile takes 1.9 s at -O2.

## 2. Semantics and syntax (decided)

### 2.1 Effects

Every checked function (item, generic instance, closure) has an inferred **effect set**:

| effect | source (local) | transitive |
|---|---|---|
| `alloc(X, …)` | a call of a method of `impl Allocator for X`; `alloc(extern)` for C allocation functions and unknown C | yes |
| `io` | a call of an extern classified io (`write`, `read`, stdio, files) | yes |
| `global` | reading or writing a `static mut` (or a C static), taking its address | yes |
| `panic` | a checked index/slice, `as E`, a panic primitive | yes |
| `diverge` | `while`, `loop`, a next-based `for`, recursion (an SCC cycle) | yes |
| `unsafe` | the body has unsafe operations, or is an `unsafe fn` | **no**: a safe function encapsulates its unsafety |

- **Sound but syntactic.** A counted `for` (range, slice, array, Vec, std's counted iterators) terminates. Indexes made by `for` desugaring, and `s[i]` in `for i in 0..s.len` with `s` an immutable slice binding, are flagged in-bounds and so cause no `panic`. Effects never depend on the optimization level.
- **Panic or stop?** Running out of memory, or misusing an allocator, is part of `alloc(X)` ("may stop the program"). It is not `panic`, so `#[no_panic]` code may allocate.
- **Encapsulation rule.** At a call site, a method of `impl Allocator for X` has exactly the effect `{alloc(X)}`. Its own refills from a parent, statics, internal panics and loops are the allocator's business: `Arena` shows `alloc(Arena)`, not `alloc(Gpa)`. The methods themselves are checked against the trait's bound, which allows everything except `io`.
- **What `pure` means.** `#[pure]` means: no `alloc`, `io` or `global`; `panic`, `diverge` and `unsafe` are allowed (Koka's `pure`, D's weak purity). It may write through its pointer parameters. `#[effects()]` is total: the empty set.
- **Closed-world indirect calls.** tachyon compiles whole programs. A call through a plain `fn(A) -> R` value therefore has an edge to every function of that type whose address is taken in safe code (coerced closures included). A call through an `extern "C" fn` value, or of an undeclared extern, is unknown: `alloc(extern) io global panic diverge`, plus the effects of every address-taken `extern "C" fn` defined in tachyon (callbacks C may call).
- **Display order.** `alloc(Gpa, Arena) io global panic diverge unsafe`. The empty set displays as `none`.

### 2.2 Declarations and bounds

```ebnf
attribute += "effects" "(" [ effect { "," effect } [","] ] ")"   (* fn, trait fn, impl fn, extern fn *)
           | "pure" | "no_alloc" | "no_io" | "no_panic"
           | "sealed" | "scoped"                                 (* structs *)
effect     = "alloc" [ "(" alloc_src { "," alloc_src } ")" ] | "io" | "global" | "panic" | "diverge" | "unsafe"
alloc_src  = type | "extern"                                     (* a type parameter, Self, Gpa, Arena, … *)
bound     += "effects" "(" [ effect { "," effect } ] ")"         (* F: Fn(i64) -> i64 + effects(panic) *)
tparam     = ident [ ":" bound { "+" bound } ] [ "=" type ]      (* defaults: structs and enums, trailing *)
```

- **A declaration is an upper bound, checked** against the inferred set. `alloc` alone means any allocator. Several attributes intersect. Callers always see the *inferred* set, which is more precise.
- **On an extern, a declaration is trusted**, like its C signature: a wrong one is a broken unsafe contract. An extern with no declaration gets the builtin table: libm functions are none; `mem*`/`str*` are none; `malloc`/`calloc`/`realloc`/`free`/`strdup` are `alloc(extern)`; stdio and POSIX I/O are `io`; `exit`/`abort` are `io diverge`. Anything else is unknown. This table replaces middle's `PURE_LIBM`.
- **Trait method declarations** (`trait Hash { #[pure] fn hash(self: *Self) -> u64; }`) bind every impl. They are checked at the impl, derived impls included. std marks `Eq::eq`, `Ord::cmp` and `Hash::hash` `#[pure]`.
- **Generics.** Effects are inferred per instance, and a declaration on a template is checked per instance (with an "in instantiation of" note). `F: … + effects(S)` is checked where `F` is bound, so the error is at the call, not inside the template.
- **std's panic.** `std::panic` calls extern aliases, `#[link_name = "write"] #[effects(panic)] fn panic_write(...)` and the same for `exit`, so its effect set is `panic`.

### 2.3 Allocation: the interface, containers, "no allocator in scope"

**Representation (decided): a trait, statically dispatched, carried as a defaulted type parameter.**

- `Vec<T, A: Allocator = Gpa>` stores `alloc: A`.
- `Gpa` is zero-sized, so `Vec<i64>` stays 24 bytes. After inlining, `push` is today's `realloc` call, and `heap_to_stack` still sees `malloc`.
- `Arena` is an 8-byte handle (`Vec<T, Arena>` is 32 bytes) with an inlined bump fast path.
- Effects name allocator **types**, which needs no flow analysis.

Alternatives considered:

1. **A Zig-style stored fat handle `{ctx, vtable}`.** It adds 16 bytes per container and an indirect call on every grow and free (devirtualized only when constant-propagated), loses `heap_to_stack`, and effects could not name the allocator without points-to analysis.
2. **Zig's unmanaged form (`v.push(a, x)`).** Maximally explicit, but pushing with a different allocator is UB unless a runtime id check is added, and every existing call breaks.
3. **An integer handle into a global table.** It makes everything `global`.
4. **An implicit context allocator (Odin/Jai).** Hidden: the opposite of transparent.

The cost of the decided form is "allocator infection" of APIs. It is contained by the default (`Vec<i64>` keeps meaning what it meant), by slices for read-only parameters, and by an exact help on the mismatch.

**Default type parameters.**

- In a *type*, missing trailing arguments take their defaults: `Vec<i64>` is `Vec<i64, Gpa>`, and `Buf` is `Buf<Gpa>`.
- In an *expression* (`Vec::<i64>::new_in(a)`, `Vec::new()`), an omitted argument is inferred, and its default is the fallback when nothing binds it.
- Display and mangling leave out trailing arguments equal to their defaults. Symbols and messages therefore stay byte-identical.
- In an impl header the arguments must be written in full (`impl<T, A: Allocator> Tr for Vec<T, A>`). The error says so, and `fix` writes it.

**`Vec::new()` keeps working** and means the global `Gpa`: `new()` calls `std::global_of::<A>()`, which requires `A: GlobalAllocator`. An instance with `A = Arena` fails with the targeted help `try: Vec::new_in(a)`. **Migration** is almost empty: `tachyonc fix --only alloc016` rewrites impl headers on std containers and direct field use (`v.len` becomes `v.len()`; the others become errors with help). All the field uses found are inside std.

**"No allocator in scope means no allocation", precisely:**

1. No language construct allocates: closures, f-strings, `?`, iterators, arrays, literals, `defer`, `match`.
2. The only allocation primitives are `Allocator` methods and C allocation functions, and every one of them shows up as `alloc(X)` in the effects of every function that can reach it.
3. The only allocator obtainable from nothing is a `GlobalAllocator`; std has one, `Gpa`. It is ambient (`Vec::new`, `Buf::new`, `format`, `collect`), and its use is always visible as `alloc(Gpa)`.
4. Hence a theorem the tools state. If a function's effects have `alloc(Arena)` but neither `alloc(Gpa)` nor `global`, it allocates only from arenas it was given (parameters or captures): creating an arena is `alloc(Gpa)`, a static is `global`, and `#[sealed]` forbids forging a handle.
5. `#[no_alloc]` and `#[effects(alloc(Arena))]` turn this into a checked promise.

The strict Zig reading (no ambient `Gpa`) is question U1.

### 2.4 Arenas: what 0.16 guarantees, what waits for 0.17

- **`Arena`** is a handle, whose state lives in its first chunk (from `Gpa`). Its safe operations never free the state. `reset` (everything at once, chunks kept) and `free_all` invalidate allocations, so they are `unsafe fn` in 0.16 (U3).
- **The safe free-all form is a scope.** `arena_scope(|s: ScopedArena| …)` makes a fresh arena and frees it at the end. `a.scope(|s| …)` rewinds the parent `a` at the end. While the scope runs, the parent is locked (its limit is set to 0, so the bump fast path costs nothing extra), and allocating from it panics: "the arena is lent to a scope".
- **The `#[scoped]` type rules** apply to `ScopedArena`, which is `#[sealed]` so only std makes one. Checked with a memoized "type holds a scoped type", like 0.14's closure-escape check:
  - (S2) a closure taking a scoped parameter must not return a type that holds the scoped type;
  - (S3) it must not capture a variable whose type holds one;
  - statics and consts cannot hold one.
  - Together these mean no arena handle, and no container on it, outlives its scope.
- **Discharge.** The effects of `arena_scope` / `Arena::scope` / `ScopedArena::scope` are the closure's effects minus `alloc(ScopedArena)`, plus the parent's: `alloc(Gpa)`, `alloc(Arena)` or `alloc(ScopedArena)` respectively. Because of (S3), every `alloc(ScopedArena)` in the closure is its own arena, so removing it is exact.
- **`#[sealed]`**: fields not marked `pub` are invisible outside the declaring module, and so are struct literals. It applies to `Vec`, `Buf`, `HashMap`, `Arena`, `ScopedArena` and `FixedBuf`, and closes the forgery hole that std's own header admits.
- **Waits for 0.17**, documented as the remaining gap and trapped by `--check-alloc`:
  - views (`[T]`, `*T`) into freed or reset memory, including a slice returned out of a scope;
  - a handle copy freed twice (closed by moves);
  - per-value destruction;
  - value-level allocator naming (U2).
- **Not guaranteed at all:** slices of dead stack arrays (`FixedBuf` over a local).

### 2.5 `--check-alloc`: the checking general-purpose allocator

`--check-alloc` is a compile flag, like `--check-unsafe` and combinable with it; it is not an opt level, so output stays identical across -O0/1/2. The compiler loads a different `Gpa` implementation into std, and `std::CHECK_ALLOC` is set.

- **Each block gets its own pages**, at the cursor of one large `PROT_NONE` reservation (`mmap`, `MAP_NORESERVE`), switched to read-write.
- **Free** checks that the address is a live block start, that the allocator is the same one, and that the size matches. It then sets the pages to `PROT_NONE`, gives back the physical memory (`madvise`), and **never reuses the addresses**.
- **Every `resize` moves the block.** This catches the "writes into a reallocated array" bugs (agents.md §6).
- **A later access to a freed block faults.** A SIGSEGV/SIGBUS handler looks up `si_addr` in the page map and reports `use after free: block #N (48 bytes), allocated at main.tach:14:9, freed at main.tach:20:5`, then exits with 101. A fault outside the region re-raises. This makes the trap deterministic: a fault is either reported, or the program stops with a defined message.
- **Errors also caught:** double free, invalid free, wrong-size free.
- **Leaks** are listed at exit (`atexit`). The exit status is unchanged; tests assert with `gpa().check_leaks()`.
- **Arenas, `ScopedArena` and `FixedBuf`** route each allocation to the debug pages in this mode, keeping their capacity accounting so that exhaustion happens at the same point. `reset` or scope end protects everything they handed out.
- **Allocation sites** come from the effects: in this mode, lowering (middle and gen0) stores a site string before each call from non-std code to a function with `alloc(Gpa|Arena|…)`.
- **Block numbers** are deterministic, and `TACHYON_ALLOC_TRAP=N` raises SIGTRAP at allocation N, for a debugger.
- **Limits.** Each live block costs one page (16 KB on Apple Silicon). Linux's `vm.max_map_count` (65530) can be exhausted. That stops the program with `try: sudo sysctl vm.max_map_count=1048576`, never a silent miss.

### 2.6 Interactions

- `defer` bodies are part of the function's effects.
- Closures are functions, so their effects are exact per instance. Iterator chains are generic, so `v.iter().map(f).sum()` has exactly `f`'s effects. `collect()` is `alloc(Gpa)`, and `collect_in(a)` is `alloc(A)`.
- A function body that failed to check gets ⊤ with an "unknown" flag, which suppresses declared-effect errors in its callers (no cascade). Query mode's `TY_ERROR` instances are the same.
- `main -> Result` and derived impls need nothing special.
- Formatting stays coarse but honest: a `Display` impl shows `io global`, because a `Fmt` may write out its full fd buffer. The two-pass `Buf` change (T2) keeps `println` from showing `alloc`.

### 2.7 std API (compiler/std/alloc.tach, appended by embed.sh)

```
pub trait Allocator {
    // size bytes aligned to align (power of two, 1..=4096), null when out of memory; size 0: aligned, non-null, unreadable
    #[effects(alloc, global, panic, diverge, unsafe)] fn try_alloc(self: *Self, size: i64, align: i64) -> *u8;
    // p (old_size bytes, from this allocator) as new_size bytes, min(old,new) kept, may move; null: p untouched
    #[effects(alloc, global, panic, diverge, unsafe)] unsafe fn try_resize(self: *Self, p: *u8, old_size: i64, new_size: i64, align: i64) -> *u8;
    #[effects(alloc, global, panic, diverge, unsafe)] unsafe fn free(self: *Self, p: *u8, size: i64, align: i64);
    fn alloc(self: *Self, size: i64, align: i64) -> *u8 { … }            // stops: "out of memory", exit 101
    unsafe fn resize(self: *Self, p: *u8, old_size: i64, new_size: i64, align: i64) -> *u8 { … }
}
pub trait GlobalAllocator { fn global() -> Self; }
pub fn global_of<A: GlobalAllocator>() -> A
pub enum AllocError { OutOfMemory }
pub const CHECK_ALLOC: bool                                              // injected: --check-alloc
pub struct Gpa {}                                                        // impl Allocator, GlobalAllocator
pub fn gpa() -> Gpa
impl Gpa { pub fn live_blocks(self: *Gpa) -> i64; pub fn check_leaks(self: *Gpa) -> bool; }  // -1 / true unless --check-alloc
#[sealed] pub struct Arena { s: *ArenaState }                            // handle; impl Allocator
impl Arena {
    pub fn new() -> Arena;  pub fn with_capacity(bytes: i64) -> Arena;  pub fn none() -> Arena   // none: constant, for statics
    pub fn used(self: *Arena) -> i64;  pub fn chunk_bytes(self: *Arena) -> i64
    pub unsafe fn reset(self: *Arena);  pub unsafe fn free_all(self: *Arena)
    pub fn scope<R, F: FnMut(ScopedArena) -> R>(self: *Arena, f: F) -> R
}
#[sealed] #[scoped] pub struct ScopedArena { s: *ArenaState, mark: i64 }  // impl Allocator
impl ScopedArena { pub fn used(self: *ScopedArena) -> i64; pub fn scope<R, F: FnMut(ScopedArena) -> R>(self: *ScopedArena, f: F) -> R }
pub fn arena_scope<R, F: FnMut(ScopedArena) -> R>(f: F) -> R
#[sealed] pub struct FixedBuf { base: *u8, cap: i64 }                     // impl Allocator; the count in mem's first 8 bytes
impl FixedBuf { pub fn new(mem: [u8]) -> FixedBuf; pub fn used(self: *FixedBuf) -> i64; pub unsafe fn reset(self: *FixedBuf) }
#[sealed] pub struct Vec<T, A: Allocator = Gpa> { ptr: *T, len: i64, cap: i64, alloc: A }
impl<T, A: Allocator> Vec<T, A> {   // + every 0.15 method, unchanged
    pub fn new() -> Vec<T, A>   pub fn new_in(a: A) -> Vec<T, A>   pub fn with_capacity_in(cap: i64, a: A) -> Vec<T, A>
    pub fn filled_in(n: i64, x: T, a: A) -> Vec<T, A>   pub fn allocator(self: *Vec<T, A>) -> A   pub fn capacity(self: *Vec<T, A>) -> i64
    pub fn try_reserve(self: *Vec<T, A>, extra: i64) -> Result<(), AllocError>   pub fn try_push(self: *Vec<T, A>, x: T) -> Result<(), AllocError>
    pub fn clone_in<B: Allocator>(self: *Vec<T, A>, b: B) -> Vec<T, B>          // T: Clone
}
#[sealed] pub struct Buf<A: Allocator = Gpa>;  #[sealed] pub struct HashMap<K: Hash + Eq, V, A: Allocator = Gpa>  // + new_in, with_capacity_in
impl<T> [T] { pub fn get(self: [T], i: i64) -> Option<T> }               // no panic
Iterator: fn collect_in<A: Allocator>(self: Self, a: A) -> Vec<Self::Item, A>
pub fn format_in<T: Display, A: Allocator>(x: T, a: A) -> Buf<A>
```

`Allocator`, `Gpa`, `Arena`, `ScopedArena` and `arena_scope` join the prelude, triggering std load the way 0.15's names do.

### 2.8 Diagnostics

Each is one line, then `help:`/`try:` (kind `error[effect]`, explain codes `effect.*`, `alloc.*`):

```
sum.tach:3:1: error[effect] 'total' is #[no_alloc], but it allocates from Gpa: 'v.push(x)' at sum.tach:7:9 grows a Vec<i64>
help: allocate in the caller and pass '*Vec<i64>' with room, or remove #[no_alloc]
try: tachyonc query effects total --why alloc
k.tach:12:5: error[effect] 'Key::hash' writes the static 'SEEN' (global), but 'Hash::hash' is #[pure]
m.tach:9:15: error[effect] the closure for 'F' of 'apply' does io (println at m.tach:9:23); 'F: Fn(i64) -> i64 + effects(panic)' allows panic only
p.tach:4:1: error[effect] 'avg' is #[no_panic], but 's[i]' at p.tach:6:14 may panic
help: iterate ('for x in s'), or 's.get(i)' (an Option)
a.tach:8:17: error[effect] unknown effect 'allocates' (effects: alloc, io, global, panic, diverge, unsafe)   help: did you mean 'alloc'?
a.tach:2:20: error[effect] effects name allocator types: 'arena' is a parameter   try: #[effects(alloc(Arena))]
s.tach:5:9: error[type error] this arena scope's value holds 'ScopedArena' (Vec<i64, ScopedArena>): its memory is gone when the scope ends
help: copy it out: 'v.clone_in(gpa())'
s.tach:7:13: error[type error] an arena scope cannot use 'outer': its type holds another scope's arena   help: take a view first: 'let s = outer.as_slice();'
v.tach:3:22: error[type error] 'Vec::new()' needs a global allocator; 'Arena' is not one   try: Vec::new_in(a)
f.tach:9:9: error[type error] expected '*Vec<i64>', found '*Vec<i64, Arena>'
help: take '[i64]' and pass 'v.as_slice()', or 'fn sum<A: Allocator>(v: *Vec<i64, A>)'
```

## 3. Representation, inference, cost

- **AST** (appended NodeKinds):
  - `EffectSet` (list = `EffectItem`, c = the attribute form);
  - `EffectItem` (a = effect symbol, list = allocator type nodes, `extern` as a sentinel).
  - Fn declarations reach their `EffectSet` through `FnInfo.effect_decl`; Phase 0 picks a free Fn field or a side table, verified with `query refs Node.*`.
  - Bound lists may contain an `EffectSet`.
  - A parameter `TyName` gets its default in a free field (Phase 0 verifies `b`).
  - Struct flags `STRUCT_SEALED = 16` and `STRUCT_SCOPED = 32` go in `Struct.c`, next to the `REPR_*` bits 1–8.
  - `NODE_IN_BOUNDS` marks in-bounds indexes.
- **Tables** (front/effects/mod.tach):
  - `pub struct Effects { bits: i64, allocs: i64 }`, where `bits` holds `EFF_IO`, `GLOBAL`, `PANIC`, `DIVERGE`, `UNSAFE`, `ALLOC_EXTERN`, plus the raw, unmasked `diverge`/`panic` kept for the optimizer.
  - `allocs` is a bitmask over `ALLOCATORS`, the interned allocator type ids. Bit 63 is overflow and is treated as "any".
  - `FN_EFFECTS: *Effects` is indexed by FNS id.
- **Inference** (`infer_effects()`, after the instance queue and `check_unchecked`, before `exit_if_errors`). A separate walk, not checker hooks, because speculative `attempt` checking would add false effects.
  1. One walk per checked function body: local bits, direct callee edges, and fn-type edges collected into a CSR edge list. Edges are masked for allocator methods (encapsulation) and for the three scope functions (discharge).
  2. Iterative Tarjan over FNS.
  3. Bottom-up OR: an SCC's set is the union of its members' local sets and its external callees' sets. A cyclic SCC also gets `diverge`. There is no iteration: within an SCC every member reaches every other, so all members have the same set.
  4. Declared bounds, trait bounds and deferred `effects(...)` bound obligations (recorded by `check_bounds`) are checked.
- **Why-chains** are rebuilt on demand by re-walking the reported function and following a callee that has the bit, down to a local source. Nothing extra is stored.
- **Cost.** O(nodes + edges) bit operations. Budget: under 3 ms on the compiler (about 1.5M nodes), under 4% of `check` and about 0.15% of -O2. Templates and unused lazy std functions cost nothing.
- **Cache.** The query cache stores one effects text per Def, so warm `def`/`show` stay at about 7 ms.
- **Optimizer feed** (`ipo::call_attrs`):
  - `¬raw_diverge` gives `WILLRETURN`. This is new information: the IR loses `WILLRETURN` on any loop, while the front end knows counted `for` loops terminate.
  - `¬raw_panic` gives `NOPANIC`.
  - An extern declared without `alloc`/`io`/`global` and with only non-pointer parameters is `READNONE`.
- **Lowering:** none. Default type parameters are resolved at type resolution. `--check-alloc` swaps std's `Gpa` source and adds the site stores.

## 4. Work split

**Phase 0, serial (the lead, about 2 days).** The interface commit: everything parses and checks, the suite passes, and the compiled programs' output is unchanged.

1. **Parser and AST**:
   - the attributes of §2.2 on fns, trait fns, impl fns and extern fns (parser/items.tach, parser/foreign.tach), `effects(...)` in `parse_bound`, `= type` defaults in `parse_generic_params`, `#[sealed]`/`#[scoped]`;
   - the NodeKinds and flags;
   - `clone_node` support for them.
2. **Default type parameters, complete**: resolution fill-in, inference fallback (`infer_from`, the template branch of `synth_path_call`), display and mangling omission (`types::buf_type`, `generics::mangle_type`), and the impl-header error. It is on everyone's critical path.
3. **std**:
   - alloc.tach with `Allocator`, `GlobalAllocator`, `global_of` and a real fast `Gpa`;
   - `Arena`, `ScopedArena` and `FixedBuf` declared with `panic("… (0.16 T2)")` bodies;
   - `Vec`, `Buf` and `HashMap` moved to `A` (all growth and frees through `self.alloc`, `new`/`new_in`);
   - `CHECK_ALLOC` injected by `load_std_if_named`;
   - a hook to choose std's `Gpa` source.
   - Verify zero-sized fields in layout, SROA, gen0 and `repr(C)`.
4. **front/effects/** with stubs:
   - mod.tach (`Effects`, constants, `FN_EFFECTS`, real `effects_text`, `union`, `subset`);
   - infer.tach (`infer_effects()` marks every function ⊤);
   - check.tach (`check_effects()`, `note_effect_bound(bound, ty, pos)`);
   - why.tach (`explain_effect(f, bit, alloc, out)`);
   - builtin.tach (`known_c_effects(sym)`).
   - Declarations are accepted silently until T1 checks them.
5. **Hooks** (one line each):
   - `check_program` calls `infer_effects(); check_effects();`;
   - `check_bounds` calls `note_effect_bound`;
   - closure creation (front/closures/mod.tach) calls `scoped::check_closure(c)`;
   - `synth_field`/`check_struct_fields` call `sealed::check_field(n, s)` / `check_literal(n, s)`;
   - `ipo::call_attrs` calls `front_attrs(f)` (returns 0);
   - `middle/lower/calls::lower_call` and `gen0/gen/call::gen_call` call `checkalloc::site_before_call(n)` (a no-op).
6. **Driver and tools**: `--check-alloc` (error "not implemented yet"), `--print-effects`, and a minimal `query effects NAME`.
7. **Tests and docs**: tests/run/err_016_check_alloc_stub; tests/query/syntax016.q; a "0.16" skeleton in grammar.md; docs/design/effects-allocation.md with this text.
8. **Acceptance**:
   - `same-output` against release-0.15: program output identical, assembly differing only in std's Vec, Buf and HashMap bodies (listed in the notes);
   - `bench/` at -O2 within noise (sort, wordcount, json, binarytrees);
   - -O0 is allowed one extra call layer.

| task | owns | consumes | provides |
|---|---|---|---|
| **T1 Effects** | front/effects/*, middle/effects_verify.tach, tests/run/eff_*, tests/query/effects016.q | P0 | inference, checks, chains, `--verify-effects` |
| **T2 Allocators** | compiler/std/{alloc,std,fmt,iter,io}.tach allocator parts, front/check/sealed.tach, front/closures/scoped.tach, the consteval constructor lines, tests/run/alloc_* | P0 | Arena, Scope, FixedBuf, container APIs, sealed/scoped rules, a non-allocating `Fmt` |
| **T3 check-alloc** | compiler/std/alloc_check.tach (the second `Gpa` source), middle/checkalloc.tach, the gen0 hook body, tests/run/checkalloc_* | P0; T2's arenas (staged) | the checking GPA |
| **T4 Optimizer** | middle/* except the files T1 and T3 own, docs/optimizer.md, bench/{purecall,arena_trees}.* | P0; T1's `FN_EFFECTS` | call numbering and hoisting, attribute seeds, arena fast path |
| **T5 Tools and guide** | tools/* except rewrite, compiler/guide/*.md, guide/, docs/{grammar,query,refactor,fmt}.md, tests/{query,refactor,fmt,guide} | P0 shapes, T1's `explain_effect` | `query effects`, def/show/context, cache, fmt, `fix --only alloc016`, guide topics `effects` and `allocators`, explain |
| **T6 Self-host** | wave 1: back/, base/, gen0/ (minus the hook), front/{lexer,cimport,cpp,derive,convert,assoc,patterns,modules}, tools/rewrite; wave 2 (after the merge): the rest | 0.15 only | compiler/src on `?`, derive, f-strings, widening; front and tools on closures and iterators; the 0.18 arena prototype |

**T1 items.**
1. The local walk, including `NODE_IN_BOUNDS` on the `for` desugars and the `0..s.len` pattern.
2. Closed-world fn-type edges and extern defaults.
3. SCC union, encapsulation and discharge masks.
4. Declared, trait and Fn-bound checks; ⊤ for failed bodies.
5. The chains, and every diagnostic of §2.8 except the type errors.
6. `--verify-effects`: after lowering, each IR function's calls of io or allocation externs and its stores to statics must appear in its front-end set; anything else is an internal error.

Acceptance:
- a case per effect source and per declaration form;
- generic instances with different `A`;
- closures and fn pointers;
- recursion;
- callbacks;
- `--verify-effects` clean on tests/run, examples, bench, compiler/src and 2000 fuzz programs;
- under 3 ms on the self-compile (`--time-passes`).

**T2 items.**
1. `Arena` (dedicated chunks for large requests, in-place growth of the last block, the lock while lent), `ScopedArena`, `arena_scope`, `FixedBuf`, `AllocError`, `try_*`, the `*_in` constructors, `clone_in`, `collect_in`, `format_in`, `[T]::get`.
2. `Fmt` without an allocating path: a `Buf` target writes into spare capacity and retries with an exact reserve on overflow, so `Display` runs twice only on overflow. fmtloop must stay within 1.05.
3. Size arithmetic checked: over 2^62 is out of memory.
4. std's hot loops made counted, so that `push`, `sort` and `reserve` show no `diverge`; std's externs declared (§2.2).
5. `#[sealed]` and `#[scoped]` (S2, S3, statics).
6. Constant constructors: a call whose body is one struct literal of constant arguments (`Vec::new_in(Arena::none())`) is a constant expression, so statics can hold containers.

Acceptance:
- every allocator under every container;
- each scope, sealed and global-new error;
- a static `Vec<Node, Arena>`;
- bench parity;
- `println`'s effects contain no `alloc`.

**T3 items.**
1. The page allocator, the page map and the signal handler, generated per target (the `si_addr` offset; the `--check-unsafe` runtime is the model).
2. Double free, invalid free and size checks; resize always moves.
3. Leak report; `TACHYON_ALLOC_TRAP`.
4. Arena, Scope and FixedBuf routing.
5. The site stores, using T1's effects with a stub predicate until T1 merges.

Acceptance:
- each misuse traps with the exact message at -O0/1/2 on aarch64-macos and both Linux containers;
- a Vec used after `free` through a copied handle, a slice after `push`, an arena container after scope end;
- the map-count failure message.

**T4 items.**
1. `front_attrs` seeds; the libm table moved to `known_c_effects`.
2. The e-graph numbers calls that are `READNONE`, and `READONLY` calls with no write between them in a block.
3. LICM hoists `READNONE`+`WILLRETURN`+`NOPANIC` calls, and `READNONE` calls in loops that run at least once.
4. The arena bump path inlines without a call; `heap_to_stack` keeps working through `Gpa`.

Acceptance:
- CHECK tests opt_effects_{cse,licm,arena};
- bench/purecall within 1.05 of its hand-hoisted twin;
- binarytrees on an arena faster than on `Gpa`;
- no regression in bench or compile time.

**T5 items.**
1. `query effects NAME|MODULE [--why EFFECT] [--has EFFECT]`; an effects column in `def`, `show` and `context`; cached.
2. fmt for attributes, bounds and defaults.
3. `fix --only alloc016`.
4. refactor keeps attributes (signature, move, inline).
5. The two guide topics; core.md rows (`#[pure]`, `Vec::new_in`, `arena_scope`, `--check-alloc`); explain entries; grammar.md "Additions of 0.16". The core guide stays within its budget.

**T6 items.** Tool-driven rewrites per 0.15's T6 method, per module:
- f-strings for `buf_str` chains;
- derive;
- `?` where Option chains exist;
- widening casts made redundant, via typed `rewrite` with `--where`;
- `same-output` against the Phase 0 compiler each time, self-compile within +2%.

T6 also builds an **unmerged prototype** with the 0.16 compiler: middle/ir's `INSTS`/`BLOCKS`/`SLOTS` in a per-function `Arena`, reset after emission. It measures compile time and reports what 0.18 needs. This design already provides: reset keeping chunks, dedicated large chunks, in-place growth, `with_capacity_in`/`filled_in`, constant constructors for statics, `#[effects(alloc(Arena))]` per phase, `query effects --has alloc(Gpa)` to find stragglers, and `--check-alloc` for stale pointers after reset.

**Merging.**
1. Phase 0.
2. T2 (it changes what programs see).
3. T1.
4. T3.
5. T4.
6. T5 throughout, with its final pass last.
7. T6 wave 1 at any time; wave 2 after all of the above.

Then `bootstrap/gate.sh --quick`, plus a `--check-alloc` pass of tests/run. `stdsrc.tach` conflicts are resolved by rerunning embed.sh. Each task appends "Tn notes" to docs/design/effects-allocation.md. The compiler's source uses effect annotations only from 0.17 (the bootstrap rule).

## 5. Risks

- **Default type parameters touch the core of generics.** `Vec<i64>` and `Vec<i64, Gpa>` must be one instance, so canonicalize at resolution. Mangling omission is injective because each default is fixed per template.
- **Zero-sized fields** in SROA, gen0, ABI and `repr(C)`.
- **The extra allocator layer** under -O1 inlining budgets: std's `Gpa` methods are `#[inline]`.
- **Effect noise** (`diverge` from `while`, `panic` from indexing, `io global` on `Display`) may make the sets look useless. The mitigations are std's counted loops, in-bounds flags and the `get` accessors. Effect-polymorphic sinks are a later fix.
- **The closed-world fn-type edges are only sound if the address-taken set is complete**: generic instances, coerced closures, defaults.
- **`--check-alloc`**: the per-target `siginfo` layout, the VMA limit, memory per page, misreporting a stack overflow (handled by re-raising), and interaction with `--check-unsafe`'s malloc wrappers (route both through one runtime).
- **(S3)** may be too strict for real code: no reading a sibling scope's containers, except through views. 0.17 relaxes it.
- **The 0.16 static guarantee excludes views.** The documentation must not oversell it.
- **Two-pass formatting** for `Buf` targets duplicates the side effects of a `Display` impl that prints. T1 can warn when a `Display` with `io` reaches `push_fmt`.
- **Merge conflicts** in check/mod.tach, traits.tach and closures. Phase 0's one-line hooks contain them.

## 6. Open questions, with recommendations

**For the user (U1–U3):**

- **U1. An ambient `Gpa`?** Recommendation: yes. `Vec::new()` keeps meaning `Gpa`, its use is always visible as `alloc(Gpa)`, and the theorem of §2.3 gives "no allocator in scope means no allocation" for every other allocator. The strict Zig alternative obtains `Gpa` only as `fn main(gpa: Gpa)` and passes it down: every `Vec::new()` becomes `Vec::new_in(gpa)`, about a thousand sites across tests, guide and eval tasks, through `fix`.
- **U2. Name allocators by type in 0.16 (`alloc(Arena)`), and defer value naming (`alloc(arena)`, meaning this parameter's arena) to 0.17?** Recommendation: yes. Value naming needs allocator provenance, which 0.17's owned values make cheap. Inferring it now would mean interprocedural points-to analysis. The combination of `alloc(Arena)`, no `alloc(Gpa)` and no `global` already says "only from arenas it was given".
- **U3. What can free memory in safe code in 0.16?** Recommendation: `Vec`/`Buf`/`HashMap::free` stay safe (as since 0.5; moves close the gap in 0.17). The new invalidating operations `Arena::reset`, `Arena::free_all` and `FixedBuf::reset` are `unsafe fn`, and the scope form is the safe way to free an arena. The alternative, making container `free` unsafe too, honours the no-UB rule strictly but turns every `defer v.free()` into `defer unsafe { … }` for a single release.

**Decided here** (not flagged; each can be revisited):

- `#[pure]` allows `panic` and `diverge`; `#[effects()]` is total.
- Running out of memory is `alloc`, not `panic`.
- `diverge` is sound and syntactic.
- Extern declarations are trusted, with a builtin libc table.
- Indirect calls use closed-world edges. Fn types with effect annotations wait for 0.17.
- `#[sealed]` is available to every module.
- std's `Eq`/`Ord`/`Hash` methods are `#[pure]`.
- Leaks print but do not fail the run; `check_leaks()` is there for tests.
- Default type parameters are for structs and enums only.
- Effects are inferred in a separate front-end pass, not in the IR: tools need them without lowering, and why-chains need source positions.

### Critical Files for Implementation
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/check/mod.tach (`check_program`, `finish_program`: where inference runs) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/types.tach (`FnInfo`, `buf_type`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/parser/items.tach (`parse_attributed_item`, `parse_fn_attribute`, `parse_generic_params`), /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/parser/types.tach (`parse_bound`), /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/parser/foreign.tach
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/generics/mod.tach (`mangle_type`, `struct_instance`) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/generics/instantiate.tach (`infer_from`), with /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/traits.tach (`check_bounds`) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/closures/escape.tach (the model for the scoped check)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/std/std.tach with /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/std/embed.sh, /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/std/fmt.tach, /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/front/modules/mod.tach (`load_std_if_named`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/ipo.tach (`call_attrs`, `compute_attrs`, `heap_to_stack`) and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/unsafecheck.tach (the model for the `--check-alloc` runtime), with /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/middle/lower/calls.tach and /Users/magniff/workspace/tachyon/.claude/worktrees/integ-0.15/compiler/src/gen0/gen/call.tach (the site hooks)

## Decisions taken for now (to confirm with the user)

U1–U3 were taken as recommended on 2026-10-15 while the user was away, and
built so that changing them later is a `tachyonc fix` migration:
- U1: an ambient `Gpa` (`Vec::new()` keeps meaning `Gpa`, always visible as
  `alloc(Gpa)`); the strict Zig form (`fn main(gpa: Gpa)`, every `new` through
  `new_in`) stays possible as `fix --only strict-alloc`.
- U2: effects name allocator types in 0.16; value naming waits for 0.17.
- U3: container `free` stays safe until 0.17's moves close the copied-handle
  gap (documented, trapped by `--check-alloc`); `Arena::reset`, `free_all`
  and `FixedBuf::reset` are `unsafe fn`.


## Phase 0 notes (the interface commit, for T1–T6)

What Phase 0 made, where it differs from or adds to §3–§4:

- **AST.** `NodeKind::EffectSet` and `EffectItem` are appended. EffectSet: list = EffectItem nodes, c = the form, `EFFECTS_DECL` 1 (`#[effects(..)]`), `EFFECTS_PURE` 2, `EFFECTS_NO_ALLOC` 3, `EFFECTS_NO_IO` 4, `EFFECTS_NO_PANIC` 5, `EFFECTS_BOUND` 6 (in a bounds list); **b = the next declaration of the same function** (several attributes chain). EffectItem: a = the effect's name as a symbol (any identifier, and `unsafe`: the parser accepts every name, T1 checks them), list = the allocator type nodes, **b = 1 when `extern` is a source** (a flag, not a node in the list). A function's declarations: **Fn/ExternFn `z`** = the first EffectSet, with `FN_EFFECT_DECL = 1 << 34` in its `p` (Node.z was used by the code generators on loop nodes only, verified with `query refs Node.z`); `clone_node` keeps `z` for Fn nodes (instances and trait defaults copied into impls keep the declarations; the EffectSet nodes are shared, not copied). `FnInfo.effect_decl` = that node (0: none), set by `add_fn`. `NODE_IN_BOUNDS = 1 << 35`. `STRUCT_SEALED = 16`, `STRUCT_SCOPED = 32` in Struct.c and so in StructInfo.repr (every reader masks). A type parameter's default is **TyName.b** (free: no reader of TyName used b; `clone_node` shares it).
- **Parser.** `parse_effect_attribute(name, pos) -> bool` and `take_effect_decls(f)` / `has_effect_decls()` (parser/items.tach); `parse_fn_attribute` returns `FN_EFFECT_DECL` for the five effect attributes; items, impl functions, trait functions and the declarations of extern blocks take them (`parse_link_name` now loops over `link_name` and effect attributes; on an extern static they are an error). `parse_effect_list(n)` (parser/types.tach) parses `(alloc(Gpa, extern), io, ...)`; `parse_bound` makes an EffectSet for `effects(...)` (a name `effects` followed by `(`). `#[sealed]`, `#[scoped]` only before a struct. `parse_generic_params(defaults: bool)`: `= type` is an error unless `defaults` (structs and enums), and a parameter without a default after one with a default is an error. The unknown-attribute messages list the new attributes (err_unknown_attribute's text changed). **`#[effects]` before a top-level `extern "C" fn` definition is not supported** (only declarations inside extern blocks, and `extern "C" fn` definitions inside an extern block).
- **Default type parameters (complete).** generics/mod.tach: `param_default(node, module, k)` (the default of parameter k resolved in the item's module with the parameters before it bound to the k types on top of TSCRATCH), `fill_defaults` (struct_instance/enum_instance complete short argument lists), `shown_targs(node, module, targs, count)` (the trailing arguments equal to their defaults are left out of the instance's name and symbol; with none left, the name is the bare `Buf` and the symbol the template's, no `.G`), `required_targs(tpl)`. `Buf` (all parameters defaulted) resolves without `<>` (resolve_type_name and resolve_named). Inference: `bind_defaults` / `bind_impl_defaults` (instantiate.tach) bind what nothing bound before `require_bound` in `instantiate_call` (the impl's parameters map to the type's, in order), `infer_enum` and `infer_struct_literal`. Symbols of method instances: `instance_symbol` leaves out the impl's trailing arguments equal to the type's defaults (`std.Vec.push.Gl` stays the symbol of `Vec<i64, Gpa>::push`; injective since a template's own parameter count is fixed). Impl header: `impl_args_error` (collect.tach), "an impl block writes every type argument of 'Vec', also those with defaults" with `help: 'impl<T, A: Allocator> Vec<T, A>'`. `impl Buf { ... }` without parameters is an impl for the one instance `Buf<Gpa>` (fmt.tach's `push_fmt` stays so: Fmt targets `*Buf`, T2's).
- **std.** alloc.tach (appended after clone.tach) has §2.7's Allocator (`alloc`, `resize` defaults `#[inline]`, stopping with "out of memory" through `out_of_memory`), GlobalAllocator, `global_of`, AllocError, `Gpa` + `impl GlobalAllocator`, `gpa()`, and Arena (with `ArenaState { base, used, cap, limit, chunks }`, T2 changes it freely), ScopedArena, `arena_scope`, FixedBuf, their Allocator impls: every stub body calls `not_yet()` (one string, so programs carry one dead literal, not twenty). Its arenas banner says "not implemented yet", which `guide::stdapi` (core guide only) skips (the core guide was over its budget with the stubs; T2 renames the banner). **Gpa's implementation is a separate file, compiler/std/gpa.tach** (`impl Allocator for Gpa` on malloc/realloc/free, posix_memalign above 16, size 0 = the alignment as a dangling pointer; `live_blocks` -1, `check_leaks` true). **The Gpa-source hook and CHECK_ALLOC**: embed.sh writes `std_source` (std … clone, alloc) ending with a call of `front/stdalloc.tach::std_alloc_tail(out)`, which appends `std_gpa_source` (gpa.tach, generated too) and `pub const CHECK_ALLOC: bool = false;` (true under `CHECK_ALLOC_MODE`). T3 makes the tail append alloc_check.tach instead when CHECK_ALLOC_MODE (deviation: the hook is at the end of std_source, not in load_std_if_named, so every reader of std's text, the tools included, sees the same source). Vec, Buf, HashMap are `#[sealed]`, take `A: Allocator = Gpa`, store `alloc: A` last, and have `new_in(a)` and `new`; **deviation: `new` is in an impl block of its own, `impl<T, A: Allocator + GlobalAllocator> Vec<T, A>`, calling `A::global()`** (not `global_of::<A>()`, which stays in std): one call layer at -O0, and `Vec::<i64, Arena>::new()` fails on the bound at the call (T2 words the targeted help). Growth calls `self.alloc.try_resize`/`try_alloc` and checks for null itself (`out_of_memory()`), frees `self.alloc.free(p, size, align)`, with sizes and `align_of`: so -O0 has exactly one call layer more than 0.15 (Vec::reserve → Gpa::try_resize → realloc). `with_capacity`, `filled` kept on any A (via `new`). iter.tach's, clone.tach's and fmt.tach's impls for them are generic over A (`Clone` clones into `self.alloc`); `collect`, `format`, `split`, `read_stdin` stay on Gpa. The prelude gains Allocator, Gpa, Arena, ScopedArena, arena_scope, with 0.15's careful trigger (`is_prelude015` covers 18..31). tests/run/index_order's static Vec literals got `alloc: Gpa {}` (T2: constant constructors, then sealed).
- **Zero-sized fields** verified at -O0/1/2 (tests/run/zero_sized_fields: fields, arrays, tuples, enum payloads, by value, methods; `Vec<i64>` 24 bytes, `HashMap` 48): the layout puts align-1 fields last and gives them no bytes. A `#[repr(C)]` struct with a non-repr(C) zero-sized field cannot cross to C (err_zero_sized_c); an empty `#[repr(C)] struct` is accepted and has size 0 (GNU C's), not in the ABI fuzzer.
- **front/effects/** (`pub mod effects` in front): mod.tach (`Effects { bits, allocs }`, `EFF_IO 1, GLOBAL 2, PANIC 4, DIVERGE 8, UNSAFE 16, ALLOC_EXTERN 32`, `EFF_VISIBLE 63`, `EFF_RAW_PANIC 64`, `EFF_RAW_DIVERGE 128`, `EFF_UNKNOWN 256`, `ALLOC_ANY = 1 << 63`, `ALLOCATORS`, `FN_EFFECTS`/`FN_EFFECTS_COUNT`, `PRINT_EFFECTS`, `effects_none`, `effects_top`, `fn_effects(f)`, `allocator_bit(t)`, real `effects_text(out, e)` (Gpa first, then by name, `extern` last; `alloc` alone for any; `none`; ` (unknown)` appended for EFF_UNKNOWN) and `print_effects(out)`); **`union` and `subset` are `effects_union` and `effects_subset`** (`union` is a keyword); infer.tach `infer_effects()` (every function ⊤); check.tach `check_effects()`, `note_effect_bound(bound, ty, pos)`; why.tach `explain_effect(f, bit, alloc, out)`; builtin.tach `known_c_effects(sym) -> Effects` (⊤).
- **Hooks.** `check_program`: `infer_effects(); check_effects();` before `exit_if_errors` (after `report_legacy_imports`). `check_bounds`: an EffectSet bound calls `note_effect_bound(b, t, pos)` and is skipped; `bound_trait` returns -1 for it. Closures: `scoped::check_closure(id)` at the end of `finish_closure` (front/closures/scoped.tach, id = CLOSURES index). `synth_field` calls `check_field(n, s)` after the field is found, `check_struct_fields` calls `check_literal(n, s)` once the instance is known (front/check/sealed.tach). `ipo::call_attrs` ORs `front_attrs(f)` (middle/ipo.tach, returns 0) for direct calls. `lower_call` calls `middle::checkalloc::site_before_call(n)`; **gen0's `gen_call` calls `gen0::gen::checkalloc::site_before_call(n)`, a file of its own** (T3 owns both).
- **Driver and tools.** `--check-alloc` dies with "--check-alloc is not implemented yet (0.16)"; `--print-effects` prints `display: effects` per function of the program (not std's, not templates) after checking, then compiles; `query effects NAME...` (tools/query/effects.tach) prints `PATH<TAB>effects`, a generic function's instances one per line (query mode's error-type instances left out); it reads the program in full (not cached).
- **Tests.** tests/run: err_016_check_alloc_stub (T3 replaces it), default_type_params, err_default_type_params{,_order,_fn}, effect_declarations, err_effect_declarations, alloc_gpa, zero_sized_fields, err_zero_sized_c; tests/query/syntax016 (a transcript; update with `tests/query/run.sh -u` and check text.q out again). Transcripts with std line numbers moved: clash, context, nostd, syntax015, budget (the usage line), tests/refactor/json.t.
- **Guide and docs.** grammar.md "Additions of 0.16" (a skeleton, "to come" marks what the tasks make). The guide topics are T5's; the core guide is 28573 bytes of its 28672 (AllocError, under the arenas' banner, and Gpa's `live_blocks`/`check_leaks`, under a "not implemented yet" banner of gpa.tach, are left out of it until T2/T3).
- **Acceptance.** Suite 758/758 at -O0, -O1, -O2; `gate.sh --quick` passes (chain built by 0.14.0, fixpoint). `same-output` against release-0.15's compiler (built from ed8357c): 1416 of 6036 compilations differ, all accounted for by a per-function comparison on aarch64-macos (scratch script, 1506 compilations of tests/run, examples, bench; string labels normalized): **-O0 and -O1**: only std's `Vec.{new,new_in,with_capacity,reserve,extend_from_slice,free,clone}`, `HashMap.{new,new_in,rehash,free,clone}`, `Buf.{clone,new_in}` instances, the new `Gpa.{try_alloc,try_resize,free,alloc,resize,global}`, `gpa_aligned`, `gpa_resize_slow`, `out_of_memory`, and `std.panic` (now emitted where only out_of_memory calls it), plus the string data (`out of memory`, the stubs' one string); **-O2**: the same plus the functions Vec/Buf growth is inlined into (`fmt_make_room` 91, `main` 51, `print_int`, `fmt_pad`, `parse_int`, `read_stdin`, sort instances, ...): `Vec.reserve` is now out of line in most of them (a bigger body). Compile errors: only std line numbers in notes (err_assoc_lazy_default, err_derive_generic), err_unknown_attribute's list, and the changed or new tests. Program output: identical (the suite's expectations are 0.15's). **Bench** (-O2, alternating rounds, min of 15): sort 0.99, wordcount 1.02, json 0.99, binarytrees identical code; compile time of the compiler at -O2 unchanged (2.2 s), `check` unchanged. **fmtloop/fmtints is now ~1.06 (above bench/run.sh's 1.05)**: fmtints got 8% faster (push no longer inlines the growth path) while fmtloop is unchanged within 1% (its hot path has no Vec code); T2's non-allocating Fmt owns that ratio.
