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
```

- `--model`: `claude:sonnet`, `claude:haiku` (any `claude --model`
  name), `ollama:MODEL`.
- `--cond`: `bare` (tachyon, the preamble says only what tachyon is and
  how to build), `guide` (bare + `tachyonc guide` inlined, generated from
  the binary under test), `tools` (bare + the tools table,
  [prompts/tools.md](prompts/tools.md)), `both`, `rust`.
- `--tasks-dir D` for another task set (`devtasks/` holds two tiny ones
  for working on the runner); `--tasks a,b` picks some.
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
- Resumable: a run whose `result.json` exists is skipped, so rerun the
  same command (same `--out`) after an interruption. A run directory
  without `result.json` is redone from scratch.
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
   `tachyonc` (tachyon conditions) or only `rustc` (Rust).
2. The agent, with the task's `timeout_s`.
3. Processes the agent left running in the workspace are killed, then
   the grading, in a copy without `.git` and the agent's `prog`: the
   fixed build command (`tachyonc main.tach -o prog`, `rustc -O
   --edition 2021 main.rs -o prog`), every hidden test (`./prog < NN.in`,
   exit 0 and stdout equal to `NN.out` up to line endings and trailing
   whitespace, within `test_timeout_s`), then `check.sh` if the task has
   one. Success = all of them.

Stored per run in `results/RUN/TASK/MODEL/COND/repN/`: `result.json`,
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

Known denials: Claude Code asks before running a command line with shell
variables (`for f in *; do ... $f; done`, `P=./prog; $P`) even in the
sandbox, and with nobody to ask that is a denial. The preamble for the
Claude backend says so and suggests a script file (`sh script.sh`, which
is allowed). Writes outside the workspace are denied by design. On the
dev runs about 1 call in 10 was denied (mostly `$?`, `$var`, subshells);
the agents carried on. `--claude-permissions bypass` runs Claude with
`bypassPermissions` inside the same sandbox instead (deny rules still
hold, plus an Edit deny rule for the home directory), so nothing is
denied; it is not verified yet and is for the repository owner to
choose.

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
`starter_builds` says it should.

## Files

- `run.py`: the command line.
- `lib/common.py` (tasks, meta.toml, processes), `lib/grade.py`,
  `lib/checktasks.py`, `lib/runner.py`, `lib/claude_backend.py`,
  `lib/ollama_backend.py`, `lib/toolkinds.py` (classifying tool calls),
  `lib/prompts.py`, `lib/report.py`.
- `prompts/`: the preamble parts.
- `devtasks/`: `00-hello-sum` (write) and `00-fix-small` (fix), for
  working on the runner.
