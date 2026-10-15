# The agent eval

How well does a coding agent write tachyon, with and without the guide
and the tools, against the same task in Rust (which it already knows)?
Each task is a small program that reads stdin and writes stdout, graded
by hidden tests. The format of a task is fixed (see "Tasks" below);
reports go to [docs/eval/](../../docs/eval/README.md).

## Running

Python 3 (stdlib only), `rustc`, the `claude` CLI for hosted models,
Ollama for local ones. The compiler under test is `target/tachyonc`
unless `--tachyonc PATH` says otherwise; the runner copies it, so a
rebuild during a run changes nothing.

```sh
# the tasks are valid: solutions pass in both languages, starters fail
tests/agent-eval/run.py check-tasks [TASK...]

# agents: every task x condition x rep, results in tests/agent-eval/results/NAME
tests/agent-eval/run.py run --model claude:sonnet --cond bare,guide,tools,both,rust \
    --reps 3 --jobs 6 --out tests/agent-eval/results/0.14-sonnet
tests/agent-eval/run.py run --model ollama:qwen3-coder:30b --cond both,rust \
    --tasks 01-wordfreq,07-fix-bugs --out tests/agent-eval/results/0.14-qwen

# tables, plus docs/eval/0.14.json with every result
tests/agent-eval/run.py report tests/agent-eval/results/0.14-* --md docs/eval/0.14.md

# (0.16) every task: id, kind, time limit, title (compiler tasks: base, filters)
tests/agent-eval/run.py list --set all

# (0.16) the compiler tasks, tools against plain (ctasks/, below)
tests/agent-eval/run.py check-tasks --set compiler
tests/agent-eval/run.py run --model claude:sonnet --set compiler \
    --cond compiler-tools,compiler-plain --reps 3 --jobs 2 --out tests/agent-eval/results/0.16-compiler

# (0.16) grade finished compiler runs again from their changes.patch,
# without the agent (--only-stopped: a suite that stopped before any case)
tests/agent-eval/run.py regrade tests/agent-eval/results/0.16-compiler --only-stopped

# (0.16) no model: workspaces, prompts, settings, and the hooks fired on
# synthetic events (result.json's dry_run)
tests/agent-eval/run.py run --model claude:haiku --set compiler \
    --cond compiler-tools,compiler-plain --dry-run --out /tmp/eval-dry
```

A round is planned in `plans/` (0.16: [plans/0.16.md](plans/0.16.md),
one command, `sh tests/agent-eval/plans/0.16.sh`; 0.17: the validation
round against 0.16, [plans/0.17-validation.md](plans/0.17-validation.md)).

```sh
# (0.17) the self-check alone: can agents build, run, test and write in
# their workspaces inside the sandbox (run.py run does it first)
tests/agent-eval/run.py selfcheck --kinds tach,rust,compiler [--offline]

# (0.17) each run's anatomy (also for runs from before 0.17), checked
# against tool_calls_by_kind; --write stores it in result.json
tests/agent-eval/run.py analyze tests/agent-eval/results/0.16-* --check

# (0.17) new runs against a baseline round, per task, with a paired test
tests/agent-eval/run.py compare --baseline DIR... --new DIR... \
    --pairs guide-core=guide,guide-core=rust --md docs/eval/FILE.md

# (0.17) reuse a baseline's cells: only the missing (task, cond, rep) run
tests/agent-eval/run.py run ... --skip-existing-in BASELINE_RUNDIR
```

- `--model`: `claude:sonnet`, `claude:haiku` (any `claude --model`
  name), `ollama:MODEL`.
- `--cond`: `bare` (tachyon, the preamble says only what tachyon is and
  how to build), `guide` (bare + `tachyonc guide` inlined, generated from
  the binary under test; from 0.17 `tachyonc guide --full`, the long
  core), `tools` (bare + the tools table,
  [prompts/tools.md](prompts/tools.md)), `both`, `rust`.
