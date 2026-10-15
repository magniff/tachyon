# Designing a language and toolchain for LLM agents: what the literature says, and what our evals say

A synthesis, written 2026-10-15 for the 0.17 cycle, of three reading
threads (languages designed for LLMs; teaching a model a language it has
not seen; tools and interfaces for coding agents) against tachyon's own
evidence: the 0.13 baseline ([../eval/0.13-findings.md](../eval/0.13-findings.md))
and the 0.16 round, which was still running when this was written
(282 finished runs: 180 Sonnet and 54 Haiku program runs, 48 compiler-task
runs; the Haiku runs of tasks 01-12 and the check-hook conditions had not
started). The companion document,
[applying-to-tachyon.md](applying-to-tachyon.md), turns this into a ranked
plan.

## How to read the evidence

Every claim carries a credibility tag, kept from the readers' reports:

- **[peer-reviewed]**: published at a named venue.
- **[accepted]**: an arXiv preprint whose page states acceptance (verified
  on the arXiv page for 2606.16827, 2608.00661, 2605.15607, 2603.14501).
- **[preprint]**: arXiv only. 2602.11988 (the AGENTS.md study) is listed
  by one reader as "on the ICLR 2026 virtual site"; its arXiv page names
  no venue, so it stays a preprint here.
- **[report]**, **[blog]**, **[project]**: a company report, a personal
  post, a README; no review, often n=1.

The numbers quoted from papers were read by the readers in the full texts
(arXiv HTML or PDF). Spot checks against the abstracts (done for the eight
most load-bearing papers) confirm the titles, venues and the abstract-level
figures ("reduces compilation errors by more than half", "over 20% cost");
the finer numbers (a 16.7% share, a 2,146-token sheet) are the readers'
and are not independently re-verified. Several papers are dated 2026 and
post-date tachyon's own design; their results were not available when
the tools were built, which makes the agreements below more informative
than they would otherwise be.

Our own numbers are medians over the finished 0.16 runs unless said
otherwise, computed from each run's `result.json` and `transcript.jsonl`
by a script over the raw transcripts (not the harness's report, which
was also run and agrees on the totals). With three reps per cell, a
difference of a run or two is noise.

## The state of our evidence, in one table

| | 0.13 (12 tasks, 1 rep) | 0.16 so far (18 tasks, 3 reps; 4 compiler tasks) |
|---|---|---|
| success, Sonnet, tachyon | 59/60 (one bare failure) | 100% in bare, guide and both (126 runs); Rust 98% |
| success, Haiku, tachyon | 59/60 | hard tasks: bare 18/18, both 17/18; Rust 18/18 |
| Sonnet cost vs Rust, small write tasks | 146k vs 55k input, $0.135 vs $0.073 | easy 01-12: 142k vs 49k input, $0.129 vs $0.062 (2.1x), **turns 5.5 vs 6** |
| Sonnet cost vs Rust, harder tasks | - | hard 13-18: 345k vs 125k input, $0.256 vs $0.174 (1.5x), **turns 12.5 vs 12.5** |
| Haiku cost vs Rust, hard tasks | - | both 1224k vs 805k input, $0.053 vs $0.039 (1.35x), turns 25.5 vs 29 |
| compiler tasks, Sonnet tools/plain | - | refactor 0.29x input, optimize 1.0x, fix 1.45x, feature 2.2x; success 100% both |
| compiler tasks, Haiku tools/plain | - | refactor 0.29x, optimize 1.05x, fix 1.95x, feature 2.3x; success 100% both |
| failed builds per run (tachyon) | median 0 | median 0 in every cell; 1-2 distinct compiler errors per Sonnet run, 0.7 per Haiku run with the guide |
| `query context` calls | 0 | 0 in 282 runs; `batch` 0; `--budget` 16 times |

Two things changed between the rounds and matter for reading the
literature. First, on tasks where the agent's turns are at parity with
Rust (Sonnet, hard tasks, with the guide), the whole premium is the
prompt: the guide inlined is about 15k tokens read on every turn
(first-turn prompt 26.5k tokens against 11.2k for Rust and bare), and
output tokens are 3.4k against 2.7k. Second, the compiler-task shape
matches the 0.13 shape exactly: the tools win large on the refactor and
cost on the small fix and on the feature, in both models.

---

## 1. Syntax familiarity versus novelty

