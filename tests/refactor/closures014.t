## The refactorings with closures (0.14; tests/refactor/closures014/):
## references and calls inside a closure's body, a captured local mapped
## back to the local it is, a closure's type never in NEW's signature.
$ main.tach -o prog
ok: built prog
% ./prog; echo "exit $?"
25
exit 0
$ query refs double
# main.tach
8:4	def	fn double(x: i64) -> i64 {
20:24	call	main	let add = |x: i64| double(x) + k;
24:9	call	main	double(z)
## A closure's function and environment are no items.
$ query unused
note query.empty: nothing unused
## The calls inside closures get the new argument.
$ refactor signature double --add 'y: i64 = 0' --fill-calls --dry-run
--- a/main.tach
+++ b/main.tach
@@ -8 +8 @@
-fn double(x: i64) -> i64 {
+fn double(x: i64, y: i64) -> i64 {
@@ -20 +20 @@
-    let add = |x: i64| double(x) + k;
+    let add = |x: i64| double(x, 0) + k;
@@ -24 +24 @@
-        double(z)
+        double(z, 0)
## A closure made before the lines and used in them: refused; the try
## line starts at its `let`.
$ refactor extract-function main --lines 21-21 --to step
error refactor.closure: lines 21-21 use 'add', a closure made before them; a closure's type has no name for NEW's signature
try: tachyonc refactor extract-function main --lines 20-21 --to step
[exit 1]
## With its `let`: k, captured, is a parameter; total is given back.
% "$COMPILER" refactor extract-function main --lines 20-21 --to step | cut -f1
extracted lines 20-21 of crate::main into step(k, total) -> i64
% sed -n '17,35p' main.tach
fn main() -> i32 {
    let k = 3;
    let mut total = 0;
    total = step(k, total);
    total += apply(|y| {
        let z = y + k;
        double(z)
    }, 2);
    total += scaled(2, 5);
    std::print_int(total);
    println("");
    0
}

fn step(k: i64, total: sink i64) -> i64 {
    let add = |x: i64| double(x) + k;
    total += apply(add, 1);
    total
}
$ main.tach -o prog
ok: built prog
% ./prog
25
% "$COMPILER" undo | cut -f1
undid extracted lines 20-21 of crate::main into step(k, total) -> i64
## Lines of a closure's body: its parameter y and the captured k become
## NEW's parameters.
% "$COMPILER" refactor extract-function main --lines 23-23 --to shift | cut -f1
extracted lines 23-23 of crate::main into shift(y, k) -> i64
% sed -n '22,35p' main.tach
    total += apply(|y| {
        let z = shift(y, k);
        double(z)
    }, 2);
    total += scaled(2, 5);
    std::print_int(total);
    println("");
    0
}

fn shift(y: i64, k: i64) -> i64 {
    let z = y + k;
    z
}
$ main.tach -o prog
ok: built prog
% ./prog
25
% "$COMPILER" undo | cut -f1
undid extracted lines 23-23 of crate::main into shift(y, k) -> i64
## A local that closures capture: renamed in their bodies too.
% "$COMPILER" refactor rename main.tach:18:9 kk | cut -f1
renamed local k to kk in crate::main, 2 uses
% grep -n kk main.tach
18:    let kk = 3;
20:    let add = |x: i64| double(x) + kk;
23:        let z = y + kk;
% "$COMPILER" undo | cut -f1
undid renamed local k to kk in crate::main, 2 uses
## Calls inside closures are renamed and inlined like any other.
% "$COMPILER" refactor rename double twice | cut -f1
renamed crate::double to twice
% grep -n twice main.tach
8:fn twice(x: i64) -> i64 {
20:    let add = |x: i64| twice(x) + k;
24:        twice(z)
% "$COMPILER" refactor inline twice | cut -f1
inlined crate::twice at 2 calls, deleted it
% sed -n '13,21p' main.tach
fn main() -> i32 {
    let k = 3;
    let mut total = 0;
    let add = |x: i64| x * 2 + k;
    total += apply(add, 1);
    total += apply(|y| {
        let z = y + k;
        z * 2
    }, 2);
$ main.tach -o prog
ok: built prog
% ./prog
25
$ fmt --check
