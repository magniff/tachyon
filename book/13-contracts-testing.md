# 13. Contracts and testing

Every function has rules its callers must follow and promises it makes
in return. `pop` needs something to pop; `sort` promises the result is
in order. Usually these live in comments, or in the author's head. In
this chapter you write them into the code as *contracts*, which the
program checks every time it runs, and then you write tests: ordinary
ones, *properties* that try a hundred generated inputs, and *fuzz
targets* that hunt for crashes. `volec test` runs them all.

Our running example is a *ring buffer*: a queue with a fixed capacity,
whose items live in one block of memory allocated up front. It's small,
but it's easy to get an index wrong in one, which makes it a good thing
to test.

## requires: what a function needs

Save this as `ring.vl`:

```vole ring.vl
// ring: a queue of at most `cap` numbers, in memory allocated once.

struct Ring {
    items: Vec<i64>,
    start: i64,
    len: i64,
}

impl Ring {
    fn new(cap: i64, gpa: Gpa) -> Ring
        requires cap > 0 else "a ring needs room for at least one item"
    {
        Ring { items: Vec::filled_in(cap, 0, gpa), start: 0, len: 0 }
    }

    fn cap(self) -> i64 {
        self.items.len()
    }

    fn push(inout self, x: i64)
        requires self.len < self.cap() else "push on a full ring"
    {
        let end = (self.start + self.len) % self.cap();
        self.items[end] = x;
        self.len += 1;
    }

    fn pop(inout self) -> i64
        requires self.len > 0
    {
        let x = self.items[self.start];
        self.start = (self.start + 1) % self.cap();
        self.len -= 1;
        x
    }
}

fn main(gpa: Gpa) {
    var r = Ring::new(3, gpa);
    r.push(10);
    r.push(20);
    println(f"{r.pop()} {r.pop()}");
    println(f"{r.pop()}");
}
```

The ring keeps its items in `items`, `cap` slots made once by
`Vec::filled_in`. `start` is the slot of the oldest item and `len` is
how many there are. `push` writes after the last item and `pop` takes
the oldest; both wrap around to slot 0 at the end, with `%`.

Between each function's signature and its body are its `requires`
clauses: conditions that must hold when it's called. `main` pushes two
numbers and pops three:

```out exit=101
10 20
ring.vl:43:16: requires failed: 'self.len > 0' of 'Ring::pop' (ring.vl:29:9): self.len = 0
```

The program stops with a panic, as a failed `unwrap` does, and exit
status 101. Read the line from the left:

- `ring.vl:43:16` is the *call* that broke the rule, the third `pop` in
  `main`, not a line inside `pop`. A requires is checked at the call,
  after the arguments are worked out, because the caller is the one who
  has to change.
- `'self.len > 0' of 'Ring::pop' (ring.vl:29:9)` is the condition that
  failed, and where it's written.
- `self.len = 0` is the value of each number in the condition.

`new` and `push` have an `else` after their condition. That replaces
the generic "requires failed" text with a message of your own; the
values are still printed after it. The message can be an f-string,
which is only formatted if the check fails.

Without a contract, the third `pop` would have read `items[0]` and
returned whatever stale number was there, and made `len` negative. The
contract turns a quiet wrong answer into a loud, early stop at the line
to fix.

## ensures: what a function promises

`ensures` is the other half: a condition that holds when the function
returns. It's checked at every `return` and at the end of the body.
Here `push` promises to add one item, and has a bug, a forgotten
`self.len += 1`:

```vole
struct Ring {
    items: Vec<i64>,
    start: i64,
    len: i64,
}

impl Ring {
    fn new(cap: i64, gpa: Gpa) -> Ring {
        Ring { items: Vec::filled_in(cap, 0, gpa), start: 0, len: 0 }
    }

    fn push(inout self, x: i64)
        requires self.len < self.items.len() else "push on a full ring"
        ensures self.len == old(self.len) + 1
    {
        let end = (self.start + self.len) % self.items.len();
        self.items[end] = x;
    }
}

fn main(gpa: Gpa) {
    var r = Ring::new(4, gpa);
    r.push(7);
    println("pushed");
}
```

```out exit=101
main.vl:14:9: ensures failed: 'self.len == old(self.len) + 1' of 'Ring::push': self.len = 0
```

This time the position is the clause in `push`: a broken promise is
the function's fault, not the caller's. Two words are special in an
ensures:

- `old(e)` is the value `e` had when the function was called, here the
  length before the push;
- `result` is the value the function returns.

