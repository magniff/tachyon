# 14. Threads

Your computer has several cores, and so far every program in this
book has used one of them. A *thread* is a sequence of steps that runs
at the same time as the program's other threads, each on a core of its
own when there are enough. In this chapter you'll start threads, give
them data to work on, collect their results, and share state between
them through a lock, an atomic counter and a channel.

Our running example is the simplest useful parallel job: adding up a
big list of numbers, by splitting it into pieces and giving each piece
to a thread.

## Why threads are hard, and what vole checks

Two threads that read the same memory are fine. Two threads where one
writes memory while the other reads or writes it, with nothing to
order them, are a *data race*: the result depends on timing, changes
from run to run, and can be garbage. Races are some of the hardest bugs
to find, because they rarely happen while you're looking.

Vole checks for them when you compile, at the place a thread starts,
by looking at what the new thread gets:

- an owned value, such as a `Vec`, may *move* into a thread, which then
  has it to itself;
- a view, such as a slice, may go only to a *scoped* thread, one that is
  guaranteed to finish before the data it views goes away;
- a scoped thread may read the caller's data, but not change it, unless
  the change goes through a lock or an atomic;
- a raw pointer never goes to another thread, and no thread but the
  main one may touch a `static var`.

Safe code that follows these rules can't have a data race. The rest of
the chapter shows each rule, and the error you get when you break it.

## spawn and join

`thread::spawn` starts a thread that runs a closure. Save this as
`spawn.vl`:

```vole spawn.vl
use std::thread;

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 1..=100 {
        v.push(i);
    }
    let h = thread::spawn(sink || {
        var total = 0;
        for x in v {
            total += x;
        }
        total
    });
    println("started a thread");
    let total = h.join();
    println(f"the thread says: {total}");
}
```

```out
started a thread
the thread says: 5050
```

`spawn` returns a *handle*, `h`, right away; the new thread runs on
its own while `main` carries on and prints its first line. `h.join()`
waits for the thread to finish and gives back the closure's result.

The closure is a `sink` closure: it takes what it uses. A spawned
thread may run longer than the function that started it, so it can't
borrow that function's variables, which might be gone by then. `v`
moves into the thread, and after the `spawn`, `main` can't use `v` any
more; the compiler says so if you try.

Views can't go to a spawned thread at all, even in a `sink` closure,
because the data they view stays behind:

```vole
use std::thread;

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..10 {
        v.push(i);
    }
    let xs = v.as_slice();
    let h = thread::spawn(sink || xs.len());
    println(f"{h.join()}");
}
```

```err
error[sync.borrow_escapes]: 'thread::spawn' moves 'xs' ([i64] is a view) to a thread that may outlive what it views
 --> main.vl: line 9, column 13
  = help: give the thread an owned copy (`.to_vec_in(gpa)`, a Buf), or start it in thread::scope, which ends before the data does
```

The help gives the two ways out: give the thread its own copy, or use a
scoped thread, which is the next section.

If any thread panics, the whole program stops, with the usual message
and exit status 101. That's why `join` gives the result directly, not a
`Result` to check: if the thread failed, `join` is never reached.

```vole
use std::thread;

fn main() {
    let h = thread::spawn(sink || {
        let v = [1, 2, 3];
        let i = 3;
        v[i]
    });
    println(f"{h.join()}");
    println("not reached");
}
```

```out exit=101
main.vl:7:9: index out of bounds: index 3, length 3
```

> **If you know Rust:** `sink ||` is `move ||`. There is no `Send` or
> `Sync` to write: the compiler works out from the types what may cross
> to another thread. `join` returns the value, not a `Result`, because
> a panic stops every thread.

## Scoped threads

Moving data into a thread works, but usually you want several threads
to read the same big piece of data. `thread::scope` makes that safe.
Save this as `sum.vl`:

```vole sum.vl
use std::thread;
use std::thread::ScopedJoinHandle;

fn sum(xs: [i64]) -> i64 {
    var total = 0;
    for x in xs {
        total += x;
    }
    total
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..1000000 {
        v.push(i % 1000);
    }
    let xs = v.as_slice();

    let half = xs.len() / 2;
    let total = thread::scope(|s| {
        let a = s.spawn(|| sum(xs[..half]));
        let b = s.spawn(|| sum(xs[half..]));
        a.join() + b.join()
    });
    println(f"two threads: {total}");

    let n = thread::available_parallelism();
    let chunk = (xs.len() + n - 1) / n;
    let total = thread::scope(|s| {
        var handles: Vec<ScopedJoinHandle<i64>> = Vec::new_in(gpa);
        for k in 0..n {
            let lo = k * chunk;
            let hi = if lo + chunk < xs.len() { lo + chunk } else { xs.len() };
            handles.push(s.spawn(sink || sum(xs[lo..hi])));
        }
        var t = 0;
        for h in handles {
            t += h.join();
        }
        t
    });
    println(f"one thread per core: {total}");
}
```

