# guide: `tachyonc guide`

The language, taught by the compiler that implements it (0.13), for a
reader who has never seen tachyon: `tachyonc guide` prints the core
guide (about 5k tokens), `tachyonc guide TOPIC` one topic, `--list` the
topics with their sizes, `--all` everything; (0.15) `--find WORDS`
the paragraphs about some words, `TOPIC#SECTION` one section, `--budget
N` a cut to about N tokens.

The text is `compiler/guide/*.md` (ASCII, in the order of
`compiler/guide/topics.txt`); `compiler/guide/embed.sh` makes `text/`
from it, as `compiler/std/embed.sh` makes `front/stdsrc.tach` from std,
so a compiler's guide is its own version's. Run it after changing the
text. A line `@STD-API@` in a topic becomes std's API and `@TOPICS@` the
list of topics, when the topic is printed.

| module | |
|---|---|
| `mod.tach` | the command: topics by name, the placeholders, `--list` |
| `find.tach` | the guide by piece (0.15): `--find WORDS` (paragraphs under `# TOPIC#SECTION`, ranked by the words they hold), `TOPIC#SECTION`, `TOPIC#`; `explain WORDS` uses it |
| `stdapi.tach` | std's API from std's embedded source: public items with their comments, signatures without bodies |
| `text/` | generated (do not edit): a module per topic, `t_NAME.tach`, and the table of topics |

`tests/guide/run.sh` (category `guide` of `tests/run.sh`) compiles every
`tach` block of every topic (a program, items, or statements in a
`main`), runs it against the `out` block after it (with the `in` block
as stdin), expects each `err` block's errors, checks the std section
against the compiler's item index (`query items std`), the core guide's
budget (28 KB, about 7k tokens) and that the embedded text is fresh.
`tests/guide/run.sh -f compiler/guide/NAME.md` checks one topic's
source while it is written. It also checks --find, sections, --budget,
`explain WORDS`, `--help` on every command and `tachyonc try`.
