# Tool gaps after 0.14: what costs agents the most

The question: where do tachyon's own tools (`tachyonc query`, `edit`,
`refactor`, `check`, `fix`, `fmt`, `explain`, `guide`, and the
query-first hook) still cost agents turns and tokens, and which changes
would cut that work the most. The aim is to make the agent's job much
simpler, not to make the tools more complete. The narrative of the 0.14
work is in [agent-tool-usage.md](agent-tool-usage.md), "0.14".

## Sources

- **The hook's log** (`.git/agent-tools.jsonl`): 1,360 records from
  20:00 to 22:56 on 2026-10-14. These are the 0.14 agents. The v0.13.0
  tag was made at 20:39, but the first 0.14 agents had started before
  it. The 0.13 release-prep and benchmark agents are left out.
- **The transcripts of the 17 agents of 0.14**:
  - std, diag, tools part 1 and part 2, phase 0, T1 closures, T2
    associated types, T3 iterators, T4 optimizer, T5 tools for closures,
    the integration;
  - the eval runner and the three eval-task authors (plus the 13–18
    author);
  - the closures/iterators planner.

  Together: 2,219 tool calls in 2,154 turns, with 405M tokens of
  context read (input plus cache), so **188k tokens per turn**. Only
  aggregates were taken from them.
- **The 0.13 agent-eval baseline transcripts**: Haiku and Sonnet, 12
  tasks, conditions bare, guide, tools, both and Rust; 120 runs. In the
  tools condition, each turn re-reads **17.8k tokens (Sonnet)** or
  **25.3k (Haiku)** of context.

How the numbers were made: each Bash call was split into its simple
commands, and every `tachyonc` invocation was classified, including
`$T query ...` with `T=target/tc0`. A tool error is an `error CODE:`
line from a tool; compile errors of the program do not count. A retry
is an errored call followed directly by another `tachyonc` call. A
give-up is an errored call followed by Edit, Write, `sed` or Python.
Token estimates count the turns a change would save, times the context
per turn above. Turns dominate the cost: in the tools condition, all
tool output together was 58k tokens (Haiku) and 24k (Sonnet), against
11.5M and 3.3M of context read.

## (a) Headline numbers

**Edits to existing compiler source through the tools.**

| agent | tool edits | shell rewrites | Edit | Write | tool share |
|---|---|---|---|---|---|
| phase 0 (interfaces) | 36 | 0 | 1 | 0 | 97% |
| tools part 2 | 18 | 0 | 0 | 0 | 100% |
| diag | 39 | 0 | 0 | 0 | 100% |
| T4 optimizer | 41 | 1 | 2 | 0 | 93% |
| tools part 1 | 27 | 1 | 1 | 0 | 93% |
| T5 tools for closures | 21 | 0 | 0 | 0 | 100% |
| T1 closures | 14 | 2 | 0 | 1 | 82% |
| T2 associated types | 10 | 3 | 4 | 1 | 56% |
| T3 iterators | 11 | 4 | 6 | 1 | 50% |
| std | 4 | 2 | 10 | 0 | 25% |
| the integration | 4 | 1 | 0 | 0 | 80% |
| **all** | **225** | **14** | **24** | **3** | **85%** |

How the table was counted:

- **Tool edits** come from the transcripts: `edit`, `refactor`, `fix`,
  `undo` and `rewrite` on compiler source, written (dry runs excluded).
- **Shell rewrites** and **Write** come from the hook. It tells whether
  a file existed before it was written.
- **Edit** counts Edit-tool calls on compiler/src and compiler/std.

The hook's own report says 69% (91 of 131), for two reasons. It does
not see `tachyonc` run through a shell variable. And five agents queried
and edited through `T=target/tc0; $T edit ...`, a copy of the compiler,
because their own builds replace `target/tachyonc`. That hid 51 tool
edits (T5 20, T1 13, T3 9) and about 280 queries from the log.

