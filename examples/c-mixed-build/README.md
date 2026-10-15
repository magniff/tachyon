# c-mixed-build

A project that is half tachyon, half C: `ring.c` is a small ring buffer
(a sliding window of the last N readings) and a fast hash (FNV-1a);
`main.tach` reads numbers from stdin, drives the ring, and prints running
statistics. The calls go both ways:

- tachyon calls C through the C file's own header (`import "./ring.h" as c;`);
- C calls tachyon through a function pointer tachyon hands over
  (`ring_each(ring, accumulate, &stats)`);
- C calls tachyon **by name**: `ring.c` calls `on_evict(value)` and
  increments `EVICTIONS`, both defined in `main.tach` and declared for C
  in a header that `tachyonc --emit-header` writes.

| file | what it is |
|---|---|
| `main.tach` | the program: input, a safe `Window` type over the C ring, the callbacks |
| `ring.h` | the C API, imported by tachyon and included by `ring.c` |
| `ring.c` | the ring buffer and the hash |
| `main.h` | written by the build: tachyon's side as a C header (not in the repository) |
| `Makefile` | the build below |

## Build and run

From this folder (with `tachyonc` on your `PATH`; from a built tree it
is `../../target/tachyonc`):

```sh
tachyonc --emit-header main.tach -o main.h       # 1. tachyon's functions and statics, for C
tachyonc main.tach ring.c -o c-mixed-build       # 2. the program and the C file, linked
echo 10 20 30 40 55 15 60 5 25 | ./c-mixed-build
```

Step 2 compiles `ring.c` with `cc` (at the program's `-O` level, with
its `-I` directories) and links it with the tachyon object. Objects
(`.o`), archives (`.a`), shared libraries, `-l NAME` and `-L DIR` go on
the same command line, in the order the linker wants them. The output's
name says what is made: `-o x.o` an object, `-o x.s` assembly, any other
name an executable linked by `cc` (`$TACHYON_CC` if set).

A build that links itself (another linker, flags of its own) takes the
tachyon program as an object, as the Makefile does:

```sh
cc -O2 -c ring.c -o ring.o                       # the C file (it includes main.h)
tachyonc main.tach -o main.o                     # the tachyon program, as an object
cc main.o ring.o -o c-mixed-build                # linked by cc
```

