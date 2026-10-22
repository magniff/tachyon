## Editing std by name in the vole repository (0.17): this copy is
## one (compiler/std/ with its embed.sh), with a small std.
% mkdir -p compiler/src/front && cp $T/../../compiler/std/embed.sh $T/../../compiler/std/index.awk compiler/std/
## A std item is edited in its file, with the edited std checked.
$ edit insert --after std::trim --dry-run < $T/inputs/strip_prefix.vl
--- a/compiler/std/flat/io.vl
+++ b/compiler/std/flat/io.vl
@@ -19,0 +20,8 @@
+
+// s without prefix at its start, or None.
+pub fn strip_prefix(s: [u8], prefix: [u8]) -> Option<[u8]> {
+    if prefix.len > s.len || s[0..prefix.len] != prefix {
+        return None;
+    }
+    Option::Some(s[prefix.len..s.len])
+}
## An error in std's new text (0.17: std sees the prelude, `None`; here
## a wrong type): the check says so, nothing is written.
$ edit insert --after std::trim < $T/inputs/strip_prefix_none.vl
compiler/std/flat/io.vl:24:21: error[type error] expected '[u8]', got 'i64'  [edited]
error edit.breaks: 1 new error; nothing written
try: volec edit insert --after std::trim --no-check
[exit 1]
## Written, then embed.sh makes the compiler's std from the files.
$ edit insert --after std::trim < $T/inputs/strip_prefix.vl
inserted after std::trim	compiler/std/flat/io.vl	+8 -0 lines
note edit.std: ran compiler/std/embed.sh: compiler/src/front/stdsrc.vl has std's new text; rebuild to use it (bootstrap/bootstrap.sh --dev)
% grep -c 'pub fn strip_prefix' compiler/std/flat/io.vl compiler/src/front/stdsrc.vl
compiler/std/flat/io.vl:1
compiler/src/front/stdsrc.vl:1
## undo embeds again.
$ undo
undid inserted after std::trim	compiler/std/flat/io.vl	+8 -0 lines
note edit.std: ran compiler/std/embed.sh: compiler/src/front/stdsrc.vl has std's new text; rebuild to use it (bootstrap/bootstrap.sh --dev)
% grep -c 'pub fn strip_prefix' compiler/std/flat/io.vl compiler/src/front/stdsrc.vl
compiler/std/flat/io.vl:0
compiler/src/front/stdsrc.vl:0
[exit 1]
## A generic method is checked too (with i64 for T).
$ edit patch Option::unwrap_or --old 'Option::None => other,' --new 'Option::None => true,'
compiler/std/std.vl:13:29: error[type error] expected 'i64', got 'bool' | note: in instantiation of 'Option<i64>::unwrap_or' at compiler/std/std.vl:10:9  [edited: std::Option::unwrap_or]
error edit.breaks: 1 new error; nothing written
try: volec edit patch Option::unwrap_or --old 'Option::None => other,' --new 'Option::None => true,' --no-check
[exit 1]
## By its file and line, as queries print it.
$ edit patch compiler/std/flat/io.vl:13 --old 'a += 1;' --new 'a = a + 1;' --dry-run
--- a/compiler/std/flat/io.vl
+++ b/compiler/std/flat/io.vl
@@ -13 +13 @@
-        a += 1;
+        a = a + 1;
$ query show compiler/std/flat/io.vl:4
// std::is_space	compiler/std/flat/io.vl:3-6	effects: none
// use std::is_space;
// ' ' or '\n'.
pub fn is_space(b: u8) -> bool {
    b == ' ' || b == '\n'
}
## std's files are not this compiler's std: check reads them.
% printf '\npub fn bad() -> Option<i64> {\n    Nothing\n}\n' >> compiler/std/flat/io.vl
$ check
compiler/std/flat/io.vl:22:5: error[type error] undefined variable 'Nothing'
[exit 1]
