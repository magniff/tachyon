# Tool gaps after 0.16: what is left, and how to close it

The shortfalls agents recorded while building 0.15 and 0.16
(`tools/agent-feedback`, in `.git/agent-tools.jsonl`; the examples/tools
sessions; the ex-c restructure; [tool-gaps-014.md](tool-gaps-014.md)'s
open items), after the first part of the 0.17 tools track. The fixed
ones are listed first, with their tests; the rest come with a proposed
design and a rough cost. This list is to be merged with the findings of
the next eval round.

## Fixed in 0.17 (first part)

Each has a case in `tests/refactor/tools017.t` (or the transcript
named).

| shortfall | reported by | now |
|---|---|---|
| `edit delete MODULE` left the module's file on disk | ex-tools | the `mod` line, its file and its children's files, one edit, one `undo` |
| `edit patch FILE:LINE` on a `mod x;` line patched x's file (reported 9 times) | c14-opt, t15-conflicts, c15-phase0, t15-context, c15-errors, c15-widen, c15-perf, c16-checkalloc, c16-alloc-checks, fix16-small | that line (`mod x;` -> `pub mod x;`); the module's name still gives its file |
| `MODULE::extern`, `crate::extern` no edit target (query show took them) | t15-feedback, t15-context, fix-index-order | `edit patch\|replace\|insert\|delete MODULE::extern`; none yet: `replace` puts it after the `use` lines |
| `refactor inline` into an f-string hole wrote a multi-line `if` | ex-tools | the body on one line in a hole (its lines when it has a `//` comment) |
| `rewrite` left the imports it made unused | ex-tools | removed in the same edit, `note rewrite.imports` |
| `rewrite --in` took a FILE or MODULE only, once | ex-tools, c16-tools, c16-selfhost | `--in` an item (a function, a type...), repeated: the scopes add up; `query refs\|grep --in ITEM` too |
| `rewrite`'s `edit.breaks` offered only `--no-check` | ex-tools | `note rewrite.where`: each type a hole has at the sites, and a `try:` with its `--where` |
| `refactor variant`'s refusal showed 2 of 3 matches | ex-tools | one `query show` naming them all (`shapes.t`, `shortfalls.t`) |
| `query grep --comments` gave a doc comment's module | ex-tools | the item below it (a field's comment: the field) |
| `refactor move --to` a missing module: `refactor.no-module`, then `new-module` (eval: every refactor run) | eval 10-refactor, 0.14 gap 6 | made in the same edit, `note refactor.made-module` (`modules.t`) |
| `refactor rename` rewrote `MODULE::header`, `main::header` in comments | t15-edits | a path mention counts only when its path names the item's module; and (new) a path mention is renamed even when another item has the name |
| extract-function's `try:` said `./calc.tach:85`; `--lines` past the end printed `FN`, `NEW` placeholders | ex-tools, c15-tools | `calc.tach:85`; past the end: `refactor.range` with the body's lines (`code.t`) |
| `query refs` missed the uses of C-string (and string) constants | s14-tools2 | found: the checker puts the literal in their place, refs finds them by name; `rename` changes them |
| `query.ambiguous`'s `try:` lines dropped `--old`/`--new` | wf-79-3 | each is the command as run, the name replaced (`shapes.t`) |
| `edit replace FILE.tach < text` wrote into the parent's `mod` line | integ-0.15, c16-alloc-checks | the whole file |
| `query unused MODULE` left out its child modules | wf-79-3 | included |
| `edit insert --after` a one-line static double-spaced the run | wf-79-5 | joins the run |
| `edit apply`: `@@ new after X` failed when an earlier block adds X | c16-selfhost | the block goes with that one's text |
| `edit new-file` did not add the imports its text needs | c15-tools | added (`note edit.imports`) |
| `fix --in ./file.tach` refused | s14-tools2 | accepted (was already; tested) |

## Left: proposed designs