**`tachyonc` calls.**

| | dev agents | eval tools, Haiku | eval tools, Sonnet |
|---|---|---|---|
| Bash calls running a tool | 995 of 2,219 | 189 | 90 |
| tool invocations (several per call) | 1,531 (+457 builds) | 319 | 171 |
| query invocations | 922 | 133 | 42 |
| calls with a tool error | 102 (10.3%) | 20 (11%) | 24 (27%) |
| errored calls retried at once with the tool | 76 (75%) | 18 | 22 |
| errored calls given up (Edit, Write, sed, Python next) | 11 (11%) | 2 | 2 |
| hook blocks / `# no-query` / `# no-tool` | 43 / 63 / 14 | – | – |

- **Queries in the dev agents:** `show` 391, `text` 131, `grep` 121,
  `refs` 113, `items` 93, `def` 42, `type` 13, `stats` 9, `diff` 9.
- **Other dev invocations:** `edit patch` 350, `check` 189, `fix` 107,
  `fmt` 88, `guide` 61, `refactor rename` 55, `edit insert` 53, `edit
  replace` 27.
- **Queries alone:** 533 calls that only queried, printing 396k tokens.
- **Chaining:** agents already put about two tool invocations in each
  Bash call (1,988 invocations in 995 calls).

**Top error codes.**

| code | dev | eval | what happened |
|---|---|---|---|
| `query.no-match` | 31 | 18 | a misspelled or stale name, often one name of several; no did-you-mean |
| `edit.breaks` | 25 | 17 | the edit is checked and refused; `--no-check` then used 51 times (dev) and 19 (eval) |
| `edit.usage`, `refactor.usage`, `guide.usage`, `explain.usage`, `query.usage`, `fmt.usage` | 23 | 17 | mostly `--help` refused, a second TARGET, or `new-module report` without `crate::` |
| `query.no-file` / `no module 'std'` | 0 | 13 | `query text std:240-300`, `query items std` from a user program |
| `explain.unknown` | 2 | 8 | `explain type`, `explain std`, `explain parser`: explain used as help on the language |
| `undo.empty` | 9 | 0 | no journal outside git (fixed in 0.14) |
| `refactor.no-module` | 0 | 8 | `move ... --to report` before `new-module` |
| `patch.no-match` | 8 | 1 | OLD text not in the item (once on a `mod` line) |
| `fmt.unformatted` | 8 | 0 | `fmt --check` after edits |
| `query.no-root` | 5 | 0 | run outside a directory with `main.tach` |

**The eval in one line each.**

- **Total tokens by condition.** Haiku: bare 7.9M, guide 7.3M, tools
  11.5M, both 7.4M, Rust 2.8M. Sonnet: bare 2.28M, guide 2.03M, tools
  3.35M, both 2.09M, Rust 0.90M.
- **The tools paid on refactors and edits of existing code:**
  - 10-refactor-rename: Sonnet with tools 105k, against 177k bare,
    315k with the guide, 174k with both, 163k in Rust. Haiku with tools
    838k, against 959k–1,458k in the other conditions.
  - 11-add-variant: Sonnet 120k, against 196k with the guide and 207k
    with both.
  - 08-fix-compile: Sonnet 87k, against 116k and 150k.
- **They cost on programs written from a spec:**
  - 04-ledger: Sonnet with tools 1,039k, against 102k with the guide.
    The agent ran `strings` on the compiler binary to find std's API.
  - 09-extend-calc: Haiku with tools 2,310k, against 594k.
  - In the tools condition the agents wrote **56 probe programs**
    (`probe/*.tach`, `t/main.tach`, `edit replace main --no-check`) to
    learn what std and the language accept, against 3–4 with the guide.

## (b) The top 10 gaps, by estimated tokens wasted

The estimates are turns saved times context per turn. Dev turns are
weighted at 188k and eval turns at about 20k. Dev numbers are larger
because every dev turn re-reads a large context; the eval numbers show
where a newcomer's work goes.

