# tachyon 0.18 design: contracts and verification in the language

Read from `.claude/worktrees/design-018` (branch design-018 at night-final
dd6fc28, built with `bootstrap/bootstrap.sh --dev`: 1042 tests passed). Sources:
`tachyonc guide debug|errors|std|allocators|effects`, `tachyonc test|reduce|probe
--help`, `query` on the compiler, docs/optimizer.md ("0.17: compile time",
"Ready for threads?"), docs/query.md ("Speed: the cache"), the 0.16 design
(branch design-016, docs/design/effects-allocation.md), the 0.17 design (branch
design-017b, docs/design/value-semantics.md, Revision 1), docs/eval/0.16-findings.md
(branch eval-run16) and docs/eval/0.17-iterations.md. Measurements: aarch64-macos,
10 cores (4 performance, 6 efficiency), 2026-10-16. Nothing but this file was changed.

The design follows the 0.16 and 0.17 documents: what exists and what is missing
(§1), the model (§2), examples (§3), the compiler's own move to values, arenas,
threads and incremental builds (§4), the algorithms and their cost (§5),
migration (§6), Phase 0 and the parallel tasks (§7), how the agent benefit is
measured (§8), risks (§9), open questions (§10) and the decisions taken.

## 0. What 0.18 needs from 0.17

**State on night-final.** 0.17's compile-speed track is merged: a per-function
pipeline, function-local IR ids and `ir_free_func`. Also merged are the cheaper
f-strings, the familiar forms, the debugging tools (`--trace`, `probe`,
`reduce`, test baselines) and `fix --suggested`. The value-semantics work is at
its Phase 0 (branch c17-phase0, which is night-final plus the design). 0.18 starts
once 0.17.0 has been released.

| # | what 0.18 needs | from | used by | if it is missing |
|---|---|---|---|---|
| 1 | moves, `Drop`, drops at scope end, explicit `.clone()` | 0.17.0 (T1) | `old(..)` (§2.1), generated property values (§2.7), test functions, the compiler's migration (§4) | 0.18 waits |
| 2 | `&T` / `&mut T`, split slices, exclusivity enforced (`--values=error`) | 0.17.0 (T2) | type invariants are sound only with exclusivity (§2.3); `&Program` / `&mut FnCtx` for the code generator's threads (§4.3) | 0.18 waits |
| 3 | inferred view summaries (V1) | 0.17.0 (T3) | the compiler's lexer and parser keep views of the source once they are migrated | for compiler/src only, V3's warnings until they land |
| 4 | `fix --values` that holds up on 95k lines | 0.17.0 (T6) | T6 and T7 (§4.1, §4.3) | the migration waits; the language features do not |
| 5 | the legacy rule (`*T` parameters checked as `&mut T`), which 0.18 removes | 0.17.0 | the compiler is built by 0.17 while it migrates | — |
| 6 | the kinds (plain / owned / view) and the `Copy` bound | 0.17.0 | `old(..)`, distinct types (over plain types only), generators | T1 and T4 wait |
| 7 | arena containers that view an `&Arena`, with a safe `reset` (U3) | 0.17.1 | per-function IR arenas in safe code (§4.2) | the island resets 0.16's `Arena` handle with `unsafe` (decided fallback) |
| 8 | written-static sets in effects | 0.17.1 | — (`Program::freeze` moves the tables out of statics, §4.3) | not needed |
| 9 | the per-function pipeline, function-local ids | 0.17 speed track | T7, T8 | done |
| 10 | effects in which reading a static is `global` | 0.16 | the proof that the code generator's workers share no mutable state (§4.3) | done |
| 11 | the query cache per Def (effects, views) | 0.13–0.17 | clauses in `query def`; the code cache sits next to it (§4.4) | done |

**The bootstrap rule.** 0.18's compiler/src is compiled by 0.17.x, so it may use
rows 1 to 8 and nothing new in 0.18. Contracts, tests, distinct types and
`NonNull` come into compiler/src from 0.19. std is different: it is compiled by
the compiler that embeds it, so it uses contracts in 0.18 (§2.1, T1).

## 1. Current state and the gaps

### 1.1 Run-time checks

- **What exits with 101:** index and slice bounds, `unwrap` on None/Err, `n as E`
  with an invalid value, `panic(..)` and `unreachable()`. Arithmetic wraps, and
  `/ 0` is 0. There is no `assert`. The guide maps `assert!(c)` to
  `if !c { panic("...") }`, and `assert!` is a parser error ("'assert!' is a
  macro call: tachyon has no macros").
- **Messages give no position.** For example `index out of bounds: index 5,
  length 3`, followed by `note: build with --trace for the line and its
  callers`. With `--trace` (a shadow stack, middle/trace.tach), the frames
  follow, innermost first.
- **std blames itself.** `Vec::insert: index out of bounds` and `called unwrap
  on None` are std's own `panic` calls, so the line where the mistake was made
  is the trace's second frame, and that frame exists only with `--trace`.
- **Lowering.** `middle::lower::calls::lower_check(ok, kind, a, b, c)` branches
  to a block that calls the runtime helper (`gen0::target::emit_runtime`, which
  uses printf) with the kind and three values. gen0 does the same at -O0.
- **The range analysis** (middle/range.tach) removes a bounds check when it
  proves the index in range. It decides comparisons from the dominating
  conditions, including the branch a check takes. It is "taken while the branch
  of a check is decided (one way ends the program)". Contract checks become the
  same kind of branch and get this machinery as it is.

### 1.2 Testing and debugging

- **`tachyonc test`** (0.17):
  - a program's cases are `tests/NAME.in` with `.out` and `.exit`; in the
    tachyon tree it runs the suite by filter;
  - builds use `--trace`; a failure shows its first stderr lines;
  - `-O N` runs one level;
  - `--against` (in the tachyon tree) labels failures `new` or `failing too`.
- **`tachyonc reduce FILE --until CMD`** shrinks an input line by line: chunks
  are left out and halved. **`tachyonc probe FILE:LINE EXPR...`** prints values
  as the program runs, without editing it.
- **What the language lacks:** test functions, property tests and fuzz targets.
  A test is a whole program's run on an input. The -O0 against -O2 comparison
  is done by hand (`tachyonc test -O 0`, then `tachyonc test`). Only the gate's
  fuzzer compares levels, and only for the programs it generates.

**What the evals say about testing and fixing:**

- **0.16** (516 runs). Haiku writes 4.0 input or expected files and 1.4 Python
  generators or reference programs per run, and runs the program 6.6 times
  (Rust: 3.5, 0.9, 5.7). The chains `run > run > run > run` (248 times in 67
  runs) and `Write × 4` (254 in 66) are its most frequent sequences. The 0.16
  findings proposed `tachyonc test --against CMD --gen CMD`.
- **0.17, iteration 4.** No agent used `--trace`, `probe`, `reduce` or `guide
  debug` in 48 runs. A tool named in one table row is not discovered on tasks
  that one test and a reading of the code solve.
- **Iteration 5.** A prompt line that steered agents to test through
  `tests/NAME.in/.out` brought 30% of runs to `tachyonc test`, and made the
  small tasks 5–9% dearer: writing the files costs turns.
- **Iteration 9.** A runnable `try:` was run 0 times out of 7. Agents fix by
  hand.
- **Iteration 2.** Agents meet under one distinct compile error per run. The
  cost is in testing and thinking, not in errors.
- **The fix tasks** (07-fix-bugs, 17-debug-crash, 23-fix-checker) cost 1.0–1.6
  × Rust, and up to 1.3 × the plain condition for Haiku before the hook fix.

**What 0.18 takes from this:**

- **D1. The facts are in the message.** The failing condition, its values and
  the position of the line to change go on one line, because agents do not run
  `try:` lines.
- **D2. Testing costs less than writing files and scripts.** A test is a
  function in the program's own file. A property replaces Haiku's generator,
  reference program and comparison script.
- **D3. Nothing to learn before it pays.** Rust's spellings work: `#[test]`,
  `assert_eq`, `#[cfg(test)] mod tests`.
- **D4. Results arrive where agents already look:** `tachyonc test`, which they
  run, and the check hook's test summary.
- **D5. No new cost on small tasks.** Nothing new is required: a program
  without contracts or tests is built and tested exactly as before.

### 1.3 Types

- **`type X = T` is a transparent alias** (generic aliases exist). The only
  nominal wrapper is a one-field struct, `struct NodeId { v: i64 }`. Tachyon
  has no tuple structs, so such a wrapper has no operators and needs `.v`
  everywhere. The compiler's own ids (nodes, types, symbols, blocks,
  instructions) are all `i64`, and mixing them up is the bug class behind
  `TYPES[node]`.
- **`*T` is nullable**, and `0 as *T` is the null idiom. `Option<*T>` takes 16
  bytes. 0.17's `&T` is non-null, but it is second-class: it cannot be a struct
  field or part of a C signature.

### 1.4 The compiler

The counts below are measured with `query grep --code --count` and
`--time-passes`.

- **State.** `static mut` statics: front 404, middle 270, back 166, gen0 20,
  tools 396, base 54. There are 3,555 occurrences of `unsafe` and 1,890
  references to `IntVec`. Tables are `static mut X: *T` plus a count and a
  capacity, grown by `base::grow`.
- **Memory (peak RSS):** `check` 203 MB; the -O0 self-compile 275 MB; -O2 516 MB
  (the IR takes 104 MB lowered and 174 MB optimized).
- **Time:** -O0 0.29 s (6.0 G instructions); -O2 1.82 s (30.2 G).
- **Phases of the -O2 self-compile** (1756 ms in all):

  | | phases | ms | share |
  |---|---|---|---|
  | serial now, and staying serial in 0.18 | parse 13.5, check 72.5, effects 4.9, lower 38.4, interprocedural constants 34.2, tail recursion 3.4, attribute inference 28.2, global DCE 13.9 | 209 | 12% |
  | per function (parallel in 0.18) | scalar pipeline 195.2, inlining 245.8, heap to stack 10.2, loop passes 505.0, LICM 65.5, promotion 25.4, SLP 15.0, instruction selection 66.9, register allocation and emission 334.3 | 1463 | 83% |
  | data and output (the assembler) | 83.3 | 83 | 5% (per function in 0.18) |

- **Ready for threads.** optimizer.md's section lists the shared state that must
  become per-thread:
  - about 440 pass statics;
  - reads of other functions' facts (`FN_ATTRS`, `FN_NOCAPTURE`, `FN_SIZE`,
    `FN_RT`, `FN_LIVE`, callee IR);
  - order-dependent program state: the inlining budget `PROGRAM_SIZE`, SROA's
    constant tables, `LABEL_COUNT`, `PANIC_USED`, `ENUM_PANICS`, `DBG_FNS`,
    statistics.

### 1.5 The gaps

