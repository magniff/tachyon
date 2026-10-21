## Positions in UTF-8 bytes (the client offers them): the local after
## "größe" is at byte 35 (character 33 in UTF-16). An unsaved document
## that is no file of a program gets nothing; a save reads the program
## again (its diagnostics published).
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{"general":{"positionEncodings":["utf-8","utf-16"]}}}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-8","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true},"serverInfo":{"name":"tachyonc","version":"@VERSION@"}}}
> @open main.tach
> {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":10,"character":35}}}
< {"jsonrpc":"2.0","id":2,"result":{"contents":{"kind":"markdown","value":"```tachyon\na: i64\n```\n"},"range":{"start":{"line":10,"character":35},"end":{"line":10,"character":36}}}}
> {"jsonrpc":"2.0","id":3,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":10,"character":35}}}
< {"jsonrpc":"2.0","id":3,"result":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":7,"character":8},"end":{"line":7,"character":9}}}}
> {"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///nonexistent/dir/x.tach"},"position":{"line":0,"character":0}}}
< {"jsonrpc":"2.0","id":4,"result":null}
> @change main.tach main-broken
> {"jsonrpc":"2.0","method":"textDocument/didSave","params":{"textDocument":{"uri":"file://@DIR@/main.tach"}}}
> {"jsonrpc":"2.0","id":5,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://@DIR@/main.tach"}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.tach","diagnostics":[{"range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}},"severity":1,"code":"type error","source":"tachyonc","message":"undefined variable 'aera'\nhelp: did you mean 'area'?","relatedInformation":[{"location":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}},"message":"try: tachyonc fix --suggested @DIR@/main.tach"}]}]}}
< {"jsonrpc":"2.0","id":5,"result":[{"name":"shapes","detail":"mod shapes","kind":2,"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":11}},"selectionRange":{"start":{"line":1,"character":4},"end":{"line":1,"character":10}}},{"name":"main","detail":"fn main(gpa: Gpa)","kind":12,"range":{"start":{"line":5,"character":0},"end":{"line":12,"character":1}},"selectionRange":{"start":{"line":5,"character":3},"end":{"line":5,"character":7}}}]}
> {"jsonrpc":"2.0","method":"textDocument/didClose","params":{"textDocument":{"uri":"file://@DIR@/main.tach"}}}
> {"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":7,"character":12}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.tach","diagnostics":[]}}
< {"jsonrpc":"2.0","id":6,"result":{"contents":{"kind":"markdown","value":"```tachyon\npub fn area(s: Shape) -> i64\neffects: none (declared #[pure])\nfeatures: none\n```\n\n`crate::shapes::area` (fn)\n"},"range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}}}
> {"jsonrpc":"2.0","id":7,"method":"shutdown"}
< {"jsonrpc":"2.0","id":7,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