- (0.17) a condition is `BASE[+MOD...]` ([lib/conds.py](lib/conds.py)):
  new bases `guide-core` (the ~2k example-first core: prompts/guide-core.md
  and `tachyonc guide` of a 0.17 compiler), `tools-core` (the tiered tools
  preamble, prompts/tools-core.md), `both-core` (the two),
  `rust-pairs` (paired Rust -> tachyon examples, prompts/rust-pairs.md,
  compiled by check-tasks), `compiler-tools-core` (the task's AGENTS.md
  with this checkout's tiered tools section); modifiers `+hook` (the
  check hook in any tachyon condition), `+test` (`tachyonc test` in the
  prompt, prompts/test.md or compiler-test.md, and the hooks of
  tools/agent-hooks/settings-eval.json, with the turn-end Stop hook),
  `+turn-end` (the Stop hook: with +hook settings-eval's `hook+turn-end`,
  alone its `turn-end`), `+recite` (prompts/recite.md after the task).
  Every check and Stop hook a condition registers is settings-eval.json's
  entry for it (`conds.Cond.settings_key`), its files copied out of the
  repository with the scripts.
- `--set programs|compiler|all|dev` (0.16): the task directories
  (`tasks/`, `ctasks/`, both, `devtasks/`: two tiny ones for working on
  the runner); or `--tasks-dir D[,D...]`; `--tasks a,b` picks some. A
  compiler task runs only in the compiler conditions, a program task only
  in the others.
- `--cond compiler-tools,compiler-plain` (0.16): the compiler tasks'
  conditions (below).
- `--reps N`: every (task, condition) N times (`repN` directories); use
  3 for a round, differences of a run or two are noise.
- `--check-hook` (0.15): in the tools and both conditions,
  tools/agent-hooks/check-after-edit.py runs after every change to a
  `.tach` file (Write, Edit, a `tachyonc edit` that wrote) and adds
  `tachyonc check`'s errors to that tool result, as it does for the
  agents working on the compiler; the prompt says so
  ([prompts/check-hook.md](prompts/check-hook.md)). Claude: a PostToolUse
  hook in `--settings` (a copy of the script outside the repository);
  Ollama: the loop runs the same script after write_file, edit_file and
  bash. result.json gets `check_hook` (checks, with_errors, errors,
  codes, ms_median; the log is kept as `check-hook.jsonl`).
- `--dry-run` (0.16): no model; each workspace is set up, `prompt.md`,
  `settings.json` and `command.json` (the `claude` command line) are
  written, and every hook in the settings is run on synthetic events as
  Claude Code would (a Write that adds an error to a `.tach` file: the
  check hook must report it; a `grep` of a `.tach` file: the query hook
  must block it); `dry_run` in result.json. A hosted run's
  `check-hook.jsonl` is written by the hook itself, so it shows the hook
  fired (checked on 00-hello-sum with Haiku, 2026-10-15: one check after
  the agent's Write; the run cost $0.007).
- Resumable: a run whose `result.json` exists is skipped, so rerun the
  same command (same `--out`) after an interruption. A run directory
  without `result.json` is redone from scratch.
- (0.17) `--selfcheck auto|hosted|offline|none`: before the first run,
  lib/selfcheck.py sets up a workspace of each kind the round needs
  (tach, rust, compiler) as a run does and runs probes in it: writing in
  the workspace and $TMPDIR, `mktemp` (with and without `-d`/`-t`),
  `python3`, `git`, the compiler, a build, a run, `check`; for compiler
  tasks `compiler/std/embed.sh -c`, `bootstrap/eval-build.sh --quick`,
  one `tests/run.sh` case; `tachyonc test` with `+test`. Offline: under
  sandbox-exec with an approximation of Claude Code's box (it reproduces
  0.16's mktemp failure when the shim is taken away). Hosted (the default
  for Claude; one Haiku session per kind, under a cent): the same probes
  in the real sandbox with the real permissions and hooks, plus the build
  and run as single commands, the Write tool in the workspace and in the
  sandbox's temp directory, and 14 command forms the 0.16 round saw
  refused (`&&`, `$?`, `$VAR`, `$TMPDIR` redirects, a loop, a heredoc,
  `$(...)`, a pipe, `cd`, `perl`, `sed -i`, ...), whose refusals are
  recorded, not required. A failed required probe stops the round
  (`OUT/selfcheck.json`, reused for 12 hours).