| # | gap |
|---|---|
| C1 | No way to state what a function expects or promises. A bad value is noticed far from where it was made: in std, or calls deeper. |
| C2 | Run-time failures have no position unless the program is built with `--trace`. |
| C3 | std's checks name std's line, not the caller's. |
| C4 | There is no `assert` / `assert_eq` (an agent's Rust habit is a parser error). |
| C5 | Tests are whole-program I/O only. Generators, reference programs and comparisons are written outside the language (Python, shell). |
| C6 | The -O0 against -O2 comparison is manual. |
| C7 | `reduce` shrinks line-based inputs, not programs (compiler bugs, level differences). |
| C8 | There are no nominal types: ids and units mix silently. |
| C9 | Nullability is invisible in pointer types and C signatures, and `Option<*T>` has no niche. |
| C10 | The compiler is single-threaded, peaks at 516 MB, has 3,555 `unsafe`, uses raw tables, and rebuilds everything every time. |

## 2. The model (decided)

### 2.1 Contract clauses: `requires`, `ensures`

```ebnf
fn_item   = signature { clause } ( block | ";" ) ;
clause    = [ "debug" ] ( "requires" | "ensures" ) expr [ "else" message ] ;
message   = STRING | fstring ;
expr     += "result"                       (* in ensures only *)
          | "old" "(" expr ")" ;           (* in ensures only *)
```

```tach
fn get(self: &Stack, i: i64) -> i64
    requires 0 <= i && i < self.len()
    ensures result == self.items[i]
{
    self.items[i]
}

fn pop(self: &mut Stack) -> i64
    requires self.len() > 0 else "pop on an empty stack"
    ensures self.len() == old(self.len()) - 1
{ ... }
```

**The words are contextual:**
- `requires`, `ensures` and `debug` are keywords only between a signature and its
  body;
- `invariant` is a keyword only after a type (§2.3, §2.10);
- `result` and `old` are special only inside an `ensures`.

No program breaks.

**`requires`** must hold when the function is entered.
- **Checked at the call site,** after the arguments are evaluated and before the
  call. The condition reads the parameters bound to the argument values.
- **A failure blames the caller.** The position printed is the call's, which is
  the line an agent has to change (D1).
- **Calls that cannot be checked at the site** (through a `fn` value, a trait
  object's vtable, or a C callback) go through the function's *checking entry*.
  That entry checks the clause in the callee and prints the callee's
  definition; `--trace` adds the caller.

**`ensures`** must hold at every return: `return e`, the tail expression, and
`?`'s early return.
- It is checked in the callee after the result is computed and before the
  defers and drops run.
- **A failure blames the callee**, at the position of the return.
- `result` is the returned value; a function returning `()` has none (`contract.result`).
- `old(e)` is `e` evaluated at entry (after the requires) and kept for the exits:
  - `e` must have a plain type (0.17's kinds);
  - an owned value is spelled `old(v.clone())`;
  - a view is refused: it would view something the body changes (`contract.old`).

**What a condition may do.**
- It may read the parameters, `result`, `old(..)`, constants, and call functions.
- Its effects (0.16's inference) must be **pure: no `alloc`, `io` or `global`**.
  `panic` and `diverge` are allowed (an index or a loop inside the condition).
- Owned parameters are read in place: a condition never moves.
- Why pure:
  - a check that passes must not change what the program does;
  - switching `debug` clauses on and off must not change the program;
  - a later static verifier can read pure conditions.

`contract.effect` names the effect and its chain.

**Several clauses** are checked in order, and the first false one is reported.
`else "message"` (or `else f"..."`, evaluated only on failure) replaces the
condition's text in the report; the values are still printed.

**`debug` clauses** are checked only in test builds (`tachyonc test`,
`--debug-contracts`), at every -O level. They are for conditions whose cost would
change the program's complexity (`debug requires is_sorted(s)` on a binary
search). They give the optimizer no facts.

**Contracts are always on.** Contracts are checks like the bounds checks: there
is no release switch. The answers to their cost are `debug` and the range
analysis (§2.5).

**Generics, traits, closures:**
- Generic functions: clauses are checked per instance, as effects are.
- Traits: a trait method's clauses bind every impl.
  - An impl may add `ensures` (a stronger promise).
  - An impl may not add `requires` (`contract.impl-requires`, Liskov).
  - A statically dispatched call checks the trait's requires at the site.
- Closures take no clauses in 0.18.

**Effects.**
- A requires check adds `panic` to the caller, unless the front end folds it to
  true for constant arguments.
- An ensures adds `panic` to the callee.
- `debug` clauses add nothing outside test builds.
- `query effects --why panic` names the clause: `requires 'i < self.len()' of
  'get' at main.tach:14:13`.

**At compile time.** A requires that the front end's constant evaluation finds
false for literal arguments (`get(-1)`) is the error `contract.violated`. It is
decided by the front end alone, so errors never depend on `-O`.

### 2.2 Assertions

- **The forms** are prelude built-ins, known to the compiler because they
  capture their text: `assert(c)`, `assert(c, "message")` (or an f-string),
  `assert_eq(a, b)`, `assert_ne(a, b)` (for `T: Eq + Debug`), `debug_assert(c)`,
  and `assert_snapshot(x)` (§2.6).
- **The bang spellings are accepted** (D3): `assert!`, `assert_eq!`,
  `assert_ne!`, `debug_assert!`, `panic!` and `unreachable!`, each with plain
  arguments, a string literal or an f-string. `fmt` writes them without the `!`.
  `panic!("x = {}", x)` is the error `macro.args`, whose `try:` gives the
  f-string. Tachyon still has no macros: these six names are spellings, not a
  mechanism.
- **The message is the same as `assert`'s:** `assert_eq(a, b)` reports like
  `assert(a == b)`, with both values printed by Debug.
- **Operands are evaluated once,** into temporaries, so
  `assert(v.pop() == Some(3))` pops once.

### 2.3 Type invariants

```tach
struct Stack { items: Vec<i64>, max: i64 }
invariant self.items.len() <= self.max
```

- **Where the invariant is checked:** when a value leaves its module's code.
  That is at the return of every function of the defining module that is
  visible outside it, for each `&mut T` parameter (`&mut self` included) and
  for a returned `T`. Inside the module, intermediate states are free.
- **Writes outside the module are refused.** Outside the module, writing a
  field or writing a struct literal of the type is `contract.sealed`; reading
  fields is allowed. This is weaker than 0.16's `#[sealed]`, which hides the
  fields: an invariant only forbids the writes that could break it.
- **Why it is sound in 0.18:** 0.17's exclusivity.
  - While a method holds `&mut self`, no other path can read the value. Nobody
    observes the broken state between the method's entry and its exit.
  - Eiffel's callback problem and Spec#'s pack/unpack are therefore not needed.
  - A plain copy taken outside is a copy of a valid value.
- Enums may have invariants; `debug invariant` exists as for clauses.
- A failure blames the method (the position of its return).
- **Loop invariants** are not in 0.18. At run time they are an `assert` at the
  top of the body (§10, Q12).

### 2.4 Run-time failures: one format

Every check that exits with 101, the new ones and the old, prints one line on
stderr:

    FILE:LINE:COL: WHAT: DETAILS

With `--trace`, the frames follow it. The `note: build with --trace ...` line
goes, because the position is now on the first line; `guide debug` keeps the
advice.

| check | the line |
|---|---|
| requires | `main.tach:31:17: requires failed: 's.len() > 0' of 'median' (stats.tach:2:14): s.len() = 0` |
| ensures | `stats.tach:19:5: ensures failed: 'result <= s.len()' of 'count_above': result = 7, s.len() = 5` |
| invariant | `stack.tach:30:5: invariant failed: 'self.items.len() <= self.max' of 'Stack' when 'Stack::push' returns: self.items.len() = 5, self.max = 4` |
| assert | `main.tach:9:5: assertion failed: 'x > 0': x = -1` |
| assert_eq | `lexer.tach:41:5: assertion failed: 'toks.len() == 0': toks.len() = 1` |
| index | `main.tach:12:13: index out of bounds: index 3, length 2` |
| unwrap | `main.tach:10:31: called unwrap on None` (std: `requires self.is_some() else "called unwrap on None"`) |
| `as E` | `main.tach:7:13: invalid value 3 for enum Level` |
| distinct | `main.tach:4:13: invariant failed: '0 <= self && self <= 100' of 'Percent' in 'x as Percent': self = 140` |
| NonNull | `ffi.tach:9:13: null pointer made NonNull<u8>: 'c::getenv(name)'` |

**Which values are printed** (power-assert style, after pytest's assertion
rewriting):
- For a failing `&&` chain, only the conjunct that failed is reported: its
  text replaces the whole condition.
- For a comparison or a call, its operands or arguments that are not literals.
- For `!e`, the operands of `e`.
- At most four values, each printed with Debug and cut at 60 bytes:
  `[1, 2, 3, …(97 more)]`.

The operands are bound to temporaries as the condition is evaluated, so nothing
runs twice.

**How the line is made.**
- Every check site, old or new, gets an entry in a per-program site table: the
  file, line and column, the kind, the condition's text, and the operands'
  texts and Debug functions.
- The check's cold block passes the site's number and the operands' values to
  the runtime helper. The hot path is the branch it was before.
- The values do not depend on `-O` (there is no undefined behaviour), so stderr
  is byte-identical at every level, and §2.6's comparison relies on that.

### 2.5 The optimizer: proven, never assumed

**A contract check is a check,** `if !c { fail(site) }`, like a bounds check. The
range analysis removes it where the dominating facts decide `c`. A removed check
leaves no trace except in `query checks` (§2.14).

**Facts come only from checks that ran.** Facts the program merely claims are
never used:

1. **In the caller, after a requires check:** the branch of the check gives its
   condition (existing machinery).
2. **In the callee, at entry:** a non-`debug` requires holds there, because
   every way in checks it: direct calls at the site, every other call through
   the checking entry. The entry block gets the condition as a fact.
   - So std's internal checks disappear behind its requires: `Vec::get`'s
     bounds check is implied by `requires 0 <= i && i < self.len()`.
3. **In the caller, after a call:** a non-`debug` ensures holds of the result,
   because the callee checked it before returning. The call's result gets its
   range facts: comparisons with constants, parameters and other results. For
   example, `ensures 0 <= result && result < n` lets the caller's `table[h(x)]`
   lose its bounds check when `table.len() == n`. This is new
   (`middle::ipo`, T5).
4. **Type invariants are not facts in 0.18.** They hold at module boundaries,
   and a value read inside its module may be in the middle of a change.

**What the optimizer never does:** remove a check because a clause says so
without the clause having been checked. That would be Ada's `pragma Assume`, C's
`__builtin_assume`, or a verified mode. A wrong contract would then be
undefined behaviour, which tachyon does not have.

**Cost.** A few range constraints per call and per entry. The range analysis
scans its facts linearly (`narrow_by_facts`, 2.5% of -O2: an open item of 0.17).
T5 indexes them by value before adding more.

### 2.6 Tests in the language

```tach
#[cfg(test)]
mod tests {
    #[test]
    fn empty_input_has_no_tokens(gpa: Gpa) {
        let toks = lex("", gpa);
        assert_eq(toks.len(), 0);
    }
}
```

- **Test functions.** A `#[test]` function takes nothing, or `gpa: Gpa` (0.16's
  strict allocation: a test gets its allocator as `main` does). It returns `()`
  or `Result<(), E>`; an `Err` fails, printed with Debug. `#[test]` items and
  `#[cfg(test)]` items or modules are compiled only for tests. `cfg(test)` is
  the one `cfg` tachyon accepts (D3).
- **A test module sees its parent's items,** private ones included, without a
  `use`, as a nested scope sees its parent's names.
  - `use super::*;` is **not** accepted, in a test module or anywhere: no
    wildcard imports is a standing rule. It is `error[import] wildcard imports
    are not allowed`, whose help says that a test module sees its parent's
    items without an import, and whose `try:` deletes the line. `fix
    --suggested` and `fix --only imports` apply that deletion (decided
    2026-10-16).
- **The harness.**
  - `tachyonc test` compiles the program with a test entry in place of `main`:
    one binary for every test, where `prog --tachyon-test NAME` runs one.
  - Each test runs in its own process, forked by the runner. A failed check
    exits with 101 there, and the other tests go on.
  - Tests run in parallel, one per core, each within a time limit (10 s,
    `--timeout`).
- **Test builds turn on** `--trace`, `--check-alloc`, `debug` clauses and
  `debug_assert`.
  - **A test that leaks fails:** `leaked 2 blocks (48 bytes): allocated at
    parse.tach:14:9`. With value semantics a leak is a `forget` or a cycle
    through raw pointers, which is rare and a bug.
  - `--no-check-alloc` turns the leak check off.
- **Snapshots.**
  - `assert_snapshot(x)` (for `T: Debug`) compares x's `{:?}` text with
    `tests/snapshots/MODULE__TEST__N.snap`.
  - A missing file is written and reported as `new snapshot` (the test
    passes); a difference fails with its first differing line.
  - `tachyonc test --accept` writes the current values. It also writes the
    `.out` of an I/O case that has none or differs (`.exit` too).
  - I/O cases (`tests/NAME.in/.out`) stay as they are: they are snapshots of a
    whole program.
- **The -O0 against -O2 comparison** (the roadmap's built-in).
  - **What runs at both levels:** every I/O case, every `#[test]`, and the first
    20 cases of every property.
  - **What must agree:** stdout, the exit status and the first line of stderr.
  - **A difference is reported as the compiler's bug,** because the program has
    no undefined behaviour to blame: `DIFF b: -O0 and -O2 differ at stdout line
    3: '7' against '8'. A compiler bug, not this program's` | `try: tachyonc
    reduce main.tach --differs --input tests/b.in`.
  - `-O N` runs one level.

### 2.7 Property tests

```tach
#[property]
fn sort_matches_naive(v: Vec<i64>) {
    let mut a = v.clone();
    sort(a.as_mut_slice());
    assert_eq(a, naive_sort(v));
}
```

**Generators come from the parameters' types.** No derive is needed.

| type | what is generated |
|---|---|
| integers | the edge values first (0, 1, -1, MIN, MAX), then mostly small values |
| `bool`, `u8`, `f64` | `f64` includes 0.0, -0.0 and the infinities, and NaN only with `--nan` |
| text (`[u8]`, `Buf`) | ASCII-biased, with digits, spaces and newlines |
| containers | `Vec<T>`, arrays, tuples, `Option`, `Result`, `HashMap` |
| structs and enums | built from generable fields, structurally |
| distinct types (§2.10) and types with invariants | the underlying value, filtered by the invariant |
| a type with an `impl Arbitrary` | that impl |

- **Not generable:** raw pointers, `fn` values and views (`test.generate`). A
  `[T]` or `&T` parameter is generated as an owned value and lent.
- **A property's `requires` filters its inputs:** a failing input is discarded,
  not a failure. When over 90% are discarded, the property fails with "the
  generator rarely satisfies 'requires ...'", whose `try:` is an
  `impl Arbitrary`.

**Runs.**
- A property runs 100 cases (`--cases N`), deterministically: the seed is a
  hash of its name (`--seed S`). Sizes grow with the case number.
- Passing cases run in one child process, which stops at the first failure and
  reports it through a pipe. Shrinking forks a child per candidate.

**Shrinking is integrated, as in Hypothesis:**
- A generator draws from a choice sequence of u64s.
- A failing case is shrunk by shortening the sequence and lowering its values,
  then replaying it.
- Values shrink without code per type. Invariants and requires still hold,
  because every candidate goes through the same generators and filters.

**The report** (in `tachyonc test`, §2.9):

```text
FAIL sort_matches_naive (property, case 37 of 100, shrunk in 41 steps): main.tach:22:5: assertion failed: 'a == naive_sort(v)': a = [1, 0], naive_sort(v) = [0, 1]
  input: v = [1, 0]
  try: tachyonc probe main.tach:21 a --test sort_matches_naive --seed 0x9e3779b9
```

Failing inputs are saved in `.tachyonc/test/corpus/NAME/` and replayed first
next time. `--accept` copies them into `tests/corpus/NAME/`, where every run
replays them.

**Contracts are properties.**
- `tachyonc test` also tests every function that has a non-`debug` `ensures`, or
  that returns a type with an invariant, when its parameters are generable and
  its effects have no `io` and no `global`.
- It gives each such function 100 argument sets that satisfy its requires.
- A failing ensures or invariant is reported as a property, with the arguments.
- An agent who writes an `ensures` gets a test of it without writing one.
  `--no-contracts` turns this off.

**std::test** (in the prelude of test builds):
- `trait Arbitrary { fn arbitrary(g: &mut Gen) -> Self; }`
- `Gen`'s methods: `int_in(lo, hi)`, `choose(n)`, `bool()`, `size()`,
  `vec_of(|g| ..)` and `text()`.

### 2.8 Fuzz entry points

```tach
#[fuzz]
fn parse_never_crashes(data: [u8]) {
    let _ = parse(data);
}
```

- **The parameter.** A `#[fuzz]` function takes one parameter: `[u8]`, or any
  generable type. With another type it is a property whose choice sequence is
  the fuzzer's bytes: one engine for properties and fuzz targets.
- **`tachyonc fuzz NAME [--time S] [--jobs N]`** is coverage-guided:
  - the program is built with `--coverage` at -O1: one 8-bit counter per CFG
    edge (middle/coverage.tach);
  - a fork server in the test binary runs each input in a forked child, so a
    failed check ends only the child;
  - inputs that reach new edges join `.tachyonc/fuzz/NAME/`;
  - mutations: bit flips, byte runs, splices, and a dictionary of the program's
    string constants, which the compiler knows;
  - a crash is shrunk with the property shrinker over bytes, saved, and
    reported as a property is.
- **`tachyonc test`** replays `tests/fuzz/NAME/*` and the saved crashes as
  regression cases. It fuzzes only with `--fuzz S` (S seconds per target).
- **Not libFuzzer or AFL.** macOS's cc ships no libFuzzer, and tachyon emits its
  own code. The engine is about 600 lines in std and middle.

### 2.9 `tachyonc test` and `tachyonc reduce`

```text
tachyonc test [FILTER...] [ROOT.tach]
  runs: tests/NAME.in cases, #[test], #[property], functions with ensures, fuzz regressions;
        each at -O0 and at -O2 (the first 20 cases of a property at -O0)
  -O N            one level only
  --cases N, --seed S, --timeout S, --fuzz S
  --accept        write new or changed snapshots, .out files and saved counterexamples
  --no-contracts, --no-check-alloc
  --against CMD [--gen CMD --cases N]   outputs compared with a reference program's,
                  on tests/ inputs and on inputs that CMD after --gen prints (the 0.16 findings' proposal)
  --budget N, --full                    (0.17)
```

**The summary** is one line of counts, then for each failure one line, its
trace on one line, and one `try:`:

```text
test main.tach: 14 passed, 2 failed, 1 new snapshot (6 cases, 7 #[test], 2 #[property], 1 contract; -O0 and -O2 agree)
FAIL empty_input_has_no_tokens: lexer.tach:41:5: assertion failed: 'toks.len() == 0': toks.len() = 1
  trace: lexer.tach:22 lexer::lex < lexer.tach:41 lexer::tests::empty_input_has_no_tokens
  try: tachyonc probe lexer.tach:22 i c --test empty_input_has_no_tokens
FAIL b: exit 101 (expected 0): main.tach:31:17: requires failed: 's.len() > 0' of 'median' (stats.tach:2:14): s.len() = 0
  trace: main.tach:31 main
  try: tachyonc probe main.tach:31 groups --input tests/b.in
```

- **The `try:` is a `probe`** at the blamed line, with the condition's names
  and the case's input, test name or seed. It is a probe and not an edit
  because a run-time failure has no exact fix. The facts the agent needs are on
  the failure's line already (D1).
- `probe` gains `--test NAME` and `--seed S`.

**`reduce` gains three program modes:**

```text
tachyonc reduce FILE --until 'CMD'                   (0.17) the lines of an input
tachyonc reduce PROG.tach --differs [--input F]      a program whose -O0 and -O2 runs disagree
tachyonc reduce PROG.tach --fails 'TEXT'             a program whose build or run prints TEXT (a compiler crash, an error code)
tachyonc reduce PROG.tach --test NAME                a failing property or fuzz case's smallest input (saved to tests/corpus)
```

- **How a program is reduced.** It removes items, statements, match arms and
  fields (`refactor field --remove`), replaces expressions with literals of
  their type, and inlines calls (`refactor inline`).
- **Every candidate goes through the edit engine,** which refuses one that does
  not check. Only the predicate is run.
- The result is `PROG.min.tach`, or a directory for several files.
- This is C-Reduce for tachyon, built on its own refactorings. It is for the
  gate's fuzz failures and for compiler tasks.

### 2.10 Distinct types

```tach
type NodeId = distinct i64;
type Meters = distinct f64;
type Id<T> = distinct i64;            // a phantom parameter: Id<Node> and Id<Edge> differ
type Percent = distinct i64 invariant 0 <= self && self <= 100;
```

- **What it is.** A distinct type is a new nominal type with T's representation
  and ABI: in `#[repr(C)]` and `extern` it passes as T. T must be plain
  (numbers, bool, raw pointers, and plain structs, tuples and arrays). Over an
  owned or view type it is `distinct.kind` in 0.18.
- **Conversions are explicit and free:** `x as NodeId`, `id as i64`.
  - The one implicit conversion is a literal: an integer or float literal
    becomes a distinct type over a numeric T, and an invariant is checked on it
    at compile time (`contract.violated`).
  - `as` into a type with an invariant checks it at run time, as `n as E` does.
- **Operators:** T's operators apply between two values of the same distinct
  type (`a + b: Meters`, `a < b: bool`), or with a literal on one side
  (`d * 2.0`).
  - Mixing types is `distinct.mix`.
  - Each arithmetic result of a type with an invariant is checked; the range
    analysis removes what it proves.
- **Traits:** X has T's `Eq`, `Ord`, `Hash`, `Debug`, `Display` and `Clone`, as if
  derived, and T's kind (plain). An explicit `impl Display for X` replaces the
  inherited one.
  - X does not have T's inherent methods: `id.abs()` is `distinct.method`, with
    `try:` `(id as i64).abs()`.
  - `impl X { .. }` adds methods.
- **Printing and patterns.** Values print as T's would. Messages name the type
  (`NodeId`). Literal patterns of T match (`match id { 0 => .. }`).
- **Generics.** A distinct type is a type argument of its own: `Vec<NodeId>` is
  a separate instance from `Vec<i64>`. Identical-body folding at emission (T5)
  takes back the duplicated code; the symbols alias.

These are Go's defined types. The alternatives are in §2.13.

### 2.11 Non-null pointers

```tach
pub type NonNull<T> = distinct *T invariant self as u64 != 0 else "null pointer made NonNull";
```

- **The std API** (std/nonnull.tach):
  - `NonNull::new(p: *T) -> Option<NonNull<T>>`; `p.as_ptr() -> *T`;
  - `p as *T`; `q as NonNull<T>`, which checks;
  - `*T` gets `is_null()`.
  - Dereferencing stays unsafe, as for any raw pointer.
- **The niche.** `Option<NonNull<T>>` is one pointer, and `None` is null. Layout
  knows `NonNull` by a std attribute (`#[niche_null]`), not by a general rule
  about invariants.
- **C interop.**
  - An `extern "C"` signature may use `NonNull<T>`. C must not return null
    there: the value is checked when C returns it: `ffi.tach:9:13: null pointer
    made NonNull<u8>: 'c::getenv(name)'`.
  - It may also use `Option<NonNull<T>>`, which is nullable, with `*T`'s ABI.
  - cimport keeps `*T` for C's pointers, and imports clang's `_Nonnull` as
    `NonNull<T>`.
- `*T` keeps its meaning (nullable). `&T` (0.17) is non-null but second-class:
  `NonNull` is for pointers that are stored (the fields of unsafe data
  structures) and for C signatures.

### 2.12 Interactions

- **Value semantics** (0.17), from the sections above:
  - `old(..)` and the kinds;
  - conditions read owned parameters in place;
  - invariants are sound through exclusivity;
  - generated values are owned and dropped after their case, and a property may
    take `&T`.
  - Views are not affected: a condition is a `bool`, so the view summaries are
    unchanged.
- **Effects.**
  - Conditions must be pure.
  - A requires is a `panic` in the caller and an ensures a `panic` in the
    callee.
  - A `#[no_panic]` function may call a function with a requires only when the
    front end proves the clause for the arguments, which in practice means
    literals.
- **Defers and drops.** `ensures` sees the state before them, and a defer may
  not be needed for the promise to hold.
- **f-strings in `else`:** the holes are pure reads, evaluated on failure only.
- **The query cache:** clauses are part of a Def's text, so `def`, `show` and
  `context` print them with the signature.
- **The checking tools:** `--check-unsafe` and `--check-alloc` are unchanged;
  test builds use `--check-alloc` (§2.6).
- **Generic instances:** messages name the instance (`Vec<i64>::get`).

### 2.13 Alternatives considered

**Contract syntax.**
- *Attributes,* `#[requires(c)]` and `#[ensures(|r| ..)]`, as in Rust's
  `core::contracts`, Prusti, Creusot and Kani. Some agents know them, and
  tachyon already has attributes for effects. Rejected:
  - a condition is part of the signature, and above it, outside fmt's
    expression layout, it reads badly;
  - a result bound by a closure (`|r|`) is noisier than `result`.

  The attribute form gets an error that names the exact rewrite (`fix
  --suggested` applies it).
- *Statement-level checks in the body* (D's `in {}` blocks): not visible in
  `query def`. Rejected.
- *Clauses checked in the callee* (Eiffel, D): they blame the callee's line.
  Checking at the caller blames the line to change and gives the optimizer the
  caller's facts. The callee-side check remains as the checking entry for
  indirect calls.
- *Assumptions for the optimizer* (Ada's `Assume`, `__builtin_assume`):
  rejected by the no-UB principle.
- *Checks switched off in release builds* (Eiffel, D, Ada's policies): rejected
  for consistency with every other check. `debug` and the range analysis
  answer the cost.
- *Static verification* (Dafny, Verus, SPARK): out of scope for 0.18. The
  clauses are pure and use `old` and `result`, so a later verifier can read them.

**Tests.**
- *Zig's `test "name" { }` blocks:* names with spaces and no fake function.
  Rejected for D3: agents write `#[test] fn`.
- *Separate test files only* (Go's `_test.go`): possible as a `#[cfg(test)]`
  module in its own file, not required.
- *Per-type shrinkers* (QuickCheck): integrated shrinking needs no code per type
  and keeps invariants.
- *libFuzzer or AFL:* not available, and external.

**Distinct types.**
- *Nim's `distinct`:* nothing is borrowed until `{.borrow.}`; too much
  boilerplate.
- *Haskell's newtype deriving:* deriving clauses to learn.
- *One-field structs:* what exists today; no operators, and `.v` everywhere.
- *Units of measure (F#):* out of scope.
- Chosen: *Go's defined types:* operators kept, methods not.

**Non-null.**
- *Zig's non-null `*T` with `?*T`:* it rewrites every `0 as *T` (the compiler
  alone has thousands) and every C import, and inverts the Rust habit.
- *A sigil (`*!T`):* unfamiliar.
- Chosen: *`NonNull<T>`* (Rust's name), built from 0.18's own distinct types and
  invariants.

**The compiler** (§4).
- *Thread-local statics* (`#[thread_local]`) instead of contexts: the smallest
  change to the source. Rejected:
  - it needs TLS in both back ends and both object formats;
  - it hides the state;
  - the effects could no longer prove that the workers share nothing mutable.
- *The front end in a context too:* not needed for threads. The front end stays
  serial in 0.18, and its tables become `Vec<T, Comp>` statics.
- *Incremental builds by object file per module* (C's way): tachyon compiles
  whole programs (inlining, IPO), so per-function keys with recorded reads follow
  the dependencies exactly.
- *A parallel front end:* 12% of -O2 serial; later.

### 2.14 What agents see

Every compile-time diagnostic keeps 0.17's contract: one line with the position
and code, then `help:`, then `try:` lines that run as they are. `check` joins
them with ` | `.

| code | when | example | `try:` |
|---|---|---|---|
| `contract.effect` | a condition does io, allocates or touches a static | `'requires' of 'push' calls 'log', which does io (log.tach:3:5); a condition may not do io, allocate or touch statics` | `tachyonc query effects log --why io` |
| `contract.old` | `old(e)` of a view, or of an owned value without `.clone()` | `'old(self.items.as_slice())' would view 'self', which 'pop' changes` | `tachyonc edit patch stack.tach:12 --old 'old(self.items.as_slice())' --new 'old(self.items.len())'` |
| `contract.result` | `result` outside an ensures, or in a function returning `()` | | `edit patch` |
| `contract.violated` | a requires false for constant arguments; a literal outside a distinct type's invariant | `'get(-1)' violates 'requires 0 <= i' of 'get' (stack.tach:4:14)` | `edit patch` |
| `contract.sealed` | a field write or struct literal outside the module of a type with an invariant | `'s.max = 3' writes a field of 'Stack', which has an invariant; outside 'crate::stack' use its methods` | `tachyonc query items stack` |
| `contract.impl-requires` | an impl adds a requires to a trait method | | `edit patch` (move it to the trait) |
| `distinct.mix` | an operator between a distinct type and another type | `'d + x' adds 'Meters' and 'f64'` | `tachyonc edit patch main.tach:9 --old 'd + x' --new 'd + x as Meters'` |
| `distinct.method` | a method of the underlying type | `'abs' is a method of i64, not of 'NodeId'` | `edit patch ... --new '(id as i64).abs()'` |
| `distinct.kind` | `distinct` over an owned or view type | | `help:` a struct |
| `test.signature` | a `#[test]` with parameters other than `gpa: Gpa` | | `edit patch` `#[test]` → `#[property]` |
| `test.generate` | a property parameter with no generator | `no generator for '*u8' (raw pointer)` | `tachyonc edit insert --after T < impl Arbitrary for T {..}` |
| `import.wildcard` | `use super::*;` (in a test module or elsewhere) | `wildcard imports are not allowed \| help: a test module sees its parent's items without an import` | `tachyonc edit delete FILE:LINE` (applied by `fix --suggested`, `fix --only imports`) |
| `macro.args` | `panic!("{}", x)` | | an f-string, by `edit patch` |

Run-time failures are §2.4's lines, and the test summary is §2.9's.

**The tools.**
- **`query def`, `show` and `context`** print the clauses with the signature.
  `query effects --why panic` names a clause.
- **`query checks FN|MODULE`** (T5) lists the checks left in a function at -O2,
  each with its kind and position, and the removed ones with the fact that
  removed them. It is for the perf tasks (12, 16), where agents now read the
  assembly.
- **The refactorings** keep clauses correct: `refactor signature --rename-param`
  and `refactor rename` rewrite them; `refactor inline` turns a requires into an
  `assert` at the call; `refactor field --rename` rewrites invariants.
- **`fmt`** puts each clause on its own line, indented four spaces, with `{` on
  the next line, and writes the bang spellings without the bang.
- **`fix --suggested`** rewrites `#[requires(c)]` and `#[ensures(|r| c)]` to the
  clause form.
- **`explain`** has an entry for every code above.
- **The guide.**
  - New topics: `contracts` (clauses, invariants, `old`, `result`, `debug`, the
    messages, what the optimizer does and does not do) and `testing`
    (`#[test]`, `cfg(test)`, the assert family, snapshots, properties, fuzz,
    `tachyonc test`'s summary, the level comparison).
  - `types` gains `distinct` and `NonNull`.
  - `debug` is rewritten around the failure line, `tachyonc test` and `probe`.
  - The core guide gains three lines (`#[test]`, `assert_eq`, `requires`)
    within its budget.
  - `errors#at-run-time` shows the new line.
- **The check hook** (tools/agent-hooks/check-after-edit.py) already runs the
  program's tests after a clean check, debounced. It now includes `#[test]` and
  the properties at 20 cases, within 2 s, and prints only the summary's counts
  and failure lines.
- **The eval prompts are unchanged** (D5); §8 measures adoption from habit.

## 3. Before and after

**1. A bug noticed far from where it was made** (the shape of 17-debug-crash).

```tach
// before (0.17): median indexes s[(n - 1) / 2]; an empty group crashes inside it
// stderr: index out of bounds: index 0, length 0
//         note: build with --trace for the line and its callers
fn median(s: [i64]) -> i64 { let n = s.len(); s[(n - 1) / 2] }
```

```tach
// after (0.18)
fn median(s: [i64]) -> i64
    requires s.len() > 0
{
    let n = s.len();
    s[(n - 1) / 2]          // the bounds check is gone: the entry fact s.len() > 0 implies it
}
// stderr: main.tach:31:17: requires failed: 's.len() > 0' of 'median' (stats.tach:2:14): s.len() = 0
```

The line printed is the caller's (main.tach:31, where the empty group was
formed), not the median's. Without the clause, 0.18 still prints the median's
position (`stats.tach:6:5: index out of bounds: index 0, length 0`), which is
0.17's first trace frame, without `--trace`.

**2. Haiku's generator, reference program and comparison, as a property** (0.16:
1.4 scripts and 4 files per run).

```text
# before: gen.py, ref.py, tests/01.in .. 10.in, then
for f in tests/*.in; do ./prog < $f > got; python3 ref.py < $f > want; cmp got want; done
```

```tach
// after: three lines in the program's file
#[property]
fn fast_matches_naive(v: Vec<i64>) { assert_eq(max_gap(v.as_slice()), max_gap_naive(v.as_slice())); }
// tachyonc test: FAIL fast_matches_naive (property, case 12 of 100, shrunk in 9 steps): main.tach:40:38:
//   assertion failed: 'max_gap(v.as_slice()) == max_gap_naive(v.as_slice())': max_gap(v.as_slice()) = 0, max_gap_naive(v.as_slice()) = 5
//   input: v = [5, 0]
```

**3. A type with an invariant.**

```tach
// stack.tach
pub struct Stack { items: Vec<i64>, max: i64 }
invariant self.items.len() <= self.max

impl Stack {
    pub fn push(self: &mut Stack, x: i64)
        requires self.items.len() < self.max else "push on a full stack"
    { self.items.push(x); }
}
// main.tach: 's.max = 3;'
// main.tach:8:5: error[contract.sealed] 's.max = 3' writes a field of 'Stack', which has an invariant; outside 'crate::stack' use its methods | try: tachyonc query items stack
```

**4. Ids that cannot be mixed up** (in the compiler from 0.19).

```tach
type NodeId = distinct i64;
type TypeId = distinct i64;
static mut TYPES: Vec<Type, Comp> = Vec::new_in(Comp {});
fn type_of(n: NodeId) -> TypeId { NODE_TYPE[n as i64] }
let t = TYPES[node];
// check.tach:41:15: error[type error] cannot index 'Vec<Type, Comp>' with 'NodeId' | help: 'TYPES' is indexed by 'i64'; was 'type_of(node)' meant? | try: tachyonc edit patch check.tach:41 --old 'TYPES[node]' --new 'TYPES[type_of(node) as i64]'
```

**5. C with nullability** (§2.11).

```tach
extern "C" { fn getenv(name: *u8) -> Option<NonNull<u8>>; }       // 8 bytes, C's ABI
match unsafe { getenv(c"HOME") } { Some(p) => .., None => .. }
```

**6. The compiler's table style** (§4.1).

```tach
// before (0.17's compiler)
static mut TYPES: *Type = 0 as *Type;  static mut TYPE_COUNT: i64 = 0;  static mut TYPE_CAP: i64 = 0;
fn add_type(t: Type) -> i64 { unsafe { TYPES = grow(TYPES, TYPE_COUNT, &TYPE_CAP); TYPES[TYPE_COUNT] = t; } TYPE_COUNT += 1; TYPE_COUNT - 1 }

// after (0.18's compiler, 0.17 features)
static mut TYPES: Vec<Type, Comp> = Vec::new_in(Comp {});     // Comp: the compilation's arena
fn add_type(t: Type) -> i64 { TYPES.push(t); TYPES.len() - 1 } // safe
```

**7. The code generator's worker** (§4.3).

```tach
// the declaration is checked: a worker reads no static and writes none
#[effects(alloc(Gpa, Arena), panic, diverge)]
fn codegen_function(p: &Program, cx: &mut FnCtx, f: i64) -> FnOutput { .. }
```

## 4. The compiler: values, arenas, threads, incremental builds

The bootstrap rule applies: every step below uses 0.17's language. Each step is a
tool-driven script, proven with `same-output` against the Phase 0 compiler
(about 7,000 compilations), and measured in instructions retired.

### 4.1 Values and the compilation's arena (front, tools, base)

1. **`base::Comp`**, a zero-sized `impl Allocator`.
   - It allocates from the compilation's arena, an unsafe island of about 80
     lines over a raw static set up in `main` from `gpa`.
   - `Comp::free` is empty, so values in it skip destruction (0.17's rule for
     arenas), and drop glue on `Vec<T, Comp>` inlines to nothing.
   - `Comp {}` is a constant, so statics can hold `Vec<T, Comp>` (0.16's
     constant constructors).
   - It shows in the effects as `alloc(Comp)`.
2. **`IntVec` becomes `Vec<i64, Comp>`** (1,890 references). A typed `rewrite`
   per operation (`iv_push($v, $x)` → `$v.push($x)`, ...) does it.
3. **Table triples become `static mut X: Vec<T, Comp>`.** The new `refactor
   table X --count X_COUNT --cap X_CAP` does it:
   - `X[i]` stays (0.17 makes Vec indexing a place);
   - `X_COUNT` becomes `X.len()`;
   - grow-and-store becomes `push`;
   - the count and capacity statics are deleted.
   - The compiler's index-and-copy style keeps 0.17's `own.static` quiet.
4. **`fix --values` per module:**
   - `*T` parameters become `&T` or `&mut T` (it must: 0.18 drops the legacy
     rule);
   - `defer x.free()` lines are deleted;
   - owned locals drop at scope end.
5. **The syntax tree's part of the arena is released after lowering.**
   - The compilation's memory is split by allocator type into `Ast` (tokens,
     nodes, node lists) and `Comp` (types, symbols, file texts, positions).
   - At -O1 and -O2, without `query` and `-g` needing the nodes, `Ast` is reset
     once the program is lowered.
   - `check` alone peaks at 203 MB, so this is the larger part of the -O2 peak
     that is not IR. T6 measures what codegen still reads (positions for `-g`,
     check-alloc sites) and moves it to `Comp`.
   - gen0 (-O0) compiles from the tree and keeps it.
6. **The measure:** `query grep unsafe --code --count` falls from 3,555 to under
   600. What stays unsafe: the allocator islands, the thread pool, C calls and
   the object writer's bytes.

### 4.2 Per-function arenas for the IR (middle, back, gen0)

- **The working arena.** Each worker thread has one IR arena (`FnCtx.arena`).
  A function is lowered, optimized and emitted in it, and the arena is reset
  once the function's output is taken.
  - With 0.17.1's `&Arena` containers, the reset is safe: it is legal once
    nothing views the arena.
  - Without them, the island resets 0.16's `Arena` handle with `unsafe`, and
    `--check-alloc` traps a stale use.
- **The inline store.** At -O2 a callee's optimized IR is needed by callers that
  are optimized later. When an optimized function is an inlining candidate, its
  IR is copied into the inline store: owned, on Gpa, compact. The store frees it
  once the last caller has been optimized; the inliner knows the callers from
  the call graph.
- **Memory in flight:** the pending inline bodies, plus one working arena per
  thread (the largest function is about 1.5 MB, 0.16's prototype), instead of
  the 174 MB of optimized IR held today.
- **Goal for -O2's peak:** 516 MB → at most 300 MB, from this and §4.1's step 5.

### 4.3 Parallel code generation

**The shared state becomes two contexts.** The new `refactor context` does it:

```text
tachyonc refactor context STATIC... --into middle::ctx::FnCtx --param cx [--shared]
```

- It makes a struct of the given statics, with their types and initial values
  as `FnCtx::new()`.
- It adds `cx: &mut FnCtx` (`&FnCtx` with `--shared`, when every function that
  reaches the statics only reads them) to every function that uses one of them
  directly or through its callees. This is `query callees --writes` computed
  backwards.
- It rewrites each `S` to `cx.s` and passes `cx` at every call.
- A call through a `fn` value on the way is an error that lists the calls.

It is useful beyond the compiler: agents' programs with statics. Applied:

1. **`FnCtx`, per thread:** the ~456 statics of middle, back and gen0 that are
   per-function by use (scratch arrays, work lists, the loop forest, range facts,
   register intervals, the emitter's frame and peephole state) plus the current
   function's tables (0.17's `ir_enter` becomes a field).
2. **`Program`, read-only:** everything a function reads that another phase made
   (`FN_ATTRS`, `FN_NOCAPTURE`, `FN_SIZE`, `FN_RT`, `FN_LIVE`, the inline store,
   types and layouts, symbol names, the target and options).
   - `Program::freeze()` moves these tables out of their statics
     (`std::take`) when the parallel phase starts. The workers get `&Program`,
     so no view of a static exists and 0.17's coarse `own.static` rule is
     satisfied without 0.17.1.
   - Anything that reads a frozen static by mistake finds it empty and fails a
     check in the suite, not silently.
3. **The proof.** The worker's entry is
   `#[effects(alloc(Gpa, Arena), panic, diverge)] fn codegen_function(p: &Program,
   cx: &mut FnCtx, f: i64) -> FnOutput`.
   - Effects are 0.16 features, so the source may use them.
   - The declaration is checked, so **the workers neither read nor write a
     static**: `global` would be an error.
   - Exclusivity (0.17) makes `&Program` read-only while it is lent.
   - The only claim the island itself makes is that each thread gets its own
     `FnCtx`.
   - The work is driven by `query effects codegen_function --why global` until
     the declaration holds.

**The schedule.**
- After the serial phases (§1.4), the work is a DAG.
- At -O2 a call-graph component (an SCC) is ready when the components it calls
  are optimized, because inlining needs them. Its functions are optimized in
  turn, then each is emitted on its own.
- At -O0 and -O1 every function is independent.
- Ready work is taken largest first, so that a big function does not start
  last on an efficiency core.

**Byte-identical output whatever the thread count:**
- **The inlining budget.** `PROGRAM_SIZE` is consumed in processing order, so
  it is replaced by budgets per component, computed before the parallel phase
  from the sizes before inlining. This changes output once, measured on bench
  and on code size; `same-output` covers the rest.
- **Labels are local to their function** (`.LF<fn>_<n>`, with the function's
  stable id), so joining needs no renumbering.
- **Constant data** (SROA's tables, strings) is recorded per function, then
  deduplicated by content at the join in function order. The first occurrence
  keeps the label and the others alias it.
- **Per-function flags** are ORed at the join: `PANIC_USED`, `ENUM_PANICS`, the
  `-g` records (`DBG_FNS`) and statistics.
- **Each worker also assembles** its function into bytes and relocations, so
  "data and output" is per function too. The join writes the functions in
  their order, as soon as each one is ready (a reorder buffer).

**The pool** (base/threads.tach) is the unsafe island over `pthread_create`,
`pthread_join`, a mutex and a condition variable: a queue of ready tasks,
`-j N` workers (all cores by default), and the main thread joining.
- `-j1` runs the same path with no thread.
- A compiler built with `--trace`, `--check-alloc` or `--check-unsafe` runs at
  `-j1`, because their runtimes are single-threaded until 0.21.

**Goals** (aarch64-macos, 4 performance and 6 efficiency cores):
- the -O2 self-compile from 1.82 s to at most 0.65 s at `-j10`, and no slower
  than 1.82 s at `-j1`;
- -O0 from 0.29 s to at most 0.20 s.

Amdahl's law, with 12% serial and efficiency cores worth about 0.4 of a
performance core, puts the limit at about 3.4×.

### 4.4 Incremental rebuilds

**The key.** Each function's output (§4.3's per-function bytes, relocations,
constants and flags) is cached under:
- the compiler's hash, the target and the options;
- a hash of the function's IR as it enters the per-function pipeline, after the
  whole-program phases;
- a **read set**: every value it read from `&Program`. `Program`'s accessors
  record each read (what, which id, a hash of the value) into `cx.reads` while
  the function is compiled.

**A hit.** On the next build an entry is valid when the IR hash matches and every
recorded read hashes the same as now. The bytes are then used as they are: no
optimization, no assembly. This is a verifying trace, as in Salsa or Bazel.

**Why it is sound.**
- The worker's checked effects say it reads nothing else: no `global`, only
  `&Program` and its arguments.
- §4.3's determinism says the output depends on nothing else. Addresses are the
  one risk (§9), and the gate checks for them.

**Storage.** `target/tachyonc-cache/` (beside the query cache, with the same
rules for when it holds): one pack file and an index per option set, compacted
to at most twice the program's code. `--no-cache` turns it off. It is on by
default when a `target` directory exists, as for the query cache.

**What a rebuild still does:** parse, check, lower and the whole-program phases
(about 210 ms on the compiler), hash every function's IR (estimated 20 ms), and
join.
- Goals: the -O2 self-compile with nothing changed at most 0.3 s (from 1.82);
  after editing one function, at most 0.4 s.
- A changed function's callers miss only if they inlined it or read a fact that
  changed.

**The same bytes as a clean build:** the gate builds clean and then
incrementally after random edits of K functions, and compares the bytes.

**For agents:** the compiler tasks (21–24) rebuild `target/tachyonc` before
every `tachyonc test` and `tests/run.sh`. Those rebuilds become sub-second.

## 5. Algorithms and their cost

**Checking clauses** (front/contracts/check.tach).
- **The AST.** A function's clauses are a `ContractList` node on its Fn
  (`FnInfo.contracts`), and a type's invariant one on the type.
- **Checking.** Each condition is checked as a `bool` expression in a scope with
  the parameters, plus `result` and `old` in an ensures.
  - Each `old(e)` becomes a hidden entry local, and its kind is checked.
  - The condition's effects come from 0.16's walk applied to a pseudo-function
    per clause, and must be pure.
  - Clauses are checked per instance, as bodies are.
- **Cost:** one walk per clause, which is nothing for programs without contracts.

**Desugaring, so the back ends change little** (front/contracts/desugar.tach). As
0.17 lowered drops as implicit defers, and f-strings straight to their writes,
clauses become checked AST before either back end sees them:

- **requires.** A direct call `f(a, b)` with clauses becomes `{ let __a = a; let
  __b = b; check(site, cond[i := __a, s := __b]); f(__a, __b) }`.
  - A condition that is small and has no call is put in place; any other
    becomes a call of a generated `f.requires(..) -> bool`.
  - If `f`'s address is taken, `f.checked`, the checking entry, wraps the body
    for indirect calls.
- **ensures.** Each return becomes `{ let __r = e; check(site, cond[result :=
  __r]); return __r }`, after the hidden `old` locals were set at entry.
- **invariant.** A check at each boundary return (§2.3).
- **`as` into a distinct type with an invariant,** and its arithmetic: a check
  of the result.
- **Shared by both back ends:** `ContractCheck` (site, condition, operand
  temporaries) lowers through `lower_check` with the kind `CONTRACT` and the site
  number. gen0 does the same. The runtime helper prints §2.4's line from the
  site table.

**The site table** (front/contracts/sites.tach, written by both back ends).
- One record per check site, of the new checks and of the existing bounds,
  unwrap and `as E` checks: about 16 bytes plus interned text.
- A generated `__site_values(site, block)` prints the operands with their Debug
  impls.
- Budget: +5% of a program's text and data. T5 measures it on the compiler and
  bench.

**Range facts** (middle/range.tach, middle/ipo.tach, T5).
- Requires conditions as entry facts, and ensures facts on call results (§2.5).
- The facts are indexed by value first, the open 0.17 item.
- Budget: -O2 self-compile instructions within +1%.

**Properties** (std/test.tach, T2).
- **The choice sequence** is a `Vec<u64>`. Generators draw from it, with sizes
  that grow with the case number.
- **The shrinker's passes:** delete chunks of 8, 4, 2 and 1 choices; set a
  choice to zero; halve it; swap neighbours into order.
- **Processes.** Passing cases run in one child process per batch. Each shrink
  candidate runs in a forked child: about 0.3 ms on macOS, so 1,000 candidates
  take about 0.3 s.
- **Time:** 100 cases of a small property take tens of milliseconds.

**Fuzzing** (middle/coverage.tach, std/fuzz.tach, T3).
- **Instrumentation:** one counter increment per critical edge, after the edges
  are split, at -O1.
- **The fork server:** one fork per input. Expect 2,000–5,000 executions per
  second on macOS, where fork dominates.

**Test runs.**
- An I/O case or `#[test]` costs one fork and exec per level.
- The -O0 build of a small program takes a few milliseconds.
- `tachyonc test` on a 300-line program with 10 tests and 2 properties is
  estimated at under 1 s at both levels.

**Compile time.**
- **Programs that use nothing new:** unchanged. The contextual words are tested
  only between a signature and `{`.
- **std's clauses** (about 150, T1) reach every program that uses std,
  including the compiler.
  - Budget: the self-compile within +1% in instructions, bench within noise.
  - The suite's run time within +3%.

## 6. Migration

**Programs.**
1. **0.17's legacy rule ends:** a `*T` parameter of a safe function is raw. The
   error steers to `fix --values` (rule 2, `&T` / `&mut T`), never to `fix --only
   unsafe` (iteration 10's lesson). 0.17's T7 already moved tests, examples and
   the eval solutions.
2. **New prelude names:** `assert`, `assert_eq`, `assert_ne`, `debug_assert` and
   `assert_snapshot`. A program's own item of one of these names shadows it, as
   for any prelude name.
3. **Run-time failure lines** gain a position and lose the `note:` line. Every
   expected stderr in tests/run, examples, the guide's examples and the eval
   tasks' checkers is regenerated with `tachyonc test --accept`, and the diff is
   read once (T5).
4. **`tachyonc test`** now runs at two levels and with `--check-alloc`. Cases
   that leak or differ between levels newly fail. In the tachyon tree,
   `tachyonc test FILTER` still runs tests/run.sh.
5. Nothing has `#[test]` today, so making those items test-only breaks nothing.

**Before 0.17 ships.** Every task is marked "can start now" or "needs 0.17"
in §7 ("When each task can start"): T1–T5, T8 and T9 start now; T6 and T7
start their 0.16-only steps now and do their `fix --values` passes after 0.17.

**std.**
- Clauses go on its public API: indexing-like methods, `insert`/`remove`,
  `unwrap`/`expect`, `split_at`, `parse_*` preconditions.
- Each std check that a requires now covers is deleted from the body, because
  the entry fact makes it redundant (T1). Messages keep their texts through
  `else`.
- `NonNull`, `std::test` and `is_null` are added.

**The compiler** (§4).
- **T6 (front, tools, base, guide, main) and T7 (middle, back, gen0) write their
  changes as scripts:** `refactor --script` files under docs/design/018-migration/.
  The steps are `fix --values` per module, `rewrite` for IntVec, `refactor
  table` and `refactor context`.
- **The scripts are replayed** on the integrated tree after the feature tasks
  merge (§7). This avoids hand-merging 95k mechanically edited lines against
  the feature branches.
- **Every step:** `same-output` against the Phase 0 compiler, and compile time
  in instructions retired within +2% per step. The arena and thread steps are
  expected to gain.

## 7. Phase 0, the parallel tasks, the merge order

### Phase 0, serial (the lead)

The interface commit: everything parses and checks, the suite passes, and
compiled programs' output is unchanged.

1. **Parser and AST:**
   - clauses on fns, trait fns and impl fns (front/parser/items), with `debug`
     and `else`;
   - `invariant` after structs and enums; `type X = distinct T [invariant ..]`
     (`parse_type_alias`);
   - the attributes `test`, `property`, `fuzz` and `cfg(test)`; `result` and
     `old`;
   - the assert family and the six bang spellings; `clone_node` for all of
     them.
   - `distinct` checks as a transparent alias until T4.
2. **front/contracts/, with fixed signatures:**

   | file | contents |
   |---|---|
   | mod.tach | `check_contracts()`, called by `check_program` after `infer_effects()`; accepts and ignores clauses |
   | desugar.tach | `desugar_call(n)`, `desugar_return(n)`, `desugar_boundary(f)` as no-ops |
   | sites.tach | `site_of(node, kind) -> i64` and the table |
   | diag.tach | the codes of §2.14 with stub `explain` entries |

3. **`lower_check` gains a `site` argument** in middle/lower/calls.tach and gen0.
   With 0 (none) the runtime prints exactly what it prints now.
4. **std:** std/test.tach (`Arbitrary`, `Gen`, `assert_snapshot`, with
   `panic("0.18 T2")` bodies) and std/nonnull.tach (`NonNull<T>` in the distinct
   form), with embed.sh's file list.
5. **Driver and tools:**
   - `--debug-contracts`, `--coverage` ("not yet") and `-j N` (1 only) are
     accepted;
   - `tachyonc test`'s new flags, `tachyonc fuzz` and `reduce`'s new modes are
     stubs whose errors name the task;
   - `query checks` is a stub.
6. **The compiler's names fixed for T6 and T7:** `base::Comp` and `base::Ast`
   (real, small); the empty structs `middle::ctx::FnCtx` and `middle::ctx::Program`,
   with `Program::freeze` as a stub; docs/design/018-migration/ with a README.
7. **Tests and docs:** tests/run/syntax018_*, tests/query/syntax018.q, a "0.18"
   skeleton in grammar.md, and this document.
8. **Acceptance:** `same-output` against night-final's compiler is identical;
   the suite passes; bench is within noise.

### Phase 0 contract (as built on b18-phase0)

Phase 0 was built on release-0.17 (0.16's compiler builds it), next to
0.17's phase 0 (c17-phase0) and 0.19's (a19-phase0), which will be merged
with it. So it changes the shared front-end files as little as it can:
everything it reads goes to side tables keyed by node (no field or kind
is added to the AST's `Node`), and each shared file gets one-line hooks.

**What phase 0 does.**
- The parser reads clauses, invariants, `distinct` and the test
  attributes (front/parser/clauses.tach) into front/contracts's tables:
  `CLAUSE_OWNER/KIND/COND/MESSAGE/POS` (`add_clause`, `clause_count`),
  `DISTINCT_ALIASES` (`mark_distinct`, `is_distinct`), `TEST_ITEM/KIND`
  (`add_test_item`, `test_kind`; TEST_FN, TEST_PROPERTY, TEST_FUZZ,
  TEST_CFG).
- `check_program` calls `check_contracts()` (empty) before
  `exit_if_errors`. Conditions are not checked: a clause's names are not
  resolved, and `query refs` does not see them yet.
- A distinct alias is a transparent alias; test items are compiled as
  ordinary items.
- `lower_check(.., site: i64 = 0)` and `emit_panic(kind, site: i64 = 0)`
  take a site (always 0, unused); front/contracts/sites.tach has
  `site_of` (returns 0) and the kinds.
- main reads `--debug-contracts`, `-j N` / `-jN` (kept in
  `front::contracts::flags::JOBS`, the compiler still runs on one thread)
  and `--coverage` (an error naming T3).
- `tachyonc test --accept|--cases|--seed|--no-contracts|--no-check-alloc|--fuzz|--gen`,
  `tachyonc reduce --differs|--fails|--test` and `tachyonc fuzz` print
  `error test.not-yet` / `reduce.not-yet` / `fuzz.not-yet` naming the
  task (tools/v018.tach).
- `explain` knows the five codes phase 0 prints or names (the `.not-yet` ones, `test.signature`, `test.generate`) (tools/explain/v018_table.tach;
  tests/refactor/run.sh wants every entry to be printed somewhere). The
  other codes of §2.14 are constants in front/contracts/diag.tach, and
  each task adds their entries when it starts reporting them (and the
  code's prefix to run.sh's list).
- `fmt` lays the syntax out (tools/fmt/clauses.tach, three hooks in
  layout.tach): clause lines continue the signature, a body's `{` after
  them is at the signature's level, the line after an `invariant` starts
  an item, `distinct *T` is a prefix `*`.
- std gains two lazy sections, loaded only when a program names them:
  `Testing (0.18)` (compiler/std/test.tach: `Arbitrary`, `Gen`,
  `assert_snapshot`, bodies that panic) and `Non-null pointers (0.18)`
  (compiler/std/nonnull.tach: `NonNull<T>` in the distinct form).
- The compiler's names: `base::comp::{Comp, Ast}` (zero-sized
  `impl Allocator`, on C's allocator for now) and `middle::ctx::{FnCtx,
  Program}` with `Program::freeze()`; docs/design/018-migration/.

**Left to the tasks** (said here so that nobody waits for phase 0):
- the assert family and the bang spellings go to **T1**: their prelude
  names would take the prelude past its 64 entries together with 0.17's
  `Drop`, `drop`, `forget`, `needs_drop`, `take` and `replace`
  (`PRELUDE_DECLARED: [bool; 64]` in front/modules/lookup.tach), so T1
  adds them after c17-phase0's merge, raising that bound;
- cloning a generic function's clauses into its instances (**T1**);
- leaving test items out of other builds, a test module's view of its
  parent, and `use super::*`'s `import.wildcard` error (**T2**, with T9's
  `fix`);
- `query checks` (**T5**: a new query command touches the query table,
  its help and the hook's tables);
- `&mut Gen`, `&Program`, `&mut FnCtx`: the reference types are 0.17's
  syntax, so phase 0 uses `*Gen` and no signatures yet.

**Per task: what it owns, its hooks, what it must not touch.**

| task | owns (new files are its own) | its hooks (already in place) | must not touch |
|---|---|---|---|
| T1 | front/contracts/{mod,desugar,diag}.tach (the tables' readers, `check_contracts`), the clause lines of compiler/std/*.tach, the prelude entries for the assert family, the bang spellings in front/parser/exprs.tach (`parse_primary`'s `at_macro_call` branch), tests/run/contract_* | `check_contracts()` in `check_program`; the parser's `parse_clauses`, `parse_type_invariant` | the table layout in front/contracts/mod.tach (add tables, do not change these), front/parser/clauses.tach's grammar (ask the lead), other tasks' std files |
| T2 | tools/testrun/*, front/tests/* (new), compiler/std/test.tach, tools/v018.tach's `test_option018`, tests/testcmd/* | `test_option018` in `test_inner`; `TEST_ITEM/KIND`; `at_cfg_test`/`parse_cfg_test_item` in `parse_top_item` | the parser's hooks (read the tables instead), main's option loop |
| T3 | middle/coverage.tach (new), compiler/std/fuzz.tach (new, a lazy section), tools/reduce.tach's program modes, tools/v018.tach's `run_fuzz` and `reduce_mode018` | `run_fuzz` in `run_command`; `reduce_mode018` in `reduce_inner`; `--coverage` in front/contracts/flags.tach | gen0 beyond one hook line; T2's harness (call it) |
| T4 | the distinct kind in front/types.tach, the operator and conversion parts of front/check, front/layout's niche, compiler/std/nonnull.tach, front/cimport's `_Nonnull`, tests/run/distinct_*, nonnull_* | `DISTINCT_ALIASES`; `parse_alias_target` | the clause tables (an invariant is T1's to check) |
| T5 | front/contracts/sites.tach, the `site` argument's use in middle/lower/calls.tach and gen0/target.tach (`emit_runtime`), middle/range.tach, middle/ipo.tach, `query checks` | `lower_check(.., site)`, `emit_panic(kind, site)`, `site_of` | the parser; the checker |
| T6 | base/comp.tach, front/tools/base edits by replayed scripts (docs/design/018-migration/front-*) | `Comp`, `Ast` | middle, back, gen0 |
| T7 | middle/ctx.tach, base/threads.tach (new), back/emit/join.tach (new), tools/refactor_ctx/ (new), middle/back/gen0 edits by replayed scripts (middle-*) | `FnCtx`, `Program::freeze`, `JOBS` | front; the files T5 owns until T5 has merged |
| T8 | back/codecache.tach (new), Program's read recording, tests/incremental/ | T7's Program | T7's schedule |
| T9 | tools/query (clauses in def/show/context), tools/fmt (with tools/fmt/clauses.tach), refactor's clause handling, fix's `--suggested` forms and the `use super::*` deletion, tools/explain/v018_table.tach's texts, compiler/guide/*, docs, tools/agent-hooks/check-after-edit.py, tests/agent-eval tasks | the explain table | the compiler's semantics |

### The tasks

| task | owns | consumes | provides |
|---|---|---|---|
| **T1 Contracts** | front/contracts/{check,desugar,old}.tach; the clause lines in compiler/std/{std,iter,io,alloc}.tach; tests/run/contract_*, err_contract_* | P0 | clause checking, purity, `old`/`result`, call-site requires with checking entries, ensures, type invariants and `contract.sealed`, `debug`, the assert family, `contract.violated` at compile time, std's clauses (and its redundant internal checks removed) |
| **T2 Tests and properties** | tools/testrun/*, front/tests/* (collection, the test entry, `cfg(test)` scoping), compiler/std/test.tach, tests/testcmd/* | P0; T1's assert (staged) | `#[test]`, harness, fork per test, parallel runs, check-alloc leaks, snapshots and `--accept`, the -O0/-O2 comparison, `#[property]` (generators, `Arbitrary`, shrinking, corpus), contracts as properties, `--against`/`--gen`, the summary format, `probe --test/--seed` |
| **T3 Fuzzing and reduce** | middle/coverage.tach, the gen0 hook, compiler/std/fuzz.tach, tools/reduce.tach and tools/reduce/*, tools/fuzzcmd.tach | P0; T2's harness and shrinker | `--coverage`, `tachyonc fuzz`, the fork server, the corpus, regressions in `test`; `reduce --differs/--fails/--test` over the edit engine |
| **T4 Distinct and NonNull** | front/types.tach (the distinct kind), the conversion and operator parts of front/check, front/layout (the niche), compiler/std/nonnull.tach, front/cimport (`_Nonnull`), tests/run/distinct_*, nonnull_* | P0 | §2.10 and §2.11, `distinct.*` codes, `is_null` |
| **T5 Checks: positions, optimizer** | middle/range.tach, middle/ipo.tach, gen0/target.tach's runtime, back's site table data, tools/query/checks.tach, bench | P0; T1's desugaring | the site table and §2.4's lines for every check, the expected-output regeneration, entry and result facts, indexed facts, `query checks`, `--print-checks`, identical-body folding |
| **T6 Compiler: front, tools, base on values and arenas** | scripts in docs/design/018-migration/front-*.txt; base/comp.tach; tools/refactor_table/ | 0.17.0; P0's names | §4.1: `Comp`/`Ast`, IntVec → Vec, `refactor table`, `fix --values` on front, tools and base, the release of `Ast` after lowering |
| **T7 Compiler: middle, back, gen0; threads** | scripts in docs/design/018-migration/middle-*.txt; tools/refactor_ctx/; middle/ctx.tach; base/threads.tach; back/emit/join.tach | 0.17.0 (0.17.1 optional); T5 merged before its replay | §4.2 and §4.3: `refactor context`, FnCtx and Program, `fix --values` there, per-function arenas and the inline store, the pool, the deterministic join, per-component inline budgets, `-j` |
| **T8 Incremental** | back/codecache.tach, Program's read recording (after T7's context step), tests/incremental/* | T7 step 1 | §4.4: keys, read sets, the pack, the gate's clean-against-incremental check |
| **T9 Tools, guide, eval preparation** | tools/query (def/show/context clauses), tools/fmt, refactor's clause handling, fix (`--suggested` forms, the deletion of `use super::*`), explain entries, compiler/guide/{contracts,testing,debug,errors,core,types}.md, docs/{grammar,query,refactor}.md, tools/agent-hooks/check-after-edit.py, tests/agent-eval tasks (§8) | P0 shapes; T1/T2 outputs | §2.14 |

**When each task can start.** Releases are pipelined: 0.18's tasks begin
while 0.17 is being built. The compiler/src that a task changes is built by
the previous release, and nothing below uses 0.17's syntax until 0.17 ships.

| task | start | why |
|---|---|---|
| T1 Contracts | **can start now** (before 0.17 ships) | clauses, desugaring, purity, messages and std's clauses need only 0.16; the `old(..)` kind rule and invariant checks at `&mut T` boundaries are finished after 0.17 merges |
| T2 Tests and properties | **can start now** | `Gen` is passed as `*Gen` until `&mut` exists; nothing else touches value semantics |
| T3 Fuzzing and reduce | **can start now** | independent of 0.17 |
| T4 Distinct and NonNull | **can start now** | "plain" is approximated by "no Vec, Buf, HashMap or Drop" until 0.17's kinds land |
| T5 Checks, optimizer | **can start now** | independent of 0.17 |
| T6 Compiler front, tools, base | **partly now**: `Comp`/`Ast`, IntVec → `Vec<i64, Comp>`, `refactor table` (0.16 features); **needs 0.17** for `fix --values` and the release of `Ast` | |
| T7 Compiler middle, back, gen0; threads | **can start now** with `cx: *FnCtx` / `p: *Program` parameters and the effects declaration (0.16); **needs 0.17** for the `&`/`&mut` signatures (one `fix --values` pass) | |
| T8 Incremental | **can start now**, after T7's context step | independent of 0.17 |
| T9 Tools, guide, eval preparation | **can start now** | |

**Task items and acceptance.**

- **T1:**
  - a case per clause form, at each of -O0, -O1 and -O2;
  - blame positions for direct, method, trait, generic and indirect calls;
  - purity errors with chains;
  - `old` of every kind;
  - invariants over `&mut self`, returned values and enums;
  - `contract.sealed`;
  - `debug` on and off;
  - std's clauses with byte-identical messages.
  - The stderr of each failing case is identical at every level.
- **T2:**
  - each summary line of §2.9 in a test;
  - a property finding the bug in tests/testcmd/ with a known shrink result;
  - leaks failing;
  - snapshots new, changed and accepted;
  - a planted -O0/-O2 difference (a test-only switch in the compiler) caught;
  - `--against` with a Python reference.
  - Timing: under 1 s for the 300-line case.
- **T3:**
  - the fuzzer finds a planted crash behind a 4-byte magic in under 30 s;
  - `reduce --differs` takes a planted miscompile from a 300-line generated
    program down to under 20 lines;
  - `--coverage` output is the same as without it, apart from the counters.
- **T4:**
  - every operator, conversion, literal and trait-inheritance case;
  - `distinct.*` errors with `try:` lines run by tests;
  - `Option<NonNull<T>>` is 8 bytes and passes C's ABI (abi fuzz mode);
  - `_Nonnull` imports.
- **T5:**
  - every check prints a position;
  - CHECK tests for entry facts (`median`), result facts (`table[h(x)]`) and
    std's removed double checks;
  - bench within noise, and -O2 self-compile instructions within +1%;
  - the site table within +5% of size.
- **T6 and T7:**
  - `same-output` identical after every step, except the one intended change
    (per-component inline budgets);
  - unsafe under 600;
  - no `static mut` left in middle, back and gen0 outside the island;
  - `codegen_function`'s effects declaration holds;
  - byte-identical output for `-j1`, `-j3` and `-j10` on the suite, examples,
    bench and the self-compile at every level;
  - §4.2 and §4.3's goals met, or the measured shortfall recorded.
- **T8:**
  - a hit gives byte-identical output;
  - 20 random edit sessions (by `edit patch`) give byte-identical clean and
    incremental builds;
  - §4.4's goals met.
- **T9:**
  - the guide's examples compile (`tests/run.sh guide`) and the core guide
    stays within budget;
  - tests/own-try's method (0.17) applied: every `try:` of §2.14 is run by a
    test;
  - the eval tasks of §8 pass `check-tasks`.

**Merge order.**
1. Phase 0.
2. T4, which changes what programs mean, and is small.
3. T1.
4. T5, which regenerates the expected outputs.
5. T2.
6. T3.
7. T9 throughout, with its final pass last.
8. T6's and T7's scripts replayed: T6 at any point after 5, T7 after T5 merged.
9. T7's thread step.
10. T8.
11. `bootstrap/gate.sh --quick`, plus:
    - a `--check-alloc` run of the suite;
    - `-j1` against `-j10` byte comparison;
    - clean against incremental comparison;
    - the bench gate.

std's `stdsrc.tach` conflicts are resolved by rerunning embed.sh. Each task
appends "Tn notes" here.

**T1 and T5 notes (branch b18-contracts).**
- *How clauses are made* (front/contracts/expand.tach): before the names
  are collected, a function with a `requires` gets a companion
  `f$pre(?site, <params>)` beside it (same module, impl, generics), and one
  with an `ensures` has its body moved to `f$body`, f calling it and
  checking `result` (`old(e)` are lets at entry). Being ordinary functions,
  they are instantiated, lazy in std and inferred like any other; nothing
  is cloned per instance by hand. A checked call of f becomes `{ let ?aI =
  argI; f$pre(SITE, ..); f(..) }` (desugar.tach; simple reads are read
  again, not bound). Both back ends lower `std::contract_check(COND, SITE,
  CHECK[, holes])` as a branch per `&&` conjunct to rt.panic.
- *Reports* (checks.tach): the integer operands of a comparison or call;
  other values are not shown yet (no Debug on the failing path). `else
  "m"` replaces the condition; `else f"..."` takes up to three integer
  holes, evaluated only on failure, which keeps std's old messages byte for
  byte. An ensures blames the clause's line, not the return's.
- *Sites* (sites.tach): one per position, (line, file << 16 | column) in
  rt.sites; rt.panic takes the site as a fifth argument and prints
  `FILE:LINE:COL: ` first. `--no-positions` makes every site 0. The `note:
  build with --trace` line is kept for now.
- *Measured* (aarch64-macos, instructions retired, -O2, against
  b18-phase0): bench within ±0.5% (sieve −1.2%); the -O2 self-compile
  +0.5%; the compiler's binary +3.1% (code and the site table).
- *Left for 0.18.1*: the checking entry for calls through fn values and
  trait objects (they skip a requires today), hence no entry facts in the
  callee and std's body checks kept; result facts in the caller; type
  invariants and `contract.sealed`; `contract.old`'s kind rule (0.17),
  `contract.violated` at compile time, `contract.impl-requires`, clauses on
  trait methods; `macro.args`; `query effects --why` naming a clause; the
  std body check behind `Vec::get`'s requires is not removed when the
  length goes through `as_slice` (`sub len, 0` of another type stops the
  ranges).

**The gate gains:**
- the level comparison over tests/run's programs as `tachyonc test` runs it;
- a fuzz mode (`-K`) whose generated programs carry clauses (the outcome must
  be the same at every level);
- the `-j` and incremental byte comparisons;
- `TACHYON_ARENA_SHUFFLE`, which randomizes the arenas' chunk addresses, so
  that any address-dependent output shows up as a byte difference.

**T4 notes** (b18-distinct).
- A distinct type is `TyKind::Distinct` (front/distinct.tach) while the
  program is checked; `erase_program_types` (front/check/distinct.tach)
  then writes its underlying type wherever the code generators read
  types (node types, fields, signatures, variants, statics, locals), so
  middle, back and gen0 never see one. Tools (QUERY) keep it.
- The inherited traits are std's `distinct_eq/cmp/hash/fmt/fmt_debug/clone`
  (clone.tach), called through `intrinsic_method` with `<X, T>`; an
  explicit impl wins. Generic distinct types have generic impls through
  `TPL_DISTINCT + alias` (`impl<T> NonNull<T>`, `NonNull::new`).
- The niche knows std's `NonNull` by its alias (std's module, that name),
  not by a `#[niche_null]` attribute: the parser takes no attributes on
  aliases yet. An enum has it with two variants, one without fields and
  one holding only a NonNull (`enum_niche`).
- `q as NonNull<T>` from a raw pointer is checked (chosen over making it
  `unsafe`: §2.10 says `as` into a type with an invariant checks it, as
  `n as E` does). It becomes `{ let p = q; if p as u64 == 0 { <panic> }
  p }`, failing with `null pointer made NonNull` (exit 101), a gen0
  runtime message (kind enum_panic_kind(-1)), so T5's sites give it a
  position and the range analysis may remove it. Without it, safe code
  could make a null NonNull whose `Some` reads back as None. T1's
  general invariant check may take it over.
- A `_Nonnull` result of a C function is not checked: the call is
  unsafe, and its caller vouches for what C returns (as for every other
  promise of a C signature).
- Field access through a distinct struct type is not offered (convert
  with `as`); `!` on a distinct bool is not either.
- Found on the way: an `extern "C" fn`'s result type `X<Y<Z>>` was a
  parser error (fixed in its own commit).

## 8. Measuring what it does for agents

The user asked that the benefit be measurable. No eval is run with this design.
This is the plan for the round after 0.18, using 0.17's method: cost × Rust,
binaries audited per run, 6 reps for Haiku cells (3-rep cells cannot separate
under about 15%), 3 for Sonnet.

| # | hypothesis | cells | measure | success |
|---|---|---|---|---|
| E1 | A contract violation names the line to change and its values, so bug fixes cost less | 07-fix-bugs and 17-debug-crash with the starter's functions given clauses (the same code otherwise) against the starters as they are; guide-mini+readfirst | cost × Rust; turns until the first edit of the faulty function; distinct run-time failures seen | cost −15% or more, and turns-to-the-fix halved, for both models |
| E2 | Tests in the language replace scripts and files | 01–06, 15 unchanged | per run: `Write` of `.in`/`.py` files, `run > run > run` chains, `#[test]`/`#[property]` written, `tachyonc test` calls | Haiku's run chains per run halved without a prompt change (D3/D5), or with one line in the loop |
| E3 | Failures far from their cause need the new facts | new tasks 25-deep-cause (a wrong value made in module A, a crash three calls later in module C; the Rust twin has the same checks as `assert!`) and 26-edge-case (a spec'd function with one edge case that properties find) | as E1 | tachyon at or below Rust's cost on 25 (Rust's asserts give no caller line) |
| E4 | No new cost on small tasks (D5) | 01, 03, 06 | cost × Rust against night-final's cells | within noise |

**`anatomy` gains:** contract and assertion failures seen per run, clauses and
tests written, `tachyonc test` calls and their summary lines, and probe calls
that follow a summary's `try:`.

The compiler tasks (21–24) gain contracts and tests only from 0.19, when
compiler/src may use them. In 0.18 they measure the incremental and parallel
rebuilds: wall time per run, and the build share of it.

## 9. Risks

- **0.17 is not built yet.** Value semantics is at its Phase 0. Every compiler
  step of 0.18 (T6, T7, T8) and the soundness of invariants depend on 0.17.0
  shipping as designed.
  - If 0.17 is late, 0.18's language and tool tasks (T1–T5, T9) can start on
    0.17's branch, but cannot release before it.
  - If inferred summaries slip, compiler/src uses V3's warnings.
- **The mechanical migration against the feature tasks.** T6 and T7 rewrite the
  same directories as T1, T3, T4 and T5. That is why the migration is replayed
  as scripts after those merge, not merged as text. A script step that no longer
  applies costs a day.
- **Determinism.** Output that depends on addresses (a hash table keyed by
  pointers, iteration order) would break the `-j` and cache byte equality, and
  the arenas change addresses. `TACHYON_ARENA_SHUFFLE` and the byte comparisons
  catch it. Order-dependent program state other than the inlining budget may
  turn up. Each piece found becomes per-function state joined in order.
- **The speedup** is bounded by the 12% serial part, the efficiency cores and
  the bottom-up schedule's critical path (deep call chains at -O2). 3× is the
  goal; the record says what was reached.
- **Runtimes that are not thread-safe** (`--trace`'s shadow stack,
  `--check-alloc`, `--check-unsafe`): the compiler runs at `-j1` when built
  with any of them, so the gate's instrumented builds are serial and slower.
- **Contracts' value to agents is unmeasured.** No agent wrote a contract or
  `#[pure]` in 516 runs (0.16). E1 measures fixing code that has contracts, not
  writing them. Contracts as properties (§2.7) are the bet that writing an
  `ensures` pays at once.
- **Code size and compile time from call-site requires.** A clause is
  duplicated at each call site. A condition that is not small becomes a call of
  `f.requires`, and std's clauses are measured (T1, T5).
- **Debug values on the cold path.** The site table and the generated
  `__site_values` grow binaries (budget +5%). Printing a value that cannot be
  shown (a large struct) is cut to 60 bytes.
- **Generated inputs.** Property and contract runs with growing sizes could
  allocate much or loop. Each case has a time limit, and a timeout is reported
  as `slow`, not as a failure. Contract properties skip functions with `io` or
  `global`.
- **Fuzzing on macOS** is fork-bound (a few thousand executions per second),
  enough for agents' minute-long runs, not for days.
- **Distinct types multiply instances** (`Vec<NodeId>` against `Vec<i64>`), so
  identical-body folding is needed before the compiler adopts them in 0.19.
- **`use super::*` in test modules** is an error (decision 8): agents who
  write Rust tests write it by habit, so it costs a turn per test module unless
  the check hook's `fix --suggested` removes it. E2 counts it.

## 10. Open questions, with recommendations

Taken as recommended (the user is away and said to proceed through 0.23); each
is listed again under "Decisions taken".

- **Q1. Contracts always on, with `debug` clauses for expensive conditions**,
  or a release switch. *Recommended: always on* (a violation is a check like any
  other; the no-UB principle; the range analysis and `debug` answer the cost).
- **Q2. Test syntax.** `#[test] fn` or Zig's `test "name" { }`. *Recommended:
  `#[test] fn`,* with `#[cfg(test)] mod tests` (D3, Rust habit). The roadmap's
  "test blocks" are these functions.
- **Q3. Requires checked at the call site, blaming the caller.** *Recommended:
  yes,* with a checking entry for indirect calls.
- **Q4. Distinct types keep T's operators and derivable traits but not its
  methods** (Go). *Recommended: yes.* Nim's opt-in borrowing is the
  alternative.
- **Q5. Non-null as std's `NonNull<T>`, built from `distinct` and an invariant,
  with `Option<NonNull<T>>` one pointer.** `*T` stays nullable. *Recommended:
  yes.*
- **Q6. The bang spellings of the six built-ins are accepted,** and `fmt` drops
  the bang. *Recommended: yes* (the familiar forms halved Haiku's name errors
  in 0.17).
- **Q7. The front end stays serial with its tables as `Vec<T, Comp>` statics;
  middle, back and gen0 move to `FnCtx`/`Program`.** *Recommended: yes.*
  A front end in a context is a later step, should the front end go parallel.
- **Q8. Test builds use `--check-alloc` and leaks fail a test.** *Recommended:
  yes,* with `--no-check-alloc`.
- **Q9. `tachyonc test` compares -O0 and -O2 by default.** *Recommended: yes*
  (it costs a few milliseconds per case on agents' programs, and it is the
  roadmap's built-in).
- **Q10. Every run-time check prints its position** (a site table, about +5%
  binary size), and the `note:` line goes. *Recommended: yes.*
- **Q11. Functions with `ensures` are tested as properties by `tachyonc test`.**
  *Recommended: yes,* with `--no-contracts`.
- **Q12. Loop invariants** (`while c invariant e { }`). *Recommended: not in
  0.18;* `assert` at the top of the body checks the same thing at run time, and
  the syntax waits for a verifier that would use it.
- **Q13. Type invariants as optimizer facts.** *Recommended: not in 0.18*
  (§2.5). They need the "inside its module" distinction in the IR.
- **Q14. The inlining budget per call-graph component** (an output change once,
  for determinism under threads). *Recommended: yes.*
- **Q15. Per-function IR arenas without 0.17.1:** the island resets 0.16's
  handle `Arena` unsafely. *Recommended: yes,* rather than wait.
- **Q16. `distinct` over owned or view types.** *Recommended: not in 0.18*
  (plain only). The cases for it (`type Name = distinct Buf`) need method
  forwarding.
- **Q17. An `implies` operator for clauses** (`ensures result.is_ok() implies
  ...`). *Recommended: no;* `!a || b` and `match` do it, and agents do not
  write it.

**Decided here** (not flagged; each can be revisited):
- the words are contextual: no new reserved words;
- conditions must be pure (no `alloc`, `io` or `global`);
- `old(e)` only of plain values, or of an explicit `.clone()`;
- an impl may add ensures but not requires;
- ensures sees the state before defers and drops;
- a type with an invariant refuses field writes and literals outside its module,
  and is checked at the module's boundary;
- `debug` clauses give no facts;
- properties use integrated shrinking over a choice sequence, and fuzz targets
  share the engine;
- the summary's `try:` is a `probe`, not an edit;
- the per-function output unit is the same for the join, the threads and the
  cache;
- the code cache lives beside the query cache, with the same validity rules.

### Critical files for implementation

- compiler/src/front/parser/items/mod.tach (`parse_type_alias`, the fn
  signature and attribute parsing) and compiler/src/front/check/mod.tach
  (`check_program`: where `check_contracts` runs, after `infer_effects`)
- compiler/src/middle/lower/calls.tach (`lower_check`, `lower_panic`: the site
  argument), compiler/src/gen0/target.tach (`emit_runtime`, `emit_panic`,
  `PANIC_USED`: the failure line) and compiler/src/middle/trace.tach (the frames)
- compiler/src/middle/range.tach (facts, `narrow_by_facts`) and
  compiler/src/middle/ipo.tach (`call_attrs`: result facts)
- compiler/src/tools/testrun/mod.tach (`run_program`, `run_case`,
  `put_failures`: the harness and the summary) and compiler/src/tools/reduce.tach,
  compiler/src/tools/probe/
- compiler/src/back/emit/function.tach (`emit_ir_functions`: the per-function
  pipeline that becomes the parallel schedule), compiler/src/middle/ir/
  (`ir_enter`, `ir_free_func`, `IRTables`), compiler/src/middle/inline.tach
  (`PROGRAM_SIZE`, `should_inline`)
- compiler/src/front/effects/infer.tach (`infer_effects`, SCCs: purity of
  conditions and the workers' declaration)
- docs/query.md "Speed: the cache" and compiler/src/tools/query/cache.tach (the
  code cache's neighbour)

## Decisions taken (for the user's review)

Taken as recommended on 2026-10-16 while the user was away. Each can be changed
later by a `fix` migration or a flag.

1. **Contracts are always checked** (exit 101). `debug requires/ensures/invariant`
   and `debug_assert` are checked only in test builds. There is no release
   switch (Q1).
2. **Clause syntax:** `requires` / `ensures` / `invariant` clauses between the
   signature and the body (after a type for invariants), with `result`,
   `old(e)` and `else "message"`. The attribute form is a guided error (§2.13).
3. **requires is checked at the call site and blames the caller;** a checking
   entry serves indirect calls (Q3).
4. **Facts from checked clauses only:** requires at the callee's entry, ensures
   on call results. Nothing is ever assumed (§2.5). Type invariants give no facts
   in 0.18 (Q13).
5. **One run-time failure line for every check,** with position, condition and
   values; the `note:` line goes (Q10).
6. **Assertions:** `assert`, `assert_eq`, `assert_ne`, `debug_assert` and
   `assert_snapshot` as prelude built-ins. The bang spellings of these and of
   `panic!`/`unreachable!` are accepted and normalized by `fmt` (Q6).
7. **Tests:** `#[test] fn` (Rust's form, not Zig's blocks), with `#[cfg(test)]`
   as the one accepted `cfg` (Q2).
8. **Test modules see their parent's items without any import.** `use
   super::*;` is not accepted, not even as a no-op (no wildcard imports is a
   standing user rule): it is `error[import] wildcard imports are not
   allowed`, whose help says test modules see the parent's items and whose
   `try:` deletes the line, applied by `fix --suggested` and `fix --only
   imports`. *Decided 2026-10-16* (coordinator, on the user's standing rule).
9. **Test builds use `--trace` and `--check-alloc`,** and leaks fail (Q8).
   `tachyonc test` compares -O0 and -O2 by default (Q9).
10. **Properties:** integrated shrinking; contracts with `ensures` are tested
    as properties by default (Q11); fuzz targets share the engine; tachyon's own
    coverage-guided fuzzer (no libFuzzer).
11. **`reduce` gains program modes** (`--differs`, `--fails`, `--test`) built on
    the edit engine.
12. **Distinct types are Go's defined types:** operators and derivable traits
    kept, methods not, literals convert, over plain types only (Q4, Q16).
13. **Non-null is `NonNull<T>`** (a std distinct type with an invariant, a null
    niche in `Option`, `_Nonnull` imported); `*T` stays nullable (Q5).
14. **No loop invariants and no `implies`** in 0.18 (Q12, Q17).
15. **The compiler:**
    - the front end stays serial, its tables become `Vec<T, Comp>` statics,
      and the syntax tree's arena is released after lowering at -O1/-O2;
    - middle, back and gen0 move to `FnCtx` (per thread) and `Program`
      (read-only, frozen out of the statics), proven race-free by a checked
      effects declaration (Q7);
    - per-function IR arenas, with an inline store for -O2;
    - 0.16's `Arena` handle if 0.17.1 has not shipped (Q15).
16. **Threads:** a pthreads island, `-j N` defaulting to all cores, the inlining
    budget per component (one intended output change, Q14), byte-identical
    output for every `-j`, checked by the gate.
17. **Incremental builds:** per-function output cached under the IR hash plus a
    verified read set, beside the query cache, on by default when `target/`
    exists.
18. **The compiler's migration is replayed scripts,** proven by `same-output`,
    not merged text.
19. **What 0.18 needs from 0.17** is §0's table: 0.18 waits for 0.17.0, and does
    not wait for 0.17.1.

### T2 notes (tests and properties, as built on b18-tests)

- **Where the test build is made.** front/tests reads the tokens after the
  modules' files are read (a hook in `load_modules`), so that std's lazy
  sections the generated code names are loaded: one `<test>` source per
  module with tests (or a type a property generates), in that module, so
  that private names resolve. The program's root `main` is renamed
  `__tachyon_program_main`; the made `main(argc, argv, gpa)` runs
  `--tachyon-test NAME` (or `--tachyon-list`). Each module on the way to a
  test gets a `pub fn __tachyon_tests(name, gpa) -> bool` dispatcher.
- **Generators are made, not derived by traits:** a parameter's type is
  turned into an expression (`std::gen_vec(g, |g: &mut std::Gen| ..)` for
  `Vec<T>`, tuples element by element, `[T]` an owned Vec lent); any other
  type goes through `std::arbitrary_of::<T>`, and a struct or enum of the
  program without its own `impl Arbitrary` gets a structural one in its
  module. Inputs are printed with `{:?}` when the type derives or
  implements Debug (tuples element by element), else `(no Debug)`.
- **Test items in other builds** are dropped after parsing in
  `compile_program` only: `check` and the queries see (and check) them.
  The lookup hook makes a `#[cfg(test)]` module see its parent's items
  (and its parent's imports) before the prelude.
- **The runtime** (std/test.tach, "The test runtime's implementation"):
  a property's cases each run in a forked child (stdout and stderr to
  /dev/null); the child tells the choices it used through a pipe. Sizes
  grow over 100 cases whatever `--cases` is, so -O0's 20 cases are -O2's
  first 20. A process that ends a test (a failed check) leaves through an
  exit handler registered after --check-alloc's, so its leaks are not
  listed after the failure; `test_exit` does the same for runner
  processes. Leaks of a `#[test]` are checked by the made code with
  --check-alloc (`gpa.live_blocks()`); properties are not leak-checked
  until 0.17's drops free their values.
- **The runner** (tools/testrun/program.tach): builds the program and the
  test binary at -O2 then -O0 (.tachyonc/test/O2, O0), runs every case
  and test as its own process, as many at once as there are processors,
  -O2's first (new snapshots are written then compared at -O0). A time
  limit at either level is not compared. `TACHYON_PLANT_MISCOMPILE` (a
  test-only switch: -O1/-O2 read the literal 12345 as 12346) is in the
  build key.
- **Left for 0.18.1:** `probe --test/--seed`, `--against CMD --gen CMD`,
  `test --fuzz S`, failing property inputs saved to a corpus (a property's
  failure is replayed from its seed: the summary's try: line), effects
  (no io, no global) as a condition for contracts tested as properties
  (it waits for T1's clause checks), the bang spellings in the summary's
  try: lines (T1), positions on every failure line (T5's site table).

### T3 notes (fuzzing and reduce, as built on b18-tests)

- **Coverage** counts blocks, not edges: every block of the program's IR
  functions as lowered (`&&` and `||` are blocks), into std's
  `COVERAGE_MAP: [u8; 65536]` (block k at k % 65536). It is done right
  after lowering, as --profile-generate's counters are, so the optimizer
  sees ordinary loads and stores (no new IR operation). -O0 is promoted to
  -O1. A program built with --coverage but no fuzz target gets an anchor
  (`__tachyon_coverage`) so that the map exists and the counters run.
- **The fuzzer** is in the test binary (std/fuzz.tach): one fork per run,
  the child's counters sent back through a pipe, AFL's count buckets,
  mutations over the input's bytes (bits, bytes, runs deleted or
  repeated, splices, the program's string constants). It found the
  crash behind a 4-byte magic in about 16,000 runs (10 s) on the M-series
  laptop (tests/refactor/fuzzcmd.t).
- **reduce's program modes** cut by the formatted layout (lines and their
  indentation: items, then statements with the lines under them), not
  through the edit engine: a candidate that does not build is simply not
  interesting. Halves, then single units, deepest last, to a fixpoint.
  The generated 428-line program of tests/refactor/reducecmd.t goes to
  12 lines in about 300 runs (11 s). Replacing expressions with literals
  and inlining calls (the design's other steps), several files, and
  candidates checked in-process are left for 0.18.1.

### Integration with 0.17 (as built on release-0.18)

The four branches were built before 0.17's value semantics; merging them
onto v0.17.0 settled these (each with a test):

- **Requires checks read in place.** A call's `{ let ?aI = arg; f$pre(..);
  f(..) }` passes the arguments to `f$pre` without a move (the own pass
  reads them), `f$pre`'s owned parameters get no drops and borrow what
  they bind (moving one is own.move_out), and the own pass sees through
  the block to the call (a borrowed copy, `v.get(i)` or its `.unwrap()`,
  keeps 0.17's meaning). tests/run/contract_values (--check-alloc).
- **`old(..)` and owned parameters (§2.1).** An ensures runs after the
  body: reading a by-value owned parameter there, or keeping a view in
  `old(..)`, is contract.old with its fix (`old(v.len())`,
  `old(v.clone())`, or a `&` parameter). The own pass would reject both
  too, with messages about generated names. tests/run/err_contract_old.
- **Distinct types are plain by 0.17's kinds.** Besides Vec, Buf,
  HashMap and slices, a reference (`distinct &T`: a copied loan the own
  pass would not see) and a type that owns by its Drop impl (known once
  the impls are, check_distinct_kinds) are distinct.kind. The own pass
  runs before the types are erased and takes every distinct type as
  plain. std's distinct Eq/Ord/Hash helpers take `&T`.
  tests/run/err_distinct_values.
- **NonNull** is `distinct *T`: a parameter of it is a value, not a
  legacy `*T` borrow, and dereferencing needs `as *T` in unsafe code. Its
  null check's message is a fixed message of the contracts' table (the
  enum checks and the contracts share the negative keys).
- **Generators take `&mut Gen`** (Arbitrary, Gen's methods, gen_vec and
  the rest, the generated code).
- **Property and fuzz cases are leak-checked**: the case's values are
  dropped after it, so a block allocated in the case and left is a
  failure listing that block (check_alloc_leaks_since).
- **The test runtime and the fuzzer are lazy sections** of std: lexed
  only by the test builds that name them.
- **One failure line**: the `note: build with --trace` line is gone
  (decision 5): `FILE:LINE:COL: message`, exit 101.

Left for 0.18.1: a leak's site names the generated `<test>` source, not
the property; facts from `ensures` at call sites (the contracts report's
list); `fmt` keeps the bang spellings of the assertions.
