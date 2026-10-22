# 10. Closures and iterators

A *closure* is a function you write right where you need it, which can
use the variables around it. You've already passed a few: `|x| x % 2
== 1` to `retain` in chapter 7, and a comparison to `sort_by`. This
chapter explains them properly, then puts them to work with
*iterators*, vole's way of processing a sequence of values step by step:
filter these, transform those, add them up.

By the end you'll be able to write closures and pass them to your own
generic functions, say exactly what a closure captures, process data
with chains like `filter(...).map(...).sum()`, and write an iterator of
your own. The running example is a small log analyzer.

## Closures

```vole
fn main() {
    let k = 10;
    let add_k = |x: i64| x + k;
    println(add_k(1));
    println(add_k(32));

    let check = |x: i64| -> bool {
        if x < 0 {
            return false;
        }
        x % 2 == 0
    };
    println(f"{check(-2)} {check(4)} {check(3)}");
}
```

```out
11
42
false true false
```

A closure is written with its parameters between bars, `|x: i64|`,
followed by its body. `add_k` uses `k`, a variable from the function
around it: it *captures* `k`. You call a closure like a function.

The body can be one expression, as in `add_k`, or a block. With a
block you can also write the result type, `-> bool`. `return` inside a
closure returns from the closure, not from the function around it.

### Parameter types

A closure kept in a `let`, as here, needs its parameter types written
out. Leave one off, and the compiler asks for it:

```vole
fn main() {
    let double = |x| x * 2;
    println(double(4));
}
```

```err
error[type error]: cannot infer the type of closure parameter 'x'
 --> main.vl: line 2, column 19
  = help: write its type: '|x: i64| ...'
```

Where a closure is passed straight to a function, the function's
signature says what the parameters are, so you can leave the types
off. That's why `v.retain(|x| x % 2 == 1)` didn't need one: `retain`
on a `Vec<i64>` says it passes an `i64`.

## What a closure captures

When a closure uses a variable from outside, it doesn't get a copy. It
uses the variable itself, in place, the way an `inout` or a `let`
parameter does (chapter 4). And like a parameter, it holds an *access*
to the variable: not just for one call, but from the moment the closure
is made until the last time it's used. What kind of access depends on
what the closure does with the variable:

| the closure | it holds | while the closure is still to be used |
|---|---|---|
| only reads the variable | a let access | the variable may be read, not changed |
| changes the variable | an inout access | nothing else may read or change it |
| is a `sink \|..\|` closure | its own copy, or the value moved in | nothing is shared at all |

After the closure's last use, the access is over, and the variable is
yours again.

### A closure that reads

```vole
fn main() {
    var limit = 10;
    let over = |x: i64| x > limit;
    println(f"{limit} {over(5)} {over(15)}");
    limit = 3;
    println(f"{limit}");
}
```

```out
10 false true
3
```

`over` only reads `limit`, so `main` can read it too, even in the same
line as the calls. Changing it is fine as well, once `over` won't be
called again. What isn't allowed is changing `limit` while `over` is
still to be used: the closure would see a value change under it.

```vole
fn main() {
    var limit = 10;
    let over = |x: i64| x > limit;
    println(over(5));
    limit = 3;
    println(over(5));
}
```

```err
error[own.conflict]: 'limit = 3' writes 'limit' while 'over' (main.vl: line 3, column 9) views it; 'over' is used at main.vl: line 6, column 13
 --> main.vl: line 5, column 5
  = help: a closure holds what it captures until its last call: move this after that call, or pass the value to the closure as a parameter instead of capturing it
  = try: volec query own main.vl:6:13
```

The message calls the closure a *view* of `limit`, as a slice is a view
of a Vec: it reads something that lives somewhere else. The help gives
the fixes: change `limit` after the closure's last call, or pass the
limit to the closure as a parameter instead of capturing it. If `over`
should keep the old limit, give it its own copy with `sink` (below).

### A closure that changes

```vole
fn main() {
    var count = 0;
    let bump = || {
        count += 1;
    };
    bump();
    bump();
    println(count);
}
```

```out
2
```

`bump` changes `count`, the real one, and `main` sees the result. A
closure that changes a variable is the only way to that variable while
it is still to be used, as an `inout` parameter is during a call. So
`main` can't even read `count` between the two calls:

```vole
fn main() {
    var count = 0;
    let bump = || {
        count += 1;
    };
    bump();
    println(count);
    bump();
}
```

```err
error[own.conflict]: 'count' is read while 'bump' (main.vl: line 3, column 9) has an inout access to it; 'bump' is used at main.vl: line 8, column 5
 --> main.vl: line 7, column 13
  = help: a closure holds what it captures until its last call: move this after that call, or pass the value to the closure as a parameter instead of capturing it
  = try: volec query own main.vl:8:5
