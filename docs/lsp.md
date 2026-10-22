# volec lsp: the language server (0.24; every name resolves, 0.25)

`volec lsp` is a language server: an editor runs it and speaks the
Language Server Protocol with it over stdin and stdout. It answers from
the same tables as `volec query` and `volec check`
([query.md](query.md)): a definition is where `query def` finds it, the
references are `query refs`', a hover shows what `query def`, `query
effects` and `query type` print, the diagnostics are `check`'s. It is
written in vole, in the compiler (`compiler/src/tools/lsp/`), with no
dependency: its JSON is read in place and written by hand.

## What it does

| LSP | what it answers with |
|---|---|
| `initialize` | the capabilities below; `positionEncoding` `utf-8` when the client offers it (`general.positionEncodings`), else `utf-16` |
| `textDocument/didOpen`, `didChange` (full text), `didSave`, `didClose` | the open documents' texts, kept in memory: the program is read with them in place of their files (unsaved edits count) |
| `textDocument/publishDiagnostics` | after an open, a change (150 ms after the last one) and a save: every error and warning of `check`, per file; the code (`type error`, `effect`, ...), the message with its `help:` and `note:` lines, the range of the token at the position, and the `try:` lines as the related information. A file whose errors are gone gets an empty list |
| `textDocument/definition` | the definition of the name under the cursor: a function, method, type, field, variant, const, static, module, or a local (its `let` or parameter); an operator's function (`a + b` of a type implementing `Add`: its `add`); a type parameter's declaration (`T` of `fn f<T: Ord>`); `std::` (std's first file), `crate::` (the root). In std: its file, written to a cache (below) |
| `textDocument/references` | every reference `query refs` finds (calls, uses, writes, imports, patterns, struct literals), with the definition when `includeDeclaration`; of a local, its declaration and uses; of a type parameter, its uses in the item; of a function an operator calls, the operators too. In the program's files; from a file of std's, in std's too |
| `textDocument/hover` | a definition's signature; a function's effects, declared or inferred, with why (below), and its CPU features; the comment above it; its path. A local or an expression: its type (one per instance in a generic function, six at most). A type parameter: its bounds. A keyword or convention (`let`, `var`, `inout`, `sink`, `fn`, `self`, `requires`, `ensures`, `result`...), an attribute (`#[derive]`, `#[pure]`, `#[test]`...) or a primitive type (`i64`, `u8`...): a line or two of the guide, with the topic to read |
| `textDocument/documentSymbol` | the file's definitions, as `query items` lists them, with their fields, variants and trait functions as children; ranges in the file (a file of std's too) |
| `workspace/symbol` | the definitions whose names match the query: the program's (its letters in order, case ignored), then std's (holding it); 256 at most, with their module as `containerName` |
| `shutdown`, `exit` | the exit status is 0 after a shutdown, else 1 |

A request for a method it does not have gets `MethodNotFound`
(-32601). Requests are answered in order.

### Hover: effects and why

On a function, at its definition or any call of it (methods too):

```
pub fn collect(gpa: Gpa, n: i64) -> Vec<i64>
effects: alloc(Gpa) panic (inferred)
features: none
```
- alloc(Gpa) ← 'v.push(i)' at shapes.vl:19:9 grows a Vec<i64>
- panic ← 'v.push(i)' at shapes.vl:19:9 calls 'Vec::push'

`crate::shapes::collect` (fn)

- `effects:` is the set `query effects` prints (`alloc(A..)`, `io`,
  `global`, `panic`, `diverge`, `unsafe`; [the guide's
  effects](../compiler/guide/effects.md)); `(declared #[pure])` when the
  function pins it with `#[pure]`, `#[effects(..)]`, `#[no_alloc]`...,
  else `(inferred)`.
- At a call of a generic function, the effects are the instance's
  called there: `effects: alloc(Gpa) panic unsafe (inferred, of
  Vec<i64>::push)`. At its definition, the instances' sets, three at
  most.
- Each effect from a callee gets one line of why: the first step of
  `query effects --why EFFECT`, the paths written from the root's
  directory. Six lines at most; the rest are counted, with the command
  that shows them.
- `features:` the CPU features the function needs (0.19), `none` when it
  needs none; an intrinsic's instruction.

## Every name (0.25)

A name is the definition it is written as: what the checker makes at a
name for itself (a local's drop at its `let`, an f-string's `display`
at a hole, a contract's check at a name in it, a derive's functions at
a field) is not a reference of the program, so a local in an f-string
or a contract is that local, and a field's name its field. Names in
f-strings, `requires`/`ensures` clauses and attributes (`#[derive(Eq)]`'s
traits) resolve as anywhere else. The test that every kind does:
`tests/lsp/resolve.lsp` on `tests/lsp/prog-resolve/main.vl`, a program
using std's prelude, std::cli, std::thread, std::gpu, Gpa, arenas,
FixedBuf, an Allocator bound, trait methods, generics, an operator,
f-strings, contracts, attributes and the conventions.

### std's files

std is in the compiler (`compiler/src/front/stdsrc.vl`): a definition in
it has no file of the user's. The worker writes std's text once, as
files, to a cache directory, and answers with their `file://` URIs, so
any client opens them; a request about such a file (a hover, a
definition, its symbols) is answered from the program the server has
read. The directory is

- `$XDG_CACHE_HOME/vole/std-VERSION-HASH/` when `XDG_CACHE_HOME` is set,
- else `~/Library/Caches/vole/std-VERSION-HASH/` on macOS and
  `~/.cache/vole/std-VERSION-HASH/` on Linux,

