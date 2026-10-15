# middle: the optimizer (-O1, -O2)

The checked AST lowered to an SSA IR, then optimized
([docs/optimizer.md](../../../docs/optimizer.md)). `opt.tach`'s
`optimize_program` is the pipeline: the scalar passes per function
(`simplify_function`: SCCP and instruction combining, SROA and constant
slots, CFG simplification, GVN, dead code), and at -O2, per function in
call-graph order, tail recursion elimination, inlining and the loop
passes (`optimize_loops`: rotation, induction variables and unrolling,
ranges, the vectorizers, strength reduction and unswitching, aggressive
DCE), then LICM and scalar promotion, each followed by the scalar passes
again. `back` takes the optimized IR.

| module | |
|---|---|
| `ir/` | the IR: functions, blocks, instructions, slots; terminators and edges (`cfg`), printing (`print`), the verifier (`verify`) |
| `lower/` | the AST to IR, building SSA on the fly (`ssa`): expressions, calls, control flow, `match`, vectors |
| `opt.tach` | the pipeline; CFG cleanups, dominators, dead code |
| `fold.tach` | constant folding, SCCP, instruction combining |
| `gvn.tach` | global value numbering, alias analysis, memory forwarding, dead stores |
| `egraph.tach` | rewrite rules by equality saturation, inside GVN |
| `sroa.tach` | scalar replacement of aggregates, constant tables |
| `copies.tach` | copy elision: a slot copied once into another (or a field of one) is that part (0.14) |
| `tags.tach` | jump threading on constant tags: `match it.next()` once `next` is inlined (0.14) |
| `exits.tach` | loops with several counted exits made counted loops; equal induction variables merged (0.14) |
| `adce.tach` | aggressive dead code elimination over control dependence |
| `inline.tach` | inlining over the call graph's components |
| `ipo.tach` | interprocedural attributes, constant propagation, devirtualization, heap to stack |
| `tre.tach` | tail recursion elimination |
| `loops.tach` | the loop forest, canonical form, LCSSA, the SSA updater, cloning, rotation |
| `scev.tach` | induction variables, trip counts, exit values, unrolling |
| `range/` | value ranges: bounds checks, comparisons, jump threading (`thread`), phis (`phi`), chains to switches (`chains`) |
| `ifconv.tach` | if-conversion in innermost loops: small branches become selects (0.15) |
| `vectorize/` | the loop vectorizer: legality, checks, the vector loop (`build`), outer loops, run-time unrolling (`unroll`) |
| `slp.tach` | the SLP vectorizer: stores to a vector's lanes |
| `lsr.tach` | loop strength reduction, unswitching |
| `licm.tach` | loop-invariant code motion |
| `promote.tach` | scalar promotion of memory in loops |
| `profile.tach` | `--profile-generate`, `--profile-use` |
| `unsafecheck.tach` | `--check-unsafe`: unsafe code's accesses checked at run time |
