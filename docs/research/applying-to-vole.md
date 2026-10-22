# Applying the research to vole: a ranked plan for the 0.17 cycle

Companion to [agent-language-design.md](agent-language-design.md) (the
literature and our evidence, by question). This document looks at
vole as it is on 2026-10-15 (AGENTS.md, the guide, the tools, the
hooks, the eval harness, the 0.17 design on branch design-017b, the
roadmap) and at what the agents actually did in tonight's 0.16 runs, and
proposes changes ranked by expected effect per unit of cost, each with
the evidence, the exact change, how to build it and how to measure it in
a focused rerun. Numbers from tonight are medians over the finished runs
of a round that was still in progress (282 runs: Sonnet on all 18
program tasks, Haiku on 13-18, both models on the four compiler tasks;
Haiku 01-12 and the check-hook conditions not yet run). Expected effects
are estimates from the literature's effect sizes and our own anatomy;
none is measured until the rerun says so.

## 1. Vole as the agent sees it today

**AGENTS.md** (2,016 words). One paragraph on the layout, then "Read
source through the compiler": a 45-row table of `query`, `edit`,
`refactor`, `rewrite`, `fix`, `fmt`, `explain`, `guide`, `try`, `batch`
forms, then the hooks' rules, the feedback command, the inner loop and
conventions. In the compiler tasks this costs 4.7k tokens per turn
(first-turn prompt 16.6k against 11.9k in the plain condition). The
first row is `query context`, phrased as a table cell ("an item with
what it calls, its types and callers, in one answer"), not as an
instruction. The table's wording is "ask volec instead of reading
files"; the guide's tools topic says the opposite for small files ("a
small program is cheaper read whole, once"), and the query-first hook
enforces the table.

**The guide** (`volec guide`, from compiler/guide/*.md; 19 topics,
~28k words). The core topic is 7,108 tokens and is what the eval inlines
in `guide` and `both`: build and run, a 20-row Rust-habits table, values,
functions, structs and match, generics, modules, slices, std (with the
whole std API listing, generated), input, unsafe, a 16-row first-errors
table, a 14-line tools block, the topic list. Every example compiles and
runs under `tests/run.sh guide`. The std topic (8k tokens) holds the API
again. The "what differs" content is carried by two rule tables, each
row a Rust form and a vole form; the examples are separate blocks.

**The tools.** `query` has 20 subcommands; `edit` 7 forms plus `apply`;
`refactor` 11; `rewrite`; `fix` with 8 kinds; `fmt`, `lint`, `try`,
`batch`, `explain`, `guide --find`, `undo`. Every problem is one line with
a stable code and `try:` lines; every edit is atomic and checked;
`--budget` defaults to 8,000 tokens (`context`: 2,000). Not there: a
`test` command (0.18 on the roadmap), editing std by name
(tool-gaps-016 item 2), `fix --only imports` for bare variants (item 1).

**The hooks.** `query-first.py` blocks shell reads of `.vl` source
(grep, sed, head, cat, awk...) and shell rewrites, suggests the query,
logs escapes; `check-after-edit.py` runs `check --json` after every
Write/Edit of a `.vl` file or writing `volec` command, prints up to
10 errors sorted edited-file-first, 35-50 ms median on the compiler
tonight. No turn-end check, no delta, no tests.

**The eval harness.** 18 program tasks (write, fix, extend, refactor,
perf) with Rust twins and hidden tests; 4 compiler tasks (optimize,
refactor, fix, feature) graded by the suite and `grade.sh`; conditions
bare/guide/tools/both/rust and compiler-tools/plain; `--check-hook`;
per-run `result.json` with tokens, turns, `tool_calls_by_kind`,
denials, `final_check`, hook records; a report with medians and tool
share. Not recorded: turn anatomy (lookup / edit / verify / re-read),
error classes per check, Rust-habit tags, deleted tests or assertions,
edit-failure recovery, hallucinated names; `check-tasks` validates that
solutions pass and starters fail, not that solutions are idiomatic.
About one Bash call in ten is refused by the permission layer (`$var`,
`&&` chains, heredocs) in every condition including Rust; the agents
recover but the refusals add turns and the tools condition suffers most
(Sonnet `both`: 34 denials against 14 bare, because `edit replace NAME
< file` and `cat > f <<EOF` are heredocs).

**The 0.17 design** (docs/design/value-semantics.md, branch design-017b).
Value semantics with inferred, level-aware view summaries; §2.9 "What
agents see" fixes a contract: one-line `own.*` diagnostics with `help:`
and tested `try:` lines, `query own` and `query views`, six situations
with their messages. The prototype measured the first version against
7,413 functions and found the one rule that rejected agent-written
parsers (13 of 379 eval functions), then replaced it; the pending
section waits for tonight's findings.

## 2. What the agents did tonight

**Sonnet, program tasks** (180 runs, 100% success in every vole
condition). With the guide, the typical easy run is four to six calls:
`Write main.vl`, `Write` an input, `volec main.vl -o prog &&
./prog < in`, a Python generator for a large case, done. The first edit
comes at call 2 (with the guide) against call 6 (bare, or Rust: the agent
reads the starter first). Hard tasks: 11.5-12.5 turns, exactly Rust's
12.5; cost 1.4-1.5x Rust, and the difference is the 26.5k-token prompt
against 11.2k (the guide is read on every turn, 87-90% of input tokens are
cache reads). Without the guide (bare), Sonnet reads it itself: `volec
guide` 23 times, `guide std` 8, `--find` twice, in 54 runs; turns double
(13 vs 5.5 easy; 20.5 vs 12.5 hard) and cost lands where `both` is. In
`both` Sonnet uses the tools it is told about: `volec edit` 112 times
in 54 runs, `refactor` 22, `check` 25, `query` 8 (`show` 6, `items` 2),
`fix` 4; the hard tasks' tool share is low because the file is new and
the agent writes it whole. Errors met: 1.1 (guide) to 2.1 (both) distinct
per run; `non-exhaustive match`, `unknown module`, `unknown type`, `no
method`, `calling a C function is unsafe`, `duplicate function` (a
Python text-splicing script that inserted an item which already
existed, caught by the next check), `cannot infer type parameter`.
The one Rust failure (18-api-refactor rep3) failed the structural check
after a `sed`-driven refactor: the same class of risk `refactor` removes.

**Haiku, hard program tasks** (54 runs; 17/18 with the guide, 18/18
bare and Rust). 25-41 turns; verification dominates: `./prog < input`
19 times per `both` run, `cmp`/`diff` 4-7, Python generators 4-5; it
writes test inputs, expected outputs, generators, and a scratch
directory, and loses calls to refusals (3.5 per run in `both`). With the
guide in the prompt it still ran `volec guide TOPIC` 32 times in 18
runs (`syntax`, `memory`, `closures`, `allocators`, `types`); 15-multi-
module took 4.8-6.2M input tokens per run and the failed rep was one
wrong output on one test after 61 turns.

**Compiler tasks** (48 runs, 100% both ways). Sonnet with the tools:
`refactor rename` + `refactor move` + `same-output` solved 22-refactor-
rename in 10-12 turns and 127k tokens against 23-25 turns and 341-437k
with grep/sed/perl and hand-edited `use` lines. On 23-fix-checker the
plain agent `cat`'d the 400-line file and patched (8 turns, 136k); the
tools agent was blocked on its `grep`, ran `query items` and two `query
show` calls naming 15 functions, hit one `patch.no-match`, and finished
in 12 turns and 225k. On 24-std-method the hook blocked `grep -n "pub fn
trim" compiler/std/std.vl`; the agent escaped with `# no-query: need
line in std.vl for Edit tool` (five escapes, all this), because
`edit insert --after std::trim` is refused (`edit.not-source`); it then
did what the plain agent did, plus the reading. Haiku with the tools ran
155 `query` calls in 12 runs (`show` 62, `refs` 25, `items` 22, `grep`
19, `def` 13, `text` 12) and 24 `refactor`; its fix and feature runs
cost twice the plain ones. `query context`: 0 calls in 282 runs; `batch`:
0; `--budget`: 16.

**The hooks in the runs.** check-after-edit: 2 checks per Sonnet run,
6.5 per Haiku run, 12 and 38 with errors, 35-50 ms each. query-first:
15 blocks in Sonnet's 12 tool runs, 7 in Haiku's; the blocked commands
are mostly compound lines where one segment reads source (`grep -n
... compiler/std/std.vl; sed -n 60,110p compiler/guide/std.md; ls`),
including lines that also ran a `query`.

## 3. The ranked plan

Ranking is by expected cost reduction or success gain per unit of build
cost, on the evidence. "Effect" is a prediction to be tested, with the
reasoning; "Measure" names the cells of the rerun matrix in §4 and the
number that confirms or refutes.

### 1. A 2k-token core guide, examples first; the rest on demand

**Evidence.** A ~2.1k-token syntax sheet is the best accuracy-per-token
intervention on record (GPT-5 4.8 to 50.4% on Cangjie) and beats raw
retrieval at similar cost [Cheng 2026]; in-context material saturates
around 3k tokens [Dutta 2024]; snippets beat rules and rules alone can be
net negative [Kumar 2026; Giagnorio 2025]; small models pay for every
token [Du 2025] and need demonstrations [Patel 2024]. Ours: the guide
halves Sonnet's turns and is also the whole cost premium on easy tasks
(2.1x Rust at parity of turns and near-parity of output tokens); Haiku
re-reads topics it already has.

**Change.** Split `compiler/guide/core.md` into:
- `core` (target 2,000 tokens, hard cap 2,500, checked by a test): build
  and run (5 lines); "what differs from Rust" as 15-18 *paired lines*,
  each `// Rust: String s = ...` / `let s: [u8] = ...;` inside one
  compiled example block, not a table; the five errors agents meet most
  (match exhaustiveness, unsafe around C and raw pointers, unknown
  type/module from Rust's std, `[u8]` vs `String`, `Vec::new_in(gpa)`)
  each with its one-line fix; a std list of the 20 items the eval
  solutions use most, one usage line each (`read_stdin_in(gpa)?`,
  `Scanner::new(s)`, `v.push(x)`, `m.get_or_insert(k, 0)[0] += 1`,
  `sort(v.as_slice())`, `format_in(f"..", gpa)`); the loop
  (`volec check`; the hook; `volec try`; `guide TOPIC` and `guide
  --find`); the topic list in one line.
- The rest of today's core becomes `guide language` (the long form) and
  the std API listing stays in `guide std`.
- `volec guide` prints the 2k core; `guide --full` the old one. The
  eval's `guide` and `both` conditions inline whatever `volec guide`
  prints, so the condition is the binary's.
- Every rule row that survives carries the snippet that exercises it
  (Wang 2023's minimal-grammar effect); no row without code.

**Effect.** Sonnet, easy tasks: input tokens down by roughly the prompt
difference times turns (26.5k to ~13k per turn, 5-6 turns: 142k to
~70-80k; cost 2.1x to ~1.3x Rust) if turns do not rise; hard tasks: from
1.5x toward 1.2x. Risk: turns rise as the agent fetches topics; the
literature says lookups cost less than carrying the text (bare costs about
what both costs today, with double the turns), so the net should still be
positive. Haiku: fewer re-reads and, if the 0.13 pattern holds, no loss
of success; the one place a success change is plausible.

**Cost.** Two to three days: the rewrite, a token-count test, the
guide examples re-run, the eval prompt unchanged.

**Measure.** Programs 01-18, Sonnet and Haiku, conditions `guide-2k`
against `guide` (today's 7k) against `rust`, 3 reps; metric: median input
tokens and cost per run, turns, success. Confirmed if input tokens fall
by at least 30% on the easy tasks with turns within one of today's and
success unchanged; refuted if turns rise by more than three or any task
loses a rep that `guide` passes. Also: `volec guide` calls per run
(expect up from 0.1 to 1-2 for Sonnet) and which topics are fetched (they
name what the core lacks).

### 2. Tier AGENTS.md: an eight-row core, the catalogue on demand

**Evidence.** Context files cost 20-23% and 2.5-3.9 steps with success
flat; the content that transfers is tool instructions the agent would not
know; overviews do not help [Gloaguen 2026]. Tool catalogues over ~10k
tokens or 10+ tools pay for deferral [Anthropic 2025]; long tool context
lowers willingness to call tools [OSWorld-MCP 2025]; doc length helps to
~600 words then hurts [Hsieh 2023]; selection follows an assertive
sentence and position, not row count [Tool Preferences 2025]. Ours: 45
rows cost 4.7k tokens a turn; Sonnet used six query forms, Haiku seven;
`context`, `batch`, `impact`, `deps`, `stats`, `conflicts`, `wrap`,
`split`, `new-module`, `move-module`, `inline`, `extract-function` were
not used once in 48 compiler runs.

**Change.** Replace the table in AGENTS.md with:

```
## Read and change source through the compiler

The compiler answers questions about the program and makes checked
edits; `volec check` runs by itself after every edit (the hook).
Use these first:

| you want | run |
|---|---|
| an unfamiliar item: its source, callers and what it calls, in one call | `target/volec query context NAME` (replaces show + refs + def) |
| the source of an item; a whole small file | `target/volec query show NAME`; `query show FILE.vl` (a file under 300 lines is cheaper read whole) |
| every use of a name | `target/volec query refs NAME` (`--count`, `--in FILE`) |
| change a few lines of an item, checked | `target/volec edit patch NAME --old 'TEXT' --new 'TEXT'` |
| replace, add, remove an item | `target/volec edit replace|insert|delete NAME` (`< text`) |
| rename, move, change a signature, field or variant everywhere | `target/volec refactor rename|move|signature|field|variant ...` |
| missing imports, `pub`, `unsafe` blocks | `target/volec fix` |
| build and test what a change touches | `target/volec test FILTER` (§3) |

Everything else (`query grep|items|type|effects|impact`, `edit apply`,
`rewrite`, `refactor extract-function|inline|split`, `batch`, `undo`):
`target/volec --help`, `volec CMD --help`, or `explain CODE` on
any error. The full table is docs/query.md and docs/refactor.md.
```

Keep the hooks' paragraph (short), the inner loop and conventions. The
first row is the imperative `query context` line with its one example;
that is the one promotion the literature supports (naming raises use
1.6-2.5x per instance; an assertive line 4:1). If a rerun still shows 0
uses, drop the row rather than keep advertising it.

**Effect.** Compiler tasks: input tokens -10 to -20% on Sonnet (the 4.7k
per turn over 14 turns is 66k of 269k), the same on Haiku; the fix and
feature overhead (1.45-2.3x) shrinks but does not vanish (its larger
part is the hook and the std edit, items 4 and 6). Success unchanged.

**Cost.** Half a day for the text; `check-tasks` already fails if the
plain variant still names the tools, so the plain-condition generator
needs its matching change.

**Measure.** Compiler tasks 21-24, both models, `compiler-tools-core`
against `compiler-tools` against `compiler-plain`, 3 reps; metric:
median input tokens and turns per task, tool share, `query context`
calls. Confirmed if tokens fall on 23 and 24 with 22's advantage kept
(tools/plain on 22 stays under 0.4); refuted if 22 loses its advantage
(the agent no longer finds `refactor`).

### 3. `volec test`: one verification command with a summary, in the hook

**Evidence.** Test feedback beats compiler feedback for repair (57.9 vs
49.2 repair@1) and the mix with a hint beats both (63.6) [FeedbackEval
2025]; validation share predicts success [Mehtiyev 2026]; one composed
action beats several [Wang 2024]; concise-by-default responses with a way
to get the rest [Anthropic 2025]. Ours: Haiku spends 11-16 calls per hard
run on verification it builds itself (`./prog < in`, `cmp`, Python
generators, `diff` of its own expected files) and loses calls to refusals
doing it; Sonnet chains `build && ./prog < in` and `tests/run.sh a | tail;
tests/run.sh b | tail`; the roadmap has `volec test` in 0.18.

**Change.** Pull a first `volec test` into 0.17, two shapes:
- a program: `volec test [ROOT] [--dir tests]` builds and runs
  `tests/NAME.in` against `tests/NAME.out` (the eval's own convention and
  the one agents invent), prints `N passed, M failed; first failure:
  NAME (line 3: expected "x", got "y")`, `--full` for everything,
  `--keep` for the outputs; with no tests directory: builds, runs the
  program on `--input FILE` or stdin, prints exit status and output size;
- the compiler: `volec test FILTER...` is `tests/run.sh FILTER` with
  the summary line first and the failed cases' first lines, `--full` for
  the table (the agents already `| tail` it).
- The check hook, after an edit that checks clean, runs the tests that
  name the edited file's module when they exist (`tests/run/*FILTER*`
  for the compiler's own source is too broad; start with the program
  case and with a `tests/map` of module to filters for the compiler) and
  appends the summary line to the same `additionalContext`. Debounced:
  not twice within 30 s for the same root unless the error set changed.
- Diagnostics delta as the headline: `check: 2 errors -> 0` / `check: 1
  new error in gvn.vl` (the hook keeps the last error set per root in
  its log).

**Effect.** Haiku, hard tasks: verification calls from 11-16 toward
Rust's 8, denials down (fewer `&&`/`$var` lines), turns -15 to -25%.
Sonnet: a few calls per run. The literature's repair ordering says the
test summary in the hook is the single upgrade most likely to move a
failing run to success; our runs are at the ceiling, so measure cost.

**Cost.** Two to four days: the command over the existing runner, the
hook's call, the debounce and delta, a walkthrough test.

**Measure.** Programs 13-18 and compiler 21-24, both models,
`both+hook+test` against `both+hook` (the planned check-hook condition)
against `both`; metrics: verify calls per run (`run`, `cmp`, `diff`,
`python3` kinds), denials, turns, cost; `final_check` errors left.
Confirmed if verify calls and denials fall by a third on Haiku with
turns down; refuted if turns do not move (then the agents distrust the
summary and still run the program themselves, and the output needs to
show the failing diff).

### 4. The hooks: unblock whole-file reads, parse per command, check at turn end

**Evidence.** The three largest SWE-agent ablation effects are output
bounds, not tool existence [Yang 2024]; reading a whole file is right
when the file is small (our own tools topic says so); Hermes checks once
at turn exit rather than per edit [harness study 2026]; per-edit returns
plateau by round 2-3 [FeedbackEval 2025; Kiecker 2026]. Ours: every
query-first block tonight was a compound line, several with a query in
them; on 23-fix-checker the plain agent's `cat` of one 400-line file beat
the tools agent's items+show+show; the five escapes were all "need a line
number for the Edit tool" (item 6 fixes the cause).

**Change** to tools/agent-hooks/query-first.py:
- judge each simple command, and block only when the reading segment
  reads compiler source; a line with a `volec query` in it is not
  blocked for its `ls`;
- allow `cat`/`sed -n`/`head` of a `.vl` file under 300 lines (one
  `wc -l`), and say so in the message when blocking a larger one: "FILE
  is 1,240 lines: `query items MODULE` lists its items, `query show NAME`
  one of them, `query show FILE:LINE` the item at a line";
- the blocked message's `try:` must be a complete command the agent can
  run as is, and the hook's log should record it (today's `blocked`
  records carry the command but not the suggestion, so the eval cannot
  tell whether the agent followed it);
- a `.vl` file the agent itself wrote under a scratch or probe
  directory is not source (tool-gaps-016 item 11): tonight's blocks
  include `head -6 scratch/diff.vl`;
- a `# no-query:` reason that says "line number for Edit" gets a reply
  naming `edit insert --after NAME` and `query def NAME` (which prints
  the line).

To check-after-edit.py: the delta line and the debounce from item 3;
cap stays 10; and a Stop hook (`turn-end`) that, when a `.vl` file
changed since the last clean check or test in this session, runs
`check` once and appends "unchecked changes in FILE: N errors" (cheap:
35-50 ms); never a second time for the same state.

**Effect.** Compiler fix/feature tasks: the tools-condition overhead on
23 and 24 shrinks (fewer blocked turns, fewer partial reads); the Stop
hook catches the "edited, never checked" end state that `final_check`
would otherwise record (tonight: 0 such runs, so expect no change there
and keep it for the longer sessions where it was designed).

**Cost.** One day for the parser and messages; half a day for the Stop
hook; the existing hook tests extend.

**Measure.** Compiler 23 and 24, both models, 3 reps, `compiler-tools`
with the new hooks against tonight's; metrics: blocks, escapes, turns,
input tokens; tools/plain ratio on 23 from 1.45 toward 1.0 and on 24
from 2.2 toward 1.2 (with item 6) confirms; unchanged refutes.

### 5. Name and API resolution: the errors agents actually meet

**Evidence.** After syntax, API use is the top failure (34.6% on
Cangjie) [Cheng 2026]; the missing-stdlib effect widens the gap 2-3x
[Kumar 2026]; E0599/E0425 lead Rust translation failures [Ou 2025];
name resolution is 29% of our distinct errors, the largest class, and
0.13's one costly failure was 30 guessed names.

**Change**, each a diagnostic help line and where possible a `fix`:
- `unknown module 'io'`/`'collections'` under `std`: "vole's std is
  one module: `use std::{read_line, HashMap};` (`volec guide std`)";
  a `mod x;` whose file is missing: "write x.vl (`volec edit
  new-file x.vl`)" instead of `cannot find the file of module`;
- `unknown type 'String'|'Box'|'char'|'&str'`: the exact vole type in
  the help (the core guide table, moved into the compiler): `[u8]` /
  `Buf`, `*T` / `Vec<T>`, `u8`;
- `no method 'len' on '[u8]'`: today's help; extend `no method` to list
  the type's closest method names (edit distance, then the three most
  used) and `try: volec query items std::Vec`;
- `duplicate function 'f'`: tonight's 14 came from agents splicing
  text with Python scripts (the shell rewrite the hook does not block in
  a program workspace); the help should name the existing definition's
  position and `try: volec edit replace f < text`, and `edit insert`
  should refuse an item that exists with the same `try:`;
- `cannot infer type parameter 'T' of 'collect_in'`: a `try:` with the
  turbofish or the annotated `let`;
- `non-exhaustive match: 'E::C' is not covered`: 35 distinct hits, the
  largest single message; the help names the arm already; add `try:
  volec refactor variant` when the match is over an enum the user
  owns, and for integer ranges the missing range literally (the
  23-fix-checker bug was exactly this message);
- the Rust-habit `unsafe` class (28 C calls, 13 raw-pointer uses): the
  help already says `volec fix --only unsafe`; put that command in
  the hook's output when the only errors are `unsafe`, so the agent runs
  one command instead of editing each site.

**Effect.** Fewer repair turns per error (each is one turn today) and
fewer guessed names; small per run (1-2 errors per Sonnet run, more on
Haiku bare), but it is the class that caused the only 0.13 failure and
the literature's largest post-syntax class.

**Cost.** One to three days across front/check and tools; each item has
a case in tests/run.

**Measure.** All program tasks, both models, `guide-2k` condition before
and after; metric: distinct errors per run by class from the check
hook's `--json` records (the harness must store them: item 8), and
repair turns (calls between an error and the next clean check).
Confirmed if the name/API class falls by half and repair turns per error
fall below 1.2; the match class is the control (it should move only with
its own change).

### 6. Edit std by name, and "how to add X" recipes

**Evidence.** Tool-gaps-016 item 2; tonight's five escapes and the 2.2x
overhead on 24-std-method; the AGENTS.md study's one reliable transfer
is build/test instructions; Agentless's fixed recipe beat agents on
small tasks [Xia 2025]; weak agents gain from executable helpers, not
prose [Sharma 2026].

**Change.** (a) `edit patch|insert|replace std::NAME` maps to
compiler/std/FILE.vl when the tree has it, checks the program with the
edited std, and ends with `note edit.std: run compiler/std/embed.sh
(done)` after running it. (b) `volec guide how TASK` (or `explain
how-TASK`): short, command-first recipes for the compiler's recurring
changes, each verified by a walkthrough test: `how add-std-fn` (the
file, the embed, the test in tests/run, the guide entry, `test std
guide`), `how add-pass`, `how add-diagnostic`, `how add-test`, `how
add-guide-example`; for programs `how read-input`, `how add-module`.
Each recipe is under 300 tokens and names the exact commands.

**Effect.** 24-std-method's tools overhead from 2.2x toward 1.0-1.2x;
Haiku's feature-task runs (39-45 turns, several embed/build cycles)
shorter. The recipes are the executable form of the "how to add X"
support planned after 0.16.

**Cost.** (a) two to three days (the embed map, the overlay check); (b)
one day plus the walkthroughs.

**Measure.** Compiler 24 (and a second feature task, item 8), both
models, 3 reps; metrics: escapes (expect 0), turns, tools/plain ratio.
Confirmed below 1.3; refuted if the plain agent is still cheaper by more
than 20% after (a) and (b) both land.

### 7. Promote `query context` once, in the imperative, with an example; then judge it

**Evidence.** Semantic navigation (definition, references, call
hierarchy merged into one call) cut input tokens 24% and turns 17.5% at
constant accuracy for strong models [Song 2026]; one-hop ~2k-token
neighbourhoods help, two-hop ~10k hurt [Ouyang 2025]; a tool is used when
named in the imperative and not otherwise [Gloaguen 2026; Tool
Preferences 2025]; usage examples lift hard-parameter accuracy 72 to 90%
[Anthropic 2025]; ablation shows structural views are the *smallest* of
the four tool effects on an unfamiliar language [Shen 2026]. Ours: 0
calls in 282 runs under the current wording.

**Change.** The first row of the new core (item 2) and one worked
example in `guide tools`: `volec query context run_gvn --budget 2000`
with its abbreviated output. Keep the default budget at 2,000 and one
hop. Nothing else. If the rerun shows under 0.5 calls per compiler run,
remove the row and let `show` plus `refs` be the path; the literature
ranks this tool last and our agents agree.

**Effect.** Unknown; the SWE-Master numbers (-17% turns) are the upper
bound and were for a merged LSP tool on bug fixes with a model trained
on it.

**Cost.** An hour.

**Measure.** Compiler 21-24, both models, under item 2's core; metric:
`query context` calls per run and, where used, turns against runs that
did not use it (within task). Confirmed useful if used in a third of runs
and those runs are not costlier; otherwise dropped.

### 8. The eval harness: anatomy, error classes, self-checks, new conditions

**Evidence.** Nobody decomposes turns; variance warnings (±0.5 points
over six runs; order effects of two points) [Yang 2024; OSWorld-MCP
2025]; the TSE protocol (10 runs, McNemar, BH); AIDL's intent erosion
[Jones 2025]; reproduction tests validating the fix 44% of the time
[Xia 2025].

**Change** to tests/agent-eval:
- `result.json` gains `anatomy`: calls by role (lookup = guide, query
  show/def/items/grep, Read of source; edit = Write/Edit/edit/refactor;
  verify = check, build, run, test, cmp/diff; other), first-edit call,
  calls between each error and the next clean check, prompt tokens per
  turn (first-turn cache creation + read), denials by cause (`$var`,
  heredoc, chain, write outside), guide topics fetched; the report gets
  an "anatomy" table per model and condition (the script behind
  docs/research/agent-language-design.md is the draft);
- the check hook's `--json` records are stored per run and classified
  (name/API, type, match, unsafe, alloc, syntax, own.* from 0.17) with a
  Rust-habit flag (`String`, `&`, `println!`, `std::io`, `.len()`, `?`
  misuse, C call without unsafe); the report prints the class table per
  model and condition, which is the ISSRE comparison against Rust (for
  Rust runs, parse `rustc`'s `error[E...]` codes the same way);
- intent erosion: per run, items, tests and `assert`-like lines deleted
  from the starter (`changes.patch` for compiler tasks; a diff against
  the starter for programs), reported;
- edit-failure recovery: P(next edit succeeds | `edit.breaks` or
  `patch.no-match` or an Edit tool miss), per model;
- `check-tasks` lints both reference solutions: `volec fmt --check`,
  `lint --max-lines`, `query unused`, `fix --dry-run` must be clean for
  vole, `rustfmt --check` and `cargo clippy`-free `rustc -W warnings`
  for Rust; and `check.sh` for every refactor/extend task should test
  idiom, not only structure (18-api-refactor's does structure);
- permissions: run the Claude backend with `--claude-permissions bypass`
  inside the sandbox (the README says it is unverified; verify it on
  the dev tasks), so that `&&`, `$?` and heredocs are not refused: the
  refusals are one call in ten in every condition and distort turn
  counts; keep the allowlist run as a condition for one round to measure
  the difference;
- new conditions: `guide-2k` (item 1), `guide-examples` and
  `guide-rules` (the 2k core as snippets only, or as the rule tables
  only, same token count), `tools-core` (item 2), `both+hook+test` (item
  3), `rust-pairs` (the core's differences as paired Rust/vole lines
  against vole-only lines, same budget), and `rust-twin-supplied`
  (the Rust reference solution in the prompt, hook on; CangjieBench
  found negative transfer one-shot and positive with an agent);
- more compiler tasks of the kinds that discriminate: a second refactor
  (a signature change with 30+ callers; a variant added to an enum
  matched in 10 files), a second feature (a diagnostic with a `try:`),
  and a 0.17 task once `own.*` exists (migrate a program with `fix
  --values`, then fix the rest from the diagnostics);
- 10 reps for the cells that decide a change (items 1-3), 3 for the
  rest; report medians with interquartile range; McNemar on success is
  moot at the ceiling, so compare costs with a paired test per task.

**Cost.** Three to five days for the harness; task authoring one day
each.

**Measure.** The harness measures everything else; its own check is that
the anatomy totals reconcile with `tool_calls_by_kind` and that the
error-class table on the 0.16 transcripts reproduces the counts in
docs/research/agent-language-design.md §1 and §5.

### 9. The harness's own prompt placement and recitation

**Evidence.** Task last and the critical rule restated near the end
[Liu 2024]; recitation of the relevant bit before acting recovers most
of a small model's loss [Du 2025]; `guide TOPIC#SECTION` exists.

**Change.** In `lib/prompts.py`, the task comes last (it does); add one
line after it in vole conditions: "Before writing a construct you are
unsure of, `volec guide --find WORDS` or `guide TOPIC#SECTION` prints
the lines on it." And in the core guide's loop section the same sentence.
Cheap; measured with item 1.

**Measure.** `guide --find` and `#SECTION` calls per run and the error
count on the construct fetched; a Haiku-only effect if any.

### 10. Longer term: a small local model, and the language-level choices

**A fine-tuned small model.** The recipe with evidence is continued
pre-training of a base model on 13-28M tokens of code and docs, then the
Instruct weight-diff transfer; SFT on thousands of functions is worse
[Giagnorio 2026]; synthetic data by validated translation doubles small
models' pass@1 [Cassano 2024]; the semantic gap (12-19 pp) does not close
with more data [Kumar 2026]. For vole: first count the corpus
(compiler/src, compiler/std, examples, tests/run, docs, the guide;
likely 3-6M tokens); then the MultiPL-T pipeline with Rust as the bridge:
tested Rust programs (the eval twins, MultiPL-E's Rust, RosettaCode)
translated by Sonnet in an agent loop with the hook, kept when they pass
under `volec` and their tests; then pre-train Qwen3-8B-Base (or
similar) on the corpus plus the synthesized programs and apply the
weight-diff recipe. Expected: a syntax-safe helper for the small write
and fix tasks, not a Sonnet replacement; the 0.13 Qwen runs (0/6, Rust
included) say the agent loop around a 30B local model is the first
problem. Cost: weeks and a GPU; the compiler and tests are the cheap
part. Measure: the eval's 18 tasks under `guide-2k` for the tuned model
against its base and against Haiku; success and build failures per run.

**Language-level, given that ownership errors are a minority class.**
- 0.17's value semantics remove a real class (G1-G8 are all undefined
  behaviour in safe code today, and the prototype found one real bug in
  the examples), but the eval says they are not where agents lose turns:
  `unsafe` around C calls and raw pointers is 15% of distinct errors,
  explicit allocation 3%, and name/API 29%. So 0.17's priority order for
  agents is: (1) §2.9's diagnostics contract with tested `try:` lines,
  since every new rejection is a new error class that must cost one turn
  and not three; (2) `fix --values` migrating the 27 `mig.borrow` sites
  and the parsers' pattern so that the eval's reference solutions check
  clean without hand edits (the gate: 0 of 379 eval functions rejected,
  as the prototype's precise rules give); (3) the `unsafe` ergonomics
  the data points at: the most common single Rust habit is a C call
  without `unsafe`, and the second is a stored pointer used safely; 0.17's
  second-class references make the second one safe code, which should
  remove those 13 errors, and `fix --only unsafe` in the hook (item 5)
  handles the first.
- The testable 0.17 claim: on the same 18 tasks, the `unsafe`+alloc
  class goes from ~18% of distinct errors to under 5%, the new `own.*`
  class stays under 5%, and no run loses success; measured by the error-
  class table (item 8) on 0.16 against 0.17 with the same guide.
- Do not spend design effort on token-count syntax: grammar-level savings
  are ~10% and need retraining [Sun 2024; Sun 2025]; our output tokens
  are at parity with Rust.
- Keep strictness: the literature's compile errors are type errors and
  the loop recovers the cost [Mündler 2025]; our premium is prompt size,
  not type reasoning.
- Macros: none; keep it that way [Ronacher 2026]. Effects: inferred
  (never a reported error tonight); surface them in a decision (a hook
  that refuses `io` added to a `#[pure]` function) only if a task ever
  needs it.
- Contracts (0.18): local pre/post on one item, checked by the hook,
  never compositional proofs to compile [DafnyComp 2025; AutoVerus
  2025]; property tests beside the item first [Pythoness 2025].

## 4. The rerun matrix

Cells in priority order; each row names the items it decides. Reps: 10
where a row decides items 1-3 and the cell is cheap (Sonnet programs),
else 3. Models: Sonnet and Haiku; a local model only when an idle machine
and item 10's harness fixes exist. Costs are extrapolated from tonight's
per-run medians.

| row | tasks | models | conditions | reps | decides | metric and threshold |
|---|---|---|---|---|---|---|
| A | programs 01-18 | Sonnet, Haiku | `guide-2k`, `guide`, `rust` | 10 (Sonnet), 3 (Haiku) | item 1 | input tokens -30% on 01-12, turns within 1, success equal; guide calls/run |
| B | programs 13-18 | Sonnet, Haiku | `guide-examples`, `guide-rules` (equal tokens), `guide-2k` | 3 | item 1's form | error classes per run, turns; snippets below rules on Rust-habit errors confirms |
| C | compiler 21-24 (+2 new) | Sonnet, Haiku | `compiler-tools-core` (items 2, 4, 6, 7), `compiler-tools`, `compiler-plain` | 3 | items 2, 4, 6, 7 | tools/plain input ratio: 22 under 0.4 kept, 23 toward 1.0, 24 under 1.3; blocks, escapes, `query context` calls |
| D | programs 13-18, compiler 21-24 | Sonnet, Haiku | `both+hook+test`, `both+hook`, `both` | 3 | item 3 | verify calls -33% (Haiku), denials, turns, `final_check` errors |
| E | programs 01-18 | Sonnet, Haiku | `guide-2k` before and after item 5 | 3 | item 5 | name/API errors per run halved; repair turns per error under 1.2 |
| F | programs 01-18 | Sonnet | allowlist vs `bypass` permissions, `guide-2k` | 3 | item 8's permission change | denials to ~0, turns -1 to -3, no success change |
| G | programs 13-18 | Sonnet, Haiku | `rust-pairs` vs `guide-2k` (same budget) | 3 | item 1's pairing | Rust-habit error count and turns |
| H | programs 13-18 | Sonnet | `rust-twin-supplied` + hook vs `guide-2k` | 3 | an open question (negative transfer) | turns, errors, success |
| I | programs 01-18 | Sonnet, Haiku | 0.16 compiler vs 0.17 compiler, `guide-2k` | 3 | item 10's 0.17 claim | `unsafe`+alloc class under 5%, `own.*` under 5%, success equal, `try:` lines applied as given (count) |
| J | the eval tasks' reference solutions | - | `check-tasks` with the new lints | - | item 8 | all clean, or the solutions are fixed first |

Reading order: A and C first (they decide the two largest changes and
cost about $60 for Sonnet and $15 for Haiku at tonight's prices); D and
E after items 3 and 5 are built; I once 0.17's checker runs on the
eval's solutions. Two cells of A and C are also the baseline of every
later row, so keep their result directories. A difference smaller than
the interquartile range of the control cell is noise, whatever the
direction; tonight's 17-debug-crash (129k bare, 368k both, 201k guide
for Sonnet) is the reminder.
