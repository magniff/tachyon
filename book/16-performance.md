# 16. Performance

Vole compiles to machine code, and a straightforward vole program is
usually fast enough without any special effort. This chapter is for
the times when it isn't: when a loop runs over gigabytes, or a tool
should answer before you notice it started.

By the end you'll be able to choose an optimization level, time code
fairly, write loops the optimizer handles well, check which bounds
checks are left in a function, look at the code the compiler produced,
and use SIMD vectors and CPU-specific instructions without making your
program crash on a machine that lacks them.

We'll follow one small job through the chapter: counting the lines of
a large text, the way `wc -l` does. It's a loop over bytes, simple
enough to read in full and hot enough that every change shows up.

A word of caution first, which applies to every number in this
chapter: timings depend on the machine, on what else it's doing, and on
the input. The numbers here are from one machine, and yours will
differ. What carries over is the method, and the rough size of the
differences.

## Optimization levels

`volec` has three optimization levels:

- `-O0` optimizes almost nothing, and compiles fastest: good while you
  are writing and rebuilding code every minute;
- `-O1` does the cheaper optimizations;
- `-O2` does them all. It's the default, so `volec prog.vl -o prog`
  already means `-O2`.

Every level gives the same results. This is a direct consequence of
safe vole having no undefined behaviour (chapter 15): in languages
where some programs are "undefined", the optimizer is allowed to
assume they never happen, and a program with a hidden bug can behave
differently at `-O2` than at `-O0`. In vole, integer overflow wraps,
an index is either checked or proven in range, and nothing else is
left for the optimizer to assume. Turning optimization up changes how
fast the program runs, never what it prints. `volec test` relies on this:
it builds your tests at both `-O0` and `-O2` and compares the results.

## Measuring

Here's our starting point. Save it as `lines.vl`:

```vole lines.vl
use std::{env, time};

// n bytes of made-up text: letters, spaces, and a newline now and then.
fn make_text(n: i64, gpa: Gpa) -> Vec<u8> {
    var v: Vec<u8> = Vec::with_capacity_in(n, gpa);
    var x: u64 = 0x9e3779b97f4a7c15;
    for _ in 0..n {
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        let r = x % 64;
        v.push(if r == 0 { '\n' } else if r < 10 { ' ' } else { 'a' + (r % 26) as u8 });
    }
    v
}

// How many times b occurs in s, a byte at a time.
fn count_loop(s: [u8], b: u8) -> i64 {
    var n = 0;
    for i in 0..s.len() {
        if s[i] == b {
            n += 1;
        }
    }
    n
}

// The same, as an iterator chain.
fn count_iter(s: [u8], b: u8) -> i64 {
    s.iter().filter(|c| c == b).count()
}

// Runs f on s five times; prints its result and the fastest time.
fn time_it(name: str, f: fn([u8], u8) -> i64, s: [u8]) {
    var best = time::Duration::max_value();
    var result = 0;
    for _ in 0..5 {
        let start = time::monotonic_now();
        result = f(s, '\n');
        let took = time::monotonic_now().abs_diff(start);
        if took.cmp(best) < 0 {
            best = took;
        }
    }
    println(f"{name:<5} {result} lines in {best.as_millis_f64():.1} ms");
}

fn main(gpa: Gpa) {
    let size = 64 << 20; // 64 MiB
    let text = make_text(size, gpa);
    let s = text.as_slice();
    if env::args().len() > 1 {
        time_it("loop", count_loop, s);
        time_it("iter", count_iter, s);
    } else {
        println(f"{count_loop(s, '\n')} {count_iter(s, '\n')}");
    }
}
```

Run without arguments, it just prints both counts, so we can check that
the two versions agree:

```out
1046799 1046799
```

`make_text` makes 64 MiB of text from a simple pseudo-random generator
(xorshift), so every run counts the same bytes. Random-looking input
matters: a benchmark over a file of one repeated line can measure
something quite different from real text.

Timing is `time_it`'s job. `time::monotonic_now()` reads a clock that
only moves forward, as a `Duration`; the difference of two readings,
`abs_diff`, is how long the work in between took. A few habits make the
numbers worth having:

- **Repeat, and keep the fastest.** The first run pays for things the
  later ones don't (memory being mapped in, caches filling up), and any
  run can be slowed by another program. The fastest of several runs is
  the most repeatable number.
- **Use the result.** `time_it` keeps `result` and prints it. A
  computation whose result is never used can be removed by the
  optimizer entirely, and then you're timing nothing.
- **Time big enough work.** A few milliseconds or more per run; below
  that, the clock's own cost and noise dominate.
- **Compare like with like:** the same input, the same machine, the same
  build options, run one after the other.

Here's a run on one machine (an Apple M-series laptop, at the default
`-O2`). Yours will differ:

```text
$ ./lines time
loop  1046799 lines in 25.1 ms
iter  1046799 lines in 30.7 ms
```

That's about 2.7 GB a second: each byte is loaded, compared and
counted in well under a nanosecond. The difference between the two is
within the noise on this machine, which was busy with other work:
run it again and the order can flip.

## What's cheap, and what isn't

The two versions run at the same speed, give or take the noise,
because they compile to the same machine code (we'll look at it in a
moment). That's worth knowing, because it's true of a lot of
vole:

- **Iterator chains** like `s.iter().filter(..).count()` (chapter 10)
  are inlined into plain loops; the closure disappears into the loop
  body.
- **Generic functions** are compiled once for each type they're used
  with (chapter 9), so a `Vec<u8>` method runs code written for `u8`.
- **Views** (chapter 4) are a pointer and a length: passing `s` to
  `count_loop` copies 16 bytes, not 64 MiB.
- **Plain values**, numbers and small structs, live in registers.
- **Dropping** a value is decided at compile time: there's no garbage
  collector and no reference counting running behind the program.

What does cost:

- **Allocating.** Each `Vec::new_in` that grows, each `String` you
  build, each `_in` call, asks the allocator for memory. That's fast,
  but not free, and in a loop that runs a million times it adds up.
  Make the buffer once, outside the loop, and `clear()` it each time
  around, as chapter 2's guessing game did with its input line. For
  many small allocations that die together, an arena (chapter 8)
  replaces them with one.
- **A bounds check the compiler can't remove.** Every `v[i]` is
  checked, unless the compiler can prove `i` is in range. The check
  itself is a compare and a branch, but it can also stop the compiler
  from unrolling or vectorizing a loop. We'll see below how to
  find the ones that remain.
- **Calls the compiler can't see through**: calls through a `fn`
  value, like `time_it`'s `f(s, '\n')`, and calls into C.

## Looking at the output

Sometimes you want to see what the compiler actually made. `-S` writes
assembly instead of an executable:

```console
$ volec lines.vl -S -o lines.s
ok: wrote lines.s
$ grep '^_vole.count' lines.s
_vole.count_loop:
_vole.count_iter:
```

Assembly is long, and you don't need to read all of it. Find your
function (its name is in it: `_vole.count_loop` here) and look for the
loop: a label near the top, and a branch back to it at the bottom.
Here's the heart of `count_loop`, on AArch64:

```text
L5:
    add x4, x0, x14
    ldrb w5, [x4]           ; load a byte
    cmp x5, #10             ; is it '\n'?
    csel x5, x10, xzr, eq   ; 1 if so, else 0
    add x13, x13, x5        ; add it to a count
    ldrb w5, [x4, #1]       ; ...and the same for the next three bytes
    ...
    add x14, x14, #4
    cmp x14, x12
    b.ne L5
```

Even without knowing AArch64, a few things are visible. There's no
bounds check: no compare against the length and branch to a panic.
There's no branch on the byte either: `csel` picks 1 or 0 without
jumping, so a random mix of letters and newlines costs the same as any
other. And the loop handles four bytes per round, with four separate
counts, so the processor can work on them in parallel. Look at
`_vole.count_iter` and you'll find the same loop.

`--emit-ir` prints the compiler's own intermediate form after
optimization, one block of instructions per function, for every
function in the program. It's a little more readable than assembly,
since it uses names like `load`, `cmp.eq` and `add`, and it's the same
on every machine. `volec guide tools` lists both options.

## Bounds checks and contracts

In `count_loop`, as the assembly showed, `s[i]` needs no check: `i`
runs from `0` to `s.len()`, so the compiler can prove it's in range,
and it removes the check. Here's a function where it can't. Save it as `window.vl`:

```vole window.vl
// How many times b occurs in v[lo..hi].
#[inline(never)]
fn count_window(v: Vec<u8>, lo: i64, hi: i64, b: u8) -> i64 {
    var n = 0;
    for i in lo..hi {
        if v[i] == b {
            n += 1;
        }
    }
    n
}

fn main(gpa: Gpa) {
    var v: Vec<u8> = Vec::new_in(gpa);
    for c in "one\ntwo\nthree\nfour\n" {
        v.push(c);
    }
    println(f"{count_window(v, 0, 8, '\n')} {count_window(v, 8, v.len(), '\n')}");
}
```

```out
2 2
```

(`#[inline(never)]` keeps the compiler from copying this small
function into `main`, so that we can look at it on its own. You
wouldn't normally write it.)

Nothing tells the compiler that `hi` is at most `v.len()`, so each
`v[i]` must be checked. `volec query checks` lists the checks left in a
function after the optimizer has run, and the ones it removed:

```console
$ volec query checks count_window window.vl
window.vl:6:12	count_window	index	left
checks: 1 left, 0 removed
```

We know something the compiler doesn't: callers should only ask about
a window that's inside `v`. Chapter 13 showed how to say that, with a
`requires` clause:

```vole window.vl
// How many times b occurs in v[lo..hi].
#[inline(never)]
fn count_window(v: Vec<u8>, lo: i64, hi: i64, b: u8) -> i64
    requires 0 <= lo && lo <= hi && hi <= v.len()
{
    var n = 0;
    for i in lo..hi {
        if v[i] == b {
            n += 1;
        }
    }
    n
}

fn main(gpa: Gpa) {
    var v: Vec<u8> = Vec::new_in(gpa);
    for c in "one\ntwo\nthree\nfour\n" {
        v.push(c);
    }
    println(f"{count_window(v, 0, 8, '\n')} {count_window(v, 8, v.len(), '\n')}");
}
```

```console
$ volec query checks count_window window.vl
window.vl:8:12	count_window	index	removed (ranges)
checks: 0 left, 1 removed
```

The check in the loop is gone. Its place is taken by one check of the
`requires`, at each call, before the loop starts. A caller that asks
for a window past the end gets a clear failure naming its own line,
instead of a failure in the middle of the loop.

The important part is what the compiler did *not* do: it didn't take
the `requires` on faith. A contract is checked every time it applies,
in every build, so the compiler can rely on it afterwards. Vole's
optimizer never assumes a fact that no check established; a contract is
simply a way to move a check to where it's cheapest, and to say what
you meant.

The analysis that removes checks has limits, and they change between
releases. In this release, for example, the same function taking a
`[u8]` slice instead of a `Vec<u8>` keeps its check. So don't guess:
when a loop matters, ask `query checks`.

> **If you know C:** there's no `-ffast-math` and no optimization based
> on undefined behaviour, such as assuming a signed integer never
> overflows. Where C programmers rely on the compiler assuming things,
> vole has contracts: you state the fact, it's checked, and then the
> optimizer uses it.

## SIMD vectors

The loop above looks at one byte per instruction. Modern processors
can do better: their *SIMD* instructions (single instruction, multiple
data) work on 16 or 32 bytes at once. Vole has vector types for them.
`v16u8` is sixteen `u8`s in one register, and the usual operators work
on all sixteen *lanes* at once:

```vole simd.vl
// How many times b occurs in s, a byte at a time.
fn count_loop(s: [u8], b: u8) -> i64 {
    var n = 0;
    for i in 0..s.len() {
        if s[i] == b {
            n += 1;
        }
    }
    n
}

// The same, 16 bytes at a time.
fn count_simd(s: [u8], b: u8) -> i64 {
    let needle = v16u8::splat(b);
    let one = v16u8::splat(1);
    var n = 0;
    var i = 0;
    while i + 16 <= s.len() {
        let eq = v16u8::load(s, i) == needle; // 0xff where equal, else 0
        n += (eq & one).sum() as i64;
        i += 16;
    }
    n + count_loop(s[i..s.len()], b)
}

fn main() {
    let text = "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\nnine\nten\n";
    println(f"{count_loop(text, '\n')} {count_simd(text, '\n')}");
}
```

```out
10 10
```

Step by step:

- `v16u8::splat(b)` makes a vector with `b` in all sixteen lanes.
- `v16u8::load(s, i)` loads `s[i]` to `s[i + 15]` into a vector. It's
  checked like `s[i]`: the whole sixteen bytes must be inside `s`.
- `==` compares lane by lane, and gives a *mask*: a vector with `0xff`
  in each lane where the bytes were equal and `0` elsewhere.
- `& one` turns each `0xff` into a 1, and `.sum()` adds the sixteen
  lanes.
- The last few bytes, fewer than sixteen, go through `count_loop`.

There are vectors of every integer and float type, in 8, 16 and 32
bytes (`v4f32`, `v8i16`, `v32u8`, ...), with `+ - *`, comparisons,
`select` (pick lanes from two vectors by a mask), `lane(i)` and
`store`. `volec guide types#simd-vectors` lists them. They're
portable: the same code compiles to NEON instructions on ARM and SSE on
x86-64.

Added to `lines.vl` as a third `time_it` line, on the same machine as
before:

```text
$ ./lines time
loop  1046799 lines in 25.1 ms
iter  1046799 lines in 30.7 ms
simd  1046799 lines in 2.3 ms
```

About ten times faster on this machine, from a function a dozen lines
long. That's not the limit (summing the lanes on every round is wasted
work, and a good implementation keeps sixteen counts in a vector and
adds them up only now and then), but it's typical of what SIMD gives a
simple byte loop.

## CPU-specific instructions: std::arch

The vector types cover what every processor can do. Processors also
have special instructions of their own: checksums, encryption,
hashing, dot products. `std::arch` has them, under the names the
processor vendors give them, which are the names C and Rust use too
(*intrinsics*). Here's one: `__crc32cb` does a step of the CRC-32C
checksum, a byte at a time, in one instruction. Save this as `crc.vl`:

```vole crc.vl
use std::arch::aarch64::__crc32cb;

// CRC-32C of s, a byte at a time, by the CPU's crc instruction.
fn crc32c_hw(s: [u8]) -> u32 {
    var c: u32 = 0xffffffff;
    for b in s {
        c = __crc32cb(c, b);
    }
    ~c
}

fn main() {
    println(f"{crc32c_hw("123456789"):08x}");
}
```

```out
e3069283
```

The catch is that not every processor has every instruction. All
Apple-silicon Macs have `crc`, so on macOS the compiler accepts this
program as it is. But 64-bit ARM Linux makes no such promise: the
build there assumes only the basics, and a processor without `crc`
would stop the program with an "illegal instruction" crash. Vole won't
let that happen. Build for a generic ARM processor, as a Linux build
does, and see:

```console
$ volec -C target-cpu=generic crc.vl -o crc
error[arch.feature]: 'crc32c_hw' needs crc (from '__crc32cb' at crc.vl:7:13), which 'main' does not know here: the build's features are neon
 --> crc.vl: line 13, column 16
  = help: test the CPU with `if std::arch::detect("crc") { ... } else { ... }` and a fallback in the else branch (one of the same signature named `crc32c_hw_portable`, `_scalar` or `_fallback` is offered here), declare #[target_feature] on the caller, or build for CPUs that have it
  = try: volec -C target-feature=+crc -C target-cpu=generic -o crc crc.vl
  = try: volec query features crc32c_hw --why crc -C target-cpu=generic crc.vl
```

The compiler worked out that `crc32c_hw` needs the `crc` feature,
because it calls `__crc32cb`, and that `main` calls it without knowing
the processor has it. The help line gives the choices: build only for
processors that have it (the first `try:` line), or check at run time
and fall back to portable code. The second is what makes one program
work everywhere:

```vole crc.vl
use std::arch::detect;
use std::arch::aarch64::__crc32cb;

// CRC-32C of s, a byte at a time, by the CPU's crc instruction.
fn crc32c_hw(s: [u8]) -> u32 {
    var c: u32 = 0xffffffff;
    for b in s {
        c = __crc32cb(c, b);
    }
    ~c
}

// The same, bit by bit: for CPUs without crc.
fn crc32c_portable(s: [u8]) -> u32 {
    var c: u32 = 0xffffffff;
    for b in s {
        c ^= b as u32;
        for _ in 0..8 {
            c = if (c & 1) != 0 { (c >> 1) ^ 0x82f63b78 } else { c >> 1 };
        }
    }
    ~c
}

fn crc32c(s: [u8]) -> u32 {
    if detect("crc") { crc32c_hw(s) } else { crc32c_portable(s) }
}

fn main() {
    println(f"{crc32c("123456789"):08x} (crc: {detect("crc")})");
}
```

`detect("crc")` asks the processor, once, when the program starts, and
the compiler accepts the call to `crc32c_hw` inside the `if`, because
there the feature is known. To test the fallback on a machine that has
the feature, the `VOLE_ARCH_DISABLE` environment variable makes
`detect` answer `false`:

```console
$ volec -C target-cpu=generic crc.vl -o crc
ok: built crc
$ ./crc
e3069283 (crc: true)
$ VOLE_ARCH_DISABLE=crc ./crc
e3069283 (crc: false)
```

Both paths give the same checksum, which is the thing to test.

A few more tools for this, in brief:

- `volec query arch WORDS` finds an intrinsic by what it does, without
  a manual: `volec query arch saturating subtract u8`, or `volec query
  arch --feature crc` for a feature's whole list.
- `#[multiversion("dotprod")]` on a function compiles it twice, with
  and without the feature, and picks the right one at run time, so you
  don't write the `detect` yourself.
- Code for the other architecture can live in the same file: under
  `if std::arch::has("avx2")`, x86-64 code is type-checked on an ARM
  machine but never compiled into the program.

`volec guide arch` has the details, with a table of which intrinsics to
reach for, by task. The repository's `examples/arch` has a byte search,
a CRC-32 and a SHA-256 tool with timings against their portable
versions.

> **If you know Rust:** this is `core::arch` with the same names, minus
> the `unsafe`: since a missing feature is a compile error rather than
> a crash, and memory intrinsics take a checked slice and an index,
> calling an intrinsic is safe. Constant arguments go last, as in C
> (`vshrq_n_u8(v, 3)`), not in a turbofish.

## Compile speed

Fast programs are half of it; the other half is how long you wait for
the compiler. Some habits:

- **Use `-O0` while you work.** It compiles noticeably faster than
  `-O2`, and since every level gives the same results, you lose nothing
  but run-time speed while you're still getting the code right.
- **Use `volec check` when you only want the errors.** It stops before
  generating any code.
- **Rebuilds reuse work.** At `-O1` and `-O2`, the compiler keeps each
  function's optimized code in a cache (`target/volec-cache/`), and a
  rebuild reuses what your edit didn't change. It does this for
  programs past a certain size, or always with `--cache=on`.
- **`-j N`** sets how many threads compile at `-O1` and `-O2`; the
  output is the same whatever N is.

For a program of this chapter's size, none of this matters much: on
the machine above, `lines.vl` builds in about a tenth of a second at
`-O2`. It matters for programs of tens of thousands of lines, like the
vole compiler itself.

## Summary

- `-O0`, `-O1` and `-O2` (the default) give the same results; only the
  speed differs.
- Time with `std::time::monotonic_now()`: repeat, keep the fastest,
  use the result, and compare like with like.
- Iterator chains, generics and views cost nothing extra; allocating in
  a hot loop and unremovable bounds checks do.
- `requires` can move bounds checks out of a loop; `volec query
  checks FN` shows what's left. Nothing is assumed without a check.
- `-S` and `--emit-ir` show what the compiler produced.
- SIMD vector types (`v16u8` and friends) work on many values at once,
  portably; `std::arch` has the processor's own instructions, and
  `detect` with a fallback keeps a program running on every processor.

The next chapter is about the compiler's tools for reading and
changing code, and about working on a vole program with an AI
assistant.

## Try it yourself

- Write `count_simd2`, which keeps a `v16u8` of counts and adds the
  `eq` mask to it each round (an `0xff` lane is -1, so subtract it),
  then sums the lanes every 255 rounds before they can overflow. How
  much faster is it?
- Add a `count_window` call with `hi` past the end of `v`. Where does
  the failure point?
- Time `lines.vl` at `-O0`. How much slower is it, and why might the
  SIMD version suffer most?