**What the literature says.** The strongest results in the three threads
agree. For a language with no training data, syntax is the first
bottleneck: two thirds (GPT-4o) to 90% (o3-mini) of failures on Gleam and
MoonBit are syntactic, against under 10% in known languages, and
zero-shot pass@1 is 0-20% ([Giagnorio et al. 2026, accepted TSE]). On
Cangjie, ~83% of direct-generation failures are foreign syntax (Python,
Rust, Java, Swift constructs) and a 2.1k-token syntax sheet moves GPT-5
from 4.8% to 50.4% ([Cheng et al. 2026, accepted ESEM]). Similarity to a
known language outweighs corpus size: Lua (517k repos) beats R (981k)
everywhere, attributed to Lua's likeness to Python [Giagnorio 2026]. The
gap to a known language is expression, not reasoning: frontier models
pick the same algorithm in an invented language ~80% of the time and fail
to realize it, and extended thinking does not close the gap ([Kumar et
al. 2026, accepted COLM]). Both LLM-targeted languages that worked kept
the model writing something familiar and put the novelty in the compiler
or solver: Quasar's model writes a Python subset that a transpiler converts
([Mell et al. 2026, preprint, journal ref COLM]); AIDL's full language had
the *lowest* first-pass validity of its own ablations ([Jones et al. 2025,
preprint]). The Lattice anecdote predicts the specific failure for a
Rust-like language: Rust-shaped code with Rust semantics where the
language differs ("familiar syntax is a bridge; novel syntax is a wall")
([blog]).

**What our data says.** Agrees, and the Rust-like surface is doing the
work: median failed builds are 0 in every cell, and the compiler errors
agents do meet are not syntax. Over all 0.16 tachyon runs, the distinct
error messages seen in tool results (one count per result, suite runs
excluded) are led by `non-exhaustive match` (35), `calling a C function
is unsafe` (28), `expected X, got Y` (24), `unknown module` (23),
`undefined variable` (19), `unknown type` (16), `no method` (14),
`duplicate function` (14), `cannot infer type parameter` (12). Parser
errors are a handful. The "Rust habit" class is visible and specific:
`unsafe` around C calls and raw-pointer field access (about 44 of ~300),
`String`/`Box`/`char` as unknown types, and `std::io`/`std::collections`
as unknown modules. The guide's "Rust habits" table targets exactly these
and the bare condition (which has the guide only on demand) shows more of
them (Sonnet, hard: 1.6 errors/run bare vs 1.1 with the guide inlined).

**Disagreement.** None on direction. The literature's effect sizes are
for one-shot, function-level generation; in an agent loop with a
compiler the syntax problem is converted into turns, which is why our
success rates sit at the ceiling and the signal is cost.

## 2. Examples versus documentation versus rules

**What the literature says.** Examples beat prose beat rules, with the
clearest numbers in the learning thread. Few-shot code examples cut
syntax errors 15.4% against 8.9% for retrieved documentation, and won
in 15 of 24 benchmark cells [Giagnorio 2026]. A task-overfitted "manual"
(short explanations plus a code example per concept, fixed in the prompt)
was "significantly better than any other in-context technique and nearly
on par with fine-tuning" on easy benchmarks, and the authors call it the
ceiling of in-context learning [Giagnorio 2026]. Rules alone can be
*worse than nothing*: for Sonnet 4 on PyLang, a bare spec scored 12.5,
rules alone 8.2, snippets plus rules 46.6; "implementation patterns helped
far more than stated constraints" [Kumar 2026]. Hand-written translation
rules were the worst technique and translation *examples* the most
consistent gain (+0.9 to +6.3 pp) across models ([Giagnorio et al. 2025,
preprint]). A full grammar in the prompt gave nothing; a per-example
minimal grammar next to each snippet helped ([Wang et al. 2023,
peer-reviewed NeurIPS]). Weaker models need demonstrations where GPT-4
learns equally from descriptions ([Patel et al. 2024, peer-reviewed
NAACL]). Retrieval on demand for API detail is justified ([Zhou et al.
2023, peer-reviewed ICLR]) but every later comparison puts retrieved docs
below a curated sheet [Giagnorio 2026; Cheng 2026; Dutta et al. 2024,
peer-reviewed EMNLP].

**What our data says.** "The guide is the biggest lever" (0.13) holds in
0.16 and is now better localized. For Sonnet on the easy tasks the guide
halves the turns (13 bare to 5.5 with the guide, Rust 6) and on the hard
tasks brings them to parity (20.5 to 11.5-12.5, Rust 12.5). The guide is
already example-dense (every section carries a compiled example, tested
by `tests/run.sh guide`), but its two tables of Rust-to-tachyon rules are
prose rules of the kind the literature finds weakest, and we have never
run the examples-only versus rules-only comparison. What we have not
measured: which part of the guide pays. The errors above say the "Rust
habits" rows for `unsafe`, `[u8]`, allocation and `match` are the ones
agents still get wrong with the guide in context.

**Open.** No paper measures a *language* guide in an agent loop with a
compiler hook; no paper compares snippets-only against rules-only at
equal tokens for an agent. Both are cheap for us to run.

## 3. Context size and tiering

