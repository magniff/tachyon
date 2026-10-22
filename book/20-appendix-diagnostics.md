# Appendix B: reading diagnostics

> **Status: outline.** This file is the plan for the appendix. Replace it
> with the appendix, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

How to read any message the compiler or a program prints, and where to
look next. By the end the reader can decode an error they have never
seen, and find its explanation.

## Contents

1. **Two forms of the same error.** The terminal form (a build: `error[KIND]:`
   line, `-->` position, `= help:` and `= try:` lines) and the one-line
   form (`volec check`, a pipe, `--diagnostics=short`): `FILE:L:C:
   error[KIND] MESSAGE | help: ... | try: ...`. One example of each, from
   real output.
2. **Kinds and codes.** The broad kinds (`tokenizer error`, `parser
   error`, `module error`, `type error`, `unsafe`, `effect`) and the
   stable codes with a family prefix: `own.*` (values, moves and views),
   `conv.*` (conventions and Rust spellings), `contract.*`, `sync.*`,
   `distinct.*`, `arch.*`, `import.*`. A table: code, one-line meaning,
   chapter. Generate the code list from `volec explain --list` and check
   it before publishing.
3. **try: lines.** Code to paste or a command to run, as is; `volec fix
   --suggested` applies every exact one.
4. **volec explain.** `volec explain own.conflict`; `explain WORDS` for
   a message's words.
5. **Run-time failures.** One line `FILE:LINE:COL: message`, exit status
   101: index out of bounds, `unwrap` on `None`/`Err`, a bad enum
   conversion, a contract, an assertion, `panic`. `--trace` for the calls.
   `main -> Result` exits 1 with `Error: ...`.
6. **Tool problems.** `SEVERITY CODE: message` and `try:` lines;
   exit status 0, 1 (refused or failed: nothing written), 2 (usage).

Every pasted message is an `err`, `out` or `console` block, so the
appendix fails its test when a message changes.

## Sources

`volec guide errors`, `guide tools#diagnostics`, `volec explain --list`.