```out
two threads: 499500000
one thread per core: 499500000
```

`thread::scope` calls its closure with a *scope*, `s`, and threads
started with `s.spawn` belong to it. Before `scope` returns, it waits
for every one of them. So the threads can't outlive anything that
existed before the scope started, and they may borrow it: both threads
read `xs`, a view of `v`, with no copying.

The first part splits the numbers in two. The second asks
`thread::available_parallelism()` how many threads the machine can run
at once, and gives each a chunk. Its threads are `sink` closures: `lo`
and `hi` are made inside the loop and change on each trip, so each
thread takes its own copy of them. (`xs`, a view, is copied too, which
copies nothing but its position and length.)

While the threads run, the scope's own closure must not change what
they read. That's the other half of the bargain, and the compiler
checks it.

## Sharing changes: Mutex

Here is a tempting mistake. Let's count the primes among the numbers
with two threads, each adding to the same counter:

```vole shared.vl
use std::thread;

fn is_prime(n: i64) -> bool {
    if n < 2 {
        return false;
    }
    var d = 2;
    while d * d <= n {
        if n % d == 0 {
            return false;
        }
        d += 1;
    }
    true
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..100000 {
        v.push(i);
    }
    let xs = v.as_slice();
    let half = xs.len() / 2;
    var primes = 0;
    thread::scope(|s| {
        s.spawn(|| {
            for x in xs[..half] {
                if is_prime(x) {
                    primes += 1;
                }
            }
        });
        s.spawn(|| {
            for x in xs[half..] {
                if is_prime(x) {
                    primes += 1;
                }
            }
        });
    });
    println(f"primes: {primes}");
}
```

```err
error[sync.scope_shared_write]: a thread of 'thread::scope' changes 'primes', which the scope's other code may use at the same time
 --> shared.vl: line 29, column 21
  = help: scoped threads only read what they borrow (0.21.0): return the result from the thread (`h.join()`), or use a Mutex or an atomic
error[sync.scope_shared_write]: a thread of 'thread::scope' changes 'primes', which the scope's other code may use at the same time
 --> shared.vl: line 36, column 21
  = help: scoped threads only read what they borrow (0.21.0): return the result from the thread (`h.join()`), or use a Mutex or an atomic
```

`primes += 1` reads the counter, adds one, and writes it back. If both
threads do that at the same moment, they both read the same number and
one of the additions is lost. In a language that allows it, this
program prints a different wrong count on each run. Vole doesn't
compile it.

The help lists three fixes. The best is usually the first, the one
`sum.vl` already uses: each thread counts its own half, returns its
count, and `join` brings the counts together. Nothing is shared, so
nothing can race.

When threads really do need to change one value, put it in a
*mutex*, a lock that lets one thread at a time at the data inside. Or
use an *atomic*, a number whose operations can't be interrupted
halfway. Here are both, in `count.vl`:

```vole count.vl
use std::thread;
use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, Ordering};

fn is_prime(n: i64) -> bool {
    if n < 2 {
        return false;
    }
    var d = 2;
    while d * d <= n {
        if n % d == 0 {
            return false;
        }
        d += 1;
    }
    true
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..100000 {
        v.push(i);
    }
    let xs = v.as_slice();
    let half = xs.len() / 2;

    let primes = Mutex::new(0);
    thread::scope(|s| {
        s.spawn(|| {
            for x in xs[..half] {
                if is_prime(x) {
                    primes.with(|n| n += 1);
                }
            }
        });
        s.spawn(|| {
            for x in xs[half..] {
                if is_prime(x) {
                    primes.with(|n| n += 1);
                }
            }
        });
    });
    println(f"primes (mutex): {primes.with(|n| n)}");

    let count = AtomicI64::new(0);
    thread::scope(|s| {
        s.spawn(|| {
            for x in xs[..half] {
                if is_prime(x) {
                    count.fetch_add(1, Ordering::Relaxed);
                }
            }
        });
        s.spawn(|| {
            for x in xs[half..] {
                if is_prime(x) {
                    count.fetch_add(1, Ordering::Relaxed);
                }
            }
        });
    });
    println(f"primes (atomic): {count.load(Ordering::Relaxed)}");
}
```