**What the literature says.** Three mechanisms, each with numbers.
*Saturation:* retrieved context stops helping around 3k tokens and then
slightly hurts [Dutta 2024]; the lift from whole example programs
saturates after 5-7 of them [Patel 2024]; tool documentation helps up to
~600 words and then falls ([Hsieh et al. 2023, preprint]). *Length tax:*
padding a prompt with irrelevant text costs Llama-8B up to 47.6 pp on
HumanEval and GPT-4o 3.1 pp ([Du et al. 2025, peer-reviewed EMNLP
Findings]); a single distractor lowers accuracy and Claude models in
particular respond to clutter by hedging ([Hong et al. 2025, report]).
*Context files in agents:* repository context files raised cost 20-23%
and steps by 2.5-3.9 with success flat or slightly down (LLM-generated)
or +2.4 to +4 pp (developer-written, not significant against none); the
smallest model lost time re-reading a prompt it already had; the one
content that reliably transfers is tool instructions the agent would not
know (`uv` used 1.6x per instance when named, <0.05 otherwise); overview
sections did not help and the testing section drove cost ([Gloaguen et
al. 2026, preprint]; the two readers quote +4 and +2.4 pp for
developer-written files from the same paper, so treat the figure as
"small and not significant"). A smaller correlational study finds the
opposite cost direction (-29% runtime with AGENTS.md) on repositories
whose files say how to build and test ([Lulla et al. 2026, preprint,
abstract only]). The vendor's own threshold for deferring tool
definitions is ~10k tokens or 10+ tools ([Anthropic 2025, blog]).

**What our data says.** This is where our data is sharpest. For Sonnet
the per-turn prompt with the guide is 26.5k tokens against 11.2k without
it; on the easy tasks the whole 2.1x cost gap to Rust is that prompt
(turns 5.5 vs 6, output tokens 3.4k vs 2.7k). The compiler tasks' tools
table and hook text add ~4.7k tokens per turn (16.6k against 11.9k) and
the tools condition reads 11% more input than plain on Sonnet with 18%
fewer turns. Haiku shows the re-reading effect the AGENTS.md paper saw
in GPT-5.1 mini: with the guide inlined it still ran `tachyonc guide
TOPIC` 32 times in 18 runs (1.8 per run), and in the bare condition 64
times, reading topics it could have had. Haiku's one 0.16 failure
(15-multi-module, 11 of 12 tests) came in the condition with the most
context, as in 0.13 where "everything up front" lowered Haiku's success.
The 0.13 finding that the tools table alone costs most (Haiku: 134
`query` calls over 12 small tasks) is the same mechanism as the paper's
"agents follow what the file names".

**Disagreement.** The paper's negative result for Claude Code with
developer-written files does not transfer to a language the model does
not know: our guide pays in success (0.13 bare failures) and turns. The
distinction the literature supports is between the *language* part (not
redundant, keep) and the *tools manual* part (discoverable, redundant with
`--help`, costs per turn).

## 4. Types, strictness and the feedback loop

**What the literature says.** Compile errors are type errors: 94% of
compilation errors in LLM-written TypeScript fail type checks, syntax is
6%; enforcing types cuts compilation errors by half or more and lifts
pass@1 by 3.5% (synthesis), 5.0% (translation) and 37.0% (repair),
relative ([Mündler et al. 2025, peer-reviewed PLDI]; abstract confirms
"more than half"). Strictness costs tokens on small tasks: across 13
languages on a ~200-line task, static languages were 1.4-2.6x slower and
costlier for Claude Code with correctness saturated at 597/600; Python
with mypy strict was 1.6-1.7x slower than Python ([Endoh 2026, blog
benchmark, >600 runs, one task]). A compiler in the loop raises
compilation success by 5-79 pp across 16 models and lets smaller models
with a compiler beat larger ones without, with syntax errors -75% and
undefined references -87% where agents win ([Kjellberg et al. 2026,
preprint]). Compiler messages alone are the *weakest* structured
feedback for repair (49.2 repair@1 against 57.9 for tests and 63.6 for
compiler plus tests plus a hint), and gains plateau by the third round
([FeedbackEval 2025, preprint]; [Kiecker et al. 2026, preprint, abstract]).
Targeted, checked edits (a changelog format) reached ~74% on real Rust
compile errors ([Deligiannis et al. 2023, preprint; ICSE 2025 listing
unconfirmed]). The lint guardrail that rejects an edit introducing a
syntax error was worth +3 points in SWE-agent's ablation, and 23.4% of its
failures were cascades of failed edits ([Yang et al. 2024, peer-reviewed
NeurIPS]).

**What our data says.** Agrees on both halves. Median failed builds are
0 and the errors agents meet are type and name errors, as the PLDI study
predicts. Our cost premium on small tasks (2.1x for Sonnet on 01-12) sits
inside Endoh's 1.4-2.6x range *between* static and dynamic languages,
and our premium is not thinking tokens: output tokens are nearly equal,
the prompt is the difference (section 3). The check-after-edit hook on
the compiler tasks runs in 35-50 ms median per check (the compiler keeps
a cache) and the eval's `check_hook` records show Sonnet needing it twice
per run, Haiku six times. Every tachyon diagnostic is one line with a
`help:` and often a `try:`; the FeedbackEval ordering (compiler plus hint
beats compiler alone) is the argument for keeping that format, and for
adding a test summary to the same channel, which we have not done. We
have not measured P(success after one failed edit); the tool-problem
counts (`edit.breaks` 17, `query.no-match` 14, `patch.no-match` 6 over
282 runs) are small.

**Disagreement.** None. The literature's warning (validate-until-pass
erodes intent: AIDL's models deleted constraints to satisfy the checker
[Jones 2025]) is unmeasured in our data; we do not count edits that
remove tests or assertions.

