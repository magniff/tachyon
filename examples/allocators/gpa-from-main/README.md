# Where allocation comes from: `fn main(gpa: Gpa)`

A shop's orders, read from stdin (`customer item quantity price`, the
price in cents), totalled per customer and per item. The program is
small on purpose: what it shows is where its memory comes from.

Since vole 0.16 nothing allocates unless it is given an allocator.
There is no global `malloc` to reach for: the general-purpose allocator
is a value of type `Gpa`, `main` receives it as a parameter, and a
function that allocates either takes one as a parameter or works on a
container that holds one. So a function's signature says whether it can
allocate, and the compiler can prove it: `volec query effects` lists
what each function may do.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-gpa-from-main.test` runs the program.

## Run it

```console
$ volec main.vl -o orders && ./orders < orders.txt
alice       4.55
bob         3.10
carol      11.00
dave       10.00
6 orders, 3 items, total 28.65
apples sold: 14
ok: built orders
skipped: bob apples one 120
```

## The allocator is a parameter

`main` takes the allocator as its last parameter (after `argc, argv`
when it takes those too). The runtime makes the one `Gpa` a program has
and passes it in; a program whose `main` takes none cannot allocate at
all (see [fixed-buffer](../fixed-buffer/)).

```tach
fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();
    let orders = parse_orders(input.as_slice(), gpa);