```out
primes (mutex): 9592
primes (atomic): 9592
```

A `Mutex` owns its data: the `0` inside `primes` can only be reached
through it. `primes.with(|n| n += 1)` locks the mutex, runs the closure
with the data, and unlocks it again, so the read, the add and the write
happen while no other thread can get in. The closure's result is
`with`'s result, which is how `primes.with(|n| n)` reads the count at
the end. `try_with` is the same, but gives up at once, returning `None`,
if another thread holds the lock.

Both threads use `primes` without a `sink`: a scoped thread may borrow a
mutex, because the mutex does the ordering itself.

The scoped threads here return nothing, so we don't keep their handles.
The scope waits for them anyway.

> **If you know Rust:** there are no lock guards yet. `with` is the way
> to reach the data, and there's no poisoning: a panic stops the program
> rather than leaving a poisoned lock behind. That may change once
> guards are safe to expose. There's no `Arc` either, because scoped
> threads borrow the mutex directly.

## Atomics

The second half of `count.vl` uses an `AtomicI64` instead. `fetch_add`
adds to it as one indivisible step and returns the old value; `load`
reads it. `std::sync::atomic` has atomics for every integer type and
for `bool`, with the operations Rust and C++ have: `store`, `swap`,
`compare_exchange`, `fetch_sub`, `fetch_max` and so on.

Each operation takes an *ordering*, which says what else the operation
promises about memory around it:

- `Ordering::Relaxed` promises nothing beyond the atomic itself. That's
  right for a counter like this one, which nothing else depends on.
- `Ordering::Release` on a store and `Ordering::Acquire` on a load are
  for handing data over: everything one thread wrote before its release
  store is visible to a thread whose acquire load sees that store.
- `Ordering::SeqCst` is the strongest, one order of operations all
  threads agree on. When you're not sure, use it.

An atomic counter is cheaper than a mutex, but it only works for one
number. For anything bigger, or for several values that must change
together, use a mutex.

## Channels

Sometimes threads don't share data so much as pass it along: one
produces work, another consumes it. A *channel* is a queue for that. It
has a `Sender` end and a `Receiver` end, and values sent into one come
out of the other, in order.

Here's a small worker pool. Three threads hash the lines of the input,
each taking every third line, and send their results to the main
thread, which collects them. Save it as `hash.vl`:

```vole hash.vl
use std::thread;
use std::sync::mpsc;

// FNV-1a, a simple hash of a line's bytes.
fn hash(line: str) -> u64 {
    var h: u64 = 0xcbf29ce484222325;
    for b in line.bytes() {
        h = (h ^ b as u64) * 0x100000001b3;
    }
    h
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = String::from_buf(input).unwrap();
    let all: Vec<str> = text.lines().collect_in(gpa);
    let lines = all.as_slice();
    let workers = 3;

    var results = thread::scope(|s| {
        let (tx, rx) = mpsc::channel_in::<(i64, u64)>(gpa);
        for w in 0..workers {
            let tx = tx.clone();
            s.spawn(sink || {
                var i = w;
                while i < lines.len() {
                    tx.send((i, hash(lines[i]))).unwrap();
                    i += workers;
                }
            });
        }
        drop(tx);
        var got: Vec<(i64, u64)> = Vec::new_in(gpa);
        for r in rx.iter() {
            got.push(r);
        }
        got
    });
    results.sort();
    for (i, h) in results {
        println(f"{lines[i]:<8} {h:016x}");
    }
}
```

```in
apple
banana
cherry
date
elder
fig
grape
```

```out
apple    f74a62a458befdbf
banana   b4d3b6b1c372c890
cherry   52d2f6df6bced8f8
date     855b516730a34339
elder    828dd4aceeb21517
fig      dc9e8d18fec95535
grape    32ec8b2977fe3c70
```