- (0.17) `--tools-tachyonc PATH`: the compiler-tools conditions get PATH
  as `target/tools/tachyonc` (newer tools on the same compiler tasks).
- Hosted runs go `--jobs` at a time; Ollama runs one at a time.

The prompt is `prompts/` assembled by `lib/prompts.py`: the language
preamble (`rust.md` or `tach-bare.md`), the guide and/or the tools for
those conditions, a note on the shell for the Claude backend
(`claude-env.md`), the closing instructions (`ending.md`), then the
task's `task.md`. Each run keeps its prompt in `prompt.md`.

## What a run does

1. A fresh workspace outside the repository
   (`$TMPDIR/tachyon-eval/RUN/TASK/MODEL/COND/repN/ws`, `--ws-root` to
   move it): the starter (`tach/` or `rust/`) copied, `git init` with
   one commit (so `tachyonc undo` and `query diff` work, and the agent
   can diff; done for Rust too), and a `bin/` on PATH holding only
   `tachyonc` (tachyon conditions) or only `rustc` (Rust), and (0.16) a
   `mktemp` shim: macOS mktemp without a template ignores `$TMPDIR` and
   writes in the per-user temp directory, which the sandbox forbids; the
   shim adds a template in `$TMPDIR`.
2. The agent, with the task's `timeout_s`.
3. Processes the agent left running in the workspace are killed, then
   the grading, in a copy without `.git` and the agent's `prog`: the
   fixed build command (`tachyonc main.tach -o prog`, `rustc -O
   --edition 2021 main.rs -o prog`), every hidden test (`./prog < NN.in`,
   exit 0 and stdout equal to `NN.out` up to line endings and trailing
   whitespace, within `test_timeout_s`), then `check.sh` if the task has
   one. Success = all of them.

Stored per run in `results/RUN/TASK/MODEL/COND/repN/`: `result.json`,
(0.17) `hook-output.jsonl` (what each hook returned to the agent:
lib/hook-tee.py wraps every hook, since the stream does not carry it),
`grade.json` (per test), `prompt.md`, `transcript.jsonl` (Claude's
stream-json, or the Ollama conversation with per-call counts),
`agent.stderr`, `workspace.tar.gz` (the final workspace, without `.git`
and binaries). `results/` is ignored by git; the report and its JSON are
what is committed.

`result.json`: `task kind model cond rep success tests_passed
tests_total build_ok check_ok wall_s turns tool_calls tool_calls_by_kind
input_tokens output_tokens cache_read_tokens cost_usd error`, and
`permission_denials` (count and the denied calls), `leftover_processes`,
`agent_env` (Claude's own report of its tools, MCP servers, skills,
plugins, permission mode), `compiler`, `model_id`; for tachyon,
`final_check` (0.15: the errors left in the finished workspace by code,
from `tachyonc check --json`; null for a compiler before 0.15) and with
`--check-hook`, `check_hook`.