```

The message says it the way this section does: `bump` has an inout
access to `count`, until its last use on line 8. The help gives the two
ways out: read `count` after `bump`'s last call, as the first version
did, or pass the value to the closure as a parameter instead of
capturing it. This is the
same rule as everywhere else in vole: while something may change a
value, nothing else looks at it, so nothing changes behind anyone's
back.

### sink closures

Sometimes you want the closure to have its own copy, taken when the
closure is made. Put `sink` in front:

```vole
fn main() {
    var n = 1;
    let snapshot = sink || n;
    n += 100;
    println(f"{snapshot()} {n}");
}
```

```out
1 101
```

`snapshot` copied `n` when it was made, so changing `n` afterwards is
fine, and doesn't reach the closure. For an owned value, `sink` moves
it into the closure: the variable can't be used after that, just as
after passing it to a `sink` parameter.

> **If you know Rust:** `sink ||` is `move ||`, and the compiler says
> so if you write `move`: `error[conv.rust]: 'move' is Rust's spelling;
> a closure that takes its captures is 'sink |..|'`, with a `try:` line
> that rewrites it. Closure parameters are plain names, `|x|`, never
> `|&x|`.

> **If you know Python or JavaScript:** a closure never sees a variable
> "change behind its back". While a closure that reads a variable is
> still to be used, nothing else changes it; while one that changes it
> is, nothing else even reads it.

## Fn, FnMut and fn

To write a function that takes a closure, give it a type parameter
bounded by `Fn` or `FnMut`:

```vole
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 {
    f(x)
}

fn repeat<F: FnMut(i64)>(n: i64, f: sink F) {
    for i in 0..n {
        f(i);
    }
}

fn main() {
    let k = 10;
    println(apply(|x| x + k, 1));
    println(apply(|x| x * 2, 21));

    var total = 0;
    repeat(4, |i| {
        total += i;
    });
    println(total);
}
```

```out
11
42
6
```

- `F: Fn(i64) -> i64` takes any closure that receives an `i64`, returns
  an `i64`, and doesn't change anything it captured.
- `F: FnMut(i64)` also accepts closures that change their captures,
  like the one adding to `total`. (A missing `-> ...` means it returns
  nothing.) To call it, `repeat` takes `f` as `sink`.

Every closure has a type of its own, with no name you can write. That's
why these functions are generic: `F` stands for whatever the closure's
type is. As with any generic function, the compiler makes a copy for
each closure, so the call `f(x)` is a direct call, usually inlined.

### Plain functions

A plain function is a value too, of a type like `fn(i64) -> i64`, and a
closure that captures nothing can be used as one:

```vole
fn twice(f: fn(i64) -> i64, x: i64) -> i64 {
    f(f(x))
}

fn add_one(x: i64) -> i64 {
    x + 1
}

fn main() {
    println(twice(add_one, 5));
    println(twice(|x| x * 3, 2));
}
```

```out
7
18
```

A closure that does capture something can't be a plain function: a
plain function is just an address, with nowhere to keep the captured
values:

```vole
fn twice(f: fn(i64) -> i64, x: i64) -> i64 {
    f(f(x))
}

fn main() {
    let k = 3;
    println(twice(|x| x + k, 1));
}
```

```err
error[type error]: a closure that captures variables cannot be a 'fn(i64) -> i64' (it captures 'k')
 --> main.vl: line 7, column 19
  = help: make the parameter generic: `fn apply<F: Fn(i64) -> i64>(f: F)`