## 5. Ownership and lifetimes

**What the literature says.** Quantified in one venue-accepted study:
of 52,669 compile failures across C++, Java, C and Rust from seven
small-to-mid models, Rust's mix is type mismatch 43.4%, missing import
20.5%, **ownership/lifetime 16.7%**, trait bounds 6.1%, undeclared names
5.2% ([Pato Nogueira et al. 2026, accepted ISSRE]; the abstract does not
carry the breakdown, the reader took it from the full text). Rust's
compile-failure share is roughly double C/C++'s ([PROBE, accepted EMSE]).
In repository-level translation to Rust, 92.3% of failures are
compilation errors and the top rustc codes are E0599 method not found
(4,079), E0425 unresolved name (2,095), E0308 mismatched types (1,035),
E0277 trait bound (976), E0609 no such field (906); "failing to
understand differences between languages" is 73.9% of causes ([Ou et al.
2025, preprint]). No study isolates lifetime *syntax* from the ownership
*model*, and none evaluates an ownership system without lifetime
annotations. A position paper claims models fall back on `unsafe` to
silence the borrow checker (AdaTrans, unread, unverified).

**What our data says.** Tachyon today has no ownership checker, so the
nearest class is the borrow rules around raw pointers and explicit
allocation: `calling a C function is unsafe` (28), `passing a raw pointer
to a pointer parameter is unsafe` (7), `access to a field through a raw
pointer is unsafe` (4), `allocation is explicit: pass an allocator` (8).
Together about 15% of distinct errors, against roughly 29% for name and
API resolution (`unknown module`, `undefined variable`, `unknown type`,
`no method`, `unresolved import`, `is private`) and 14% for match
exhaustiveness. So in our runs, as in Rust's, the memory-model class is a
minority and name resolution is the largest. The 0.17 design's own
prototype measured the other side: value semantics with inferred view
summaries rejects none of the 379 eval-solution functions, where the
first (one-region) version rejected 13 (3.4%), all parsers and lexers
holding views of their input ([../design/value-semantics.md](../design/value-semantics.md)
§8.4 on branch design-017b).

**Disagreement and the testable claim.** The literature cannot say
whether removing lifetime syntax while keeping an ownership discipline
helps agents; our 0.17 can. The claim to test is: the `unsafe`/alloc
class and the (currently unobservable) use-after-free class go to near
zero under 0.17 with no new `own.*` class above a few percent, and the
agents' `try:` lines are applied as given.

## 6. Names and API resolution

**What the literature says.** After syntax, API use is the dominant
failure: with the Cangjie cheat sheet, foreign syntax drops from 83% to
30% of failures and API/library errors become the top class at 34.6%
[Cheng 2026]. The gap between an unseen language and Python widens from
12-17 pp on low-stdlib problems to 36-39 pp on problems needing missing
built-ins [Kumar 2026]. Names carry meaning for weaker models: aliasing
function names to random strings costs GPT-3.5 20 points and GPT-4 almost
nothing [Patel 2024]. In Rust translation the top three rustc codes are
all name resolution [Ou 2025]. Models invent tool and API names by analogy
(AutoCodeRover's hallucinated `search_file` [Zhang et al. 2024,
peer-reviewed ISSTA]; AIDL's `Rotate` [Jones 2025]). The vendor's tool
guidance: actionable errors, closest-match suggestions, every mature
harness has them ([Anthropic 2025, blog]; [harness study 2026, preprint]).

**What our data says.** Agrees: the name/API class is our largest
(section 5), and the 0.13 failure that cost a whole run was Sonnet
guessing ~30 names for reading stdin with "undefined variable" and no
hint. 0.14 added did-you-mean across the program and std and the exact
`use std::{name};` line; in 0.16 the agents still meet `unknown module`
23 times (the Rust paths `std::io`, `std::collections`, and `mod` lines
for files not yet written), `unknown type` 16 (`String`, `Box`, `char`)
and `no method` 14. The guide's std topic carries the full API listing
(8k tokens), which is the retrieval tier the literature puts second;
whether the agents read it before guessing is not measured.

## 7. Tool interfaces, discovery and manuals