```

Each standard-library function that allocates has an `_in` form taking
the allocator last: `Vec::new_in(gpa)`, `Buf::new_in(gpa)`,
`HashMap::new_in(gpa)`, `read_stdin_in(gpa)`, `split_in(s, sep, gpa)`,
`format_in(x, gpa)`, `it.collect_in(gpa)`. A function of the program
that allocates takes it the same way and passes it on:

```tach
fn parse_orders(text: [u8], gpa: Gpa) -> Vec<Order> {
    var orders: Vec<Order> = Vec::new_in(gpa);
    let lines = split_in(text, '\n', gpa);
```

There are four kinds of function in `main.vl`, by what they are given:

| function | signature | allocates |
|---|---|---|
| `parse_orders` | `(text: [u8], gpa: Gpa) -> Vec<Order>` | from the `gpa` it is passed |
| `total` | `(orders: [Order]) -> i64` | never: a slice and no allocator |
| `by_customer` | `(orders: Vec<Order>) -> HashMap<[u8], i64>` | from the allocator the Vec holds: `orders.allocator()` |
| `count_items` | `<A: Allocator>(orders: [Order], a: sink A) -> HashMap<[u8], i64, A>` | from whichever allocator the caller picks |

A container keeps its allocator: `Vec<T>` is short for `Vec<T, Gpa>`
(and costs three words, as before: a `Gpa` takes no bytes), and its
`push`, `clone` and drop use the allocator it holds. That is why
`by_customer` needs no allocator parameter: it makes its map on the one
the orders' Vec was made with. And it is why `total`, which takes a
slice, cannot allocate: a slice is a view, it holds no allocator.

## What the compiler knows

`query effects` prints what each function may do, inferred from its
body and everything it calls (`volec guide effects`):

```console
$ volec query effects crate
crate::parse_orders	alloc(Gpa) io global panic diverge
crate::total	none
crate::by_customer	alloc(Gpa) panic
count_items<Gpa>	alloc(Gpa) panic
crate::main	alloc(Gpa) io global panic diverge
```

`total` is `none`: no allocation, no I/O, no statics, and not even a
possible panic. `count_items` is generic, so its effects are its
instances': here only `Gpa`. `parse_orders` does I/O (`eprintln` of a
bad line, which writes through a static buffer: `global`) and may not
terminate (`diverge`: std's `split_whitespace_in` loops with `while
let`); `query effects parse_orders --why diverge` shows the chain.

## Forgetting the allocator

A 0.15 program allocated without saying so. Here is one, using the old
forms:

```console
$ cat > old.vl <<'EOF'
> use std::Buf;
>
> fn shout(words: [[u8]]) -> Buf {
>     var b = Buf::new();
>     for w in words {
>         if b.len() > 0 {
>             b.push_str(" ");
>         }
>         b.push_str(w);
>         b.push_str("!");
>     }
>     b
> }
>
> fn main() -> i32 {
>     let words: Vec<[u8]> = std::split_whitespace("hello explicit allocation");
>     let b = shout(words.as_slice());
>     println(b.as_slice());
>     0
> }
> EOF
$ volec check old.vl
old.vl:4:13: error[type error] allocation is explicit: pass an allocator (try: Buf::new_in(gpa)) | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'shout' and pass it down | try: volec fix --only alloc016 old.vl
old.vl:16:28: error[type error] allocation is explicit: pass an allocator (try: split_whitespace_in(s, gpa)) | help: main takes the allocator: `fn main(gpa: Gpa)`, passed down as a parameter | try: volec fix --only alloc016 old.vl
[exit 1]
```

Each old form is an error naming its `_in` form. `fix --only alloc016`
makes the whole change: every call becomes its `_in` form, and `gpa:
Gpa` is added to each function from `main` down to the calls, and passed
at each call:

```console
$ volec fix --only alloc016 --dry-run old.vl
--- a/old.vl
+++ b/old.vl
@@ -3,2 +3,2 @@
-fn shout(words: [[u8]]) -> Buf {
-    var b = Buf::new();
+fn shout(words: [[u8]], gpa: Gpa) -> Buf {
+    var b = Buf::new_in(gpa);
@@ -15,3 +15,3 @@
-fn main() -> i32 {
-    let words: Vec<[u8]> = std::split_whitespace("hello explicit allocation");
-    let b = shout(words.as_slice());
+fn main(gpa: Gpa) -> i32 {
+    let words: Vec<[u8]> = std::split_whitespace_in("hello explicit allocation", gpa);
+    let b = shout(words.as_slice(), gpa);
$ volec fix --only alloc016 old.vl
fixed 2 allocations made explicit	old.vl	+5 -5 lines
$ volec old.vl -o old && ./old
hello! explicit! allocation!
ok: built old
```

It compiles and runs, and frees what it allocated: since 0.17 `words`
and `b` are dropped at the end of `main`, so `--check-alloc` (below)
finds nothing left:

```console
$ volec --check-alloc old.vl -o old && ./old
hello! explicit! allocation!
ok: built old
```

A function that allocates and is not given an allocator cannot make
one: `gpa` is a name like any other, and here it is not in scope.

```console
$ cat > count.vl <<'EOF'
> fn count(text: [u8]) -> i64 {
>     let words = std::split_whitespace_in(text, gpa);
>     words.len()
> }
>
> fn main(gpa: Gpa) -> i32 {
>     println(count("one two three"));
>     0
> }
> EOF
$ volec check count.vl
count.vl:2:48: error[type error] undefined variable 'gpa'
[exit 1]
```

The fix is a parameter, and the allocator passed at every call;
`refactor signature` does both (`--fill-calls`: each call gets `gpa`,
which is in scope at every call since the callers have one):

```console
$ volec refactor signature count --add 'gpa: Gpa = gpa' --fill-calls count.vl
added parameter gpa: Gpa to crate::count, 1 call	count.vl	+2 -2 lines
$ volec count.vl -o count && ./count
3
ok: built count
```

Nor can a `Gpa` be made, or kept in a static: `Gpa` is `#[sealed]`, so
only std makes one (the one `main` gets), and no constant expression
does.

```console
$ cat > forge.vl <<'EOF'
> static var CACHE: Vec<i64> = Vec::new_in(Gpa {});
>
> fn main() -> i32 {
>     let mine = Gpa {};
>     0
> }
> EOF
$ volec check forge.vl
forge.vl:1:42: error[type error] 'Gpa' is sealed: only module 'std' makes one | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)' and is passed down as a parameter
forge.vl:4:16: error[type error] 'Gpa' is sealed: only module 'std' makes one | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)' and is passed down as a parameter
[exit 1]
```

So the rule the effects state holds for every program: **a function
allocates only from allocators it was given** (its parameters, what it
captures, the containers it was handed) **or reaches through statics**
(and then it has the effect `global` too).

## Checking the frees

Every container here is dropped at the end of its scope: no `free` is
written. `--check-alloc` builds the program with a checking `Gpa` that
lists, at exit, every block still allocated (and stops at a use after
free or a double free: see [check-alloc](../check-alloc/)). It lists
nothing here: stdout is as before, and stderr has only the skipped
line.

```console
$ volec --check-alloc main.vl -o orders-checked && ./orders-checked < orders.txt > /dev/null
ok: built orders-checked
skipped: bob apples one 120
```

## Read more

- `volec guide allocators`: the `_in` forms, containers and their
  allocator, arenas, `--check-alloc`, `fix --only alloc016`.
- `volec guide effects`: what `alloc(Gpa)`, `io`, `global`, `panic`,
  `diverge` mean, and how to promise them.
- [arena-parser](../arena-parser/), [scoped-arena](../scoped-arena/) and
  [fixed-buffer](../fixed-buffer/): the other allocators.
