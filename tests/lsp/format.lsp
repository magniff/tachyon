## Formatting (0.25.1): the document's text as the editor has it
## (unsaved), formatted by `volec fmt`'s engine; the edit is the lines
## that change. A text that does not parse gets no edits. A range: only
## the lines it touches. A file not opened: its text on disk.
## quiet: formatting does not wait for the program to be read, so the
## diagnostics (published when it is) are left out of the transcript.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true,"workspaceSymbolProvider":true,"documentFormattingProvider":true,"documentRangeFormattingProvider":true,"completionProvider":{"triggerCharacters":[".",":"],"resolveProvider":true},"signatureHelpProvider":{"triggerCharacters":["(",","]}},"serverInfo":{"name":"volec","version":"@VERSION@"}}}
> @open main.vl
## formatted already: no edits
> {"jsonrpc":"2.0","id":2,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"options":{"tabSize":4,"insertSpaces":true}}}
< {"jsonrpc":"2.0","id":2,"result":[]}
> @change main.vl format-messy
## the lines that change
> {"jsonrpc":"2.0","id":3,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"options":{"tabSize":4,"insertSpaces":true}}}
< {"jsonrpc":"2.0","id":3,"result":[{"range":{"start":{"line":3,"character":0},"end":{"line":8,"character":0}},"newText":"use shapes::{Shape, area, collect, total};\n\nfn main(gpa: Gpa) {\n    let s = Shape::Square(3);\n    let a = area(s);\n"}]}
## a range: the line it touches (line 6)
> {"jsonrpc":"2.0","id":4,"method":"textDocument/rangeFormatting","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"range":{"start":{"line":6,"character":0},"end":{"line":6,"character":5}},"options":{"tabSize":4,"insertSpaces":true}}}
< {"jsonrpc":"2.0","id":4,"result":[{"range":{"start":{"line":6,"character":0},"end":{"line":7,"character":0}},"newText":"    let s = Shape::Square(3);\n"}]}
> @change main.vl format-broken
## a text that does not parse: no edits
> {"jsonrpc":"2.0","id":5,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file://@DIR@/main.vl"},"options":{"tabSize":4,"insertSpaces":true}}}
< {"jsonrpc":"2.0","id":5,"result":[]}
## a file not opened
> {"jsonrpc":"2.0","id":6,"method":"textDocument/formatting","params":{"textDocument":{"uri":"file://@DIR@/shapes.vl"},"options":{"tabSize":4,"insertSpaces":true}}}
< {"jsonrpc":"2.0","id":6,"result":[]}
> {"jsonrpc":"2.0","id":7,"method":"shutdown"}
< {"jsonrpc":"2.0","id":7,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