its real path (no link, no `..`). VERSION is the compiler's, HASH a
64-bit FNV-1a of std's text: a compiler built from other sources
writes its own. In it each of std's files is at its path under
`compiler/std` (`std.vl`, `flat/alloc.vl`, `collections/hash_map.vl`,
`gpu/mod.vl`...), the same text line for line, then the end of std's
text: `gpa.vl`, `alloc_flag.vl` (`std::CHECK_ALLOC`) and
`sys/macos.vl` or `sys/linux.vl`. The files are read-only (0444; the
VS Code extension also marks their editors read-only). The text is
written into a directory of another name, then renamed: a directory
with the name is whole, and servers running at once write it once.
Each worker compares the files with its std's text before it answers
with them: a directory of its name holding anything else (an edit) is
renamed away and written again, so no answer depends on what the cache
held, and compilers with another std (another HASH) never share one
(`tests/lsp/run.sh`: std-cache). Only `volec lsp` writes or reads it.
A hover's reasons name places in std the same way (`at std.vl:286:37`).
When std is read from its files (`--std-tree`, an edit of std in the
vole repository) its positions are in those files already.

`tools/lsp/stdfiles.vl` does it, from `std_files` (where embed.sh put
each file in the text, `front/stdtree.vl: built_files`) and the tail's
lengths.

## The program it reads

The root is the nearest `main.vl` in the document's directory or one
above it, the rule the tools and their hooks use. The extension is one
constant, `SOURCE_EXT` in `tools/lsp/mod.vl`. One program at a time: a
document of another program makes it the program read.

## How it works

The server process keeps the documents and speaks JSON-RPC. The program
is read by a worker: a copy of the server (fork) that runs the front end
once on the root, with each open document's text in a file of a scratch
directory (`$TMPDIR/volec-lsp-PID/`) given to the front end in place
of the document's file (the overlay `check --overlay` uses), publishes
the diagnostics, collects every reference, the locals' declarations and
`query type`'s index, then answers the requests the server hands it on a
pipe, one line each, from those tables. Nothing it does changes them, so
it answers any number of requests.

After a change the worker is replaced: 150 ms after the last change
(debounced), at once when a request comes first or on a save. A request
about a document with a change already waiting behind it gets
`ContentModified` (-32801), as LSP has it, so that edits typed faster
than the program is read cost one reading, not one each. The worker's
stdout is its stderr: only the server writes the protocol.

## Speed

On the compiler's source (compiler/src: 377 files, about 390,000 lines, and std),
on an aarch64 Mac under load (a load average of about 25 on 12 cores,
other builds running), `VOLE_LSP_TIME=1` and a client measuring each
round trip (median of 15):

| request | time |
|---|---|
| definition of a call | 0.2 ms |
| references, 15 results | 0.7 ms |
| references of `IntVec::push`, 2024 results | 7 ms |
| hover on a call (signature, effects, why) | 2 ms |
| hover on a call of a generic function (the instance) | 2 ms |
| hover on a local (its type) | 13 ms |
| documentSymbol of a 1,040-line file (53 symbols) | 0.4 ms |
| the first request after an edit: the program read again | ~710 ms |

Every request on a program read is well under 50 ms. Reading the
program is the front end's time (`check --time-passes` without the
cache: about 450 ms of CPU here, the rest the machine's load): an edit
costs one reading, in the background after the debounce, and the
first request that comes before it is done waits for it. The front end
has no incremental mode yet; that is where the next gain is.

`VOLE_LSP_TIME=1` prints each request's time on stderr (`lsp:
textDocument/hover 1.7 ms`) and the worker's (`lsp worker: load 740.2
ms`).

## Editors

Any LSP client; the command is `volec lsp` (no options), the
language's files `*.vl`.

Neovim (0.10):

```lua
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'vole',
  callback = function(ev)
    vim.lsp.start({
      name = 'volec',
      cmd = { 'volec', 'lsp' },
      root_dir = vim.fs.root(ev.buf, { 'main.vl' }),
    })
  end,
})
vim.filetype.add({ extension = { tach = 'vole' } })
```

Helix (`languages.toml`):

```toml
[language-server.volec]
command = "volec"
args = ["lsp"]

[[language]]
name = "vole"
scope = "source.vole"
file-types = ["tach"]
roots = ["main.vl"]
language-servers = ["volec"]
```

VS Code needs an extension to start a server; any generic LSP client
extension works with the command above.

## Tests

`tests/lsp/run.sh` (in `tests/run.sh`, category `lsp`): scripted
sessions, `tests/lsp/*.lsp`, with the program `tests/lsp/prog` (or
`tests/lsp/prog-NAME/` for `NAME.lsp`). A line
`> JSON` is the client's (`> @open FILE`, `> @change FILE TEXT` for the
documents), `< JSON` the server's; each request waits for its answer,
as an editor's does, except in a `## burst` session. `-u` writes the
answers they get now. std's files are written under the scratch
directory (`XDG_CACHE_HOME`), `@DIR@/.cache/vole/std-@STD@/` in the
answers; a session that asks about one names it so, and std is written
first to know the directory. Then the compiler's source is opened and asked
for symbols, references and a hover, which must be plausible; the
times are printed.

## Known limits

- One program at a time; a document outside any program (no `main.vl`
  above it) gets empty answers.
- In a file of std's, a local's definition and references are not
  found (a generic function of std is checked per instance); its items'
  are. A builtin operator (`+` of integers) has no definition.
- No rename, completion, signature help or formatting yet: `volec
  refactor rename`, `volec fmt` do them from the command line.
- A program that does not parse gets its diagnostics, and empty answers.
