## burst: every message sent at once. A request about a document with a
## change queued after it is answered "content modified" (-32801), not
## from a program read for a text already replaced; the last one is
## answered, after one reading, with the change's errors.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> @open main.vl
> {"jsonrpc":"2.0","id":2,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":12}}}
< {"jsonrpc":"2.0","id":2,"error":{"code":-32801,"message":"content modified"}}
> @change main.vl main-fixed
> {"jsonrpc":"2.0","id":3,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":7,"character":12}}}
< {"jsonrpc":"2.0","id":3,"error":{"code":-32801,"message":"content modified"}}
> @change main.vl main-broken
> {"jsonrpc":"2.0","id":4,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"position":{"line":9,"character":4}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.vl","diagnostics":[{"range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}},"severity":1,"code":"type error","source":"volec","message":"undefined variable 'aera'\nhelp: did you mean 'area'?","relatedInformation":[{"location":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}},"message":"try: volec fix --suggested @DIR@/main.vl"}]}]}}
< {"jsonrpc":"2.0","id":4,"result":{"uri":"file://@DIR@/main.vl","range":{"start":{"line":8,"character":8},"end":{"line":8,"character":9}}}}
> {"jsonrpc":"2.0","id":5,"method":"shutdown"}
< {"jsonrpc":"2.0","id":5,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