**What the literature says.** The measured tool effects are about
bounding output and composing steps. SWE-agent's largest ablation losses
are all output-size effects: whole-file viewer -5.3, one-result-at-a-time
search -6.0, no history collapsing -3.0 [Yang 2024]. Symbol-level search
returning definitions rather than grep lines gave a 6x token reduction at
equal accuracy [Zhang 2024]. An LSP tool (definition, references, call
hierarchy merged into one call, hover) cut input tokens 24% and turns
17.5% at constant accuracy on bug fixes, +1-2 points for teacher models
([Song et al. 2026, preprint; abstract confirms 61.4%/70.8% only]). A
one-hop code-graph neighbourhood of ~2.3k tokens helps +2-3 points; a
two-hop one of ~10.5k tokens hurts below baseline ([Ouyang et al. 2025,
peer-reviewed ICLR]). Code actions that compose several tools in one call
cut turns from 7.6 to 5.5 and lift success 52 to 74% on multi-step tool
tasks, but lose to single calls on atomic tasks ([Wang et al. 2024,
peer-reviewed ICML]). Tool catalogues over ~10k tokens or 10+ tools pay
for deferral (Opus 4 49 to 74% on an internal eval with a tool-search
tool) [Anthropic 2025, blog]; listing 158 tool descriptions lowered a
model's willingness to call tools at all ([OSWorld-MCP 2025, preprint]);
a strong model is flat to ~220 tools and loses ~18 points at ~550
([MCPVerse 2025, preprint]). Which tool gets chosen is driven by an
assertive sentence and by position, not by merit or length: "should be
called whenever possible" shifted usage 4.4:1, a longer description
1.3:1, an example 1.1:1 ([Tool Preferences 2025, preprint]). Shipped
harnesses converged on a small core tool set, exact-match edits with a
closest-match suggestion on failure, diagnostics appended to edit
results, and deferred loading of the rest ([harness study 2026,
preprint]; [Rombaut 2026, preprint, abstract]). Bash-only scaffolds reach
the mid-70s on SWE-bench Verified with frontier models [mini-SWE-agent,
website], and the framework's share of the outcome shrinks with model
strength: 19.4 points (claude-3.5-sonnet), 3.8, 0.9 (newest) ([Mehtiyev
and Assunção 2026, preprint]). Agents find the right file but the wrong
function ([Majgaonkar et al. 2025, preprint]).

**What our data says.** Largely agrees, with one sharp new data point.
The refactor task is the one where the tools win by 3.4x on input tokens
for both models (Sonnet 127k vs 437k, Haiku 349k vs 1215k; 22 files, 88
uses), which no paper has because no benchmark has refactors; on the fix
and feature tasks the tools cost 1.45-2.3x, in line with the literature's
"tools move cost, not success, on bug fixes". The transcripts show why:
on 23-fix-checker the plain agent ran `cat usefulness.tach` once (one
file, under 500 lines) and patched; the tools agent ran `query items`,
then `query show` on 15 names, met one `patch.no-match`, and finished
later. On 24-std-method the tools agent was blocked by the query-first
hook twice, escaped with `# no-query: need line in std.tach for the Edit
tool` (the tool cannot edit std by name, tool-gaps-016 item 2), and then
did what the plain agent did. `query context` was never called in 282
runs; `batch` never; `--budget` 16 times. Of 56 Sonnet `query` calls on
the compiler, 21 were `show`, 19 `grep`, 5 `def`, 5 `items`, 5 `text`,
1 `refs`. The composition preference is visible everywhere: agents chain
`build && ./prog < in`, `tests/run.sh a | tail; tests/run.sh b | tail`,
and that is where the harness refuses them (`&&` chains and `$vars` are
52 of the denials in the `both` condition). The AGENTS.md table lists 45
forms in ~3k tokens; the vendor's deferral threshold is in sight.

**Disagreement.** The literature's "tools do not raise success" is
confirmed here (100% everywhere), but our cost finding is more
discriminating than theirs: the sign flips with the task, not with the
model.

## 8. Feedback: compiler versus tests

**What the literature says.** Test feedback beats compiler feedback for
repair (57.9 vs 49.2) and the mix with a hint beats both (63.6)
[FeedbackEval 2025]. The share of steps spent validating correlates with
success (rho +0.50) and delaying the first edit correlates with success
(rho +0.68) [Mehtiyev 2026]. Reproduction tests generated by the agent
validated the gold fix only 44% of the time [Xia et al. 2025,
peer-reviewed FSE]. Per-edit returns plateau by round 2-3; one harness
checks once at turn end ("verify-on-stop") instead of after every edit
[harness study 2026]. A diagnostics delta ("2 errors to 0") is the
cheapest reading of a check ([Zhang 2025/2026, preprint, no experiments]).