```

The `help:` line is the fix: make `twice` generic, `fn twice<F: Fn(i64)
-> i64>(f: F, x: i64)`, and it takes both kinds.

A struct can hold a closure in a field whose type is a type parameter:
`struct Button<F> { label: str, on_click: F }`, called as
`(b.on_click)(3)`.

What isn't there yet: there is no `FnOnce`, and a function can't return
a closure, because there is no way to write its type.

## Iterators

An *iterator* is a value that produces a sequence of values, one each
time you ask. Many things give you one:

- `v.iter()` on a `Vec` or a slice: each element in turn;
- a range used as a value, `(0..n)`: the numbers from 0 up to `n`;
- `m.iter()`, `m.keys()` and `m.values()` on a `HashMap`;
- `s.split(',')`, `s.lines()`, `s.chars()` on text, from chapter 7.

The items of `v.iter()`, and of a map's `iter`, `keys` and `values`,
are the container's own elements, read in place, as `for x in v` reads
them. To keep an owned one, a `String` say, take a copy with
`.clone()`, as chapter 7's `sorted_counts` did with the map's words.

On its own, an iterator does nothing. *Adapters* such as `map` and
`filter` wrap it in a new iterator that changes the values or skips
some; *consumers* such as `sum` and `count` run the whole thing and give
you a result:

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 1..7 {
        v.push(i);
    }
    let even_squares = v.iter().filter(|x| x % 2 == 0).map(|x| x * x).sum();
    let big = v.iter().filter(|x| x > 2).count();
    println(f"{even_squares} {big} {v.iter().max():?}");

    let tenfold: Vec<i64> = v.iter().map(|x| x * 10).collect_in(gpa);
    println(f"{tenfold:?}");
}
```

```out
56 4 Some(6)
[10, 20, 30, 40, 50, 60]
```

Read the first chain from left to right: take the elements of `v`, keep
the even ones, square each, add them up: 4 + 16 + 36 = 56.
`collect_in(gpa)` gathers the values into a new `Vec`, and since that
allocates, it takes the allocator (chapter 8).

### Lazy until consumed

Adapters don't do any work when you call them. Nothing happens until
something asks for values:

```vole
fn main() {
    let tens = (1..4).map(|x| {
        println(f"  making {x * 10}");
        x * 10
    });
    println("nothing made yet");
    for t in tens {
        println(f"got {t}");
    }
}
```

```out
nothing made yet
  making 10
got 10
  making 20
got 20
  making 30
got 30
```

`tens` is an iterator, not a list: each value is made when the `for`
loop asks for it, and the closure runs once per value. A `for` loop
works on any iterator, and so does every adapter.

### The adapters and consumers

Here are the ones std has, by example:

```vole
fn main() {
    let words: [str; 3] = ["ant", "bee", "cat"];
    for (i, w) in words.iter().enumerate() {
        print(f"{i}:{w} ");
    }
    println("");

    let dot = (1..4).zip(10..13).map(|(a, b)| a * b).sum();
    let product = (1..6).fold(1, |acc, x| acc * x);
    let first_three: i64 = (1..100).take(3).sum();
    println(f"{dot} {product} {first_three}");

    println(f"{(1..20).find(|x| x * x > 50):?} {(1..20).position(|x| x == 5):?}");
    println(f"{(1..5).any(|x| x > 3)} {(1..5).all(|x| x > 3)} {(1..5).min():?}");
}
```

```out
0:ant 1:bee 2:cat 
68 120 6
Some(8) Some(4)
true false Some(1)
```

- `enumerate()` pairs each value with its index; `zip(other)` pairs it
  with the next value of another iterator, stopping when either runs
  out. A pair comes as a tuple, which the closure can take apart:
  `|(a, b)|`.
- `take(n)` stops after `n` values.
- `fold(start, |acc, x| ...)` carries a value through the sequence:
  here, a running product.
- `find` gives the first value that passes a test, and `position` its
  index; both return an `Option`.
- `any` and `all` ask whether some, or every, value passes a test.
- `min`, `max`, `sum` and `count` do what they say. `min` and `max`
  return an `Option`, since the sequence may be empty.

A consumer takes the iterator for good (`sink self`, chapter 4) and
uses it up, so a chain is one value from start to end. `find`,
`position`, `any` and `all` are different: they stop at the value that
decides the answer, and change the iterator rather than take it
(`inout self`), so the rest of its values are still there. To go on
with them, keep the iterator in a `var`, as `parse` below does for
`next`.

> **If you know Rust:** these are Rust's names. `collect_in(gpa)` makes
> a `Vec` and nothing else; there's no `collect::<HashSet<_>>()`.

## A log analyzer

Let's use all of this on something real: a web server's log, one
request per line, with the status code, the method, the path, the size
of the reply in bytes, and the time it took in milliseconds. Save this
as `logs.vl`:

```vole logs.vl
struct Request {
    status: i64,
    path: str,
    bytes: i64,
    ms: i64,
}

// "200 GET /index.html 512 31" is a Request; anything else is None.
fn parse(line: str) -> Option<Request> {
    var fields = line.split_whitespace();
    let status = fields.next()?.parse::<i64>().ok()?;
    let _method = fields.next()?;
    let path = fields.next()?;
    let bytes = fields.next()?.parse::<i64>().ok()?;
    let ms = fields.next()?.parse::<i64>().ok()?;
    Some(Request { status, path, bytes, ms })
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = str::from_utf8(input.as_slice()).unwrap();
    var reqs: Vec<Request> = Vec::new_in(gpa);
    for line in text.lines() {
        match parse(line) {
            Some(r) => reqs.push(r),
            None => println(f"skipped: {line}"),
        }
    }

    let ok_bytes = reqs.iter().filter(|r| r.status < 400).map(|r| r.bytes).sum();
    let failed = reqs.iter().filter(|r| r.status >= 400).count();
    println(f"{reqs.len()} requests, {failed} failed, {ok_bytes} bytes served");

    var by_status: HashMap<i64, i64> = HashMap::new_in(gpa);
    reqs.iter().for_each(|r| {
        by_status.get_or_insert(r.status, 0)[0] += 1;
    });
    var codes: Vec<i64> = by_status.keys().collect_in(gpa);
    codes.sort();
    for code in codes {
        println(f"  {code}: {by_status.get(code).unwrap()}");
    }

    match reqs.iter().map(|r| (r.ms, r.path)).max() {
        Some((ms, path)) => println(f"slowest: {path} ({ms} ms)"),
        None => println("no requests"),
    }

    var broken: Vec<str> = reqs.iter().filter(|r| r.status >= 400).map(|r| r.path).collect_in(gpa);
    broken.sort_by(|a, b| a.cmp(b));
    println(f"failed paths: {broken:?}");
}
```

```in
200 GET /index.html 512 31
404 GET /missing 0 4
200 GET /about.html 1024 18
oops
500 POST /login 0 250
200 GET /index.html 512 29
404 GET /favicon.ico 0 3
```

```out
skipped: oops
6 requests, 3 failed, 2048 bytes served
  200: 3
  404: 2
  500: 1
slowest: /login (250 ms)
failed paths: ["/favicon.ico", "/login", "/missing"]
```

Let's go through it.

`parse` calls `next()` on the iterator of fields itself, one field at a
time. `next` changes the iterator (it moves it along), so `fields` is a
`var`. Each `?` returns `None` from `parse` as soon as a field is
missing or isn't a number (chapter 6), so `oops` is skipped.

The two totals are one chain each: keep the successful requests and add
up their bytes; keep the failed ones and count them.

`for_each` runs a closure on every value. This one changes `by_status`,
a `var` it captured, so it counts each status code. A map's order is
unspecified, so we collect its keys into a Vec and sort them before
printing.

To find the slowest request, `map` turns each one into a pair `(ms,
path)`, and `max` finds the largest pair. Tuples compare by their first
element, then the second, so the largest pair is the one with the
biggest time.

The last chain collects the failed paths into a `Vec<str>`. These are
views of the input text, so nothing is copied. `sort_by` sorts them with
the comparison we give it, here the paths' own `cmp`.

## Writing an iterator

Any type can be an iterator: it needs an `impl Iterator` with one
function, `next`, which returns the next value, or `None` at the end.
Here is one that never ends, the Fibonacci numbers:

```vole
struct Fibonacci {
    a: i64,
    b: i64,
}

impl Iterator for Fibonacci {
    type Item = i64;

    fn next(inout self) -> Option<i64> {
        let n = self.a;
        self.a = self.b;
        self.b = n + self.b;
        Some(n)
    }
}

fn fibonacci() -> Fibonacci {
    Fibonacci { a: 0, b: 1 }
}

fn main(gpa: Gpa) {
    for n in fibonacci().take(10) {
        print(f"{n} ");
    }
    println("");
    let even_sum = fibonacci().take(30).filter(|n| n % 2 == 0).sum();
    let first_big = fibonacci().position(|n| n > 1000);
    let five: Vec<i64> = fibonacci().take(5).collect_in(gpa);
    println(f"{even_sum} {first_big:?} {five:?}");
}
```

```out
0 1 1 2 3 5 8 13 21 34 
257114 Some(17) [0, 1, 1, 2, 3]
```

`type Item = i64;` is the associated type from chapter 9: it says the
iterator produces `i64`s. `next` takes `inout self`, because producing a
value moves the state along.

That's all the impl has, and yet `take`, `filter`, `sum`, `position` and
`collect_in` all work on it. They are default functions of the
`Iterator` trait, written once in std in terms of `next`. Since
`Fibonacci` never returns `None`, it's an endless sequence, and the
`take(...)` and `position(...)` are what stop each chain.

## Chains cost nothing

Closures and adapters look like they might be slow: a function call per
value, a struct per adapter. They aren't. Every adapter is a small
generic struct, and every closure has its own type, so the compiler
makes a copy of `filter` and `map` for exactly these closures and
inlines them. With optimizations on, a chain compiles to the loop you
would write by hand.

You can check this yourself. Here is a program that runs a chain over
fifty million numbers, ten times. Build it with `-O2`, which turns the
optimizations on, and time it:

```vole sum_chain.vl
fn main(gpa: Gpa) {
    var xs: Vec<i64> = Vec::new_in(gpa);
    for i in 0..50000000 {
        xs.push(i % 1000);
    }
    var total = 0;
    for round in 0..10 {
        total += xs.iter().filter(|x| x % 2 == 0).map(|x| x * x + round).sum();
    }
    println(total);
}
```

```text
$ volec -O2 sum_chain.vl -o sum_chain && time ./sum_chain
83084625000000
real 3.68
```

And here is the same work written as a loop:

```vole sum_loop.vl
fn main(gpa: Gpa) {
    var xs: Vec<i64> = Vec::new_in(gpa);
    for i in 0..50000000 {
        xs.push(i % 1000);
    }
    var total = 0;
    for round in 0..10 {
        for x in xs {
            if x % 2 == 0 {
                total += x * x + round;
            }
        }
    }
    println(total);
}
```

```text
$ volec -O2 sum_loop.vl -o sum_loop && time ./sum_loop
83084625000000
real 3.98
```

These are one busy machine's numbers, and yours will differ, but the
two take the same time, give or take the noise of the machine.

Chapter 16 shows how to look at the machine code itself.

## What's not there yet

std's iterators cover the common cases, but some familiar ones are
missing for now: there is no `iter_mut` (change elements through an
index loop, as in chapter 7), and no `chain`, `flat_map`, `filter_map`,
`peekable`, `step_by` or `skip`. A `for` loop with an `if` inside does
the job of each. The list will shrink.

## Summary

- A closure, `|x: i64| x + k`, is a function written where it's used.
  Its parameter types come from where it's passed, or are written out.
- A closure uses what it captures in place, and holds an access to it
  from its creation to its last use: a let access if it only reads the
  variable (others may read it, not change it), an inout access if it
  changes it (nothing else may read or change it). After its last use,
  the variable is free again. A `sink ||` closure takes its own copies.
- Functions take closures through bounds, `F: Fn(i64) -> i64` or `F:
  FnMut(i64)`; a closure that captures nothing is also a plain `fn(i64)
  -> i64`.
- Iterators come from `iter()`, ranges, maps and text. Adapters (`map`,
  `filter`, `enumerate`, `zip`, `take`) are lazy; consumers (`sum`,
  `count`, `fold`, `min`, `max`, `any`, `all`, `find`, `position`,
  `for_each`, `collect_in`) run them.
- An `impl Iterator` with `type Item` and `next` gets every adapter for
  free.
- Chains compile to the loop you'd write by hand.

The next chapter takes the word counter from chapter 7 and splits it
into modules, then gives it files and command-line arguments.

## Try it yourself

- In `logs.vl`, print the average time of the successful requests, with
  one decimal. (`sum` and `count` give you the parts; `as f64` converts.)
- Write an iterator `Countdown { n: i64 }` that yields `n`, `n - 1`, ...
  down to 1, and print `Countdown { n: 5 }.map(|x| x * x).sum()`.
- Rewrite `trim_punct`'s two `while` loops from chapter 7 with
  `position` on `word.bytes()`. Which version do you find clearer?
