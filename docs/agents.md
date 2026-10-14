# Notes: tachyon for agents

Ideas, not scheduled: candidates for the iterations between 0.10 and 1.0
(see [roadmap.md](roadmap.md), "Toward 1.0").

The premise: most code is written by agents now, so a language should be
designed for them as much as for people. What slowed agents down while
they built this compiler was rarely writing code. It was finding out what
code means, what else a change touches, and whether it is correct. And a
new language has a problem of its own: models know nothing about it from
training, so every agent learns tachyon from its context window. The
compiler has to be the teacher.

## 1. The compiler teaches the language

- `tachyonc guide`: a compact, version-matched reference sized for a
  context window (grammar, idioms, the std API). Done in 0.13: the core
  guide and topics, from `compiler/guide/`, every example tested.
- `tachyonc doc std::Vec`: documentation from the binary itself, never the
  wrong version from the web.
- Diagnostics that show the right form, not only what is wrong ("`extern
  fn` was removed in 0.4; write `extern "C" { fn ... }`").
- `tachyonc migrate --from 0.5`: mechanical rewrites across breaking
  changes, which so far have been done by hand at every release.

## 2. Ask the compiler instead of reading source

(Measured: [agent-tool-usage.md](agent-tool-usage.md) records how agents
actually read and searched tachyon's source while building it.)

A batch, token-efficient query interface (an LSP for programs, not
editors): `type-at file:line:col`, `callers f`, `refs Node::kind`,
`layout S` (offsets), `api module` (signatures and doc lines only, like a
generated header). Agents spend most of their tokens reading code to
answer small questions like these.

## 3. Semantic edits instead of text edits

`tachyonc refactor rename a::b::f g`, `move-item`, `add-param`,
`change-field-type`: done consistently across the whole program in one
call. Text edits are where half-applied changes come from.

## 4. Diagnostics as data

JSON output with stable error codes, exact spans and fix-its an agent can
apply verbatim. 0.5's multi-error recovery is the foundation.

## 5. Signatures that tell the whole truth

Effects (allocates, does IO, can panic, pure, captures nothing) inferred by
the compiler (0.6's attribute inference computes most of this), shown, and
optionally declared and checked; contracts (pre- and postconditions)
checked in debug builds. An agent reviewing a call should need the
signature, not the body.

## 6. Catch plausible-but-wrong code

Agent code is fluent and occasionally subtly wrong, so lean on the
compiler: no implicit conversions, exhaustive `match`, `Option` rather
than null, checked arithmetic in debug builds, and a safe story for
pointers: a checking mode that traps use-after-free and out-of-bounds
accesses at a source location, or a light ownership discipline. The bugs
met while building the compiler (writes into reallocated arrays, element
sizes written by hand, stale state) are of the kind such a mode catches
at once.

## 7. Verification in the language

`test` blocks, `#[property]` and `#[fuzz]` functions, snapshot tests,
differential testing between optimization levels as one command, and
automatic reduction of failing cases (`tachyonc reduce`). The machinery
that kept this project honest (the fuzzers, `tests/compare.sh`, the
fixpoint) as a feature every program gets.

## 8. Fast, reproducible feedback

A check that answers in milliseconds, a watch mode, and builds that are
deterministic and byte-reproducible (they already are; it is what made
`tests/compare.sh` possible).

## 9. Performance you can ask about

Optimization remarks as data: "not inlined: cost 140 > 75", "bounds check
kept: length unknown", "loop not vectorized: possible alias", so code can
be tuned against reasons instead of by trial.

## 10. Many agents at once

The worst merge of 0.4 was semantic, not textual: one branch made a
slice's length `i64` and silently disabled an optimization written in
another. Explicit module interfaces, an `api-diff` that reports changes
other modules rely on, and whole-program checking fast enough to run on
every merge.

## 11. Surface style

One canonical formatter without options (minimal diffs); regular,
unambiguous syntax with one way to do each thing; explicit types at
function boundaries, inference inside; no dependence on declaration order.
For agents ambiguity costs more than verbosity.

## Later: a compiler server (MCP, then LSP)

`tachyonc serve`: the program kept resolved in memory and re-checked
incrementally, so queries and edits answer in milliseconds instead of a
35 ms re-check each; its tools (query, edit, check, fix, refactor) typed,
over MCP for agents and later over LSP for editors, one core for both.
Keep the tool set small (its schemas sit in every agent's context) and
keep the CLI for one-off calls. Not a language model inside the compiler:
its answers must stay exact and reproducible, and the caller is already a
model. Fuzzy questions ("where is X handled?") could get an optional,
clearly approximate semantic search outside the build, if the tool-usage
log (`# no-query:` reasons) ever shows demand for it.

## If only three

The compiler as teacher (1), the query and refactoring interface (2, 3),
and verification as a language feature (7): they answer the three
questions that took agents' time here: what the language is, what the
program is, and whether a change is right.