**What our data says.** The check hook is cheap (35-50 ms) and
lowered cost in 0.15's study; tonight's compiler runs show it firing 2
(Sonnet) to 6.5 (Haiku) times per run. Verification by the agent itself
dominates Haiku's turns: 11-16 verify actions per hard run (`./prog <
input` 19 times per run in `both`) against 8 in Rust, and Haiku writes its
own test inputs and comparison scripts in nearly every run. There is no
`tachyonc test`; the agents build one from `./prog`, `diff`, `cmp` and
Python, and the harness refuses part of it. Sonnet's first edit comes at
call 2-3 with the guide and at call 6 without it or in Rust, which
reads as "the guide replaces exploration", not "front-loaded patching".

## 9. Fine-tuning a small model

**What the literature says.** The recipe that works for a no-resource
language is continued pre-training of a *base* model on 13-28M tokens of
code plus docs, then adding the Instruct-minus-Base weight difference; an
8B model so treated beat a 32B Instruct under any prompting and reached
22-33% on the hard benchmark where in-context methods got 1-12%
[Giagnorio 2026, accepted TSE; the abstract confirms the qualitative
claim]. Supervised fine-tuning on a few thousand functions is worse and
can hurt a large model (DeepSeek 33B below baseline) [Giagnorio 2025].
Fine-tuning teaches syntax (errors fall to 2.5-4.5%) but leaves a 12-19 pp
semantic gap that does not close with more data, DPO/GRPO, infilling or
latent objectives [Kumar 2026]. Synthetic corpora by translating tested
programs from a high-resource language and keeping what passes the
target's tests double or triple pass@1 for small models (MultiPL-T:
StarCoderBase-15B OCaml 6.9 to 19.9, Racket 11.8 to 21.0; ~10k A100-hours
to generate) ([Cassano et al. 2024, peer-reviewed OOPSLA]); a Python
"bridge" solution in the training data helps most when the bridge
language is closest ([Zhang et al. 2025, peer-reviewed ACL Findings],
training-time only, never tested as a prompt trick). A fine-tuned
translator reached a high compile rate (85%) with poor correctness (61%)
[Shen et al. 2026, preprint]. The esoteric-languages study finds weak
agents gain from executable helpers, not from distilled prose ([Sharma
et al. 2026, preprint, abstract]).

**What our data says.** Only the 0.13 Qwen3-Coder 30B runs: 0 of 6 solved,
Rust included, so local models are off until an idle machine. Corpus
size is the first question and is unmeasured: tokens in compiler/src,
compiler/std, examples, tests, docs. The eval's Rust twins (18 tasks ×
reference solutions in both languages) are the seed of exactly the
MultiPL-T recipe, with `tachyonc` and the hidden tests as the filter.

## 10. Evaluation methodology

**What the literature says.** Every no-resource result is function-level
(HumanEval, MBPP, McEval-Hard, Codeforces); none has an agent loop with a
compiler hook, and the one agent-level study of context files is Python
only with one sample per instance [Gloaguen 2026]. Nobody decomposes
turns: papers report pass@1, dollars and sometimes steps [Mehtiyev 2026
is the exception, and it is observational]. Run-to-run variance on
SWE-bench Lite is ±0.5 points over six runs [Yang 2024]; shuffling tool
descriptions moved an accuracy 20.5 to 22.7 [OSWorld-MCP 2025], a
warning for any tool ablation of our size. Benchmarks are contaminated
(4.3% of SWE-bench Lite issues contain the patch) [Xia 2025]. A good
protocol, from the TSE paper: 10 runs per task, McNemar with
Benjamini-Hochberg; its hard benchmark is what separated techniques that
tied on easy ones.

**What our data says.** Our suite is at the success ceiling for hosted
models (0.13: 59/60; 0.16: 100% in every tachyon cell), so the
instrument measures cost, and cost is where the literature's effects are
too. Three reps show the noise: Sonnet 17-debug-crash runs 129k (bare),
368k (both), 201k (guide) — the ordering of conditions on one task is
not stable. We do not yet record: the error class of each check (we can,
from `check --json`), lookups versus verification versus edit turns per
run (the script behind this document does it from the transcripts), the
share of re-read prompt tokens, edits that delete tests or assertions,
P(edit success | prior failure), hallucinated std names, or Rust-habit
tags on errors.

---

## Open questions nobody has answered (where tachyon's eval can contribute)

1. **Same frontier agent, same tasks, two languages that share a syntax
   and differ in semantics.** Rust versus tachyon is the nearest thing to
   this in existence; nobody has it. The publishable result is the
   cost-versus-task-size curve (Endoh has one size; we have three task
   kinds and 18 tasks).
2. **Instruction tiering by model strength for a language the model does
   not know.** The AGENTS.md study has the Python case; the
   esoteric-languages study has distilled prose failing on weak agents.
   A 2k core versus the 7k guide, on Haiku and Sonnet, is unmeasured.
3. **Examples-only versus rules-only at equal tokens, in an agent loop.**
   The TSE and COLM results are one-shot.
4. **A language guide in the prompt versus on demand per step**
   (recitation before the edit, Du et al.'s mitigation). Our `bare`
   condition is accidentally the on-demand version and costs about the
   same as inlined for Sonnet, with twice the turns.
5. **Ownership without lifetime syntax, by error class, against Rust's
   16.7%.** 0.17's inferred views are the only such system with an eval
   attached.
6. **Explicit allocators and capability parameters.** No study measures
   them; our `allocation is explicit` count (8 in ~300 errors) is the first
   number.
7. **Effects.** Inferred effects produced zero annotation errors in 282
   runs and were never queried; whether surfacing them in a decision (a
   hook refusing `io` in a pure function) changes anything is open.
8. **Turn anatomy as the cost driver.** Every paper reports dollars or
   steps; none splits turns into lookup, edit, verify and re-read. We can,
   and tonight's split says: Sonnet's premium is prompt size, Haiku's is
   verification and re-reading.
9. **Agent-designed diagnostics.** Our one-line `help: | try:` format
   against rustc's long form is a clean A/B nobody has run.
10. **Intent erosion under validate-until-pass.** Count deleted tests,
    assertions and items per run; zero papers report it.
11. **The refactor benchmark.** No tool paper has one; our 3.4x is the
    first number and deserves more tasks (signature changes, moves,
    variant additions across files).

## Bibliography

Languages and DSLs for LLMs
- Al Mazrouei. Anka: A Domain-Specific Language for Reliable LLM Code Generation. arXiv:2512.23214, 2025. [preprint]
- Mell, Zhang, Mell, Li, Ramalingam, Yu, Zdancewic, Bastani. Quasar: A Programming Language Specialized for LLM Code Actions. arXiv:2506.12202, 2026 (journal ref COLM 2026). [preprint]
- Jones, Hähnlein, Zhang, Ahmad, Kim, Schulz. AIDL: A Solver-Aided Hierarchical Language for LLM-Driven CAD Design. arXiv:2502.09819, 2025. [preprint]
- Levin, Gwilt, Berger, Freund. Pythoness: Effective LLM-Driven Code Generation. arXiv:2501.02138, 2025. [preprint]
- Zhang et al. Renaissance of Literate Programming in the Era of LLMs. arXiv:2502.17441, 2025. [preprint]
- Vercel Labs. Zero. github.com/vercel-labs/zero, 2026. [project]
- Ronacher. A language for agents. lucumr.pocoo.org, 2026-02-09. [blog]
- tinycomputers.io. Teaching LLMs languages they've never seen (Lattice). [blog]
- Reitz. The language an LLM would invent. 2025. [blog; speculative]

Learning an unseen language
- Giagnorio, Martin-Lopez, Bavota. No Resource, No Benchmarks, No Problem? Evaluating and Improving LLMs for Code Generation in No-Resource Languages. arXiv:2606.16827, 2026. [accepted, IEEE TSE]
- Giagnorio, Martin-Lopez, Bavota. Enhancing Code Generation for Low-Resource Languages: No Silver Bullet. arXiv:2501.19085, 2025. [preprint]
- Bannihatti Kumar, Makhija, Arivazhagan, Gangadharaiah. Syntax Without Semantics: Teaching LLMs to Code in an Unseen Language. arXiv:2605.15607, 2026. [accepted, COLM 2026]
- Cheng, Liu, Li, Wu, Jiang, Zhang. CangjieBench: Benchmarking LLMs on a Low-Resource General-Purpose Programming Language. arXiv:2603.14501, 2026. [accepted, ESEM 2026]
- Shen, Cheng, Yang, Zhang, Wu, Hu. Bridging the Knowledge Void: Inference-time Acquisition of Unfamiliar Programming Languages. arXiv:2602.06976, 2026. [preprint]
- Sharma, Thorat, Chopra. Frontier Coding Agents Use Metaprogramming to Adapt to Unfamiliar Languages. arXiv:2606.10933, 2026. [preprint, abstract only]
- Dutta, Singh, Verbruggen, Gulwani, Le. RAR: Retrieval-augmented retrieval for code generation in low-resource languages. EMNLP 2024. [peer-reviewed]
- Patel, Reddy, Bahdanau, Dasigi. Evaluating In-Context Learning of Libraries for Code Generation. NAACL 2024. [peer-reviewed]
- Cassano et al. Knowledge Transfer from High-Resource to Low-Resource Programming Languages for Code LLMs. OOPSLA 2024. [peer-reviewed]
- Zhang et al. Bridge-Coder. Findings of ACL 2025. [peer-reviewed]
- Wang et al. Grammar Prompting for Domain-Specific Language Generation. NeurIPS 2023. [peer-reviewed]
- Zhou et al. DocPrompting. ICLR 2023. [peer-reviewed]
- Joel, Wu, Fard. A Survey on LLM-based Code Generation for Low-Resource and Domain-Specific Programming Languages. arXiv:2410.03981. [accepted, ACM TOSEM; a map, not evidence]
- Anirudh et al. Code Generation in Unseen Robot Programming Languages using LLMs. TechRxiv 2025. [preprint, unreadable beyond abstract]
- Jia, Gao, Li. Middle Code Prediction. ACML 2024. [peer-reviewed, abstract only]
- Willison. NanoLang. simonwillison.net, 2026-01-19. [blog, n=1]

Context length and context files
- Gloaguen, Mündler, Müller, Raychev, Vechev. Evaluating AGENTS.md: Are Repository-Level Context Files Helpful for Coding Agents? arXiv:2602.11988, 2026. [preprint]
- Lulla et al. On the Impact of AGENTS.md Files on the Efficiency of AI Coding Agents. arXiv:2601.20404, 2026. [preprint, abstract only]
- Du et al. Context Length Alone Hurts LLM Performance Despite Perfect Retrieval. Findings of EMNLP 2025. [peer-reviewed]
- Liu et al. Lost in the Middle. TACL 2024. [peer-reviewed; 2023-era models]
- Hong, Troynikov, Huber. Context Rot. Chroma, 2025. [report]

Types, strictness, feedback
- Mündler, He, Wang, Sen, Song, Vechev. Type-Constrained Code Generation with Language Models. PLDI 2025 (PACMPL, DOI 10.1145/3729274). [peer-reviewed]
- Huang et al. TyFlow. arXiv:2510.10216. [preprint]
- Endoh. Which programming language is best for Claude Code? dev.to/mame, 2026; github.com/mame/ai-coding-lang-bench. [blog benchmark]
- Kjellberg, Staron, Fotrousi. From LLMs to Agents in Programming: The Impact of Providing an LLM with a Compiler. arXiv:2601.12146, 2026. [preprint]
- FeedbackEval. arXiv:2504.06939, 2025. [preprint]
- Kiecker et al. Is Three the Magic Number? arXiv:2607.05197, 2026. [preprint, abstract only]
- Blyth et al. Static Analysis as a Feedback Loop. arXiv:2508.14419, 2025. [preprint, abstract only]
- openJiuwen. arXiv:2608.27969, 2026. [preprint; no ablation]

Rust, ownership, errors
- Pato Nogueira, Vieira, Campos. Unreliable in Practice? A Comprehensive Study of Errors in LLM-Generated Code. arXiv:2608.00661, 2026. [accepted, ISSRE 2026]
- Pato Nogueira, Vieira, Campos. PROBE. arXiv:2607.13820. [accepted, Empirical Software Engineering]
- Ou, Liu, Chen, Wang, Peng, Zheng. RustRepoTrans. arXiv:2411.13990, 2025. [preprint]
- Deligiannis, Lal, Mehrotra, Rastogi. Fixing Rust Compilation Errors using LLMs (RustAssistant). arXiv:2308.05177. [preprint; ICSE 2025 listing unconfirmed]
- AdaTrans. arXiv:2606.31706. [position, unread]

Token efficiency of syntax
- Sun et al. AI Coders Are Among Us: Rethinking Programming Language Grammar (SimPy). arXiv:2404.16333, 2024. [preprint]
- Sun, Yang, Du, Yang, Li, Lo. Token Sugar. ASE 2025. [peer-reviewed]
- Alderson. Which programming languages are most token-efficient? 2026. [blog]

Verification-aware languages
- AutoVerus. OOPSLA 2025. [peer-reviewed]
- Xu, Li, Qu, Fu, Yuan. Local Success Does Not Compose (DafnyComp). arXiv:2509.23061. [preprint]
- Li, Zetzsche, Somayyajula. Dafny as Verification-Aware Intermediate Language. arXiv:2501.06283. [preprint]

Tools and harnesses
- Yang, Jimenez, Wettig, Lieret, Yao, Narasimhan, Press. SWE-agent. NeurIPS 2024. [peer-reviewed]
- Xia, Deng, Dunn, Zhang. Agentless. FSE 2025. [peer-reviewed]
- Zhang, Ruan, Fan, Roychoudhury. AutoCodeRover. ISSTA 2024. [peer-reviewed]
- Wang et al. Executable Code Actions Elicit Better LLM Agents (CodeAct). ICML 2024; OpenHands, ICLR 2025. [peer-reviewed]
- Ouyang et al. RepoGraph. ICLR 2025. [peer-reviewed]
- Song et al. SWE-Master. arXiv:2602.03411, 2026. [preprint]
- Zhang. Language Server CLI / RL from Compiler and Language Server Feedback. arXiv:2510.22907. [preprint; design only, no experiments]
- MCPVerse. arXiv:2508.16260. [preprint]; OSWorld-MCP. arXiv:2510.24563. [preprint]; RAG-MCP. arXiv:2505.03275. [preprint, abstract only]
- Anthropic. Introducing advanced tool use (2025-11-24); Writing effective tools for agents (2025-09-11). [vendor blog]
- Hsieh et al. Tool Documentation Enables Zero-Shot Tool-Usage. arXiv:2308.00675. [preprint]
- Tool Preferences in Agentic LLMs are Unreliable. arXiv:2505.18135. [preprint]
- Mehtiyev, Assunção. Beyond Resolution Rates. arXiv:2604.02547, 2026. [preprint]
- Majgaonkar et al. Understanding Code Agent Behaviour. arXiv:2511.00197. [preprint]
- Harness Engineering: A Source-Code Study of Eleven Systems. arXiv:2609.00006, 2026. [preprint]
- Rombaut. Inside the Scaffold. arXiv:2604.03515. [preprint, abstract only]
- mini-SWE-agent. mini-swe-agent.com. [website]
- Cheng et al. To Diff or Not to Diff? Findings of ACL 2026. [peer-reviewed, abstract only]; SWE-Edit, arXiv:2604.26102; Cascaded Code Editing, arXiv:2604.19201. [preprints, abstracts only]

Our own
- docs/eval/0.13-findings.md; docs/eval/0.13-baseline.md.
- The 0.16 round in progress (2026-10-15): .claude/briefs/evalruns/0.16/, the compiler and program result directories; tests/agent-eval/plans/0.16.md.
- docs/tool-gaps-014.md, docs/tool-gaps-016.md; docs/agent-tool-usage.md.
- docs/design/value-semantics.md (branch design-017b), §8 prototype results.
