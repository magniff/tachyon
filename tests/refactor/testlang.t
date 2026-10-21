## Tests in the language (0.18): #[test] functions (taking nothing or
## `gpa: Gpa`, returning () or a Result), #[property] functions (values
## generated from their parameters' types, a failure shrunk), functions
## with an `ensures` (tested as properties), snapshots; each at -O0 and
## -O2, built with --trace and --check-alloc (a test that leaks fails).
## The summary first, then one line per failure (and its trace, input,
## try:).
$ test --timeout 5
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
## a property's failure again, from its seed
$ test bubble_sorts --seed 0xf788dd27897d1fed
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
## a snapshot that changed fails with its first differing line; --accept
## writes it
% printf 'Range { lo: 0, hi: 9 }\n' > tests/snapshots/checks__span_snapshot__1.snap
tests/refactor/run.sh: line 91: tests/snapshots/checks__span_snapshot__1.snap: No such file or directory
[exit 1]
$ test span
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
$ test span --accept
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
% cat tests/snapshots/checks__span_snapshot__1.snap
cat: tests/snapshots/checks__span_snapshot__1.snap: No such file or directory
[exit 1]
$ test span
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
## one level only
$ test -O 2 gap_of
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
## the program built without its tests (a #[cfg(test)] module is left out)
% "$COMPILER" main.tach -o prog && ./prog < tests/gaps.in
5 12345
ok: built prog
## the levels must agree: a difference is the compiler's bug (here a
## test-only switch makes -O2 read the literal 12345 as 12346)
% TACHYON_PLANT_MISCOMPILE=1 "$COMPILER" test gaps
test main.tach: its tests do not build (2 errors)
<std>:2969:17: error[conv.marker] 'g' is lent inout here (the callee may change it): mark it '&g' | help: an inout parameter takes '&place'; when the callee nev...
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in...
[exit 1]
## a test module sees its parent's items: `use super::*` is not needed
## (and wildcard imports are not allowed)
% printf 'use super::*;\n' > extra.tach && cat checks.tach >> extra.tach && mv extra.tach checks.tach
$ check
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in<Interp<closure(&mut Fmt) -> () at <std>:2798:26>, Gpa>' at <std>:2798:16 | note: in instantiation of 'assert_snapshot<Range>' at checks.tach:29:5
checks.tach:1:1: error[import.wildcard] wildcard imports are not allowed: 'use super::*;' is not needed | help: a #[cfg(test)] module sees its parent's items, private ones too, without an import | try: tachyonc edit patch checks.tach:1 --old 'use super::*;' --new '' main.tach
[exit 1]
$ edit patch checks.tach:1 --old 'use super::*;' --new ''
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in<Interp<closure(&mut Fmt) -> () at <std>:2798:26>, Gpa>' at <std>:2798:16 | note: in instantiation of 'assert_snapshot<Range>' at checks.tach:28:5
error edit.breaks: 1 new error; nothing written
try: tachyonc edit patch checks.tach:1 --old 'use super::*;' --new '' --no-check
[exit 1]
$ check
<std>:10090:33: error[type error] expected '*[u8; 256]', got '[u8; 256]' | help: a pointer to it: its address | try: &tmp | note: in instantiation of 'format_in<Interp<closure(&mut Fmt) -> () at <std>:2798:26>, Gpa>' at <std>:2798:16 | note: in instantiation of 'assert_snapshot<Range>' at checks.tach:29:5
checks.tach:1:1: error[import.wildcard] wildcard imports are not allowed: 'use super::*;' is not needed | help: a #[cfg(test)] module sees its parent's items, private ones too, without an import | try: tachyonc edit patch checks.tach:1 --old 'use super::*;' --new '' main.tach
[exit 1]
## a #[test] takes nothing or `gpa: Gpa`
% printf '#[test]\nfn takes(n: i64) {\n}\n' > checks.tach
$ test
test main.tach: its tests do not build (1 error)
checks.tach:2:4: error[test.signature] 'takes' is a #[test] with parameters: a #[test] takes nothing or `gpa: Gpa` | help: a function of generated arguments is ...
[exit 1]
## a property's parameters must be generable
% printf '#[property]\nfn takes(p: *i64) {\n}\n' > checks.tach
$ test
test main.tach: its tests do not build (1 error)
checks.tach:2:10: error[test.generate] no generator for '*i64' (a pointer), parameter 'p' of 'takes' | help: parameters are generated from their types: numbers,...
[exit 1]
