## (0.18.1) A clean check and a build end with `ok: ...` (stderr); a
## failed one does not.
$ check main.vl
ok: 0 errors in main.vl
$ main.vl -o prog
ok: built prog
% ./prog
42
$ check bad.vl
bad.vl:2:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: volec fix --suggested bad.vl
[exit 1]
$ bad.vl -o bad
bad.vl:2:5: error[type error] undefined variable 'prinln' | help: did you mean 'println'? | try: volec fix --suggested bad.vl
[exit 1]
## --emit-ir (and --emit-mir) without -o print to stdout, no a.o
% "$COMPILER" --emit-ir main.vl | head -1
fn main:
% test -e a.o || echo no a.o
no a.o
% "$COMPILER" --emit-mir main.vl | head -1
fn main:
## with -o, the file, as before
$ --emit-ir main.vl -o main.ir
ok: wrote main.ir
% head -1 main.ir
fn main:
