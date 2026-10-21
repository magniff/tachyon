## (0.20) fmt writes a receiver in its short form (`self: inout Self` is
## `inout self`, `self: let Self` `self`, `self: sink Self` `sink self`:
## one meaning in every spelling), and the program prints what it printed
## (6, 3). With --syntax=0.20 it drops a written `let` of a parameter
## (let is the default there; a field's `let P` stays).
$ fmt main.tach
formatted	main.tach	+3 -3 lines
$ main.tach -o prog
ok: built prog
% ./prog
6
3
$ fmt main.tach --syntax=0.20 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -10 +10 @@
-fn d(x: let P) -> i64 { x.n }
+fn d(x: P) -> i64 { x.n }
