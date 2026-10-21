## A session: positions in UTF-16 (the default), the documents opened, each
## request answered from the worker that read the program; an edit that
## breaks it publishes the error, one that fixes it clears it.
> {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}
< {"jsonrpc":"2.0","id":1,"result":{"capabilities":{"positionEncoding":"utf-16","textDocumentSync":{"openClose":true,"change":1,"save":{"includeText":true}},"definitionProvider":true,"referencesProvider":true,"hoverProvider":true,"documentSymbolProvider":true},"serverInfo":{"name":"tachyonc","version":"@VERSION@"}}}
> {"jsonrpc":"2.0","method":"initialized","params":{}}
> @open main.tach
## definition and references of a function (from a call)
> {"jsonrpc":"2.0","id":2,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":7,"character":12}}}
< {"jsonrpc":"2.0","id":2,"result":{"uri":"file://@DIR@/shapes.tach","range":{"start":{"line":8,"character":7},"end":{"line":8,"character":11}}}}
> {"jsonrpc":"2.0","id":3,"method":"textDocument/references","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":7,"character":12},"context":{"includeDeclaration":true}}}
< {"jsonrpc":"2.0","id":3,"result":[{"uri":"file://@DIR@/main.tach","range":{"start":{"line":3,"character":20},"end":{"line":3,"character":24}}},{"uri":"file://@DIR@/main.tach","range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}},{"uri":"file://@DIR@/shapes.tach","range":{"start":{"line":8,"character":7},"end":{"line":8,"character":11}}}]}
## hover: a declared function, one whose effects are inferred (and why),
## a method of std, a local (after "größe": UTF-16 columns)
> {"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":7,"character":12}}}
< {"jsonrpc":"2.0","id":4,"result":{"contents":{"kind":"markdown","value":"```tachyon\npub fn area(s: Shape) -> i64\neffects: none (declared #[pure])\nfeatures: none\n```\n\n`crate::shapes::area` (fn)\n"},"range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}}}
> {"jsonrpc":"2.0","id":5,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":8,"character":16}}}
< {"jsonrpc":"2.0","id":5,"result":{"contents":{"kind":"markdown","value":"```tachyon\npub fn collect(gpa: Gpa, n: i64) -> Vec<i64>\neffects: alloc(Gpa) panic (inferred)\nfeatures: none\n```\n- alloc(Gpa) ← 'v.push(i)' at shapes.tach:19:9 grows a Vec<i64>\n- panic ← 'v.push(i)' at shapes.tach:19:9 calls 'Vec::push'\n\n`crate::shapes::collect` (fn)\n"},"range":{"start":{"line":8,"character":12},"end":{"line":8,"character":19}}}}
> {"jsonrpc":"2.0","id":6,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":9,"character":7}}}
< {"jsonrpc":"2.0","id":6,"result":{"contents":{"kind":"markdown","value":"```tachyon\npub fn push(inout self, x: sink T)\neffects: alloc(Gpa) panic unsafe (inferred, of Vec<i64>::push)\nfeatures: none\n```\n- alloc(Gpa) ← 'self.reserve_more(1)' at <std>:286:37 grows a Vec<i64>\n- panic ← 'out_of_memory()' at <std>:287:13 calls 'std::out_of_memory'\n- unsafe ← 'self.ptr[self.len]' at <std>:290:13 indexes a raw pointer\n\n`std::Vec::push` (method)\n"},"range":{"start":{"line":9,"character":6},"end":{"line":9,"character":10}}}}
> {"jsonrpc":"2.0","id":7,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":10,"character":33}}}
< {"jsonrpc":"2.0","id":7,"result":{"contents":{"kind":"markdown","value":"```tachyon\na: i64\n```\n"},"range":{"start":{"line":10,"character":33},"end":{"line":10,"character":34}}}}
> {"jsonrpc":"2.0","id":8,"method":"textDocument/hover","params":{"textDocument":{"uri":"file://@DIR@/shapes.tach"},"position":{"line":23,"character":8}}}
< {"jsonrpc":"2.0","id":8,"result":{"contents":{"kind":"markdown","value":"```tachyon\npub fn total(v: Vec<i64>) -> i64\neffects: io global panic (inferred)\nfeatures: none\n```\n- io ← 'println(f\"total {sum}\")' at shapes.tach:29:5 calls 'std::fmt::println'\n- global ← 'println(f\"total {sum}\")' at shapes.tach:29:5 calls 'std::fmt::println'\n- panic ← 'for x in v.iter() { ..' at shapes.tach:26:5 calls 'SliceIter::as_slice'\n\n`crate::shapes::total` (fn)\n"},"range":{"start":{"line":23,"character":7},"end":{"line":23,"character":12}}}}
## a local: its definition and references
> {"jsonrpc":"2.0","id":9,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":9,"character":4}}}
< {"jsonrpc":"2.0","id":9,"result":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":8,"character":8},"end":{"line":8,"character":9}}}}
> {"jsonrpc":"2.0","id":10,"method":"textDocument/references","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":9,"character":4},"context":{"includeDeclaration":true}}}
< {"jsonrpc":"2.0","id":10,"result":[{"uri":"file://@DIR@/main.tach","range":{"start":{"line":8,"character":8},"end":{"line":8,"character":9}}},{"uri":"file://@DIR@/main.tach","range":{"start":{"line":9,"character":4},"end":{"line":9,"character":5}}},{"uri":"file://@DIR@/main.tach","range":{"start":{"line":11,"character":29},"end":{"line":11,"character":30}}}]}
## a file's symbols (not opened)
> {"jsonrpc":"2.0","id":11,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":"file://@DIR@/shapes.tach"}}}
< {"jsonrpc":"2.0","id":11,"result":[{"name":"Shape","detail":"pub enum Shape","kind":10,"range":{"start":{"line":2,"character":4},"end":{"line":5,"character":1}},"selectionRange":{"start":{"line":2,"character":9},"end":{"line":2,"character":14}},"children":[{"name":"Square","detail":"Square(i64)","kind":22,"range":{"start":{"line":3,"character":4},"end":{"line":3,"character":15}},"selectionRange":{"start":{"line":3,"character":4},"end":{"line":3,"character":10}}},{"name":"Rect","detail":"Rect(i64, i64)","kind":22,"range":{"start":{"line":4,"character":4},"end":{"line":4,"character":18}},"selectionRange":{"start":{"line":4,"character":4},"end":{"line":4,"character":8}}}]},{"name":"area","detail":"pub fn area(s: Shape) -> i64","kind":12,"range":{"start":{"line":8,"character":4},"end":{"line":13,"character":1}},"selectionRange":{"start":{"line":8,"character":7},"end":{"line":8,"character":11}}},{"name":"collect","detail":"pub fn collect(gpa: Gpa, n: i64) -> Vec<i64>","kind":12,"range":{"start":{"line":15,"character":4},"end":{"line":21,"character":1}},"selectionRange":{"start":{"line":15,"character":7},"end":{"line":15,"character":14}}},{"name":"total","detail":"pub fn total(v: Vec<i64>) -> i64","kind":12,"range":{"start":{"line":23,"character":4},"end":{"line":30,"character":1}},"selectionRange":{"start":{"line":23,"character":7},"end":{"line":23,"character":12}}}]}
## an unsaved edit that breaks the program, then one that fixes it
> @change main.tach main-broken
> {"jsonrpc":"2.0","id":12,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":9,"character":4}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.tach","diagnostics":[{"range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}},"severity":1,"code":"type error","source":"tachyonc","message":"undefined variable 'aera'\nhelp: did you mean 'area'?","relatedInformation":[{"location":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":7,"character":12},"end":{"line":7,"character":16}}},"message":"try: tachyonc fix --suggested @DIR@/main.tach"}]}]}}
< {"jsonrpc":"2.0","id":12,"result":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":8,"character":8},"end":{"line":8,"character":9}}}}
> @change main.tach main-fixed
> {"jsonrpc":"2.0","id":13,"method":"textDocument/definition","params":{"textDocument":{"uri":"file://@DIR@/main.tach"},"position":{"line":9,"character":4}}}
< {"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{"uri":"file://@DIR@/main.tach","diagnostics":[]}}
< {"jsonrpc":"2.0","id":13,"result":{"uri":"file://@DIR@/main.tach","range":{"start":{"line":8,"character":8},"end":{"line":8,"character":9}}}}
## no such method; the end
> {"jsonrpc":"2.0","id":14,"method":"textDocument/rename","params":{}}
< {"jsonrpc":"2.0","id":14,"error":{"code":-32601,"message":"unknown method textDocument/rename"}}
> {"jsonrpc":"2.0","id":15,"method":"shutdown"}
< {"jsonrpc":"2.0","id":15,"result":null}
> {"jsonrpc":"2.0","method":"exit"}