### 1. One question per call: exploring an item takes 3–5 queries (~17M dev, ~0.3M eval)

Evidence:

- `query show` followed by `query show` 89 times in the dev
  transcripts. Other pairs: `items` then `show` 26, `show` then `refs` 8,
  `refs` then `show` 8, `grep` then `text` 8, `show` then `grep` 8.
- The longest chains run `items > show > show > items > show`.
- Example (tools part 2):

  ```
  query items crate::tools::script --comments
  query show split_words run_step script_inner
  query show put_loc try_refactor ...
  ```

  Each step reads names out of the previous output.
- In the eval, Haiku in the tools condition made 133 queries on
  programs of 200–500 lines.

Proposal: `tachyonc query context NAME... [--budget TOKENS] [--depth 1]`.
One answer, sized to the budget (default 3,000 tokens):

```
// crate::tools::script::run_step	tools/script.tach:88-140  (section: "Running a step")
<signature, doc comment, body>
callers (3): script_inner script.tach:52, run_script script.tach:30, tests: refactor/script.t
calls: split_words(line: [u8]) -> Vec<[u8]>   script.tach:20
       put_loc(out: *Buf, at: Loc)            loc.tach:14
types: Step { kind, words, line }             script.tach:8
(2 more callees over budget: try: tachyonc query context run_step --budget 6000)
```

For a module, `query context MODULE` gives its banners, its items with
their signatures, and the bodies of the items that most of the others
call, up to the budget.

