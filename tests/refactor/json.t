## --json (0.15, tests/refactor/json/): every diagnostic, and every line of
## output, one JSON object per line, for a harness rather than a reader
## (the check hook, the agent eval); the try: lines as the agent would run
## them, without --json.
$ check --json
$ query def add --json
crate::add	main.vl:3:4	fn	fn add(a: i64, b: i64) -> i64	effects: none
std::ops::Add::add	<std>:4696:20	trait-method	fn add(self, other: Self) -> Self
## (quotes and tabs escaped)
$ query grep bad --json
# main.vl
9:18	string	main	println("bad");
$ query show nosuch --json
{"kind":"diagnostic","severity":"error","code":"query.no-match","file":null,"line":null,"col":null,"message":"no definition 'nosuch'","help":[],"notes":[],"try":["volec query items"]}
[exit 1]
## An edit's new errors, its refusal, its summary.
$ edit patch add --old 'a + b' --new 'a + q' --json
{"kind":"diagnostic","severity":"error","code":"type error","file":"main.vl","line":4,"col":9,"message":"undefined variable 'q'  [edited: crate::add]","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"edit.breaks","file":null,"line":null,"col":null,"message":"1 new error; nothing written","help":[],"notes":[],"try":["volec edit patch add --old 'a + b' --new 'a + q' --no-check"]}
[exit 1]
$ edit patch add --old 'a + b' --new 'b + a' --json
{"kind":"output","fields":["patched crate::add","main.vl","+1 -1 lines"]}
$ undo --json
{"kind":"output","fields":["undid patched crate::add","main.vl","+1 -1 lines"]}
## A compiler error with help and its position; --json anywhere on the line.
% printf 'use std::{println};\nfn main() {\n    let x: i64 = "s\\t";\n    prinln(x);\n}\n' > bad.vl
$ --json check bad.vl
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":3,"col":18,"message":"expected 'i64', got '[u8]'","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":4,"col":5,"message":"undefined variable 'prinln'","help":["did you mean 'println'?"],"notes":[],"try":["volec fix --suggested bad.vl"]}
[exit 1]
$ bad.vl -o prog --json
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":3,"col":18,"message":"expected 'i64', got '[u8]'","help":[],"notes":[],"try":[]}
{"kind":"diagnostic","severity":"error","code":"type error","file":"bad.vl","line":4,"col":5,"message":"undefined variable 'prinln'","help":["did you mean 'println'?"],"notes":[],"try":["volec fix --suggested bad.vl"]}
[exit 1]
## A build whose stderr is not a terminal (here, a file) prints check's
## one-line form; --diagnostics=human the human form.
$ bad.vl -o prog
bad.vl:3:18: error[type error] expected 'i64', got '[u8]'
bad.vl:4:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: volec fix --suggested bad.vl
[exit 1]
$ --diagnostics=human bad.vl -o prog
error[type error]: expected 'i64', got '[u8]'
 --> bad.vl: line 3, column 18
error[type error]: undefined variable 'prinln'
 --> bad.vl: line 4, column 5
  = help: did you mean 'println'?
  = try: volec fix --suggested bad.vl
[exit 1]
