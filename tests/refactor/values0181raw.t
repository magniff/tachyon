## (0.18.1) fix --values keeps a raw pointer raw: a `*T` parameter
## passed on to C's (strlen), given `c"..."` or null, compared with an
## address, indexed or `&p[i]`, cast, kept in an aggregate stays `*T`, and
## so does one passed on to such a parameter (is_help: streq's); `&` of a
## place reached through a raw pointer keeps its parameter (npreds); a
## slice shown in an f-string is read (show). Before 0.18.1 these became
## `&mut u8`, and their calls `&mut *(c"help")`.
## (0.18.1, V4: a `*T` parameter is raw, so the program before the fix no
## longer builds; the output after it is the one 0.16's semantics gave,
## recorded here before 0.18.1: `true true 122 true true 5 1 <bc>`. What the fix keeps raw is wrapped in
## `unsafe` by `fix --only unsafe`, the second try: of the error.)
$ fix --values
fixed 1 parameter to &mut T, 1 parameter to &T, 2 arguments	main.tach	+4 -4 lines
% grep -n 'fn \|add(' main.tach
2:    fn strlen(s: *u8) -> u64;
3:    fn memcmp(a: *u8, b: *u8, n: u64) -> i32;
12:fn streq(a: *u8, b: *u8) -> bool {
19:fn is_help(s: *u8) -> bool { unsafe { streq(s, c"help") } }
21:fn or_default(s: *u8) -> *u8 {
25:fn byte_at(s: *u8, i: i64) -> u8 {
29:fn second(s: *u8) -> *u8 {
33:fn pair(a: *u8, b: *u8) -> [*u8; 2] { [a, b] }
37:fn add(s: &mut Stats, x: i64) { s.count += 1; s.sum += x; }
38:fn mean(s: &Stats) -> i64 { if s.count == 0 { 0 } else { s.sum / s.count } }
39:fn npreds(v: *Vec<i64>) -> i64 { v.len() }
40:fn show(t: [u8], gpa: Gpa) -> Buf {
46:fn main(gpa: Gpa) {
48:    add(&mut st, 4);
49:    add(&mut st, 6);
$ fix --only unsafe
fixed 1 unsafe block	main.tach	+1 -1 lines
$ main.tach -o prog
main.tach:37:11: error[conv.rust] '&mut Stats' is Rust's spelling; an exclusive access is 'inout T' (a parameter 'x: inout T', called with '&x') | try: tachyonc edit patch main.tach:37 --old '&mut Stats' --new 'inout Stats' | try: tachyonc fix --suggested main.tach
main.tach:38:12: error[conv.rust] '&Stats' is Rust's spelling; a parameter is borrowed read-only by default (let): 'x: T', called with 'x' | try: tachyonc edit patch main.tach:38 --old '&Stats' --new 'Stats' | try: tachyonc fix --suggested main.tach
main.tach:41:5: error[conv.rust] 'let mut' is Rust's spelling; a mutable binding is 'var x' | try: tachyonc edit patch main.tach:41 --old 'let mut' --new 'var' | try: tachyonc fix --suggested main.tach
main.tach:47:5: error[conv.rust] 'let mut' is Rust's spelling; a mutable binding is 'var x' | try: tachyonc edit patch main.tach:47 --old 'let mut' --new 'var' | try: tachyonc fix --suggested main.tach
main.tach:48:9: error[conv.rust] '&mut st' is Rust's spelling; an inout argument (the callee may change it) is marked '&x' | try: tachyonc edit patch main.tach:48 --old '&mut st' --new '&st' | try: tachyonc fix --suggested main.tach
main.tach:48:9: error[conv.marker_extra] '&' marks an argument the callee may change; 'st' is taken let or sink here (read, or moved): pass 'st' | try: tachyonc edit patch main.tach:48 --old '&mut st' --new 'st' | try: tachyonc fix --suggested main.tach
main.tach:48:14: error[type error] expected 'let inout Stats', got 'Stats'
main.tach:49:9: error[conv.rust] '&mut st' is Rust's spelling; an inout argument (the callee may change it) is marked '&x' | try: tachyonc edit patch main.tach:49 --old '&mut st' --new '&st' | try: tachyonc fix --suggested main.tach
main.tach:49:9: error[conv.marker_extra] '&' marks an argument the callee may change; 'st' is taken let or sink here (read, or moved): pass 'st' | try: tachyonc edit patch main.tach:49 --old '&mut st' --new 'st' | try: tachyonc fix --suggested main.tach
main.tach:49:14: error[type error] expected 'let inout Stats', got 'Stats'
main.tach:50:5: error[conv.rust] 'let mut' is Rust's spelling; a mutable binding is 'var x' | try: tachyonc edit patch main.tach:50 --old 'let mut' --new 'var' | try: tachyonc fix --suggested main.tach
main.tach:58:70: error[conv.marker_extra] '&' marks an argument the callee may change; 'st' is taken let or sink here (read, or moved): pass 'st' | try: tachyonc edit patch main.tach:58 --old '&st' --new 'st' | try: tachyonc fix --suggested main.tach
[exit 1]
% ./prog
tests/refactor/run.sh: line 91: ./prog: No such file or directory
[exit 127]