```vole
// Slot i of a ring of cap slots, for i up to two laps around.
fn wrap(i: i64, cap: i64) -> i64
    requires cap > 0 && 0 <= i && i < 2 * cap
    ensures 0 <= result && result < cap
{
    if i >= cap { i - cap } else { i }
}

fn main() {
    println(f"{wrap(4, 3)} {wrap(2, 3)}");
}
```

```out
1 2
```

### What a condition may do

A condition reads the parameters, `result`, `old(...)` and constants,
and it can call functions. Those functions must be pure (chapter 12):
a check that passes must not change what the program does.

```vole
fn checked(v: [i64]) -> bool {
    println(f"checking {v.len()} items");
    v.len() > 0
}

fn first(v: [i64]) -> i64
    requires checked(v)
{
    v[0]
}

fn main() {
    let v = [1, 2, 3];
    println(f"{first(v)}");
}
```

```err
error[contract.effect]: the 'requires' of 'first' calls 'checked', which does io: a condition may not do io, allocate or touch statics
 --> main.vl: line 7, column 14
  = help: a check that passes must not change what the program does: compute the value in the body, or check it with assert there
  = try: volec query effects checked --why io main.vl
```

### Assertions

Inside a body, `assert(cond)`, `assert(cond, "message")`, `assert_eq(a,
b)` and `assert_ne(a, b)` check a condition at that point, and fail the
same way: one line with the position, the condition or message, and the
values, then exit 101. You'll use them in tests in a moment.

> **If you know Eiffel, Ada/SPARK or Dafny:** these are run-time
> checks, not proofs. The compiler doesn't try to prove a contract
> holds; it checks it, and uses what a passed check establishes (next
> section).

## Contracts and speed

Contracts are checked in every build. There is no "release mode" that
turns them off, for the same reason bounds checks stay on: a program
that skips its checks in production is where the bugs end up.

They are not just a cost, though. Once a check has passed, the
optimizer knows the condition holds, and it can drop later checks that
it implies. Save this as `checks.vl`:

```vole checks.vl
use std::env;

#[inline(never)]
fn at(v: Vec<i64>, i: i64) -> i64 {
    v[i]
}

#[inline(never)]
fn at_checked(v: Vec<i64>, i: i64) -> i64
    requires 0 <= i && i < v.len()
{
    v[i]
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..10 {
        v.push(i * i);
    }
    let i = env::args().count();
    println(f"{at(v, i)} {at_checked(v, i)}");
}
```

`volec query checks` lists the run-time checks left in a function after
optimization, and the ones the optimizer removed:

```console
$ volec query checks at checks.vl
checks.vl:5:5	at	index	left
checks: 1 left, 0 removed
$ volec query checks at_checked checks.vl
checks.vl:12:5	at_checked	index	removed (ranges)
checks: 0 left, 1 removed
```

`at` keeps the bounds check on `v[i]`. In `at_checked`, every call has
already checked `i < v.len()` before entering, so the index check is
gone: the contract costs one check at the call, and the body runs
without any. (A small function like this is usually inlined into its
caller, where the same reasoning applies; `#[inline(never)]` keeps it
separate so we can see it.)

Nothing is assumed: a fact comes only from a check that ran. And
integers wrap around in vole, so a condition may not mean what it looks
like. `i + 1 < v.len()` is true for an `i` near the largest `i64`,
where `i + 1` wraps to a negative number, so it doesn't prove that
`v[i + 1]` is in range, and that check stays. Write the condition about
the index you use.

## debug requires: the expensive checks

Some conditions cost more than the function they guard. A binary search
needs a sorted slice, but checking that takes longer than the search.
Put `debug` in front:

```vole search.vl
fn is_sorted(v: [i64]) -> bool {
    for i in 1..v.len() {
        if v[i - 1] > v[i] {
            return false;
        }
    }
    true
}

// Whether x is in v, which must be sorted.
fn contains(v: [i64], x: i64) -> bool
    debug requires is_sorted(v) else "contains needs a sorted slice"
{
    var lo = 0;
    var hi = v.len();
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if v[mid] == x {
            return true;
        } else if v[mid] < x {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    false
}

fn main() {
    let sorted = [1, 3, 5, 7];
    let shuffled = [7, 1, 5, 3];
    println(f"{contains(sorted, 7)} {contains(shuffled, 7)}");
}
```

A normal build doesn't check a `debug` clause, so the search on the
shuffled slice quietly gives a wrong answer. `volec test` builds with
debug clauses on, and so does `--debug-contracts`:

```console
$ volec search.vl -o search
ok: built search
$ ./search
true false
$ volec search.vl -o search --debug-contracts
ok: built search
$ ./search
search.vl:32:38: contains needs a sorted slice
```

`debug ensures` works the same way.

## Tests

Contracts check the cases your program happens to run. Tests choose the
cases. Here is the ring again, grown up: it has `is_full` and `get`,
the wrapping is done by one function, `wrap`, and below the code are
three tests. There's a bug in `wrap`. Can you see it?

```vole ring.vl
// ring: a queue of at most `cap` numbers, in memory allocated once.

struct Ring {
    items: Vec<i64>,
    start: i64,
    len: i64,
}

// Slot i of a ring of cap slots: past the end, it wraps to the front.
fn wrap(i: i64, cap: i64) -> i64 {
    if i > cap { i - cap } else { i }
}

impl Ring {
    fn new(cap: i64, gpa: Gpa) -> Ring
        requires cap > 0 else "a ring needs room for at least one item"
    {
        Ring { items: Vec::filled_in(cap, 0, gpa), start: 0, len: 0 }
    }

    fn cap(self) -> i64 {
        self.items.len()
    }

    fn is_full(self) -> bool {
        self.len == self.cap()
    }

    fn push(inout self, x: i64)
        requires !self.is_full() else "push on a full ring"
        ensures self.len == old(self.len) + 1
    {
        let end = wrap(self.start + self.len, self.cap());
        self.items[end] = x;
        self.len += 1;
    }

    fn pop(inout self) -> i64
        requires self.len > 0 else "pop on an empty ring"
        ensures self.len == old(self.len) - 1
    {
        let x = self.items[self.start];
        self.start = wrap(self.start + 1, self.cap());
        self.len -= 1;
        x
    }

    fn get(self, i: i64) -> i64
        requires 0 <= i && i < self.len else f"no item {i} in a ring of {self.len}"
    {
        self.items[wrap(self.start + i, self.cap())]
    }
}

#[test]
fn first_in_first_out(gpa: Gpa) {
    var r = Ring::new(3, gpa);
    r.push(1);
    r.push(2);
    assert_eq(r.pop(), 1);
    assert_eq(r.pop(), 2);
}

#[test]
fn wraps_around(gpa: Gpa) {
    var r = Ring::new(2, gpa);
    r.push(1);
    r.push(2);
    assert_eq(r.pop(), 1);
    r.push(3);
    assert_eq(r.get(0), 2);
    assert_eq(r.get(1), 3);
}

#[property]
fn pop_gives_back_what_push_put(xs: Vec<i64>, gpa: Gpa) {
    for cap in 1..5 {
        var r = Ring::new(cap, gpa);
        var next = 0;
        for x in xs {
            if r.is_full() {
                assert_eq(r.pop(), xs[next]);
                next += 1;
            }
            r.push(x);
        }
    }
}

fn main(gpa: Gpa) {
    var r = Ring::new(3, gpa);
    for x in [10, 20, 30] {
        r.push(x);
    }
    println(f"{r.pop()} {r.get(0)} {r.get(1)}");
    r.push(40);
    println(f"{r.get(0)} {r.get(1)} {r.get(2)}");
}
```

A *test* is a function marked `#[test]`. It lives next to the code it
tests, takes nothing or `gpa: Gpa`, and fails if it panics: an
`assert_eq` that doesn't hold, a contract, an index out of bounds. (It
may also return a `Result`, and then an `Err` fails it.) A normal build
leaves the tests out, so they cost the program nothing.

The third function is a *property*, which we'll come to in a moment.

### volec test

```console
$ volec test ring.vl
test ring.vl: 1 passed, 2 failed (2 #[test], 1 #[property]; -O0 and -O2 agree)
FAIL wraps_around: ring.vl:34:9: index out of bounds: index 2, length 2
  trace: ring.vl:34 Ring::push$body < ring.vl:29 Ring::push < ring.vl:70 wraps_around
FAIL pop_gives_back_what_push_put (property, case 5 of 100, shrunk in 226 steps): ring.vl:34:9: index out of bounds: index 1, length 1
  trace: ring.vl:34 Ring::push$body < ring.vl:29 Ring::push < ring.vl:85 pop_gives_back_what_push_put
  input: xs = [0, 0]
  try: volec test pop_gives_back_what_push_put --seed 0xd098fbd5a16acb77 ring.vl
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
```

