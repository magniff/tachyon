# Threads

Threads, atomics, locks and channels (0.21; the design is
docs/design/concurrency.md). Safe code cannot make a data race: what
crosses threads is checked where a thread starts, from the types (Rust's
`Send` and `Sync`, inferred) and the effects (no `static var` on another
thread). The errors are `sync.*` (`volec explain sync.global`).

## Atomics

`std::sync::atomic` has `Atomic<T>` for integers, `bool` and raw
pointers, with Rust's names as aliases (`AtomicI64`, `AtomicU32`,
`AtomicBool`, `AtomicPtr<T>`...) and Rust's methods: `load`, `store`,
`swap`, `compare_exchange` (`Ok(old)` or `Err(found)`), `fetch_add`,
`fetch_sub`, `fetch_and`, `fetch_or`, `fetch_xor`, `fetch_nand`,
`fetch_max`, `fetch_min`, `into_inner`, and `fence(order)`. The orderings
are C++'s (`Ordering::Relaxed`, `Acquire`, `Release`, `AcqRel`,
`SeqCst`); one an operation cannot have (a load with `Release`) is made
`SeqCst`. An atomic is move-only. A static one needs no `var` (and so has
no `global`): `static HITS: AtomicI64 = AtomicI64 { v: 0 };`.

```tach
use std::sync::atomic::{AtomicI64, Ordering};

fn main() {
    let n = AtomicI64::new(5);
    let old = n.fetch_add(3, Ordering::Relaxed);
    let r = n.compare_exchange(8, 10, Ordering::AcqRel, Ordering::Acquire);
    println(f"{old} {r.is_ok()} {n.load(Ordering::SeqCst)}");
}
```
```out
5 true 10
```

On AArch64 they are `ldar`/`stlr` and LSE's `ldadd`, `cas`, `swp`... on
macOS, exclusive-pair loops (`ldxr`/`stxr`) on Linux (`--atomics=lse` or
`--atomics=llsc` chooses). The optimizer moves no memory access across an
atomic or a fence, and invents no store to memory another thread may see.

## Threads

`std::thread::spawn(sink || ...)` runs the closure on a new thread; its
handle's `join()` waits and gives the result (a panic in any thread stops
the program, so there is no `Result` to unwrap). The closure is a `sink`
one: the thread may outlive the caller, so it takes owned values (a Vec
moves in), no views (`sync.borrow_escapes`) and no raw pointers
(`sync.not_send`). `thread::scope(|s| ...)` joins every thread started
with `s.spawn` before it returns, so those may use the caller's values
and views; while the scope runs its closure changes nothing they use
(`sync.scope_write`; a counter no thread uses is fine), and a scoped
thread only reads what it is given (`sync.scope_shared_write`, also for
`&v`, `&a[..]`, `v[i] = x` and `a.sort()`: return results through `join`,
or use a Mutex or an atomic; two threads cannot yet each write their own
part of one slice, there is no `split_at_mut`). Neither the scope nor a
scoped thread's handle leaves `thread::scope` (`sync.scope_escape`): join
inside and return the results. No thread may reach a `static var` (`sync.global`; `query
effects FILE:LINE --why global` shows the chain); printing is fine.

```tach
use std::thread;

fn sum(s: [i64]) -> i64 {
    var t = 0;
    for x in s { t += x; }
    t
}

fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for i in 0..1000 { v.push(i); }
    let s = v.as_slice();
    let total = thread::scope(|sc| {
        let a = sc.spawn(|| sum(s[0..500]));
        let b = sc.spawn(|| sum(s[500..]));
        a.join() + b.join()
    });
    let h = thread::spawn(sink || v.len());
    println(f"{total} {h.join()}");
}
```
```out
499500 1000
```

`thread::yield_now()`, `thread::available_parallelism()`. Printing is safe
from any thread: once threads run, each print holds a lock, so output
never interleaves.

## Mutex, Once, Condvar and channels

`std::sync::Mutex<T>` owns its data: `m.with(|data| ...)` locks, runs the
closure and unlocks (`try_with` when the lock is free now), the way to
reach the data in 0.21.0. The closure's result may not view the data,
nor may it store a view of it elsewhere (`own.escape`: the lock is
released when `with` returns): copy out what you need. Scoped threads share the Mutex (and an atomic). `m.lock()` gives a guard that unlocks when dropped, but it is
`unsafe` and internal until a type holding a view may implement Drop
(0.21.x): nothing keeps the guard inside the mutex's life yet. `Once`'s
`call_once(f)` runs f once whatever the threads; `Condvar`'s
`wait_then(m, ready, then)` sleeps until `ready(data)`, then runs `then`
under the lock (`notify_one`, `notify_all`). There is no poisoning.

`std::sync::mpsc::channel_in(gpa)` gives a `Sender` (clone it for more
senders) and a `Receiver`: `send(x)` fails, giving `x` back, when the
receiver is gone; `recv()` waits, and fails when every sender is gone and
nothing is left; `for x in rx.iter()` runs until then. What a channel
carries, a Mutex holds and `with`'s closure returns is no view
(`sync.view_item`): it comes out elsewhere, later, maybe after what it
views is gone; send an owned copy (`s.to_vec_in(gpa)`,
`s.to_string_in(gpa)`).

```tach
use std::thread;
use std::sync::{Mutex, mpsc};

fn main(gpa: Gpa) {
    let count = Mutex::new(0);
    let total = thread::scope(|s| {
        let (tx, rx) = mpsc::channel_in::<i64>(gpa);
        s.spawn(sink || {
            for i in 1..=10 { tx.send(i).unwrap(); }
            0
        });
        s.spawn(|| {
            for _ in 0..10 { count.with(|n| n += 1); }
            0
        });
        var sum = 0;
        for x in rx.iter() { sum += x; }
        sum
    });
    println(f"{total} {count.with(|n| n)}");
}
```
```out
55 10
```

The locks wait on a futex (Linux) or `__ulock` (macOS).

## Thread-locals

`#[thread_local] static var X: T = INIT;` gives each thread its own `X`,
made from `INIT` when the thread first uses it. Using one is safe; its
effect is `tls`, not `global`. A thread-local's drop does not run.

```tach
use std::thread;

#[thread_local]
static var CALLS: i64 = 0;

fn work() -> i64 {
    for _ in 0..3 { CALLS += 1; }
    CALLS
}

fn main() {
    let h = thread::spawn(sink || work());
    CALLS = 100;
    println(f"{h.join()} {CALLS}");
}
```
```out
3 100
```

## Effects

Three effects (0.21): `sync` (an atomic, a fence, a lock, a join, a
channel), `thread` (starting a thread) and `tls` (a thread-local).
`query effects f` shows them; `#[pure]` excludes them.
