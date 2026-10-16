## (0.18) The symbols the compiler makes are portable: letters, digits,
## `_`, `.` and `$` (a contract's companions, `f$pre` and `f$body`), so
## every system assembler takes the `-S` output (GNU as refused `?`).
## Every label of the assembly, for each target and kind of build.
% for t in aarch64-macos x86_64-macos aarch64-linux x86_64-linux; do for f in "-O0" "-O2" "-O0 --test-build" "-O1 --coverage --test-build" "-O0 -g --trace --check-alloc"; do $COMPILER --target $t $f -S main.tach -o x.s || echo "failed: $t $f"; grep -oE '^[^ 	#][^:]*:' x.s | sed 's/:$//' | grep -v '^[A-Za-z0-9_.$]*$' | sed "s/^/$t $f: /"; done; done; echo checked
checked
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
ok: wrote x.s
% grep -c '\$pre' x.s
5
