# Agent eval reports

Results of the agent eval ([tests/agent-eval](../../tests/agent-eval/README.md)):
how well coding agents write tachyon with no help (`bare`), with the
guide inlined (`guide`), with the tools table (`tools`), with both
(`both`), against the same tasks in Rust (`rust`).

Each report is `NAME.md` (the tables: success rate and mean test score
per model and condition, median tokens, tool calls and wall time, the
per-task matrix, the share of tachyonc tools in the tools conditions)
and `NAME.json` (every run's result.json, compactly), made by

    tests/agent-eval/run.py report tests/agent-eval/results/RUN... --md docs/eval/NAME.md

Transcripts and final workspaces stay in `tests/agent-eval/results/`
(not committed).

From 0.16 the eval also has compiler tasks (`tests/agent-eval/ctasks/`):
changes to tachyon's own compiler, with AGENTS.md and its tools and hooks
(`compiler-tools`) against AGENTS.md without them (`compiler-plain`); the
report's "Compiler tasks: tools against plain" section. The next round
is planned in [tests/agent-eval/plans/0.16.md](../../tests/agent-eval/plans/0.16.md).

| report | compiler | models | conditions | tasks x reps |
|---|---|---|---|---|
| (none yet: the first is 0.14's) | | | | |
