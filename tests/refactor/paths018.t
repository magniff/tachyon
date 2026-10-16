## (0.18) Every path the compiler writes into what it makes is relative
## to the root file's directory: the same object whatever the current
## directory and however the root's path is spelled (main.tach,
## ./main.tach, an absolute path, ../main.tach from elsewhere).
% mkdir elsewhere
$ main.tach -c -o a.o
$ ./main.tach -c -o b.o
% $COMPILER "$PWD/main.tach" -c -o c.o
% cd elsewhere && $COMPILER ../main.tach -c -o ../d.o
% cmp a.o b.o && cmp a.o c.o && cmp a.o d.o && echo identical
identical
## The same with every option that writes positions or file names.
$ main.tach -g --trace --check-alloc --check-unsafe -c -o ga.o
% $COMPILER "$PWD/main.tach" -g --trace --check-alloc --check-unsafe -c -o gb.o
% cd elsewhere && $COMPILER ../main.tach -g --trace --check-alloc --check-unsafe -c -o ../gc.o
% cmp ga.o gb.o && cmp ga.o gc.o && echo identical
identical
## The messages name the file from the root's directory, wherever the
## program was built and runs.
% cd elsewhere && $COMPILER ../main.tach -o ../prog && ../prog; echo "exit $?"
6
exit 101
main.tach:18:16: requires failed: 's.len() > 0' of 'median' (main.tach:6:5): s.len() = 0
% cd elsewhere && ../prog x y; echo "exit $?"
6
3
exit 101
util.tach:6:5: index out of bounds: index 5, length 2
