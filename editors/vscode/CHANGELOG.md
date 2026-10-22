# Changelog

## 0.25.1

For vole 0.25.1.

- Formatting with the compiler's formatter (`volec fmt`'s style): Format
  Document, Format Selection, and on save: vole is the default formatter
  of `.vl` files, `editor.formatOnSave`, `editor.tabSize` 4 and
  `editor.insertSpaces` for `[vole]` by default (overridable). A file
  that does not parse is not changed.
- Completion from `volec lsp`, on code being typed: members after `.`,
  paths after `::`, names in scope, the prelude, keywords and snippets;
  documentation (the comment, effects) of the selected item. Signature
  help in calls.
- Tests: the manifest (`test/package.test.js`) and the server's answers
  (`test/lsp.test.js`).

## 0.24.0 (unreleased)

The first version, for vole 0.24.

- TextMate grammar for `.vl`: the parameter conventions
  `let`, `inout`, `sink`, `var` beside the older spelling, contracts,
  types, numbers with suffixes, strings, `c"..."`, `b"..."`, f-strings
  with holes and format specs, chars, nested block comments, attributes,
  labels, paths, operators; tested by `test/tmgrammar.py` and
  vscode-tmgrammar-test.
- Language configuration: comments, brackets, auto-closing, indentation.
- Language client for `volec lsp` (diagnostics, go to definition,
  references, hover, document symbols), the compiler from
  `vole.server.path`.
- The vole icon.