Ordered by how often agents hit them, then by cost (S: under a day, M:
a few days, L: a release's track).

### 1. `fix --only imports` for a bare enum variant (reported 4 times; S, front)

`NodeKind::If` used bare, after a merge dropped `use ...::NodeKind::{If}`:
`undefined variable 'If'`, no help, `fix` says `nothing to fix`.

Design: when a name is undefined, the checker's help looks for items of
that name; let it also look for variants (`VARIANTS[v].name`) of the
enums the module can reach, and say `add use crate::front::ast::NodeKind::If;`
(several enums: the one whose other variants the module already imports,
else `fix.ambiguous` with one `--use` per enum). `fix --only imports`
then takes the help as it does for items, and adds the name to an
existing `use E::{...}` list. The change is in front/check (the help) and
tools/fix (the list); held back here because front is being migrated.

### 2. Edits of std's own files (S–M)

`edit patch std::sort ...` says `edit.not-source: std::sort is in <std>`:
std is one embedded text. In the compiler's tree, map a std definition
to its file under `compiler/std/` (the embed's sections give the file
and its first line), make the edit there, check the program with the
new std (the checker given std's text from the edited files instead of
the embed), and finish with `note edit.std: run
compiler/std/embed.sh` (or run it). `query show` already numbers std as
`<std>`; it would print `compiler/std/FILE.tach:LINE` instead when the
tree has it.

### 3. `edit apply` blocks that patch (S)

A change that makes a function `pub` and adds an item calling it is two
edits today (the apply alone is refused: unresolved import). Allow `@@
patch NAME` followed by `<<<<<<< OLD` / `=======` / `>>>>>>> NEW` pairs
in an apply file (the pairs syntax of `edit patch --pairs`), and the
reverse: `@@ new after NAME` blocks in a `--pairs` file. One parser for
both files, one checked edit.

### 4. `fix --only shorthand` (S)

`S { name: name }` -> `S { name }` (and fmt rejoining a struct literal
that now fits on one line): an agent did it with a text script and a
hand rejoin. A fix kind over StructLit inits whose value is an Ident
with the field's name (as parsed, not a path, no comment between); fmt
rejoins a literal whose one-line form fits in 100 columns, as it does
for calls.

### 5. rewrite: a one-line block stays on one line (M)

`if $c { $s... } else { $x as i64 }` -> `... else { $x }` expanded the
site's `} else { e as i64 };` to three lines, because the site's `if`
had lines. Layout should be decided per block: a replacement block whose
pattern counterpart matched a block written on one line at the site
stays on one line; only blocks that hold a `$s...` or that the site wrote
on several lines take lines. Needs the pattern-block to site-block map
the matcher already builds (B_NODE for holes; blocks need theirs).

### 6. rewrite: runs of statements, and splicing a string into an f-string (L)

Folding `buf_str(b, c"x = "); buf_int(b, x); buf_str(b, c"\n");` into
`b.push_str(f"x = {x}\n")` needs:

- a repeat hole for a run of statements of one of several shapes:
  `$run{ buf_str($b, $s) | buf_int($b, $n) }+` (each match binds per
  element);
- a replacement that builds text from the run: `f"{$run: $s => text($s),
  $n => {$n}}"`, where `text($s)` splices a string literal's contents
  (escaped for an f-string: `{` doubled).

A smaller first step: `$s:text` in a replacement, the contents of the
literal `$s` matched, spliced into the replacement's own f-string.

### 7. A check against the previous release (M)

Compiler source must build with the previous release (the bootstrap
rule), but an edit is checked with the tools binary only. `edit ...
--with OLD_TACHYONC` (and a `TACHYON_CHECK_WITH` setting for the hook):
after the root check, run `OLD check` on a copy of the edited files
(the overlay written to a temp tree), and refuse with its errors tagged
`[0.15]`. Costs one more check per edit: the old binary has no cache of
the edited tree, about 1 s on the compiler.

### 8. alloc016: sealed field reads (S, integrator's area)

A 0.15 program reading `v.len` on a `#[sealed]` std type fails on 0.16;
the error's help names `.len()`. `fix --only alloc016` could rewrite a
FieldAccess of a sealed field to the method of the same name when the
type has one (reads only; a write stays an error with its help).

### 9. guide --find ranks the std API listing first (S)

`guide --find "newline string"` matched the whole std listing (one
paragraph over every budget) before the paragraph on string escapes.
Rank by the words' density in a paragraph and by their nearness, and
cut a paragraph over the budget to its matching lines with `try:
guide TOPIC#SECTION`.

### 10. A parser error's position after an unclosed `}` (S, front)

A `fn` left without its closing `}` at the end of main.tach is reported
at `<std>:19:1` (the next file read). The parser should report the
unclosed block at the end of the file it was in: `main.tach:END:
expected '}' to close the block opened at main.tach:L`.

### 11. The hook (tools/agent-hooks, outside this track)

- a command that runs Python on docs and later names `compiler/src/main.tach`
  (`-o` taken for Python's write target) is blocked; parse per simple
  command, not per line;
- `grep -n 'a\|b' x.tach` is suggested as `query refs ab`: split the
  alternation into names;
- reads of `.tach` in the scratchpad are blocked: allow paths outside
  the repository.
