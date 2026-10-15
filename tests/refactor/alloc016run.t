## tachyonc fix --only alloc016 (0.16) on a program written against 0.15's
## std, whose containers took their memory from an ambient allocator
## (tests/refactor/alloc016run/): std's 0.15 forms become their `_in`
## forms, `fn main()` takes `gpa: Gpa`, and every function between them
## takes it too (methods, a trait's function with its impl and its generic
## caller, a closure's function, another module's); the imports follow.
## The migrated program compiles as 0.16 asks and prints what it printed
## under 0.15 (the design's acceptance: the migration is exact); a second
## run finds nothing to do.
$ fix --only alloc016
fixed 11 allocations made explicit	2 files	+30 -30 lines
% git diff --stat | tail -1
 2 files changed, 30 insertions(+), 30 deletions(-)
% "$COMPILER" main.tach -o prog && ./prog < input.txt
6 words, shortest 3, longest 5
squares 16
(1, 2)
area 14
7 0
$ fix --only alloc016
note fix.none: nothing to fix
