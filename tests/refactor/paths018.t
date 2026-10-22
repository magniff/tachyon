## (0.18) Every path the compiler writes into what it makes is relative
## to the root file's directory: the same object whatever the current
## directory and however the root's path is spelled (main.vl,
## ./main.vl, an absolute path, ../main.vl from elsewhere).
% mkdir elsewhere
$ main.vl -c -o a.o
ok: wrote a.o
$ ./main.vl -c -o b.o
ok: wrote b.o
% $COMPILER "$PWD/main.vl" -c -o c.o
ok: wrote c.o
% cd elsewhere && $COMPILER ../main.vl -c -o ../d.o
ok: wrote ../d.o
% cmp a.o b.o && cmp a.o c.o && cmp a.o d.o && echo identical
identical
## The same with every option that writes positions or file names.
$ main.vl -g --trace --check-alloc --check-unsafe -c -o ga.o
ok: wrote ga.o
% $COMPILER "$PWD/main.vl" -g --trace --check-alloc --check-unsafe -c -o gb.o
ok: wrote gb.o
% cd elsewhere && $COMPILER ../main.vl -g --trace --check-alloc --check-unsafe -c -o ../gc.o
ok: wrote ../gc.o
% cmp ga.o gb.o && cmp ga.o gc.o && echo identical
identical
## The messages name the file from the root's directory, wherever the
## program was built and runs.
% cd elsewhere && $COMPILER ../main.vl -o ../prog && ../prog; echo "exit $?"
6
exit 101
ok: built ../prog
main.vl:18:16: requires failed: 's.len() > 0' of 'median' (main.vl:6:5): s.len() = 0
% cd elsewhere && ../prog x y; echo "exit $?"
6
3
exit 101
util.vl:6:5: index out of bounds: index 5, length 2