The first line is the summary: what ran and how it went. `volec test`
builds the tests twice, without optimization (`-O0`) and with it
(`-O2`), and runs both; "agree" means they behaved the same. If they
ever don't, it says `DIFF`, and that's a bug in the compiler rather
than in your code.

Then one block per failure. `first_in_first_out` passed, but
`wraps_around` failed in `push`, at `self.items[end] = x`: index 2 in a
ring of length 2. The `trace:` line is the chain of calls that led
there, innermost first: `push` (the `$body` part is the function's body
inside its contract checks) called from line 70 of the test.

Now the bug is easy to see. When `start + len` is exactly `cap`, it
should wrap to 0, but `wrap` only wraps when `i > cap`. Fix the `>` in
your editor, or let the compiler do it:

```console
$ volec edit patch wrap --old 'i > cap' --new 'i >= cap' ring.vl
patched crate::wrap	ring.vl	+1 -1 lines
$ volec test ring.vl
test ring.vl: 3 passed (2 #[test], 1 #[property]; -O0 and -O2 agree)
```

`volec test wraps` runs only the tests whose names contain `wraps`.
Tests are built with `--check-alloc`, so a test that leaves memory
allocated fails too, with the line that allocated it.

> **If you know Rust:** `#[test]` is what you know, and properties and
> fuzzing are built in, like proptest and cargo-fuzz would be. One
> difference: contracts and asserts are checked in optimized builds
> too.

## Properties: a hundred inputs for free

Look at the property again:

```vole skip
#[property]
fn pop_gives_back_what_push_put(xs: Vec<i64>, gpa: Gpa) {
    for cap in 1..5 {
        var r = Ring::new(cap, gpa);
        var next = 0;
        for x in xs {
            if r.is_full() {
                assert_eq(r.pop(), xs[next]);
                next += 1;
            }
            r.push(x);
        }
    }
}
```

A test checks one case you thought of. A *property* states something
that should be true for every input, and `volec test` makes up the
inputs: 100 cases, generated from the parameters' types, starting small
and growing. This one says: push the numbers `xs` through rings of
capacity 1 to 4, popping whenever the ring is full, and what comes out
is what went in, in order.

When a case fails, the input that failed is usually big and messy, so
`volec test` *shrinks* it: it tries smaller and simpler inputs while
the property still fails. Above, the failing case was the fifth, and
after 226 steps of shrinking it came down to `xs = [0, 0]`: two pushes
into a ring of capacity 1. That's about the smallest case there is,
which makes it the easiest to debug.

The `try:` line replays exactly that run, with the same seed, so you
can check your fix against the case that failed.

Numbers, `bool`, `String`, `Vec`, slices, `Option`, `Result`, tuples
and your own structs and enums can all be generated. For a type that
needs special values, `impl std::Arbitrary` gives it a generator of its
own (`volec guide testing` shows how).

A property may take `gpa: Gpa`, as a test can. That parameter is the
test's allocator, not a generated input, so it isn't shown among the
inputs when a case fails.

A function with an `ensures` gets tested as a property even if you
don't write one: `volec test` generates its arguments, keeps the ones
its `requires` accept, and checks the promise. The summary counts these
as `contract`.

## Testing a whole program

The last kind of test runs the program itself. Next to the program,
make a `tests` directory with a file of input, `NAME.in`, and the
output you expect, `NAME.out`. The ring's `main` reads nothing and
prints two lines, so its input is empty:

```console
$ mkdir tests
$ printf '' > tests/demo.in
$ volec test ring.vl
test ring.vl: 3 passed, 1 failed (1 case, 2 #[test], 1 #[property]; -O0 and -O2 agree)
FAIL demo: no tests/demo.out to compare with; it printed 2 lines (--accept writes it)
  + 10 20 30
  + 20 30 40
(outputs: .volec/test/O2/case-NAME.got, .err; test-NAME.got, .err)
$ volec test --accept ring.vl
test ring.vl: 4 passed (1 case, 2 #[test], 1 #[property]; -O0 and -O2 agree)
```

The first run says what the program printed and that there's nothing
to compare it with yet. If the output is right, `--accept` saves it as
`tests/demo.out`, and from then on any change to what the program
prints fails the case, with the first line that differs.

`assert_snapshot(x)` does the same for a value inside a test: the first
run saves `x`'s debug form under `tests/snapshots/`, and later runs
compare against it. Tests that are only for test builds can also go in
a module of their own, `#[cfg(test)] mod tests;`, which normal builds
leave out.

## Fuzzing: hunting for crashes

