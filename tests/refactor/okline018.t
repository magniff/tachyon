## (0.18.1) A clean check and a build end with `ok: ...` (stderr); a
## failed one does not.
$ check main.tach
ok: 0 errors in main.tach
$ main.tach -o prog
ok: built prog
% ./prog
42
$ check bad.tach
bad.tach:2:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: tachyonc fix --suggested bad.tach
[exit 1]
$ bad.tach -o bad
bad.tach:2:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: tachyonc fix --suggested bad.tach
[exit 1]
## --emit-ir (and --emit-mir) without -o print to stdout, no a.o
% "$COMPILER" --emit-ir main.tach | head -1
fn main:
% test -e a.o || echo no a.o
no a.o
% "$COMPILER" --emit-mir main.tach | head -1
fn main:
## with -o, the file, as before
$ --emit-ir main.tach -o main.ir
ok: wrote main.ir
% head -1 main.ir
fn main:
