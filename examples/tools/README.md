# The compiler as a toolset

Each directory here is a small, realistic program and a session that
changes it with `volec`'s tools: the queries that read a program by
name, and the edits and refactorings that change it by name, checked
before they are written. The sessions are written for a reader who
drives the tools by hand, and for an agent that drives them in a loop.

| example | the program | what the tools do |
|---|---|---|
| [rename-and-move](rename-and-move/) | a lending library, 5 files | `refactor rename` of a field, two same-named functions, a local and a parameter; `refactor new-module` and `refactor move`; `query diff`, `undo` |
| [split-a-module](split-a-module/) | a shop's till in one 381-line module | `lint --max-lines`, `query items --comments`, `query deps`, `refactor split --plan`, then `--auto --names`; `undo` |
| [signature-and-variants](signature-and-variants/) | a small bank, 5 files | `refactor signature --reorder / --remove / --add / --rename-param`, `refactor field --rename / --add`, `refactor variant --add --arm-in`, `edit insert`, a multi-target `edit patch` |
| [rewrite-idioms](rewrite-idioms/) | word statistics, 5 files | typed `rewrite` of deprecated helpers into methods, `--where` on a type, index loops into `for x in v`; the imports it leaves unused removed; `query unused`, `edit delete` |
| [explore-unknown-code](explore-unknown-code/) | a transit route planner, 5 files | a first look and a bug found: `query items`, `query context --budget`, `query refs --kind`, `query grep --comments`, `query type`, `query impact`, `guide --find`, `try`, then `edit patch` |
| [fix-the-errors](fix-the-errors/) | a gradebook that does not compile | `check`, `explain`, `fix`, `query show FILE:LINE`, `edit patch` and its `try:` lines, `edit apply` for a fix that spans items |
| [prove-it-unchanged](prove-it-unchanged/) | a run-length encoder | renames, a named constant and `fmt` proven by identical assembly; `extract-function` proven by identical output; `same-output` for a compiler change |
| [merge-conflicts](merge-conflicts/) | a unit converter, two branches merged | `query conflicts`, `edit resolve --ours` and with new text, then `fix` and `edit patch` |

## Why tools, and not grep and sed

An agent working on code spends most of its effort reading it, and
reads it blind. Over the first ten releases of vole (about thirty
agents, two days of work), every shell command the agents ran was
recorded and classified ([docs/agent-tool-usage.md](../../docs/agent-tool-usage.md)):

- **56%** of all operations on source were reads of line ranges
  (`sed -n 'N,Mp'`, `head`, `tail`), and another **9%** were
  `grep "fn name" -A30`: the agent wanted one function and got it by
  guessing line numbers, often twice. `query show NAME` prints exactly
  the item, with its comment.
- **17%** were "who uses this": `grep -rn NAME`, which returns
  comments, strings and other things of the same name, and misses uses
  through imports. `query refs NAME` returns the uses the compiler
  resolved, with their kind and enclosing function.
- **3%** were mechanical edits with `sed -i`, `perl -pi` or Python, and
  they carried the bugs that were hardest to see: a rename that also hit
  a comment, a replacement that compiled and meant something else.
  `refactor` and `rewrite` change what the compiler resolved, and every
  edit is checked: one that adds an error writes nothing.
- The tally of programs run: `grep` 3310 times, `head` 2585, `sed` 1937,
  `volec` 410.

The tools were built from that list. The evaluation of 0.13
([docs/eval/0.13-findings.md](../../docs/eval/0.13-findings.md)) measured
what they buy, with Claude Sonnet and Haiku on twelve tasks, in vole
and in Rust:

- **The refactor task is where the tools win.** On a rename across a
  program, Sonnet with the tools used 103k tokens; the same task
  in Rust took 160k tokens. With the tools and the guide together it
  took 27 seconds, against 33 in Rust.
- On existing code (fix and extend tasks), vole cost about what Rust
  does: 51-197k tokens against 73-123k.
- **They do not pay off everywhere.** Given the tools without the
  guide, agents explored small programs query by query (Haiku made 134
  `query` calls over 12 small tasks); on a program of a few hundred
  lines, reading a file once costs less (`query show FILE.vl` prints
  one). The tools pay off on renames, moves, signature, field and
  variant changes, errors across files, and code too large to read,
  which is what these examples do.

What makes them suited to an agent, beyond being right:

- **One fact per line**, fields separated by tabs, sizes bounded
  (`--budget N` cuts any answer to about N tokens, and says what it
  left out).
- **Every problem is one line** `error CODE: message`, then `try:`
  lines that are commands to run as they are; `volec explain CODE`
  says what a code means.
- **Edits are atomic and checked**: the program is checked with the
  change before the change is written; an edit that adds an error writes
  nothing and prints the errors. `--show` prints what an edit wrote, so
  nothing needs to be read back; `undo` takes it back.
- **Names, not line numbers**: an edit names the item it changes, and a
  name does not move when an earlier edit adds lines.

## The sessions are tests

Each example's `README.md` is a transcript, and `tests/walkthrough/run.sh`
runs it: every `console` block's commands, in order, in a fresh copy of
the example's directory (made a git repository, so that edits are
journaled), and compares what they print with what the README says.
`tests/run.sh` runs it with the rest of the suite (`tests/run.sh
walkthrough` runs only it). When a tool's output changes on purpose,
`tests/walkthrough/run.sh -u` writes the new output into the READMEs
(the prose around it is kept), and the diff shows what changed.

```text
$ COMMAND      a shell line, run in the copy; `volec` is the compiler under test
> MORE         the command's next line (a heredoc's text)
other lines    what it printed: stdout, then stderr, then [exit N] when N is not 0
```

To try one by hand, copy its directory, commit it to a new git
repository on a branch `main` (the sessions use `git diff`, and
merge-conflicts makes branches), and type the commands.

## More tools

The sessions use a part of the toolset. Since 0.16 there are also
`rewrite --subst` and `--list`, `query callees --transitive`, `query
refs` on locals (`FN::x`), and `edit patch --nth` for text that occurs
more than once in an item; `volec guide tools` and
[docs/query.md](../../docs/query.md) list every command.
