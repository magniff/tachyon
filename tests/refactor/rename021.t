## (0.21) The tools of 0.24's rename (tachyon to vole, .tach to .vl):
## query grep --ignore-case, rewrite --text (any tracked file, word and
## case aware, places of a source, exclusions, moves, --check, undo) and
## refactor extension (a program, or --all; the build compared).
## Every mention, in a source's strings and comments, in either case:
$ query grep --ignore-case --strings --comments tachyon
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query grep tachyon path/to/main.vl
[exit 2]
## A dry run with the per-file summary and the diff; an exclusion file
## keeps the history section of notes.md and all of keep.txt.
$ rewrite --text tachyon vole --word --case --exclude-from rename.keep --dry-run --diff
docs/notes.md	3 matches	2 lines kept
geo/shapes.tach	1 match
main.tach	3 matches
would rewrite 7 matches in 3 files
--- a/docs/notes.md
+++ b/docs/notes.md
@@ -1,2 +1,2 @@
-# Tachyon notes
-Run `tachyonc check main.tach`; the module geo/shapes.tach; TACHYON_CACHE=off.
+# Vole notes
+Run `tachyonc check main.tach`; the module geo/shapes.tach; VOLE_CACHE=off.
@@ -6 +6 @@
-tachyon now.
+vole now.
--- a/geo/shapes.tach
+++ b/geo/shapes.tach
@@ -1 +1 @@
-// See geo/mod.tach. TACHYON_ROOT is read by tachyonc.
+// See geo/mod.tach. VOLE_ROOT is read by tachyonc.
--- a/main.tach
+++ b/main.tach
@@ -1 +1 @@
-// The tachyon demo: main.tach and geo/shapes.tach.
+// The vole demo: main.tach and geo/shapes.tach.
@@ -5,2 +5,2 @@
-    println(f"{geo::area(3, 4)} tachyon");
-    println("main.tach says Tachyon");
+    println(f"{geo::area(3, 4)} vole");
+    println("main.tach says Vole");
note rewrite.excluded: 1 match left in 1 excluded file
note rewrite.kept: 1 match left in 1 file: in kept lines (the exclusions), or in other places than --comments, --strings, --code ask
## In the sources' comments and strings only, checked: tachyonc is a word
## of its own (TACHYON_ROOT has TACHYON, tachyonc has no tachyon).
$ rewrite --text tachyonc volec --word --case --comments --strings --check main.tach
rewrote 0 matches in 0 files
% git status --short
$ undo
error undo.empty: no edit to undo
[exit 1]
% git status --short
## A regular expression, within a line.
$ rewrite --text 'tach[a-z]*' X --regex --files '*.sh' --dry-run --diff
tachyon-run.sh	6 matches
would rewrite 6 matches in 1 file
--- a/tachyon-run.sh
+++ b/tachyon-run.sh
@@ -2,3 +2,3 @@
-# Builds main.tach with tachyonc; every *.tach here.
-tachyonc main.tach -o prog && ./prog
-ls geo/*.tach
+# Builds main.X with X; every *.X here.
+X main.X -o prog && ./prog
+ls geo/*.X
## A path with a match moves too (as git mv moves it), and undo moves it
## back.
$ rewrite --text tachyon vole --word --case --move-paths --files '*.sh'
vole-run.sh <- tachyon-run.sh	0 matches
rewrote 0 matches in 1 file, 1 moved
% git status --short
R  tachyon-run.sh -> vole-run.sh
% test -x vole-run.sh && echo executable
executable
$ query diff
# rewrote --text tachyon vole	1 files	0 matches
moved WORK/tachyon-run.sh -> WORK/vole-run.sh
$ undo
undid rewrote --text tachyon vole	1 files	0 matches
% git status --short
% test -x tachyon-run.sh && echo executable
executable
## The files that are no vole source only.
$ rewrite --text tachyonc volec --word --no-sources --dry-run
docs/notes.md	1 match
geo/shapes.tach	1 match
tachyon-run.sh	2 matches
would rewrite 4 matches in 3 files
## A check that finds a new error writes nothing.
$ rewrite --text 'shapes::rect' 'shapes::nope' --code --check main.tach
rewrote 0 matches in 0 files
% git status --short
## A program's files: the mentions that name them change, the ones that
## name no file (a glob) and the strings are left, and are reported.
$ refactor extension .tach .vl --dry-run
error extension.usage: no program here: name a ROOT, a DIR, or --all
try: volec refactor extension .vl .vl --all --dry-run
[exit 2]
## The whole tree, less the exclusions: every mention, the build compared.
$ refactor extension .tach .vl --all --exclude-from rename.keep
docs/notes.md	2 mentions
geo/shapes.vl	1 mention
main.vl	2 mentions
tachyon-run.sh	4 mentions
*.tach -> *.vl	2 files
geo/*.tach -> *.vl	2 files
renamed 4 files (.tach -> .vl), 9 mentions in 4 files
note extension.strings: 1 mention in string literals of 1 source left: changing them changes what the program does
try: volec rewrite --text .tach .vl --word --strings --dry-run
note extension.excluded: 0 files kept their name (excluded); 1 mention left in excluded files and lines
error extension.differs: 1 of 1 programs build differently after the rename (main.vl: exit status 1 before, 0 after); the rename is undone, the outputs are in target/extension-check
error undo.changed: 'WORK/alias.vl' changed since the edit; nothing undone
try: volec undo --force
[exit 1]
% git status --short
R  alias.tach -> alias.vl
 M docs/notes.md
R  geo/mod.tach -> geo/mod.vl
RM geo/shapes.tach -> geo/shapes.vl
RM main.tach -> main.vl
 M tachyon-run.sh
?? target/
% test -x tachyon-run.sh && echo executable
executable
## (0.24) A link to a renamed file is moved and points at its new name.
% readlink alias.vl
geo/shapes.tach
% cat tachyon-run.sh docs/notes.md
#!/bin/sh
# Builds main.vl with tachyonc; every *.vl here.
tachyonc main.vl -o prog && ./prog
ls geo/*.vl
# Tachyon notes
Run `tachyonc check main.vl`; the module geo/shapes.vl; TACHYON_CACHE=off.
History, 0.1:
tachyon 0.1 had main.tach only.
Now, 0.2:
tachyon now.
% "$COMPILER" main.vl -o prog && ./prog
12 tachyon
main.tach says Tachyon
ok: built prog
$ undo
error undo.changed: 'WORK/alias.vl' changed since the edit; nothing undone
try: volec undo --force
[exit 1]
% test -x tachyon-run.sh && echo executable
executable
% git status --short
R  alias.tach -> alias.vl
 M docs/notes.md
R  geo/mod.tach -> geo/mod.vl
RM geo/shapes.tach -> geo/shapes.vl
RM main.tach -> main.vl
 M tachyon-run.sh
?? prog
?? target/
## Mistakes.
$ rewrite --text tachyon
error rewrite.usage: --text takes OLD and NEW
try: volec rewrite --text vole vole --word --case --files '*.md' --dry-run
[exit 2]
$ rewrite --text a b --exclude 'x:/[a/'
error rewrite.exclude: 'x:/[a/' is no exclusion: GLOB, GLOB:/RE/ (its lines) or GLOB:/A/,/B/ (from A to before B)
[exit 2]
$ refactor extension .tach .tach
error extension.usage: OLD and NEW are two extensions
try: volec refactor extension .vl .vl --all --dry-run
[exit 2]
$ refactor extension .tach .vl nowhere
error extension.no-files: no file of git's ends with .tach under 'nowhere'
[exit 1]
