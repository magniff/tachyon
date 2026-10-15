## 0.13: refactor extract-function and refactor inline (tests/refactor/code/).
$ main.tach -o prog
% ./prog; echo "exit $?"
exit 0
## ---- extract-function ----
## Inside an unsafe block: an unsafe block in NEW too; t, assigned, is
## given back.
$ refactor extract-function bytes --lines 92-94 --to sum_bytes --show
extracted lines 92-94 of crate::calc::bytes into sum_bytes(t, p) -> i64	calc.tach	+8 -1 lines
// calc.tach:92-98
92	        t = sum_bytes(t, p);
93	    }
94	    t
95	}
96	
97	fn sum_bytes(mut t: i64, p: *u8) -> i64 {
98	    unsafe {
// calc.tach:102
102	        t
// calc.tach:103: 1 line removed after line 103
$ undo
undid extracted lines 92-94 of crate::calc::bytes into sum_bytes(t, p) -> i64	calc.tach	+8 -1 lines
## Two locals declared in the lines and used after them: a tuple.
$ refactor extract-function sum_to --lines 24-31 --to sums
extracted lines 24-31 of crate::calc::sum_to into sums(n) -> (i64, i64)	calc.tach	+7 -2 lines
% sed -n '22,40p' calc.tach
// 1 + 2 + ... + n, plus the squares.
pub fn sum_to(n: i64) -> i64 {
    let (total, squares) = sums(n);
    let both = total + squares;
    both
}

fn sums(n: i64) -> (i64, i64) {
    let mut total = 0;
    let mut squares = 0;
    let mut i = 1;
    while i <= n {
        total += i;
        squares += i * i;
        i += 1;
    }
    (total, squares)
}

## A local assigned (given back), a value whose method takes its address
## (by pointer).
$ refactor extract-function mean_to --lines 45-48 --to add_all --show
extracted lines 45-48 of crate::calc::mean_to into add_all(i, n, acc) -> i64	calc.tach	+6 -1 lines
// calc.tach:45-49
45	    i = add_all(i, n, &acc);
46	    acc.mean()
47	}
48	
49	fn add_all(mut i: i64, n: i64, acc: *Acc) -> i64 {
// calc.tach:54
54	    i
## In a method, using self: a method of the same impl.
$ refactor extract-function Acc::mean --lines 16-17 --to raw_mean --show
extracted lines 16-17 of crate::calc::Acc::mean into raw_mean() -> i64	calc.tach	+5 -0 lines
// calc.tach:16-20
16	        let m = self.raw_mean();
17	        m
18	    }
19	
20	    fn raw_mean(self: *Acc) -> i64 {
$ main.tach -o prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid extracted lines 16-17 of crate::calc::Acc::mean into raw_mean() -> i64	calc.tach	+5 -0 lines
$ undo
undid extracted lines 45-48 of crate::calc::mean_to into add_all(i, n, acc) -> i64	calc.tach	+6 -1 lines
$ undo
undid extracted lines 24-31 of crate::calc::sum_to into sums(n) -> (i64, i64)	calc.tach	+7 -2 lines
% git status --short
?? prog
## Refused: control flow leaving the lines, a cut statement, two results
## one of which was declared before.
$ refactor extract-function first_big --lines 51-55 --to step
error refactor.escapes: line 53 returns from crate::calc::first_big: out of lines 51-55, which NEW cannot do for its caller
try: tachyonc refactor extract-function first_big --lines 51-51 --to step
[exit 1]
$ refactor extract-function first_big --lines 50-55 --to step
error refactor.range: lines 50-55 cut a statement of crate::calc::first_big (lines 50-56); NEW takes whole statements of one block
try: tachyonc refactor extract-function first_big --lines 50-56 --to step
[exit 1]
$ refactor extract-function bytes --lines 85-89 --to fill
error refactor.results: lines 85-89 set t, i, buf, used after them; NEW gives back one local it assigns, or the ones it declares
try: tachyonc query show calc.tach:85
[exit 1]
$ refactor extract-function sum_to --lines 40-41 --to x
error refactor.range: lines 40-41 are not inside the body of crate::calc::sum_to (lines 23-34)
try: tachyonc query show crate::calc::sum_to
[exit 1]
$ refactor extract-function sum_to --lines 24-31 --to quad
error refactor.collision: 'quad' is already a name there
try: tachyonc query def quad
[exit 1]
## ---- inline ----
## A statement call: the body's statements in its place.
$ refactor inline Acc::add --show
inlined crate::calc::Acc::add at 1 call, deleted it	calc.tach	+2 -7 lines
// calc.tach:8: 6 lines removed after line 8
// calc.tach:35-36
35	        acc.total = acc.total + i;
36	        acc.count = acc.count + 1;
## An expression body: parenthesized where it binds looser.
$ refactor inline twice --show
inlined crate::calc::twice at 3 calls, deleted it	calc.tach	+2 -6 lines
// calc.tach:54: 4 lines removed after line 54
// calc.tach:68-69
68	    let y = x + x;
69	    y + y + (1 + 1) * square_plus(x + 1, 2) + clamp(x, 0, 9)
## Statements and an argument that is not a name: a block; the parameter
## renamed (the argument names x).
$ refactor inline square_plus --show
inlined crate::calc::square_plus at 1 call, deleted it	calc.tach	+5 -6 lines
// calc.tach:61: 5 lines removed after line 61
// calc.tach:64-68
64	    y + y + (1 + 1) * {
65	        let x_2 = x + 1;
66	        let s = x_2 * x_2;
67	        s + 2
68	    } + clamp(x, 0, 9)
$ main.tach -o prog
% ./prog; echo "exit $?"
exit 0
## Into another module: what the body names there made pub and imported;
## the function, unused then, deleted with its import.
$ refactor inline quad
inlined crate::calc::quad at 1 call, deleted it	2 files	+10 -12 lines
% git diff main.tach | sed -n '/^@@/,$p'
@@ -1,9 +1,16 @@
 // A program to extract functions from and inline (tests/refactor/code.t).
 mod calc;
 
-use crate::calc::{bytes, first_big, mean_to, quad, sum_to};
+use crate::calc::{bytes, clamp, first_big, mean_to, sum_to};
 
 fn main() -> i32 {
-    let s = sum_to(3) + mean_to(5) + first_big(10, 20) + quad(2) + bytes(4);
+    let s = sum_to(3) + mean_to(5) + first_big(10, 20) + {
+        let y = 2 + 2;
+        y + y + (1 + 1) * {
+            let x_2 = 2 + 1;
+            let s = x_2 * x_2;
+            s + 2
+        } + clamp(2, 0, 9)
+    } + bytes(4);
     if s == 78 { 0 } else { 1 }
 }
$ main.tach -o prog
% ./prog; echo "exit $?"
exit 0
$ undo
undid inlined crate::calc::quad at 1 call, deleted it	2 files	+10 -12 lines
$ undo
undid inlined crate::calc::square_plus at 1 call, deleted it	calc.tach	+5 -6 lines
$ undo
undid inlined crate::calc::twice at 3 calls, deleted it	calc.tach	+2 -6 lines
$ undo
undid inlined crate::calc::Acc::add at 1 call, deleted it	calc.tach	+2 -7 lines
% git status --short
?? prog
## One call, --at FILE:LINE: the function stays.
$ refactor inline sum_to --at main.tach:7 --dry-run
--- a/main.tach
+++ b/main.tach
@@ -7 +7,12 @@
-    let s = sum_to(3) + mean_to(5) + first_big(10, 20) + quad(2) + bytes(4);
+    let s = {
+        let mut total = 0;
+        let mut squares = 0;
+        let mut i = 1;
+        while i <= 3 {
+            total += i;
+            squares += i * i;
+            i += 1;
+        }
+        let both = total + squares;
+        both
+    } + mean_to(5) + first_big(10, 20) + quad(2) + bytes(4);
## Refused: an early return, no call there.
$ refactor inline first_big
error refactor.escapes: crate::calc::first_big returns early, on line 53: inline takes a function that ends with its value
try: tachyonc query show calc.tach:53
[exit 1]
$ refactor inline sum_to --at calc.tach:3
error refactor.no-call: crate::calc::sum_to is not called on calc.tach:3
try: tachyonc query refs crate::calc::sum_to
[exit 1]