A property checks that something is true. Sometimes you only want to
know that a function never crashes, whatever it's given. That's what
*fuzzing* is for, and it's at its best on code that reads input. Here
is a parser for commands a user might type at a ring, `push 5`, `pop`
and `get 0`, in a file of its own, `commands.vl`:

```vole commands.vl
// The commands of a ring: `push N`, `pop`, `get N`.

enum Command {
    Push(i64),
    Pop,
    Get(i64),
}

fn parse_command(line: str) -> Option<Command> {
    if line == "pop" {
        return Some(Command::Pop);
    }
    if line.starts_with("push ") {
        let n = line[5..].parse::<i64>().ok()?;
        return Some(Command::Push(n));
    }
    if line.starts_with("get") {
        let n = line[4..].parse::<i64>().ok()?;
        return Some(Command::Get(n));
    }
    None
}

#[fuzz]
fn parse_never_crashes(data: [u8]) {
    match str::from_utf8(data) {
        Ok(line) => {
            let _ = parse_command(line);
        }
        Err(_) => {}
    }
}

fn main() {
    match parse_command("push 42") {
        Some(Command::Push(n)) => println(f"push {n}"),
        _ => println("something else"),
    }
}
```

A `#[fuzz]` target takes bytes, any bytes, and here it hands the ones
that are text to the parser. `volec fuzz` runs it over and over,
changing the input a little each time and keeping the inputs that
reach code no earlier input reached:

```console
$ volec fuzz parse_never_crashes commands.vl --time 10
...
```

The inputs are made up as it goes, so every run is different. Here is
one:

```text
FAIL parse_never_crashes (fuzz, after 685 runs, shrunk in 0 steps): commands.vl:18:17: slice range out of bounds: 4..3, length 3
  input: data = "get"
  saved: .volec/fuzz/parse_never_crashes/crash-d4e26318faaa79f7 (volec test replays it; test --accept keeps it in tests/fuzz/parse_never_crashes/)
  try: volec test parse_never_crashes commands.vl
```

`--time 10` would let it search for ten seconds; this run found a
crash in less than one. The input `get`, with no space and no number, passes
`starts_with("get")`, and then `line[4..]` asks for text past the end of
a three-byte line. (`push` is fine: it checks for the space.)

The crashing input is saved, and every later `volec test` runs it
again, so once you fix the bug it stays fixed. `volec test --accept`
moves saved inputs into `tests/fuzz/`, which you keep with your code.

## When a test can't be a test

One mistake is common enough to show. A test that wants an argument:

```vole doubles.vl
fn double(x: i64) -> i64 {
    x * 2
}

#[test]
fn doubles(x: i64) {
    assert_eq(double(x), x + x);
}

fn main() {
    println(f"{double(21)}");
}
```

```console
$ volec test --full doubles.vl
test doubles.vl: its tests do not build (1 error)
doubles.vl:6:4: error[test.signature] 'doubles' is a #[test] with parameters: a #[test] takes nothing or `gpa: Gpa` | help: a function of generated arguments is a #[property]
```

A test has no one to give it an `x`. The help says what was meant: a
function whose arguments are generated is a `#[property]`. (`--full`
prints every message whole; without it, `volec test` cuts long ones to
keep the summary short.)

## Summary

- `requires` states what a function needs; it's checked at each call,
  and a failure names the caller's line. `ensures` states what it
  promises, with `result` and `old(...)`; a failure names the function.
- Conditions must be pure. They are checked in every build, and the
  optimizer uses the facts they establish; `volec query checks` shows
  which checks are left.
- `debug requires` and `debug ensures` are for expensive checks, run by
  `volec test` and `--debug-contracts`.
- `#[test]` functions check cases you choose; `#[property]` functions
  check a claim on generated, shrunk inputs; `#[fuzz]` targets look for
  crashes; `tests/NAME.in` and `NAME.out` check the whole program.
- `volec test` runs them all at two optimization levels, and its `try:`
  lines replay a failure.

So far, everything has happened one step at a time. The next chapter
runs code on several threads at once, and shows what the compiler
checks so that they can't trip over each other.

## Try it yourself

- Add `fn peek(self) -> i64` to the ring, returning the oldest item
  without removing it. Give it a `requires`, and an `ensures` that says
  it's what `get(0)` returns.
- Write a property that checks `len` never goes above `cap`, whatever
  sequence of pushes and pops you do. (Hint: generate a `Vec<bool>`, and
  push on `true`, pop on `false`, when allowed.)
- Fix `parse_command` so `get` needs its space too, then run `volec
  fuzz` again for a few seconds. Does it find anything else?
