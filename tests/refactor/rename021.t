## (0.21) The tools of 0.24's rename (tachyon to vole, .tach to .vl):
## query grep --ignore-case, rewrite --text (any tracked file, word and
## case aware, places of a source, exclusions, moves, --check, undo) and
## refactor extension (a program, or --all; the build compared).
## Every mention, in a source's strings and comments, in either case:
$ query grep --ignore-case --strings --comments tachyon
# geo/shapes.tach
1:22	comment	geo::shapes::rect	// See geo/mod.tach. TACHYON_ROOT is read by tachyonc.
1:46	comment	geo::shapes::rect	// See geo/mod.tach. TACHYON_ROOT is read by tachyonc.
# main.tach
1:8	comment	geo	// The tachyon demo: main.tach and geo/shapes.tach.
5:33	string	main	println(f"{geo::area(3, 4)} tachyon");
6:29	string	main	println("main.tach says Tachyon");
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
geo/shapes.tach	1 match
rewrote 1 match in 1 file
% git status --short
 M geo/shapes.tach
$ undo
undid rewrote --text tachyonc volec	1 files	1 matches
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
tachyon-run.sh	2 matches
would rewrite 3 matches in 2 files
## A check that finds a new error writes nothing.
$ rewrite --text 'shapes::rect' 'shapes::nope' --code --check main.tach
geo/mod.tach:2:38: error[type error] no 'nope' in module 'geo::shapes'
error rewrite.breaks: 1 new error in the --check programs; nothing written
try: tachyonc rewrite --text shapes::rect shapes::nope --code --check main.tach --dry-run --diff
[exit 1]
% git status --short
## A program's files: the mentions that name them change, the ones that
## name no file (a glob) and the strings are left, and are reported.
$ refactor extension .tach .vl --dry-run
docs/notes.md	3 mentions
geo/shapes.vl	1 mention
main.vl	2 mentions
tachyon-run.sh	2 mentions
geo/*.tach -> *.vl	2 files
*.tach -> *.vl	1 file
would rename 3 files (.tach -> .vl), 8 mentions in 4 files
note extension.strings: 1 mention in string literals of 1 source left: changing them changes what the program does
try: tachyonc rewrite --text .tach .vl --word --strings --dry-run
note extension.unresolved: 2 mentions name no file, 0 the end of several files' paths: left (tachyon-run.sh: *.tach)
note extension.check: 1 program would be compiled before and after the rename, and compared
## The whole tree, less the exclusions: every mention, the build compared.
$ refactor extension .tach .vl --all --exclude-from rename.keep
docs/notes.md	2 mentions
geo/shapes.vl	1 mention
main.vl	2 mentions
tachyon-run.sh	4 mentions
geo/*.tach -> *.vl	2 files
*.tach -> *.vl	1 file
renamed 3 files (.tach -> .vl), 9 mentions in 4 files
same build	1 program builds as before (the paths aside)
note extension.strings: 1 mention in string literals of 1 source left: changing them changes what the program does
try: tachyonc rewrite --text .tach .vl --word --strings --dry-run
note extension.excluded: 0 files kept their name (excluded); 1 mention left in excluded files and lines
% git status --short
 M docs/notes.md
R  geo/mod.tach -> geo/mod.vl
RM geo/shapes.tach -> geo/shapes.vl
RM main.tach -> main.vl
 M tachyon-run.sh
% test -x tachyon-run.sh && echo executable
executable
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
undid renamed 3 files .tach -> .vl	9 mentions in 4 files
% test -x tachyon-run.sh && echo executable
executable
% git status --short
?? prog
## Mistakes.
$ rewrite --text tachyon
error rewrite.usage: --text takes OLD and NEW
try: tachyonc rewrite --text tachyon vole --word --case --files '*.md' --dry-run
[exit 2]
$ rewrite --text a b --exclude 'x:/[a/'
error rewrite.exclude: 'x:/[a/' is no exclusion: GLOB, GLOB:/RE/ (its lines) or GLOB:/A/,/B/ (from A to before B)
[exit 2]
$ refactor extension .tach .tach
error extension.usage: OLD and NEW are two extensions
try: tachyonc refactor extension .tach .vl --all --dry-run
[exit 2]
$ refactor extension .tach .vl nowhere
error extension.no-files: no file of git's ends with .tach under 'nowhere'
[exit 1]
