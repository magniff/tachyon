# 14. Threads

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

Run code in parallel without data races. By the end the reader can:

- start a thread with `thread::spawn(sink || ...)` and get its result
  with `join()`;
- use `thread::scope` to run threads that read the caller's data, and
  explain why scoped threads may use views and spawned ones may not;
- share changing state through a `Mutex` (`m.with(|data| ...)`) or an
  atomic, and pass messages through a channel;
- read the `sync.*` errors the compiler gives when a program could race;
- use a thread-local.

## Running example

Summing and counting over a large Vec in parallel: first with two
scoped threads splitting a slice, then N threads from
`thread::available_parallelism()`, then a producer/consumer over an
`mpsc` channel (a "worker pool" that hashes lines), and a shared
`Mutex<i64>` counter. Outputs must be deterministic: print totals, not
interleavings.

## Sections

1. **Why threads are hard, and what vole checks.** A data race in two
   sentences. vole checks, where a thread starts, what crosses into it:
   owned values may move in, views only into scoped threads, raw
   pointers never; no thread may touch a `static var`.
2. **spawn and join.** `sink` closures (they take what they capture,
   because the thread may outlive the caller). A panic in any thread
   stops the program.
3. **Scoped threads.** `thread::scope(|s| { s.spawn(|| ...) })` joins
   them all before returning, so they may read the caller's data. While
   they run, the caller's closure changes nothing they read.
4. **Mutex.** It owns its data; `with` locks, runs, unlocks. `try_with`.
   No poisoning. (Guards are not public yet: say so, it may change.)
5. **Atomics.** `AtomicI64` and friends, Rust's method names, the
   orderings in one paragraph each (Relaxed for counters, Acquire/Release
   for handing data over, SeqCst when unsure).
6. **Channels.** `mpsc::channel_in(gpa)`, `send`, `recv`, `for x in
   rx.iter()`, cloning senders.
7. **Thread-locals.** `#[thread_local] static var`.
8. **Effects.** `sync`, `thread`, `tls` in `query effects`; `#[pure]`
   excludes them.

## Errors to show

- `sync.global`: a spawned closure reaching a `static var`.
- `sync.borrow_escapes`: a view captured by `thread::spawn`.
- `sync.not_send`: a raw pointer sent to a thread.
- `sync.scope_shared_write`: two scoped threads writing one variable,
  with the Mutex or atomic fix.

## Asides

- If you know Rust: `Send`/`Sync` are inferred, not written; `sink ||`
  is `move ||`; `Mutex::with` instead of guards (for now); no `Arc`:
  scoped threads share the caller's data.
- If you know Go: no goroutines; threads are OS threads; channels are
  similar, typed and closed when every sender is gone.

## Sources

`volec guide threads`, `volec explain sync.global` (and the other
`sync.*` codes).
