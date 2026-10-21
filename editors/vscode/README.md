# Vole for Visual Studio Code

Language support for **vole** (the language called tachyon until 0.24):
syntax highlighting for `.vl` files (and `.tach` during the rename), and
diagnostics, go to definition, references, hover and document symbols
from the compiler's language server, `volec lsp`.

![Vole in VS Code](images/screenshot.png)

<!-- Screenshot placeholder: images/screenshot.png is not committed yet. -->

## Features

- **Highlighting** (`syntaxes/vole.tmLanguage.json`, scope `source.vole`):
  keywords, including the parameter conventions `let`, `inout`, `sink`
  and `var` and the older `let mut`, `&mut`, `static mut` spelling, so
  both read well during the transition; contracts (`requires`,
  `ensures`, `result`, `old(..)`); types and numbers with suffixes
  (`255u8`, `1.5f32`); strings with escapes, `c"..."`, `b"..."`,
  f-strings with their holes and format specs (`f"{x:>4}"`), char
  literals; nested block comments; attributes `#[...]`; labels; paths;
  operators.
- **Editing:** comment toggling, bracket matching and auto-closing,
  indentation after an open bracket.
- **Language server:** started from `volec lsp` over stdio. Errors and
  warnings appear as you type; F12, Shift+F12, hover and the outline come
  from the compiler.

The extension makes no network requests and collects no telemetry.

## Settings

| setting | default | |
|---|---|---|
| `vole.server.path` | `volec` | the compiler: a name looked up on PATH, or a path (relative to the first workspace folder) |
| `vole.server.fallbackPath` | `tachyonc` | tried when `vole.server.path` is not found; in the compiler's own repository, `target/tools/tachyonc` |
| `vole.server.args` | `["lsp"]` | the arguments that start the server |
| `vole.server.enabled` | `true` | `false` keeps highlighting only |
| `vole.trace.server` | `off` | `messages` or `verbose` logs the protocol to the Vole output |

Commands: **Vole: Restart Language Server**, **Vole: Show Language
Server Output**. Changing a `vole.server.*` setting restarts the server.

## Building

Node 18 or newer and npm:

```sh
cd editors/vscode
npm install
npm run compile          # src/extension.ts -> out/extension.js
npm test                 # grammar assertions (vscode-tmgrammar-test) and snapshots
npm run package          # vole.vsix, with @vscode/vsce
code --install-extension vole.vsix
```

`npm run package` is `vsce package --out vole.vsix`; without the npm
dependencies, `npx @vscode/vsce package --out vole.vsix` does the same.
Nothing here publishes to the marketplace; `publisher` in package.json
(`vole-lang`) is a placeholder until a publisher exists.

To try it without packaging, open `editors/vscode` in VS Code and press
F5 (Extension Development Host).

## Testing the grammar

`test/samples/*.test.vl` are source files with assertions in
vscode-tmgrammar-test's format:

```vl
    fill(&v, 4);
//       ^ keyword.operator.access.vole
```

`python3 test/tmgrammar.py` checks them and the token snapshots in
`test/snapshots/` with a small TextMate tokenizer in Python, so the
grammar can be tested without node; `--update` rewrites the snapshots
after an intended change, `--dump FILE` prints a file's tokens.
`npm test` runs both vscode-tmgrammar-test and the snapshot check.