Expected effect: if one call replaces 2.5 of the consecutive queries,
about 90 fewer dev turns (~17M context tokens, 4% of 0.14's dev total).
The output is also shorter than the several shows it replaces.

### 2. Several edits to related items take several calls (~8.5M dev, ~0.6M eval)

Evidence:

- 52 consecutive `edit patch` pairs in the dev transcripts. 37 of them
  edit a different item and the first did not fail, so these are one
  change spread over several calls. 10 run three in a row.
- Two `# no-tool` escapes in T2 went to Python instead: "several
  related additions in generics/mod.tach (a const and slice cases in
  three functions); edit patch per item would be four calls", and
  "coordinated edits across collect.tach, calls.tach, instantiate…".
- Feedback: "adding an import and its first use in two items needs two
  edits; the first fails unless --no-check".
- `edit.usage: one TARGET at a time` 3 times.
- In the eval, Haiku wrote replacement items to files and fed them one
  by one: 44 probe Writes and 33 `edit replace|insert|patch < FILE` in
  the tools condition.

Proposal, both forms checked once, as one journal entry (`undo` takes
all of it back):

- `tachyonc edit patch --pairs FILE`, where a block may name its own
  target:

  ```
  @@ crate::front::generics::TPL_SLICE
  <<<<<<< OLD
  ...
  >>>>>>> NEW
  @@ crate::front::check::calls::method_of
  ...
  ```

  On the command line, `--in NAME` switches the target for the pairs
  after it:

  ```
  edit patch f --old A --new B --in g --old C --new D
  ```

- `tachyonc edit apply FILE`: every item in FILE replaces the item of
  the same path, or is inserted (at the end of its module, or after
  `--after NAME`). Imports are added, and the file is formatted.

Expected effect: about 45 fewer dev turns (~8.5M), about 30 eval turns
(~0.6M). It also removes the strongest reason left for Python rewrites
of compiler source.

### 3. A check after every Write and Edit, and a check before every build (~8M dev, ~3M eval)

Evidence:

- In the eval, 124 calls ran `check` or a build directly after a
  Write or Edit of a `.tach` file: 51 in tools, 37 bare, 21 guide, 15
  both.
- `Write > check > Write > check` is the commonest 3-gram of the tools
  condition (13 and 12 occurrences).
- A `check` call followed by a build call: 37 times in dev, 32 in the
  eval. `check && build` in one call: 55 times in dev, 53 in the eval.
- In dev, 21 checks came straight after an Edit or Write of compiler
  source.

Proposal:

- **A PostToolUse hook**, shipped in `tools/agent-hooks/` and in the
  eval harness. After Write or Edit of a `.tach` file, it runs
  `tachyonc check --root R` (cached, under 0.1 s) and appends at most
  10 one-line errors, or `check: ok`, to the tool result.
- **A build prints `check`'s one-line diagnostics** with the same
  `try:` lines, so a check before a build is redundant.
- **`tachyonc check --run 'ARGS' < input`**: check, build to a cached
  binary, run.

Expected effect: about 150 eval turns (~3M tokens, 7% of all
non-Rust eval tokens) and about 40 dev turns (~8M).

### 4. std and the language cannot be looked up from a user program (~3.8M dev, ~2.4M eval)

Evidence:

- In the eval, 57 std lookups in the tools condition:
  - `query items std`;
  - `query text std:240-300`, giving `query.no-file: cannot read 'std'`
    (10 times);
  - `query def std::read_line`, `query show std::malloc`;
  - `strings $(which tachyonc) | grep 'pub fn'` (6 of the 24 runs).
- The 56 probe programs of (a) were the same need.
- In dev, 13 escapes said "std.tach is a separate program root",
  "query grep --root compiler/std/std.tach finds nothing" and "std
  source is not part of the tree query indexes".
- The std agent made 10 of its 16 compiler edits with the Edit tool
  (25% tool share), and T3 drafted std's iterators in staged copies
  edited by Python.
- Feedback: "a std item is not found unless the program uses std".

Proposal:

- **std is always part of the program** for `query` (`items std`,
  `show std::HashMap::get_or_insert`, `def`, `grep --in std`, `text
  std/iter.tach:1-40`), whether or not the program imports it. Each
  answer carries the `use std::{...};` line that brings the item in.
- **In the compiler tree, `compiler/std/*.tach` are edit targets** by
  path (`edit patch std::sort --old ...`), with the embed regenerated.
- **`tachyonc try 'STATEMENTS'`** (std imported, wrapped in `fn main`)
  prints the type of the last expression and the program's output: one
  call instead of Write, build and run.

Expected effect: most of the tools condition's extra cost on the
writing tasks. About 110 eval turns (~2.4M), and 20 dev turns (~3.8M).
The std agent's edits move to the tools.

### 5. `edit.breaks` sends agents to `--no-check`, and does not point to the refactoring that fits (~4.7M dev, ~0.4M eval)

Evidence:

- `edit.breaks` 25 times in dev and 17 in the eval.
- The `try:` line offers `--no-check`, and agents took it: 51 runs
  with `--no-check` in dev and 19 in the eval, each followed by a
  `check`.
- Example: Sonnet (09-extend-calc) patched `run_line` to take `vars:
  *Vec<Var>` and use it. Three new errors came back: two missing
  imports, whose `help:` already gave the `use` line (0.14 now adds
  them), and the one call in `main`. The `try:` line repeated the same
  patch with `--no-check`. The agent took it, then ran `fix --only
  imports` and patched `main`: four calls. `refactor signature run_line
  --add 'vars: *Vec<Var> = &mut vars'` and one patch would have been
  two.
- Feedback: "edit.breaks says '1 new error; nothing written' but not
  which error".

Proposal: the new errors are printed as they are now, and always,
whatever the command (insert and `--pairs` too). Each error is tagged
with the item it falls in. The `try:` line is chosen by what broke:

- the item's signature changed and the errors are at its uses: `try:
  tachyonc refactor signature F --add '...'`, or `--rename-param`;
- errors in other items: `try:` the multi-target patch of gap 2, with
  those items named;
- a missing import: written, with the import added (0.14 does this for
  edits that add new text);
- otherwise `--no-check`, last.

Expected effect: about 25 dev turns and 20 eval turns. Fewer broken
trees left by `--no-check`.

### 6. Names and paths in forms the tools print but do not accept (~4M dev, ~0.6M eval)

Evidence:

- `query.no-match` 49 times, with no nearest name. For example
  `query def err_help ... err_note` fails on `err_note`, and the other
  names' answers are lost in the error.
- `refactor new-module report` gives `refactor.usage: a module path is
  needed (crate::a::b)` 6 times. `refactor move ... --to report` gives
  `refactor.no-module` 8 times, and every 10-refactor run that used the
  tools spent a call on `new-module`.
- `fix --in ./catalog.tach` and `fix --in front::check::mod`
  (`fix.bad-in`), `query grep --in crate::driver` (`query.bad-in`), and
  `edit patch bench/sort.tach:12` outside compiler/src
  (`query.no-match`, "no file in the program").

Proposal:

- Every spelling that a tool prints is accepted wherever a NAME, FILE
  or MODULE is expected: `./x.tach`, `x.tach`, `x`, `crate::x`,
  `a::mod`. A FILE outside the default root becomes the root.
- `query.no-match` prints the nearest three names with the commands to
  run them (`try: tachyonc query def crate::diag::err_note_at`), and a
  multi-name query answers the names it found.
- `refactor move ... --to crate::report` creates the module and its
  file when they do not exist (`--create` if that is too implicit).

Expected effect: about 20 dev turns and 30 eval turns.

### 7. Large guide and help outputs, re-read (~4.4M dev, ~0.4M eval)

Evidence:

- `guide > guide > guide` 6 times in dev and 7 in the eval, each about
  30–40k tokens of output in all.
- Dev agents ran `guide` 42 times (73k tokens of output), the eval's
  tools condition 18 times (27k).
- `tachyonc guide` with no topic prints 22k characters.
- Output stays in context for the rest of the session. A 5k-token
  topic read at turn 10 of a 150-turn session costs about 700k tokens
  of context.

Proposal:

- `guide --find WORDS` prints the matching paragraphs, each with
  `topic#section`, at most `--budget` tokens.
- `guide TOPIC#SECTION` prints one section.
- `guide` with no topic prints the topic list and the one-screen core
  (the 30 lines a newcomer needs first), not the whole guide.

Expected effect: guide output cut by half or more at the same use.

### 8. Merge conflicts are out of the tools' reach (~2.8M dev)

Evidence:

- 8 `# no-query` and 3 `# no-tool` escapes in the integration and T1
  agents, giving reasons like "counting conflict markers", "conflict
  region", "query cannot run on a tree mid-merge" and "resolving merge
  conflict markers, which edit cannot parse".
- Python and `awk '/<<<<<<< HEAD/,0'` were used instead.
- Proposed in the 0.13 gaps and not built.

Proposal:

- `tachyonc query conflicts [FILE|MODULE]`: one line per region, as
  `file:line  ours: ITEMS (+n -m)  theirs: ITEMS (+n -m)`.
- `query show FILE:LINE --conflict` shows both sides.
- `tachyonc edit resolve FILE:LINE --ours|--theirs|--both|--new <
  text`.

These read the file as text around the regions, so they work on a tree
that does not parse.

Expected effect: about 15 turns per integration, and no Python on
source.

### 9. Help and explain used as the language's documentation (~1.1M dev, ~0.4M eval)

Evidence:

- `--help` was refused by `edit`, `fmt`, `refactor`, `refactor
  signature`, `explain` and `guide` (6 times).
- `explain` was called on words: `explain type`, `explain std`,
  `explain parser` and `explain essentials` (8 `explain.unknown`),
  and `explain --help` (3 `explain.usage`).
- Sonnet in the tools condition ran `explain` 17 times.

Proposal:

- Every command and subcommand accepts `--help`, printing its rows of
  the tools table (≤15 lines).
- `explain WORD`, when WORD is not a code, answers like `guide --find
  WORD`.
- `explain 'MESSAGE TEXT'` matches a compiler message and prints its
  explanation (`explain 'expected [u8], got i64'`).

Expected effect: about 25 eval turns over 12 tasks, more for a new
user.

### 10. The tools binary changes under the agent, and the hook loses sight of it (no direct tokens; it hides the data)

Evidence:

- The language agents (T1, T3, T5, tools part 1, the eval-task
  authors) copied `target/tachyonc` to `target/tc0`. Their own builds
  replace the binary, and a broken build breaks `query`.
- They then ran `T=target/tc0; $T query ...`. The hook recognizes
  neither the shell variable nor the copy, so 51 tool edits and about
  280 queries are missing from the log.
- The old copy cannot parse the new syntax the agent is adding
  (closures).

Proposal:

- `bootstrap/bootstrap.sh --dev` installs a tools binary at
  `target/tools/tachyonc` only when its suite passes.
- AGENTS.md and the hook treat it as `tachyonc`.
- The hook resolves `X=...tachyonc; $X ...`.

Expected effect: the edit-share metric becomes right (69% reported
against 85% real). Agents stop maintaining copies.

## Sequences

The n-grams are runs of 2–4 consecutive tool calls by the same agent.
Each call is reduced to its kind: `q:show`, `e:patch`, `check`,
`build`, `test` (tests/run.sh), `Write:tach`, `sh:write` (a heredoc
writing a `.tach`), and so on. A call with several commands is joined
with `+`. They are ranked by count × (calls saved × context per turn +
output). The top 10 over dev and eval:

| # | sequence | dev | eval | example | one command instead |
|---|---|---|---|---|---|
| 1 | `q:show > q:show` (and `> q:show`) | 89 | 10 | `query show Module child_module mod_fqn`, then `query show emit_use_edits rewrite_imports` (the callees of the first) | `query context NAME --budget N` (gap 1) |
| 2 | `q:items > q:show`, `q:show > q:items`, `q:items+q:show > q:show` | 38 | 4 | `query items crate::middle::opt`, then `query show optimize_program optimize_loops ...` | `query context MODULE` (banners, signatures, central bodies) (gap 1) |
| 3 | `e:patch > e:patch` (different items, no error) | 37 | 10 | `edit patch run_edit_inner ...`, then `edit patch run_patch ...` | `edit patch --pairs FILE` with `@@ TARGET` blocks, `--in NAME`, or `edit apply FILE` (gap 2) |
| 4 | `Write:tach > check`, `check > Write:tach > check` | 21 | 124 | Write `t/main.tach`, `tachyonc check --root main.tach`, Write again | a PostToolUse auto-check (gap 3) |
| 5 | `check > build` (next call, or `check && build`) | 92 | 85 | `tachyonc check; tachyonc main.tach -o prog` | build prints check's lines; `check --run` (gap 3) |
| 6 | `sh:write > sh:write`, `Write:tach(probe) > check/build > run` | 20 pairs, 129 probes | 56 probes | `cat > p/main.tach <<EOF ... EOF; tachyonc p/main.tach -o p/a && p/a` | `tachyonc try 'STATEMENTS'` (gap 4) |
| 7 | `guide > guide > guide` | 6 | 7 | `guide --list`, `guide core; guide std`, `guide std` | `guide --find WORDS`, `guide TOPIC#SECTION` (gap 7) |
| 8 | `q:grep > q:text` or `q:show` (including chained) | 55 | 0 | `query grep 'did you mean'`, then `query text names.tach:190-300` | `query grep TEXT --show` (the enclosing item) or `--context N` (lines around each hit) |
| 9 | `r:new-module > r:move` | 1 | 10 | `refactor new-module crate::report`, then `refactor move report_stock ... --to crate::report` | `refactor move ... --to crate::report --create` (gap 6) |
| 10 | edit `> test` (19), `test > test` (32), `test > q:*` (19) | 70 | – | `edit patch ...`, then `tests/run.sh closure`, then `tests/run.sh closure -O 0` | `tachyonc query tests NAME`: the test cases that reach an item; `edit ... --test` runs them after a written edit |

Shortcuts already in plain sight, which agents chain by hand today:

- `query show A B C` takes several names. Agents used it, but rarely
  with the names of the next step.
- `refactor --script` runs several refactorings checked once, but it
  was run 3 times in all.
- `--show` on an edit replaces the `query show` that follows (an edit
  then `q:show`, 16 times in dev).
- `query refs --count` replaces a `refs` piped to `wc -l`.

AGENTS.md, the guide's tools topic and the eval prompt's table can say
"chain these into one call" for each of them, at no cost to the tools.

## (c) Bolder ideas

Each idea comes with a benefit estimated from the same data.

1. **`edit apply FILE`: declare the new state of the items and let the
   compiler make it so.**
   - The agent writes the new versions of N items, as it would anyway,
     in one file. One call replaces or inserts each item by its path,
     adds and removes imports, formats, checks once, and reports errors
     per item. One `undo` takes it all back.
   - It does what a `tachyonc do 'describe the change'` would do,
     without guessing intent. The description is the code.
   - Data: it absorbs sequences 3, 4 and most of the probe and replace
     pairs in the eval: about 80 eval turns (~1.6M tokens) and about 60
     dev turns (~11M).
   - Risk: an item that should have been patched is rewritten whole.
     The diff in the report (`--show`) keeps that visible.

2. **`query context` with a token budget on every query.**
   - Every query takes `--budget TOKENS`, and stops with `(N more: try:
     ...)` instead of printing all.
   - `query context` builds the answer an agent would assemble from
     3–5 queries.
   - Dev query output was 396k tokens in 533 calls. Kept in context for
     an average of about 70 more turns, that is about 28M context tokens
     (7% of the dev total). Capping and merging should save half, plus
     the ~17M of gap 1.

3. **Automatic feedback through the harness, not through calls.**
   - Hooks that append to the agent's own tool results:
     - `check`'s one-line errors after a Write or Edit of a `.tach`;
     - the `query show` of the item at the first error after a failing
       build;
     - after `tests/run.sh` fails, the failing case's diff at most 20
       lines long.
   - Zero calls for the agent. Data: 124 eval and 21 dev check-after-
     write calls, 92 dev check-then-build pairs, and `test > q:*`
     (19). About 150 eval turns (~3M) and 50 dev turns (~9M).

4. **A batch mode, and a server: smaller than they look.**
   - Agents already chain about two invocations per Bash call. A cached
     query takes 0.00–0.02 s (0.13's cache), so a long-lived server
     would save almost no wall time.
   - What batching would add is the transaction. That is gap 2 (`edit
     patch --pairs` with targets, `edit apply`, `refactor --script` for
     every command, all checked once and undone once).
   - A server's one real benefit is a pinned tools binary while the
     compiler under it is rebuilt (gap 10). That is cheaper to get from
     `target/tools/tachyonc`.
   - Estimate: under 1% of tokens beyond what gaps 2 and 10 give.

5. **JSON output (`--json`) for the harness, not for the model.**
   - Models read the one-line text format well: the error rate after
     the first try is low, and 75% of errors were retried successfully
     with the tool.
   - JSON would serve the eval runner, the hook's statistics and a
     future MCP front end: `{kind, path, file, lines, signature, text,
     errors[], try[]}`.
   - Estimate: no token saving for agents. It makes this analysis exact
     (today it parses shell lines and misses `$T`).

**What to build first, by tokens saved per unit of work:**

- the PostToolUse check hook (a script);
- `--help` everywhere, and `explain WORD` falling back to the guide;
- std in every program's queries;
- `edit patch --pairs` with `@@ TARGET` blocks;
- `query context` with `--budget`.
