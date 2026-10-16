# Effects for agents: moving a module onto an arena

A session of the kind an agent runs: a task, the queries that answer it
without reading every function, one checked refactoring, and a
declaration that keeps the result true. The program renders a small
subset of Markdown to HTML (`markup.tach`; `main.tach` renders two
documents). The task:

> `markup` makes many small blocks for each document, each freed on its
> own when it is dropped. Move the module's allocations into an arena
> that `main` empties after each document, and make sure nothing in
> `markup` allocates from the general-purpose allocator again.

Every command below is run by `tests/walkthrough/run.sh` in a fresh
copy of this directory (a git repository, so that the edits are
journaled and `git diff` shows them), and its output is checked against
this file. `tests/examples/effects-effects-for-agents.test` runs the
program as it is before the session.

## 1. Before

```console
$ tachyonc main.tach -o render && ./render > before.txt && head -4 before.txt
<ul>
<li><a href="#arenas">Arenas</a></li>
<li><a href="#why-arenas">Why arenas?</a></li>
</ul>
$ tachyonc --check-alloc main.tach -o render-checked && ./render-checked > /dev/null
```

Nothing is left allocated: every value is dropped at the end of its
scope (0.16's version of this program leaked nine blocks here). They are
made at five lines of `markup.tach`: the lines' `Vec` (line 11), each
heading's id (25), the headings' `Vec` (59), and the HTML's `Buf`, grown
at lines 49 and 105, which `render` returns and `main` drops after
printing it. One arena can hold all of them, emptied at once.

## 2. What allocates, and from what

The question "what in this module allocates from `Gpa`?" has an exact
answer:

```console
$ tachyonc query effects crate::markup --has 'alloc(Gpa)'
crate::markup::lines	alloc(Gpa) panic
crate::markup::slug	alloc(Gpa) panic
crate::markup::inline	alloc(Gpa) panic
crate::markup::headings	alloc(Gpa) panic
crate::markup::render	alloc(Gpa) panic
```

All five functions. Four of them take `gpa: Gpa`; the fifth, `inline`,
takes no allocator, so a search for `Gpa` misses it:

```console
$ tachyonc query refs Gpa --in crate::markup
# markup.tach
10:26	type	markup::lines	fn lines(src: [u8], gpa: Gpa) -> Vec<[u8]> {
16:27	type	markup::slug	fn slug(title: [u8], gpa: Gpa) -> Buf {
55:30	type	markup::headings	fn headings(ls: [[u8]], gpa: Gpa) -> Vec<Heading> {
66:31	type	markup::render	pub fn render(src: [u8], gpa: Gpa) -> Buf {
$ tachyonc query effects markup::inline --why 'alloc(Gpa)' | head -2
crate::markup::inline	alloc(Gpa) panic
  'out.push_str(if code { "</code>" } else { "<..' at markup.tach:41:13 grows a Buf
```

`inline` appends to a `Buf` it is given, and a `Buf` grows with the
allocator it holds: the `out` that `render` made on `gpa`. `--why`
follows the chain from a function to the line that has the effect; the
first step is the one in the function asked about.

## 3. The refactoring, planned by the compiler

Four parameters change type, `Gpa` to `Arena`. `refactor --script` runs
several refactorings and checks the program once, at the end, all or
nothing; `--dry-run` shows the diff and the errors without writing. A
first script with just the four parameters:

```console
$ cat > steps.txt <<'EOF'
> refactor signature markup::lines --type gpa Arena
> refactor signature markup::slug --type gpa Arena
> refactor signature markup::headings --type gpa Arena
> refactor signature markup::render --type gpa Arena
> EOF
$ tachyonc refactor --script steps.txt --dry-run | grep ': error'
main.tach:10:40: error[type error] expected 'Arena', got 'Gpa'  [in crate::main]
markup.tach:11:25: error[type error] expected 'Gpa', got 'Arena'  [edited: crate::markup::lines]
markup.tach:31:5: error[type error] expected 'Buf', got 'Buf<Arena>'  [edited: crate::markup::slug]
markup.tach:56:44: error[type error] expected 'Gpa', got 'Arena'  [edited: crate::markup::headings]
markup.tach:75:25: error[type error] expected '&mut Buf', got '&mut Buf<Arena>'  [edited: crate::markup::render]
markup.tach:90:28: error[type error] expected '&mut Buf', got '&mut Buf<Arena>'  [edited: crate::markup::render]
markup.tach:100:23: error[type error] expected '&mut Buf', got '&mut Buf<Arena>'  [edited: crate::markup::render]
markup.tach:107:5: error[type error] expected 'Buf', got 'Buf<Arena>'  [edited: crate::markup::render]
warning edit.breaks: 8 new errors (7 in the edited text, 1 in crate::main, which the edit does not change) (dry run)
```

The errors are the rest of the plan: the return types (`Vec<[u8]>`
from `split_in` on an `Arena` is `Vec<[u8], Arena>`; `Buf` is
`Buf<Arena>`), the field `Heading.id`, `inline`'s `out`, and the call in
`main`, which must now pass an arena. The script grows to cover them,
and renames the parameters to say what they are:

```console
$ cat > steps.txt <<'EOF'
> refactor signature markup::lines --type gpa Arena
> refactor signature markup::slug --type gpa Arena
> refactor signature markup::headings --type gpa Arena
> refactor signature markup::render --type gpa Arena
> refactor signature markup::inline --type out '&mut Buf<Arena>'
> refactor field markup::Heading --type id 'Buf<Arena>'
> edit patch markup::lines --old '-> Vec<[u8]>' --new '-> Vec<[u8], Arena>'
> edit patch markup::slug --old '-> Buf' --new '-> Buf<Arena>'
> edit patch markup::headings --old 'Vec<Heading>' --new 'Vec<Heading, Arena>' --all
> edit patch markup::render --old '-> Buf' --new '-> Buf<Arena>'
> refactor signature markup::lines --rename-param gpa arena
> refactor signature markup::slug --rename-param gpa arena
> refactor signature markup::headings --rename-param gpa arena
> refactor signature markup::render --rename-param gpa arena
> edit replace main <<END
> fn main(gpa: Gpa) -> i32 {
>     let docs = [
>         "# Arenas\nAn *arena* hands out memory\nby bumping a pointer.\n\n# Why arenas?\nFreeing is `free_all`: once.",
>         "# Effects\nEach function has a set: `alloc(Gpa)`, *io*, ...",
>     ];
>     // One arena for every document: what render makes for a document
>     // is freed at once, before the next one.
>     let mut arena = Arena::new_in(gpa);
>     defer unsafe { arena.free_all() };
>     for doc in docs {
>         let html = markup::render(doc, arena);
>         print(html.as_slice());
>         drop(html); // before the reset, which takes its memory
>         // (unsafe: every view into the arena is dead from here)
>         unsafe { arena.reset() };
>     }
>     0
> }
> END
> EOF
$ tachyonc refactor --script steps.txt
changed parameter gpa to Arena in crate::markup::lines	markup.tach	+1 -1 lines
changed parameter gpa to Arena in crate::markup::slug	markup.tach	+1 -1 lines
changed parameter gpa to Arena in crate::markup::headings	markup.tach	+1 -1 lines
changed parameter gpa to Arena in crate::markup::render	markup.tach	+1 -1 lines
changed parameter out to &mut Buf<Arena> in crate::markup::inline	markup.tach	+1 -1 lines
changed field id to Buf<Arena> in crate::markup::Heading	markup.tach	+1 -1 lines
patched crate::markup::lines	markup.tach	+1 -1 lines
patched crate::markup::slug	markup.tach	+1 -1 lines
patched crate::markup::headings	markup.tach	+2 -2 lines
patched crate::markup::render	markup.tach	+1 -1 lines
renamed parameter gpa to arena of crate::markup::lines	markup.tach	+2 -2 lines
renamed parameter gpa to arena of crate::markup::slug	markup.tach	+2 -2 lines
renamed parameter gpa to arena of crate::markup::headings	markup.tach	+3 -3 lines
renamed parameter gpa to arena of crate::markup::render	markup.tach	+4 -4 lines
replaced crate::main	main.tach	+8 -1 lines
script steps.txt: 15 commands	2 files	+21 -14 lines
$ git diff --stat
 main.tach   |  9 ++++++++-
 markup.tach | 26 +++++++++++++-------------
 2 files changed, 21 insertions(+), 14 deletions(-)
```

`Arena::new_in(gpa)` makes an arena whose chunks come from `gpa`.
`reset` frees everything allocated from it but keeps its memory for the
next document, and `free_all` gives the memory back at the end. Both are
`unsafe`: nothing stops a view into the arena (`html.as_slice()` here),
or a value still holding its memory, from being used after them; so
`html` is dropped before the reset (dropped after it, its `Buf` would
give back memory the reset already took: `--check-alloc` stops at
that). 0.17.1's arena references close the hole; an
`arena.scope(|a| ...)` per document has none today, but its arena is a
`ScopedArena`, and the task asked for `Arena`.

## 4. Checked

The same output, and nothing left allocated:

```console
$ tachyonc main.tach -o render && ./render | diff before.txt - && echo same output
same output
$ tachyonc --check-alloc main.tach -o render-checked && ./render-checked > /dev/null
$ tachyonc query effects crate::markup
crate::markup::lines	alloc(Arena) panic
crate::markup::slug	alloc(Arena) panic
crate::markup::inline	alloc(Arena) panic
crate::markup::headings	alloc(Arena) panic
crate::markup::render	alloc(Arena) panic
```

Every function of `markup` now allocates from `Arena` only, and none
has `global`: since nothing obtains an allocator out of thin air (a
`Gpa` exists only as `main`'s parameter and the copies passed down), a
function without `alloc(Gpa)` and without `global` cannot reach a `Gpa`
at all.

## 5. Locked

The effects are inferred: today `render` allocates only from the arena,
but a later change could add a `gpa` parameter, a `Vec` on `Gpa` passed
in, a debugging print. A declaration makes the current set a promise,
checked on every build:

```console
$ tachyonc edit patch markup::render --old 'pub fn render' --new '#[effects(alloc(Arena), panic)]
> pub fn render' --show
patched crate::markup::render	markup.tach	+1 -0 lines
// markup.tach:66
66	#[effects(alloc(Arena), panic)]
```

`render`'s set covers everything it calls, so the one declaration
guards the whole module. A debugging print three calls down, in `slug`:

```console
$ tachyonc edit patch markup::slug --old '    let mut dash = false;' --new '    eprintln(f"slug of {title}");
>     let mut dash = false;'
markup.tach:68:5: error[effect] 'markup::render' is #[effects(alloc(Arena), panic)], but it does io: 'headings(ls.as_slice(), arena)' at markup.tach:71:14 calls 'markup::headings' | help: return the data and let the caller print it, or add 'io' to #[effects(alloc(Arena), panic)] | try: tachyonc query effects markup::render --why io  [in crate::markup::render]
error edit.breaks: 1 new error (1 in crate::markup::render, which the edit does not change); nothing written
note edit.together: change crate::markup::render in the same edit: one `edit apply FILE` with a block per item, or `edit patch --pairs FILE` with `@@ NAME` blocks
try: tachyonc query show crate::markup::render
try: tachyonc edit patch markup::slug --old '    let mut dash = false;' --new '    eprintln(f"slug of {title}");
    let mut dash = false;' --no-check
[exit 1]
```

Refused, and nothing written: the edit tools check the program with the
change before writing it. A build, a `tachyonc check` or the check hook
an agent runs after each edit reports the same error.

## What the agent used

| step | command | instead of |
|---|---|---|
| what allocates, from what | `query effects MODULE --has 'alloc(Gpa)'` | reading every function and its callees |
| why this one | `query effects NAME --why EFFECT` | following calls by hand into std |
| the plan | `refactor --script --dry-run`: the errors are the remaining steps | editing and building until it compiles |
| the change | `refactor --script`, checked once, all or nothing | a series of edits, some leaving the program broken |
| proof | `--check-alloc`, `diff` of the output, `query effects` again | trusting the change |
| the lock | `#[effects(alloc(Arena), panic)]` | a comment |

## Read more

- `tachyonc guide effects` and `tachyonc guide allocators`.
- `tachyonc guide tools`: query, edit, refactor; docs/refactor.md.
- [../../tools/](../../tools/): more sessions with the tools.
