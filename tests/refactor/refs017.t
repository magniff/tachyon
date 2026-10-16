## (0.17) refactor signature and field with references: --type to `&mut T`
## turns the calls' `&v` into `&mut v`; to `&T` from a value, `v` into
## `&v`; to `&mut [T]` from a slice, `a[..]` into `&mut a[..]`; --default
## `&$v` of an argument `&v` is `&v`, not `&(&v)`; refactor field --type
## with --default rewrites each literal's value.
$ refactor signature add --type v '&mut Vec<i64>'
changed parameter v to &mut Vec<i64> in crate::add, 1 argument in 2 calls	main.tach	+2 -2 lines
% cat main.tach
struct Lexer { src: Buf, pos: i64 }

fn lexer(text: Buf) -> Lexer {
    Lexer { src: text, pos: 0 }
}

fn total(v: Vec<i64>) -> i64 {
    let mut s = 0;
    for x in v { s += x; }
    s
}

fn add(v: &mut Vec<i64>, x: i64) {
    v.push(x);
}

fn fill(s: [i64]) {
    s[0] = 7;
}

struct Bag { items: Vec<i64> }

fn main(gpa: Gpa) {
    let mut v: Vec<i64> = Vec::new_in(gpa);
    add(&mut v, 1);
    add(&mut v, 2);
    let n = total(v);
    let bag = Bag { items: Vec::new_in(gpa) };
    let m = total(bag.items);
    let mut a = [1, 2];
    fill(a[..]);
    let lx = lexer(Buf::new_in(gpa));
    println(f"{n} {m} {a[0]} {lx.pos}");
}
$ refactor signature total --type v '&Vec<i64>'
changed parameter v to &Vec<i64> in crate::total, 2 arguments in 2 calls	main.tach	+3 -3 lines
$ refactor signature fill --type s '&mut [i64]'
changed parameter s to &mut [i64] in crate::fill, 1 argument in 1 call	main.tach	+2 -2 lines
$ query diff
# changed parameter s to &mut [i64] in crate::fill, 1 argument in 1 call	main.tach	+2 -2 lines
--- a/main.tach
+++ b/main.tach
@@ -17 +17 @@
-fn fill(s: [i64]) {
+fn fill(s: &mut [i64]) {
@@ -31 +31 @@
-    fill(a[..]);
+    fill(&mut a[..]);
$ refactor field Lexer --type src '[u8]' --default '$src.as_slice()' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -1 +1 @@
-struct Lexer { src: Buf, pos: i64 }
+struct Lexer { src: [u8], pos: i64 }
@@ -4 +4 @@
-    Lexer { src: text, pos: 0 }
+    Lexer { src: text.as_slice(), pos: 0 }
main.tach:4:5: error[own.escape] 'lexer' returns a view of 'text', which is dropped when 'lexer' returns | help: return the owner itself; a caller that wants a view takes '.as_slice()' of it  [edited: crate::lexer]
warning edit.breaks: 1 new error (dry run)
[exit 1]
$ undo
undid changed parameter s to &mut [i64] in crate::fill, 1 argument in 1 call	main.tach	+2 -2 lines
$ undo
undid changed parameter v to &Vec<i64> in crate::total, 2 arguments in 2 calls	main.tach	+3 -3 lines
$ undo
undid changed parameter v to &mut Vec<i64> in crate::add, 1 argument in 2 calls	main.tach	+2 -2 lines
$ refactor signature add --type v '&mut Vec<i64>' --default '&mut $v' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -13 +13 @@
-fn add(v: *Vec<i64>, x: i64) {
+fn add(v: &mut Vec<i64>, x: i64) {
@@ -25 +25 @@
-    add(&v, 1);
+    add(&mut v, 1);
$ check
main.tach:18:5: error[own.readonly] writes through 's', a '[i64]', which is read-only | help: take the slice as '&mut [T]' ('v.as_mut_slice()', '&mut a[..]') to write its elements | try: tachyonc refactor signature fill --type s '&mut [i64]'
[exit 1]