`mpsc::channel_in(gpa)` makes a channel; it allocates its queue, so it
takes an allocator. ("mpsc" stands for "multiple producers, single
consumer": many senders, one receiver.) Each worker gets its own clone
of the sender, `tx.clone()`, and takes it with `sink`.

`for r in rx.iter()` receives until the channel is empty and every
sender is gone. A sender is gone when it's dropped, which for the
workers' clones happens when their threads finish. The original `tx`
would keep the channel open forever, so we drop it ourselves with
`drop(tx)` once the workers have their clones.

The results arrive in whatever order the threads happen to finish, so
each carries its line number, and we sort them before printing. That
keeps the output the same on every run, which is a good habit for any
threaded program: decide the order yourself instead of letting the
timing decide it.

`send` returns a `Result` because it fails, giving the value back, when
the receiver is gone. `recv()` waits for one value, and fails when every
sender is gone and nothing is left.

> **If you know Go:** threads here are operating-system threads, not
> goroutines, so start tens of them, not millions. Channels are much
> like Go's, typed and in order. There's no `close`: a channel closes
> when the last sender is dropped.

## Globals and thread-locals

A `static var` is a single variable shared by the whole program.
Threads would race on it, so only the main thread may use one:

```vole
use std::thread;

static var COUNT: i64 = 0;

fn bump() {
    COUNT += 1;
}

fn main() {
    let h = thread::spawn(sink || {
        bump();
        0
    });
    bump();
    println(f"{h.join()} {COUNT}");
}
```

```err
error[sync.global]: 'thread::spawn' runs a closure on another thread, but it reaches a static mut (its effects have `global`): a static mut is for the main thread
 --> main.vl: line 10, column 13
  = help: make the static an atomic or a Mutex without `mut` (`static N: AtomicI64 = AtomicI64 { v: 0 };`), a #[thread_local], or pass the data in | try: volec query effects main.vl:10 --why global
```

The compiler uses the closure's effects (chapter 12) to find this: the
closure calls `bump`, `bump` has the `global` effect, and that's
enough, however deep the call. (The message says "static mut", Rust's
name for what vole calls a `static var`.)

The help lists the fixes. A `static` atomic or mutex, without `var`,
can be shared, since it orders its own changes. Or the variable can be a
*thread-local*: each thread gets its own copy, which starts from the
initial value the first time that thread uses it:

```vole
use std::thread;

#[thread_local]
static var CALLS: i64 = 0;

fn work() -> i64 {
    for _ in 0..3 {
        CALLS += 1;
    }
    CALLS
}

fn main() {
    let h = thread::spawn(sink || work());
    CALLS = 100;
    println(f"the thread counted {h.join()}, main has {CALLS}");
}
```

```out
the thread counted 3, main has 100
```

The thread's `CALLS` and `main`'s are different variables, so there is
nothing to race on.

## Threads and effects

Threads add three effects to the six from chapter 12: `thread` for
starting one, `sync` for an atomic, a lock, a join or a channel, and
`tls` for a thread-local. Ask about the thread-local program:

```console
$ volec query effects crate main.vl
crate::work	tls
crate::main	alloc(extern) io global tls thread sync panic
```

`work` uses a thread-local, which is `tls`, not `global`. `main` starts
a thread and joins it. It's also `alloc(extern)`: starting a thread
allocates a little memory for it from the C library's allocator, which
the compiler reports like any other allocation. A `#[pure]` function
can do none of these things, so a pure function is also one you can
call from any thread.

## Raw pointers stay home

The last rule: a raw pointer (chapter 15) can't go to another thread,
because the compiler can't tell what it points to or who else is using
it:

```vole
use std::thread;

fn main() {
    var x = 5;
    let p: *i64 = &x;
    let h = thread::spawn(sink || unsafe { *p });
    println(f"{h.join()}");
}
```

```err
error[sync.not_send]: 'thread::spawn' moves 'p' (*i64 is a raw pointer) to another thread, which may alias memory this one still uses
 --> main.vl: line 6, column 13
  = help: hold the data in std's owned containers (Vec, Buf, HashMap), or share it in thread::scope, through a Mutex or an atomic
```

## Summary

- `thread::spawn(sink || ...)` starts a thread that owns what it uses;
  `join` waits for it and gives its result. A panic in any thread stops
  the program.
- `thread::scope(|s| ...)` starts threads with `s.spawn` that may
  borrow the caller's data, views included, because the scope waits for
  them all before it returns.
- Threads read shared data freely, but change it only through a `Mutex`
  (`with`) or an atomic; better still, each thread returns its own
  result.
- Channels (`mpsc::channel_in`) pass values from threads to a receiver,
  and close when every sender is dropped.
- The compiler checks all of this when a thread starts, with the
  `sync.*` errors: no views escaping into spawned threads, no shared
  writes, no `static var` and no raw pointers on another thread.

The next chapter goes where these checks can't follow: unsafe code,
raw pointers, and calling C.

## Try it yourself

- In `sum.vl`, make each thread return both the sum and the largest
  number in its chunk, as a tuple, and combine them after `join`.
- Change `hash.vl` to use one channel per worker instead of a shared
  one. Is it simpler or not?
- Make the word counter from chapter 11 count each file on its own
  thread, then merge the counts. (Each thread needs its own `HashMap`;
  merge them after `join`.)
