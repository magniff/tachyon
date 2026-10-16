## tachyonc fix --only alloc016 (0.16) on a program written against 0.15's
## std, whose containers took their memory from an ambient allocator
## (tests/refactor/alloc016run/): std's 0.15 forms become their `_in`
## forms, `fn main()` takes `gpa: Gpa`, and every function between them
## takes it too (methods, a trait's function with its impl and its generic
## caller, a closure's function, another module's; before a parameter
## with a default); the imports follow; reads of the fields of std's
## sealed types become their methods (`v.cap` -> `v.capacity()`; `v.len` stays,
## 0.17 reads it as `v.len()`).
## The migrated program compiles as 0.16 asks and prints what it printed
## under 0.15 (the design's acceptance: the migration is exact); a second
## run finds nothing to do.
$ fix --only alloc016
fixed 13 allocations made explicit	2 files	+36 -36 lines
% git diff --stat | tail -1
 2 files changed, 36 insertions(+), 36 deletions(-)
% "$COMPILER" main.tach -o prog && ./prog < input.txt
6 words, shortest 3, longest 5
squares 16
(1, 2)
area 14
7 0
padded 0 4 9
ok: built prog
$ fix --only alloc016
note fix.none: nothing to fix
