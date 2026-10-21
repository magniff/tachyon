# Changelog

## 0.24.0 (unreleased)

The first version, for vole 0.24 (the language called tachyon before).

- TextMate grammar for `.vl` (and `.tach`): the parameter conventions
  `let`, `inout`, `sink`, `var` beside the older spelling, contracts,
  types, numbers with suffixes, strings, `c"..."`, `b"..."`, f-strings
  with holes and format specs, chars, nested block comments, attributes,
  labels, paths, operators; tested by `test/tmgrammar.py` and
  vscode-tmgrammar-test.
- Language configuration: comments, brackets, auto-closing, indentation.
- Language client for `volec lsp` (diagnostics, go to definition,
  references, hover, document symbols), with `vole.server.path` and the
  `vole.server.fallbackPath` (`tachyonc`) used until the rename.
- The vole icon.