Or with make (`TACHYONC` defaults to the tree's compiler):

```sh
make run                       # builds and runs on the readings above
make TACHYONC=tachyonc         # with a tachyonc on the PATH
make clean
```

An argument sets the window size: `./c-mixed-build 2 < readings`; a size
of 0 is an error (exit status 2).

## Expected output

```
$ echo 10 20 30 40 55 15 60 5 25 | ./c-mixed-build
a window of 4 readings
  +10   n=1 mean=10.00 min=10 max=10
  +20   n=2 mean=15.00 min=10 max=20
  +30   n=3 mean=20.00 min=10 max=30
  +40   n=4 mean=25.00 min=10 max=40
    (dropped 10)
  +55   n=4 mean=36.25 min=20 max=55
    (dropped 20)
  +15   n=4 mean=35.00 min=15 max=55
    (dropped 30)
  +60   n=4 mean=42.50 min=15 max=60
    (dropped 40)
  +5    n=4 mean=33.75 min=5 max=60
    (dropped 55)
  +25   n=4 mean=26.25 min=5 max=60
pushed 9, holding 4, dropped 5
first reading above 50: number 2 of the window (60)
fnv1a("tachyon"): C cb01e1cd, tachyon cb01e1cd
```

The `(dropped N)` lines are printed by tachyon's `on_evict`, called from
inside C's `ring_push`.

## How it works

### Tachyon imports the C file's header

```tach
import "./ring.h" as c;
```

A path starting with `./` is relative to the importing file. The header's
`typedef struct Ring { ... } Ring;` becomes a `#[repr(C)]` struct
`c::Ring` with the same fields, so tachyon can read them directly:

```tach
fn len(self: *Window) -> i64 {
    unsafe { (*self.ring).len as i64 }
}
```

`size_t` fields are `u64`; `as i64` converts to tachyon's length type.

### C imports tachyon's header

The C file needs declarations of what tachyon defines. They are not
written by hand: `tachyonc --emit-header main.tach -o main.h` writes them
from the program's `extern "C"` items:

```c
extern int64_t EVICTIONS;
void on_evict(int64_t value);
int32_t accumulate(int64_t value, uint8_t *ctx);
int32_t above(int64_t value, uint8_t *ctx);
```

`ring.c` includes it and uses them like any C function and global:

```c
if (r->len == r->cap) {
    int64_t oldest = r->items[r->head];
    ...
    EVICTIONS++;           /* a tachyon static */
    on_evict(oldest);      /* a tachyon function */
}
```

On the tachyon side:

```tach
extern "C" static mut EVICTIONS: i64 = 0;

extern "C" fn on_evict(value: i64) {
    println(f"    (dropped {value})");
}
```

`extern "C"` gives an item C's calling convention and an unmangled
symbol; without it, a tachyon function's name and convention are the
compiler's business and C could not link to it. Reading the static from
tachyon is `unsafe { EVICTIONS }`, since C may change it.

### Callbacks with a context pointer

C callbacks cannot be closures: a closure carries what it captures, and
a C function pointer has nowhere to put it. The C convention is a
`void *ctx` that the library passes back untouched:

```c
typedef int (*ring_visit)(int64_t value, void *ctx);
size_t ring_each(const Ring *r, ring_visit visit, void *ctx);
```

Tachyon passes the address of its own state, and the callback casts it
back:

```tach
struct Stats { count: i64, sum: i64, min: i64, max: i64 }

extern "C" fn accumulate(value: i64, ctx: *u8) -> i32 {
    let stats = ctx as *Stats;
    unsafe {
        stats.count += 1;
        stats.sum += value;
        ...
    }
    0 // keep going
}

fn stats(self: *Window) -> Stats {
    let mut s = Stats { count: 0, sum: 0, min: i64::MAX, max: i64::MIN };
    unsafe { c::ring_each(self.ring, accumulate, &s as *u8); }
    s
}
```

`Stats` is not `#[repr(C)]`: C never looks inside it, it only hands the
pointer back. `above` uses the same mechanism to stop early: its context
is an `i64` limit, and returning nonzero ends the walk.

### A safe face over the C API

```tach
struct Window { ring: *c::Ring }

impl Window {
    fn new(cap: i64) -> Option<Window> { ... }
    fn push(self: *Window, value: i64) { unsafe { c::ring_push(self.ring, value); } }
    fn get(self: *Window, i: i64) -> i64 { ... }   // checks i first
    fn free(self: *Window) { ... }
}
```

All the `unsafe` lives in the methods, each of which keeps the C side's
rules (the ring is non-NULL, the index is in range). `main` uses only
safe code: `Window::new(size)` returns `None` for a bad size or a failed
allocation, and `defer window.free();` releases the C memory on every way
out of `main`.

### A tachyon slice to C

```tach
let word = "tachyon";
let from_c = unsafe { c::fnv1a(word.ptr, word.len as u64) };
println(f"fnv1a(\"{word}\"): C {from_c:08x}, tachyon {fnv1a(word):08x}");
```

A `[u8]` is a pointer and a length, which is exactly what a C function
taking `(const uint8_t *data, size_t n)` wants: no NUL needed. The same
hash written in tachyon gives the same bits (`u32` arithmetic wraps, as
in C), printed in hex with `{x:08x}`.

## C interop rules in brief

- **Calling C**: `import "./mine.h" as c;` for your own headers (`-I DIR`
  adds an include directory), `import "stdio.h" as c;` for the system's.
  Every call is `unsafe`.
- **C calling tachyon**: only `extern "C" fn` and `extern "C" static`;
  `tachyonc --emit-header prog.tach -o prog.h` writes their C
  declarations, with the `#[repr(C)]` types they use.
- **Layout**: `#[repr(C)]` for any struct whose fields both sides read;
  anything C only passes along (a context pointer) can be any type.
- **Callbacks**: `extern "C" fn` plus a `void *` context, never a
  closure.
- **Linking**: C files, objects and `-l`/`-L` on `tachyonc`'s command
  line; or compile tachyon to an object (`-o main.o`) and link it
  yourself.
- **Ownership**: C frees what C allocated (`ring_free`); wrap it in a
  tachyon type with a `free` method and `defer` it.

## Language features

- `import "./ring.h" as c`, `extern "C" fn`, `extern "C" static mut`,
  `--emit-header`, linking: `tachyonc guide c-interop`
- `unsafe` blocks kept inside methods, raw pointers, casts of `*u8`:
  `tachyonc guide unsafe`
- `impl` blocks and `self: *Window` methods: `tachyonc guide syntax`
- `Option` from a constructor, `parse_int(..).unwrap_or(0)`, `Scanner` and
  `read_stdin`: `tachyonc guide conversions`, `tachyonc guide std`
- `defer` for C resources: `tachyonc guide memory`
- f-strings with width and hex (`{x:<4}`, `{h:08x}`, `{m:.2}`):
  `tachyonc guide formatting`
