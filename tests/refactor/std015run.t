## needs: 0.15 io
## tachyonc fix --only std015 on a program written against 0.14's std
## (tests/refactor/std015run/, whose output under 0.14 is below): with
## 0.15's std it does not compile, migrated it prints what it printed
## under 0.14 (the design's acceptance: the migration is exact); a second
## run finds nothing to do.
$ fix --only std015
fixed 5 calls of 0.14's std	main.tach	+5 -5 lines
% "$COMPILER" main.tach -o prog && ./prog < input.txt
a 42
b -1
c 7
empty 1
total 10
count 4
more 0
$ fix --only std015
note fix.none: nothing to fix
