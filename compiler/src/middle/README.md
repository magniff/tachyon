# middle: the optimizer (-O1, -O2)

The checked AST lowered to an SSA IR, then optimized
([docs/optimizer.md](../../../docs/optimizer.md)). `opt.vl`'s
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
| `opt.vl` | the pipeline; CFG cleanups, dominators, dead code |
| `fold.vl` | constant folding, SCCP, instruction combining |
| `gvn.vl` | global value numbering, alias analysis, memory forwarding, dead stores |
| `egraph.vl` | rewrite rules by equality saturation, inside GVN |
| `sroa.vl` | scalar replacement of aggregates, constant tables |
| `copies.vl` | copy elision: a slot copied once into another (or a field of one) is that part (0.14) |
| `tags.vl` | jump threading on constant tags: `match it.next()` once `next` is inlined (0.14) |
| `exits.vl` | loops with several counted exits made counted loops; equal induction variables merged (0.14) |
| `adce.vl` | aggressive dead code elimination over control dependence |
| `inline.vl` | inlining over the call graph's components |
| `ipo.vl` | interprocedural attributes, constant propagation, devirtualization, heap to stack |
| `tre.vl` | tail recursion elimination |
| `loops.vl` | the loop forest, canonical form, LCSSA, the SSA updater, cloning, rotation |
| `scev.vl` | induction variables, trip counts, exit values, unrolling |
| `range/` | value ranges: bounds checks, comparisons, jump threading (`thread`), phis (`phi`), chains to switches (`chains`) |
| `ifconv.vl` | if-conversion in innermost loops: small branches become selects (0.15) |
| `vectorize/` | the loop vectorizer: legality, checks, the vector loop (`build`), outer loops, run-time unrolling (`unroll`) |
| `slp.vl` | the SLP vectorizer: stores to a vector's lanes |
| `lsr.vl` | loop strength reduction, unswitching |
| `licm.vl` | loop-invariant code motion |
| `promote.vl` | scalar promotion of memory in loops |
| `profile.vl` | `--profile-generate`, `--profile-use` |
| `trace.vl` | `--trace` (0.17): a shadow stack of frames, each at the statement its function runs; failures and fatal signals print it |
| `unsafecheck.vl` | `--check-unsafe`: unsafe code's accesses checked at run time |
