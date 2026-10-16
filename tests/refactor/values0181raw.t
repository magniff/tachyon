## (0.18.1) fix --values keeps a raw pointer raw: a `*T` parameter
## passed on to C's (strlen), given `c"..."` or null, compared with an
## address, indexed or `&p[i]`, cast, kept in an aggregate stays `*T`, and
## so does one passed on to such a parameter (is_help: streq's); `&` of a
## place reached through a raw pointer keeps its parameter (npreds); a
## slice shown in an f-string is read (show). Before 0.18.1 these became
## `&mut u8`, and their calls `&mut *(c"help")`.
$ --values=off main.tach -o prog
ok: built prog
% ./prog
true true 122 true true 5 1 <bc>
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
$ main.tach -o prog
ok: built prog
% ./prog
true true 122 true true 5 1 <bc>
