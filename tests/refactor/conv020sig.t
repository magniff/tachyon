## (0.20) refactor signature --convention x let|inout|sink: the parameter
## and every call's marker (`&` for inout, none for let and sink); in a
## file read mixed a let is written `x: let T` (`x: T` is 0.19's by-value
## parameter there). `--type x 'inout T'` marks the calls too.
$ refactor signature Acc::show --convention self let
made parameter self let in crate::Acc::show	main.tach	+1 -1 lines
$ refactor signature peek --convention a inout --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10 +10 @@
-fn peek(a: let Acc) -> i64 { a.n }
+fn peek(a: inout Acc) -> i64 { a.n }
$ refactor signature eat --convention v let
made parameter v let in crate::eat	main.tach	+1 -1 lines
$ refactor signature bump --type k 'inout i64' --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn bump(a: inout Acc, k: i64) { a.n += k; }
+fn bump(a: inout Acc, k: inout i64) { a.n += k; }
@@ -16 +16 @@
-    bump(&a, 2);
+    bump(&a, &2);
$ refactor signature eat --convention v lent
error refactor.usage: --convention takes a parameter and let, inout or sink
try: tachyonc refactor signature NAME --convention x inout
[exit 2]
% cat main.tach
struct Acc { n: i64 }

impl Acc {
    fn show(self) -> i64 { self.n }
    fn add(inout self, k: i64) { self.n += k; }
}

fn bump(a: inout Acc, k: i64) { a.n += k; }

fn peek(a: let Acc) -> i64 { a.n }

fn eat(v: let Vec<i64>) -> i64 { v.len() }

fn main(gpa: Gpa) {
    var a = Acc { n: 1 };
    bump(&a, 2);
    println(peek(&a));
    println(a.show());
    Acc::add(&a, 3);
    let v: Vec<i64> = Vec::new_in(gpa);
    println(eat(v));
}