- (0.17) `anatomy` ([lib/anatomy.py](lib/anatomy.py)): `tokens` (turns,
  output, fresh, cache write, cache read, cost, first and median prompt
  per model call), `roles` (calls as lookup / edit / verify / other;
  `segment_roles` add up to `tool_calls_by_kind`), `first_edit_call`,
  `errors` (the distinct compile errors seen in tool results and hook
  output, each with its class: name, type, match, syntax, unsafe, alloc,
  own, effects, other; Rust's by rustc code) with `classes` and `habits`
  (Rust habits in tachyon errors: `String`, `std::io`, a C call without
  `unsafe`, `Vec::new`, ...), `repair` (calls from an error to the next
  clean build/check/checked edit, per error), `edit_recovery` (failed
  edits and whether the next one worked), `denials` (by cause: heredoc,
  `$(...)`, `$VAR`, loop, `cd`, unlisted command, chain, pipe, redirect,
  a file outside the workspace), `ngrams` (the call sequence, top
  bigrams and trigrams), `guide_topics`, `erosion` (starter items, test
  files and assert-like lines gone at the end), `query_hook` (blocks and
  whether the suggestion was followed). The report adds tables for each.
- `input_tokens` is every prompt token the model read, summed over its
  calls: for Claude fresh + cache writes + cache reads
  (`cache_read_tokens` separately); for Ollama `prompt_eval_count`, the
  whole prompt of each call. `cost_usd` is Claude Code's list-price
  figure (not what a subscription pays).
- `tool_calls_by_kind` counts the commands inside each tool call:
  `tachyonc:query`, `tachyonc:edit`, `tachyonc:refactor`,
  `tachyonc:check`, `tachyonc:fix`, `tachyonc:explain`,
  `tachyonc:guide`, `tachyonc:undo`, ... (`tachyonc:build` for a
  compile), `rustc`, `run` (`./prog`), `shell:CMD` for the rest (`cat`,
  `sed`, `grep`, ...), `file:TOOL` for the file tools (Claude's Read,
  Write, Edit, Glob, Grep; the loop's read_file, write_file, edit_file).
  The report's tool share is tachyonc tools / (those + file tools + shell
  reads).

## Isolation

The agent must see only the workspace, the prompt and its compiler, not
this machine's configuration or this repository.

Claude (`lib/claude_backend.py`) runs `claude -p PROMPT --model M
--output-format stream-json --verbose` in the workspace with:

- an environment built from scratch (HOME, USER, PATH = bin dir +
  `/usr/bin:/bin:/usr/sbin:/sbin`, TMPDIR, LANG), with
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, `DISABLE_AUTOUPDATER=1`,
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`: nothing from a calling
  Claude session leaks in;
- `--setting-sources ""`: no user, project or local settings (no hooks,
  plugins such as an LSP, permissions, model settings);
- `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`: no MCP servers,
  the account's connectors included; `--disable-slash-commands`: no
  skills; `--no-session-persistence`;
- `--tools Read,Write,Edit,Glob,Grep,Bash`: no subagents, no web;
- `--settings` with the sandbox on (`autoAllowBashIfSandboxed`, no
  unsandboxed retry; `denyRead` and `Read(...)` deny rules for this
  repository, its main checkout and `~/.claude`), and a Bash allowlist of
  the commands a programmer runs (tachyonc, rustc, ./prog, cat, ls, echo,
  printf, head, tail, grep, sed, diff, wc, mkdir, cp, mv, touch, find,
  python3, sh, git, ...);
- `--permission-mode acceptEdits --permission-prompts none`: edits in
  the workspace go through, anything that would ask is denied at once
  and counted in `permission_denials`.

Verified on dev runs: the init event reports no MCP servers, no skills,
only built-in plugins and the six tools (`agent_env` in every
result.json); asked to, the agent found no CLAUDE.md, memory or hook
output in its context; `ls` and `cat` of the repository and
`~/.claude/projects` fail with "Operation not permitted"; network and
writes outside the workspace and temp fail; the repo's
`.git/agent-tools.jsonl` (written by its hook) has no entry from an eval
session.

Known denials: Claude Code splits a command line at `&&`, `;`, `|` and
newlines and wants every part allowed; a command it cannot resolve asks,
and with nobody to ask that is a denial. The preamble for the Claude
backend says so and suggests a script file (`sh script.sh`). In the 0.16
round 461 of 7,872 calls were denied (6%: heredocs, `$VAR`, chains, Write
calls to the sandbox's temp directory /tmp/claude-UID). (0.17) The
allowlist was widened from those denials (every command the agents
chained, `Bash(./*)` for programs built in the workspace, `Edit` rules
for the sandbox's temp directory, loops), all still inside the sandbox
and the permission system; the self-check measures what is still refused
(2026-10-15, Haiku: of 14 forms only a `for` loop), and every run's
`anatomy.denials` says why each denial happened. `--claude-permissions
bypass` (bypassPermissions in the sandbox) exists but is not used: the
rounds keep the permission system.

Ollama (`lib/ollama_backend.py`): a minimal loop against `/api/chat`
(`tools`, `options: {num_ctx: 32768, temperature: 0.2}`,
`keep_alive: 30m`), a short system prompt naming the tools, then the same
prompt as a user message. Tools: `bash(command)` (in the workspace,
under macOS `sandbox-exec` with the same box: writes only in the
workspace and temp, no network, the repository and `~/.claude`
unreadable; 60 s; output cut to about 8 KB with a note),
`read_file(path)`, `write_file(path, content)`, `edit_file(path, old,
new)` (paths confined to the workspace). It stops when the model answers
without a tool call, after 60 model calls, or at the task's timeout.

## Fairness caveats

- The two backends are different agents: Claude Code has a tuned system
  prompt, rich file tools (Read with line numbers, Edit with exact
  matching, Grep, Glob), a 120 s Bash limit that moves long commands to
  the background, context management and long context; the loop has four
  plain tools, 60 s commands and a 32k context that Ollama truncates
  silently. Compare models within a backend; across backends, compare
  the tachyon/Rust gap rather than the absolute numbers.
- Rust is the control: the agents know it from training, tachyon only
  from the prompt. `bare` is not "no help": `tachyonc` alone prints a
  usage line naming `tachyonc guide`, and agents find it (`tachyonc:guide` in
  `tool_calls_by_kind`).
- The tools table names the tools; whether an agent uses them is
  measured (the report's tool share), not forced.
- The Claude backend's shell note (variables are refused) appears only
  in Claude prompts; a few denials remain and are counted.
- Hosted runs are nondeterministic and the models change under their
  aliases (`model_id` records the one used); use `--reps` and read
  differences of a few runs as noise.
- Wall time depends on the API's load and, for Ollama, on the machine;
  tokens and tool calls are the steadier cost measures.

## Tasks

`tasks/NN-name/`: `task.md` (language-neutral), `meta.toml` (`kind`
write|fix|extend|refactor|perf, `title`, `timeout_s`, `test_timeout_s`,
optional `check = "check.sh"`, optional `starter_builds = false` for a
"fix the compile errors" task), starters `tach/` and `rust/`, reference
`solution/tach/` and `solution/rust/` (twins: same files and names),
hidden `tests/NN.in`/`NN.out` (6-15, under 1 MB each, a generator in
`tests/gen.py` for big ones), optional `check.sh` (run in the finished
workspace with `EVAL_LANG=tach|rust`, non-zero with a one-line reason).
`check-tasks` checks all of that: ids, files, test counts and sizes,
twin file names, both solutions build and pass every test and the check,
no solution test takes more than half its time limit, and every starter
fails (does not build, a test, or the check), building when
`starter_builds` says it should. (0.17) Also: the reference solutions'
lints (tachyon `fmt --check`, `lint --max-lines 1000`, `query unused`,
`fix --dry-run`; Rust `rustfmt --check`, `rustc -D warnings`;
`--no-lint` skips), every `variants/LANG-NAME.patch` (`diff -ruN a b`
against solution/LANG: a second correct solution written another way,
such as struct-like enum variants in Rust, one-line items, an iterator
with `type Item`, a scratch copy left in the workspace) builds and passes
the tests and the check, so a check.sh tests the task and not one way of
writing it; and every ```` ```tach ```` block of prompts/*.md builds.

## Compiler tasks (0.16)

`ctasks/NN-name/`: a change to tachyon's own compiler, made in a copy of
the repository, graded by building the compiler and running part of its
suite. The format is in `lib/ctasks.py`'s header: `meta.toml` (`kind`
optimize|refactor|fix|feature, `base`: the commit the task is made
from (0.16's round: `v0.16.0`; 0.17's rerun: the integrated release-0.17
tree, so the new tools are in play; `base_fallback`, optional: a commit
used while `base` does not exist), `suite`: the tests/run.sh filters that must
pass, optional `same_output` corpus), `task.md`, `README.md` (for
people), `starter.patch` (optional: a planted bug), `solution.patch` (the
reference), `hidden/` (tests copied over the graded tree), `grade.sh`.

- **The workspace**: `git archive` of the base, the starter patch,
  `git init` with one commit; `bootstrap/eval-build.sh`
  ([lib/eval-build.sh](lib/eval-build.sh): what bootstrap.sh does for
  HEAD, from `target/builder/tachyonc`, the release that builds the base,
  since the copy has no tags); `target/tachyonc` built from the starter;
  CLAUDE.md and `.claude/` removed: the prompt carries AGENTS.md; (0.17)
  tests/agent-eval removed (the reference solutions are in it). A base
  after the last release is built by that release, as bootstrap.sh
  builds HEAD.
- **compiler-tools**: AGENTS.md as it is; `target/tools/tachyonc`; the
  query-first hook (PreToolUse on Bash, Read, Grep, Edit, Write; PostToolUse
  on Bash) and the check hook (PostToolUse), registered in `--settings`
  as the repository's `.claude/settings.json` does, the scripts copied out
  of the repository; the prompt adds `prompts/check-hook.md`.
- **compiler-plain**: AGENTS.md without "Read source through the
  compiler" (the tools table), replaced by a paragraph on the file tools
  and the shell, and without the hook's lines (`ctasks.agents_md`; it
  fails if the result still names the tools, so a changed AGENTS.md is
  caught by `check-tasks`); no hooks, no `target/tools`.
- The prompt: `prompts/compiler-intro.md`, AGENTS.md, `compiler-env.md`
  (build with `bootstrap/eval-build.sh`, test with `tests/run.sh FILTER`,
  no gate, no commit needed), the shell note, `compiler-ending.md`, then
  `task.md`.
- **The grading** (`ctasks.grade`), in a copy without `.git` and
  `target/`: `hidden/` copied over it; the build with the fixpoint; every
  `suite` filter; `tachyonc same-output STARTER` on the corpus; `grade.sh`
  (with `TACHYONC`, `EVAL_STARTER_TACHYONC`, `EVAL_STARTER_TREE`).
  `tests_passed`/`tests_total` count those steps.
- **Kept per run**: `changes.patch` (the agent's diff, `target/` left
  out), `agent-tools.jsonl` (the query hook's log), `check-hook.jsonl`;
  result.json adds `changes` (files, lines added and removed),
  `query_hook` (records by kind, blocks, escapes and their reasons),
  `check_hook`, `grade_summary`, `base`, `base_commit`.
- `check-tasks` builds the starter (cached per task and commit) and the
  reference, and wants the reference to pass the grading and the starter
  to fail it. `--base REF` and `--builder PATH` override the base and the
  compiler that builds it (by default the `built_by` release of the
  base's releases.toml, from a bootstrap cache).
- The report's "Compiler tasks: tools against plain" section: success,
  medians and their tools/plain ratio per model, per task, tool use and
  the hooks, and the grading step failed runs stopped at.

## Files

- `run.py`: the command line.
- `lib/ctasks.py` (0.16): the compiler tasks: bases, workspaces,
  AGENTS.md per condition, grading, their check; `lib/eval-build.sh`.
- `plans/`: the commands of a round (`0.16.sh`, `0.16.md`).
- (0.17) `lib/conds.py` (conditions and modifiers), `lib/selfcheck.py`,
  `lib/anatomy.py` (`run.py analyze`), `lib/compare.py` (`run.py
  compare`), `lib/hook-tee.py` (logs what a hook returned).
- `lib/common.py` (tasks, meta.toml, processes), `lib/grade.py`,
  `lib/checktasks.py`, `lib/runner.py`, `lib/claude_backend.py`,
  `lib/ollama_backend.py`, `lib/toolkinds.py` (classifying tool calls),
  `lib/prompts.py`, `lib/report.py`.
- `prompts/`: the preamble parts.
- `devtasks/`: `00-hello-sum` (write) and `00-fix-small` (fix), for
  working on the runner.
