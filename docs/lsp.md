# volec lsp: the language server (0.24)

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
| `textDocument/definition` | the definition of the name under the cursor: a function, method, type, field, variant, const, static, module, or a local (its `let` or parameter). In std (no file): none |
| `textDocument/references` | every reference `query refs` finds (calls, uses, writes, imports, patterns, struct literals), with the definition when `includeDeclaration`; of a local, its declaration and uses |
| `textDocument/hover` | a definition's signature; a function's effects, declared or inferred, with why (below), and its CPU features; its path. A local or an expression: its type (one per instance in a generic function) |
| `textDocument/documentSymbol` | the file's definitions, as `query items` lists them, with their fields, variants and trait functions as children; ranges in the file |
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
sessions, `tests/lsp/*.lsp`, with the program `tests/lsp/prog`. A line
`> JSON` is the client's (`> @open FILE`, `> @change FILE TEXT` for the
documents), `< JSON` the server's; each request waits for its answer,
as an editor's does, except in a `## burst` session. `-u` writes the
answers they get now. Then the compiler's source is opened and asked
for symbols, references and a hover, which must be plausible; the
times are printed.

## Known limits

- One program at a time; a document outside any program (no `main.vl`
  above it) gets empty answers.
- Definitions in std have no file to go to (std is in the compiler).
- No rename, completion, signature help or formatting yet: `volec
  refactor rename`, `volec fmt` do them from the command line.
- A program that does not parse gets its diagnostics, and empty answers.
