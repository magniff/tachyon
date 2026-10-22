# 15. Unsafe code and C

Everything in this book so far has been *safe* vole: code the compiler
can check, so that a mistake ends in an error message or a clean panic,
never in a program that quietly reads the wrong memory. Most programs
never need anything else. Some do: a program that calls a C library,
talks to hardware, or builds a data structure out of raw memory has to
do things the compiler can't check.

This chapter is about that small, fenced-off part of the language. By
the end you'll know what `unsafe` allows and why, how to use raw
pointers, how to call C functions and let C call yours, how to lay out
data the way C expects, and how to wrap all of it in a safe type that
the rest of your program can use without thinking about it. You'll also
see the two compiler modes that catch memory bugs in unsafe code at run
time.

## What safe code promises

Let's recall what the earlier chapters showed. In safe vole:

- arithmetic on integers wraps around instead of overflowing into
  nonsense (chapter 3);
- every index into an array, a `Vec` or a slice is checked, and a bad
  one stops the program with a panic (chapter 7);
- every variable is set before it's used;
- a view of a value can't outlive the value or see it change underneath
  it (chapter 4).

Together these mean safe code has no *undefined behaviour*: there is
no program you can write in safe vole whose meaning is "whatever the
machine happens to do". A bug gives you a wrong answer or a panic with
a line number, and you can find it.

C doesn't work that way. Reading past the end of an array in C isn't
an error; it reads whatever is there. A C library can't keep vole's
promises, because the compiler can't see inside it. So the moment a
program calls C, or does something C-like, the compiler needs you to
say: "I've checked this part myself." That's what `unsafe` is for.

## A first call to C

The C library has a square root function, `sqrt`. Let's call it. Save
this as `roots.vl`:

```vole roots.vl
extern "C" {
    fn sqrt(x: f64) -> f64;
}

fn main() {
    for i in 1..5 {
        let r = sqrt(i as f64);
        println(f"sqrt({i}) = {r:.4}");
    }
}
```

The `extern "C"` block declares a function that lives somewhere else,
written in C (or anything that follows C's calling conventions). We
give its name and its signature in vole's types: C's `double` is
`f64`. The compiler believes the declaration; it has no way to check
it against the real function.

Build it:

```err
error[unsafe]: calling a C function is unsafe
 --> roots.vl: line 7, column 17
  = help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place)
  = try: volec fix --only unsafe roots.vl
```

The compiler won't let a C call sit in ordinary code. If our
declaration were wrong (say we'd written `-> i64`), the program would
read a garbage result, and no check could catch it. So the call has to
go in an `unsafe` block, which marks the spot where you, not the
compiler, vouch that the call is right. The `try:` line does that for
us:

```console
$ volec fix --only unsafe roots.vl
fixed 1 unsafe block	roots.vl	+1 -1 lines
$ cat roots.vl
extern "C" {
    fn sqrt(x: f64) -> f64;
}

fn main() {
    for i in 1..5 {
        let r = unsafe { sqrt(i as f64) };
        println(f"sqrt({i}) = {r:.4}");
    }
}
$ volec roots.vl -o roots
ok: built roots
$ ./roots
sqrt(1) = 1.0000
sqrt(2) = 1.4142
sqrt(3) = 1.7321
sqrt(4) = 2.0000
```

`unsafe { ... }` is an expression, like any block: its value is the
value of its last expression, so `let r = unsafe { sqrt(i as f64) };`
works. Keep unsafe blocks small. A block around one call says exactly
which call you checked; a block around a whole function says nothing
useful.

We didn't have to tell the compiler where `sqrt` is. On macOS it's in
the system library every program links with; on Linux it's in `libm`,
and the compiler links that when a program calls one of its
functions.

## What unsafe allows

An `unsafe` block doesn't turn the checks off. It allows five more
operations, each one something the compiler can't check:

- **calling a C function or an `unsafe fn`**: the compiler can't see
  what the other side does;
- **dereferencing a raw pointer** (`*p`, or `p.field` through one): the
  pointer could point anywhere;
- **indexing a raw pointer** (`p[i]`): there's no length to check
  against;
- **casting an integer to a pointer**: the compiler can't know there's
  anything at that address;
- **reading a field of a `union`**: the compiler can't know which field
  was last written.

Everything else stays checked, inside `unsafe` too. Indexing a `Vec` in
an unsafe block is still checked, arithmetic still wraps, and a view
still can't outlive its value. Here's an index past the end of a `Vec`,
inside `unsafe`:

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    let i = v.len() + 2;
    unsafe {
        println(f"{v[i]}");
    }
}
```

```out exit=101
main.vl:6:20: index out of bounds: index 3, length 1
```

So `unsafe` is narrow on purpose: it's a short list of things you take
responsibility for, not a switch that turns vole into C.

> **If you know Rust:** this is Rust's model, with the same five
> operations. Two things look different: pointer arithmetic is indexing
> (`p[i]` instead of `p.add(i)`), and there's no bindgen step, because
> vole reads C headers itself (you'll see `import` below).

## Raw pointers

A *raw pointer* is an address and a type: `*i64` is "the address of an
`i64`, maybe". It's vole's equivalent of a C pointer, and nothing
checks what it points to.

```vole pointers.vl
fn main() {
    let xs: [i64; 4] = [10, 20, 30, 40];
    let p = &xs as *i64; // a raw pointer to the first element
    let null = 0 as *i64;
    println(f"{p.is_null()} {null.is_null()}");
    let third = unsafe { p[2] };
    println(f"{third}");
}
```

```out
false true
30
```

Making a pointer is safe: `&xs as *i64` takes the address of `xs`, and
`0 as *i64` is the *null pointer*, the address that points at nothing.
Comparing pointers and asking `is_null()` are safe too. Only using a
pointer to reach memory needs `unsafe`, as `p[2]` does here. It reads
the `i64` two places after the one `p` points to, with no bounds check:
`p` doesn't know how many elements there are.

That's the danger. Change the `2` to `7`, and the program still builds
and runs. It reads 8 bytes from beyond the end of the array, whatever
happens to be there, and prints a number that can differ from run to
run, or between `-O0` and `-O2`. That is undefined behaviour, and it's
exactly what safe code rules out.

Casting any integer other than `0` to a pointer is unsafe, since
there's rarely anything you can know about an address you made up:

```vole
fn main() {
    let p = 4096 as *u8;
    println(f"{p.is_null()}");
}
```

```err
error[unsafe]: casting an integer to a pointer is unsafe
 --> main.vl: line 2, column 13
  = help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place)
  = try: volec fix --only unsafe main.vl
```

When a pointer can never be null, say so with `std::NonNull<T>`.
`NonNull::new(p)` returns `None` for a null pointer and `Some` for any
other, and an `Option<NonNull<T>>` takes no more room than the pointer
itself: `None` is stored as null. It's the usual type for a link in a
hand-built list or tree, and for a C pointer that may be null.
Dereferencing a `NonNull` is still unsafe; it promises only "not null",
not "valid".

> **If you know Rust:** the `&` in `&xs as *i64` isn't a reference
> being cast. Vole has no references to store. `&place` is the marker
> for "the callee may change this", and where a raw pointer is wanted,
> it is simply the place's address. It takes no inout access, so it
> works on a `let`; writing through it to a `let` would be the unsafe
> code's mistake.

## unsafe fn and its contract

Sometimes a whole function can only be used correctly if the caller
keeps a promise the compiler can't check. Mark it `unsafe fn`, and
write the promise in its comment:

```vole text.vl
import "string.h" as c;

// The text of a C string, as a vole slice.
//
// Unsafe: `p` must point to a NUL-terminated string, which must stay
// alive and unchanged while the result is used.
unsafe fn c_text(p: *u8) -> [u8] {
    p[0..c::strlen(p) as i64]
}

fn main() {
    let t = c_text(c"hello");
    println(f"{t.len()}");
}
```

(`import "string.h" as c;` reads C's header for `strlen`; the next
section explains it. `c"hello"` is a C string.)

The body of an `unsafe fn` is unsafe code, so it can call `strlen` and
slice the pointer without a block of its own. In exchange, every call
of `c_text` is an unsafe operation:

```err
error[unsafe]: calling an `unsafe fn` is unsafe
 --> text.vl: line 12, column 13
  = help: put it in an `unsafe { ... }` block, or the function's body in an `unsafe fn` (the try: line wraps every such place)
  = try: volec fix --only unsafe text.vl
```

The comment is the contract, and the caller's `unsafe { }` block is
where the promise is made. Someone reading `unsafe { c_text(p) }`
knows to check that `p` really is a live C string. Without the comment,
they'd have to guess what to check; that's why every `unsafe fn` should
start with one.

## Calling C

### Importing a header

Declaring every C function by hand is tedious and easy to get wrong.
Vole can read C's header files instead:

```vole math.vl
import "math.h" as m;

fn main() {
    var exp: i32 = 0;
    let frac = unsafe { m::frexp(48.0, &exp) };
    let e = unsafe { m::erf(0.5) };
    println(f"48 = {frac} * 2^{exp}");
    println(f"erf(0.5) = {e:.6}");
}
```

```out
48 = 0.75 * 2^6
erf(0.5) = 0.520500
```

`import "math.h" as m;` runs the system's C compiler over the header
and makes its functions available under `m::`. Their types come from
the header: C's `int` is `i32`, `long` and `int64_t` are `i64`,
`double` is `f64`, `size_t` is `u64`, and any pointer to bytes, `char
*` or `void *`, is `*u8`.

`frexp` splits a number into a fraction and a power of two, and returns
the power through a pointer: its C signature is `double frexp(double x,
int *exp)`. We pass `&exp`, which converts to the address of `exp`
where a `*i32` is wanted. As always, `&` marks the argument that may
change.

Headers can't give everything. C macros that look like functions,
`static inline` functions and `errno` aren't functions the linker can
find, so they aren't imported. For those, declare a small C helper of
your own (below), or look for the real function behind the macro.

### C strings

C's text is a pointer to bytes ending with a zero byte, a
*NUL-terminated* string. Vole's `str` and `[u8]` are a pointer and a
length, with no zero at the end, so they can't be passed to C as they
are. For C, write the literal with a `c` in front: `c"HOME"` is a `*u8`
to the bytes `HOME` and a zero.

```vole env.vl
import "stdlib.h" as c;
import "string.h" as c;

fn main() {
    let missing = unsafe { c::getenv(c"VOLE_BOOK_NO_SUCH_VARIABLE") };
    println(f"{missing.is_null()}");
    let path = unsafe { c::getenv(c"PATH") };
    if !path.is_null() {
        let n = unsafe { c::strlen(path) };
        println(f"PATH is set: {n > 0}");
    }
}
```

```out
true
PATH is set: true
```

`getenv` returns a null pointer when the variable isn't set, so we
check before using the result. (Two headers can share one name, `c`
here: all of a program's headers go into one C module.)

To turn a C string into vole text, slice the pointer up to its length,
as `c_text` did above: `p[0..c::strlen(p) as i64]`. In the other
direction, a vole slice `s` is `s.ptr` and `s.len()`, which is exactly
what C functions that take a pointer and a length want.

> **If you know C:** for reading the environment, there's a safe
> `std::env::get_in(name, gpa)`; std wraps the common C calls this way,
> so you rarely need `getenv` itself. This chapter calls C directly to
> show how it works.

### Variadic functions

`printf` takes any number of arguments after its format. Vole passes
numbers, `bool`s and pointers to it as C would:

```vole printf.vl
import "stdio.h" as c;

fn main() {
    unsafe {
        c::printf(c"%s has %ld letters, pi is about %.3f\n", c"vole", 4, 3.14159);
    }
}
```

```out
vole has 4 letters, pi is about 3.142
```

The format has to match: `%ld` for an `i64`, `%d` for an `i32` or a
`bool`, `%f` for an `f64`, `%s` for a `*u8`. Nothing checks this; it's
part of what the `unsafe` block vouches for.

One practical warning: C's `printf` and vole's `println` each keep
their own output buffer. When the output goes to a pipe or a file,
they're flushed at different times, so lines from the two can come out
of order. Use one or the other for a stream, not both.

### Linking

A function you declare must be found when the program is linked. The C
library is always linked. For anything else, name the library, either on
the command line or in the code:

```sh
volec prog.vl -l png -o prog           # link libpng
volec prog.vl helper.c -o prog         # compile helper.c and link it in
```

```vole ilogb.vl
#[link(lib = "m")]
extern "C" {
    fn ilogb(x: f64) -> i32;
}

fn main() {
    println(f"{unsafe { ilogb(1000.0) }}");
}
```

```out
9
```

The `#[link]` attribute goes on an `extern "C"` block, and says which
library its functions come from: here `libm`, the C math library
(`ilogb` is the exponent of a number in base 2, and 1000 is between
2^9 and 2^10). The library is linked only when the program calls one
of the block's functions. A `.c`
file on the command line is compiled with the system's C compiler (`cc`)
and linked in, which is the easy way to add a little C of your own.

## Laying out data for C

When vole and C both read the same struct, they must agree on where
each field is. Vole doesn't promise any particular layout for its own
structs: the compiler may reorder fields or pad them as it likes, and
that may change between releases. `#[repr(C)]` asks for C's layout
instead: the fields in the order written, with C's padding.

```vole layout.vl
#[repr(C)]
struct Header {
    tag: u8,
    size: u32,
}

#[repr(C, packed)]
struct Packed {
    tag: u8,
    size: u32,
}

#[repr(u8)]
enum Color {
    Red = 1,
    Green = 2,
    Blue = 4,
}

fn main() {
    println(f"{size_of(Header)} {size_of(Packed)} {size_of(Color)}");
    println(f"{Color::Blue as u8}");
}
```

```out
8 5 1
4
```

`Header` takes 8 bytes: a byte for `tag`, three bytes of padding so
that `size` starts at a multiple of 4, as C does it, then 4 bytes for
`size`. `#[repr(C, packed)]` removes the padding (5 bytes), for file
formats and network packets. `#[repr(u8)]` gives an enum a one-byte tag
with the values you choose, the way C enums are usually passed around.
There's also `#[repr(C, align(16))]`, to make a struct start at a
multiple of 16.

A C `union` is a `#[repr(C)] union` in vole: its fields share the same
memory. Writing one is safe; reading one is unsafe, since the compiler
can't know which field holds a meaningful value:

```vole bits.vl
#[repr(C)]
union Bits {
    f: f32,
    u: u32,
}

fn main() {
    let b = Bits { f: 1.0 };
    let raw = unsafe { b.u };
    println(f"{raw:08x}");
}
```

```out
3f800000
```

Only some types can appear in an `extern "C"` signature: numbers,
`bool`, raw pointers, `#[repr(C)]` types and C function pointers. A
`Vec`, a slice, a tuple or an ordinary struct is rejected, with a hint
about what to use instead.

## Callbacks: qsort

Some C functions take a function as an argument. The C library's
`qsort` sorts an array of anything, and calls your function to compare
two elements. That function has to follow C's calling convention, so
it's declared `extern "C" fn`:

```vole scores.vl
import "stdlib.h" as c;

#[repr(C)]
struct Score {
    player: i32,
    points: i32,
}

// qsort's comparison: negative, zero or positive, as C expects.
// Highest points first.
extern "C" fn by_points(a: *u8, b: *u8) -> i32 {
    let x = unsafe { (*(a as *Score)).points };
    let y = unsafe { (*(b as *Score)).points };
    if x > y { -1 } else if x < y { 1 } else { 0 }
}

fn main() {
    var scores = [
        Score { player: 1, points: 40 },
        Score { player: 2, points: 75 },
        Score { player: 3, points: 10 },
        Score { player: 4, points: 55 },
    ];
    let n = scores.len() as u64;
    let size = size_of(Score) as u64;
    unsafe { c::qsort(&scores as *u8, n, size, by_points); }
    for s in scores {
        println(f"player {s.player}: {s.points}");
    }
}
```

```out
player 2: 75
player 4: 55
player 1: 40
player 3: 10
```

`qsort` only knows it has `n` elements of `size` bytes each, at some
address. It hands our comparison two `void *` pointers, which arrive
as `*u8`, and the comparison casts them back to `*Score`, the type it
knows the array holds. `Score` is `#[repr(C)]` because C moves its
bytes around; `size_of(Score)` tells `qsort` how many bytes an element
is.

An `extern "C" fn` is an ordinary function you can call from vole too.
It just has C's calling convention and a name C can link to, which a
plain `fn` doesn't. Closures can't be passed to C: a closure carries
the values it captured, and a C function pointer has nowhere to put
them. C libraries usually solve this with an extra `void *` argument
they pass back to your callback untouched; pass the address of your
state there.

## C calling vole

The same `extern "C" fn` lets C call vole by name. Here's a vole
program with one function for C, and one C function it calls in turn.
Save it as `main.vl`:

```vole skip
// Called by C: the C calling convention, and a name C can link to.
extern "C" fn vole_square(x: i64) -> i64 {
    x * x
}

extern "C" {
    fn sum_squares(n: i64) -> i64; // defined in sum.c
}

fn main() {
    println(f"1 + 4 + 9 + 16 = {unsafe { sum_squares(4) }}");
}
```

The C side needs to know `vole_square`'s signature. Rather than
writing that by hand, ask the compiler for a header:
`volec --emit-header main.vl -o main.h` writes the C declarations of a
program's `extern "C"` functions and statics, with any `#[repr(C)]`
types they use. The C file includes it. Save this as `sum.c`:

```c
#include "main.h"

int64_t sum_squares(int64_t n) {
    int64_t total = 0;
    for (int64_t i = 1; i <= n; i++) {
        total += vole_square(i);
    }
    return total;
}
```

Then build both together, by putting the C file on `volec`'s command
line. (The book's tests replay this session in an empty directory, so
its first two commands write the two files; you'd save them from your
editor.)

```console
$ printf '%s\n' '// Called by C: the C calling convention, and a name C can link to.' 'extern "C" fn vole_square(x: i64) -> i64 {' '    x * x' '}' '' 'extern "C" {' '    fn sum_squares(n: i64) -> i64; // defined in sum.c' '}' '' 'fn main() {' '    println(f"1 + 4 + 9 + 16 = {unsafe { sum_squares(4) }}");' '}' > main.vl
$ printf '%s\n' '#include "main.h"' '' 'int64_t sum_squares(int64_t n) {' '    int64_t total = 0;' '    for (int64_t i = 1; i <= n; i++) {' '        total += vole_square(i);' '    }' '    return total;' '}' > sum.c
$ volec --emit-header main.vl -o main.h
ok: wrote main.h
$ grep vole_square main.h
int64_t vole_square(int64_t x);
$ volec main.vl sum.c -o squares
ok: built squares
$ ./squares
1 + 4 + 9 + 16 = 30
```

`volec` compiled `sum.c` with the system's C compiler and linked the
two halves into one program: vole calls C, which calls vole. For a
bigger build that runs its own linker, `volec main.vl -o main.o`
produces an object file instead. The repository's
`examples/c-mixed-build` is a complete program built both ways.

## A safe wrapper

Unsafe code is easiest to get right when there's little of it, all in
one place, behind a safe interface. Let's build the classic example: a
growable list of numbers, on memory from C's `malloc`. (You'd use a
`Vec` for this, of course; the point is to see how a `Vec`-like type
is built and kept safe.)

```vole ints.vl
extern "C" {
    fn realloc(p: *u8, n: u64) -> *u8;
    fn free(p: *u8);
}

// A growable list of i64s, on C's heap.
struct Ints {
    data: *i64,
    len: i64,
    cap: i64,
}

impl Ints {
    fn new() -> Ints {
        Ints { data: 0 as *i64, len: 0, cap: 0 }
    }

    fn push(inout self, x: i64) {
        if self.len == self.cap {
            let cap = if self.cap == 0 { 4 } else { self.cap * 2 };
            let p = unsafe { realloc(self.data as *u8, (cap * 8) as u64) };
            if p.is_null() {
                panic("out of memory");
            }
            self.data = p as *i64;
            self.cap = cap;
        }
        // in bounds: len < cap, and data holds cap i64s
        unsafe { self.data[self.len] = x; }
        self.len += 1;
    }

    fn get(self, i: i64) -> i64 {
        assert(i >= 0 && i < self.len);
        unsafe { self.data[i] }
    }

    fn len(self) -> i64 {
        self.len
    }
}

impl Drop for Ints {
    fn drop(inout self) {
        unsafe { free(self.data as *u8); }
    }
}

fn main() {
    var xs = Ints::new();
    for i in 0..10 {
        xs.push(i * i);
    }
    println(f"{xs.len()} items, the last {xs.get(xs.len() - 1)}");
}
```

```out
10 items, the last 81
```

Look at where the `unsafe` blocks are. Each one is a single operation,
and each relies on something the safe code around it made true:

- `push` writes `data[len]` only after making sure `len < cap`, and
  `data` always has room for `cap` numbers;
- `get` checks the index itself, with `assert`, before reading,
  because a raw pointer won't;
- `drop` frees the memory exactly once, when the list goes away.

`main` contains no `unsafe` at all. Whoever uses `Ints` can't break it:
`get` with a bad index panics just like indexing a `Vec` does.

`impl Drop` does more than free the memory. A type with a `Drop` is
owned, as chapter 4 showed, even when its fields are plain numbers and
pointers: assigning it moves it, and the old name can't be used
again. That matters here. If `Ints` could be copied, two copies would
hold the same `data` pointer; one `push` could move the numbers to a
new block and free the old one, leaving the other copy pointing at
freed memory. Because it's owned, the compiler stops that:

```vole skip
    let ys = xs;
    println(f"{xs.len()} {ys.len()}");
```

```text
error[own.moved]: 'xs' is used here after it moved at 54:14
 --> ints.vl: line 55, column 16
```

Those are the rules unsafe code has to keep, so that the safe code
around it stays safe:

- every pointer or slice it hands to safe code points at live memory
  of the right type, for as long as it's used;
- it never makes a second way to change a value while something else
  has the right to change it (an `inout` parameter is the only way to
  its value while the call runs, and the optimizer relies on that);
- a type that manages memory through raw pointers implements `Drop`,
  which makes it owned, so it is moved, never copied.

`volec guide unsafe` has them in full.

> **If you know C:** this is the deal vole offers. Safe code can't have
> undefined behaviour, and the parts that can are exactly the C-like
> parts, marked `unsafe`, usually a few lines. When something goes
> wrong, those few lines are where to look first.

## Checking unsafe code

Even small unsafe code has bugs. Let's plant one in `Ints`: suppose we
forgot that an `i64` is 8 bytes, and asked `realloc` for `cap * 4`
bytes. Here's the same program with that one change:

```vole ints.vl
extern "C" {
    fn realloc(p: *u8, n: u64) -> *u8;
    fn free(p: *u8);
}

// A growable list of i64s, on C's heap.
struct Ints {
    data: *i64,
    len: i64,
    cap: i64,
}

impl Ints {
    fn new() -> Ints {
        Ints { data: 0 as *i64, len: 0, cap: 0 }
    }

    fn push(inout self, x: i64) {
        if self.len == self.cap {
            let cap = if self.cap == 0 { 4 } else { self.cap * 2 };
            let p = unsafe { realloc(self.data as *u8, (cap * 4) as u64) };
            if p.is_null() {
                panic("out of memory");
            }
            self.data = p as *i64;
            self.cap = cap;
        }
        // in bounds: len < cap, and data holds cap i64s
        unsafe { self.data[self.len] = x; }
        self.len += 1;
    }

    fn get(self, i: i64) -> i64 {
        assert(i >= 0 && i < self.len);
        unsafe { self.data[i] }
    }

    fn len(self) -> i64 {
        self.len
    }
}

impl Drop for Ints {
    fn drop(inout self) {
        unsafe { free(self.data as *u8); }
    }
}

fn main() {
    var xs = Ints::new();
    for i in 0..10 {
        xs.push(i * i);
    }
    println(f"{xs.len()} items, the last {xs.get(xs.len() - 1)}");
}
```

The list now writes past the end of its memory. And yet, built the
usual way, the program seems to work:

```console
$ volec ints.vl -o ints
ok: built ints
$ ./ints
10 items, the last 81
```

That's what makes such bugs dangerous: they corrupt memory that
belongs to someone else, and the program fails later, somewhere
unrelated, or not at all until the input grows. `--check-unsafe`
builds the program with a check on every raw-pointer access into the
heap:

```console
$ volec --check-unsafe -O1 ints.vl -o ints
ok: built ints
$ ./ints
unsafe access out of bounds (just past the end): 8 bytes at offset 16 of a block of 16 bytes
 --> ints.vl: line 29, column 18
$ echo $?
101
```

The first write past the end is caught, with its line: the `i64` at
offset 16 of a 16-byte block, which should have been 32 bytes. A
checked program runs many times slower, so it's for tests, not for
the build you ship. It checks pointers into memory from `malloc` and
friends, not into the stack.

The other mode, `--check-alloc`, checks memory from vole's own
allocator. It puts every block on memory pages of its own and never
reuses them, so touching a block after it was freed is caught. Here's
a classic mistake, keeping a raw pointer to a `Vec`'s elements while
the `Vec` grows:

```vole stale.vl
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(7);
    let p = v.as_slice().ptr; // a raw pointer to the first element
    for i in 0..100 {
        v.push(i); // the Vec grows: its elements move to a new block
    }
    let first = unsafe { p[0] };
    println(f"{first}");
}
```

Safe code couldn't do this: a slice of `v` can't be used after `v`
changes (chapter 4), and the compiler rejects it. A raw pointer is
outside those checks, so built normally, this prints whatever is in the
freed block. With `--check-alloc`:

```console
$ volec --check-alloc stale.vl -o stale
ok: built stale
$ ./stale
use after free: block #1 (32 bytes), allocated at stale.vl:3:5, freed at stale.vl:6:9
```

It says which block, where it was allocated and where it was freed:
the `push` that grew the `Vec`. Add `--check-unsafe -O1` as well, and
the report also names the line of the read itself. `volec test` builds
tests with `--check-alloc` already (chapter 13), so a test that
exercises your unsafe code gets this checking for free.

## Summary

- Safe vole has no undefined behaviour; `unsafe` marks the few
  operations the compiler can't check: calling C or an `unsafe fn`,
  using a raw pointer, casting an integer to a pointer, reading a
  union.
- Everything else stays checked inside `unsafe`. Keep the blocks small,
  and give every `unsafe fn` a comment saying what its caller must
  promise.
- `extern "C"` declares C functions; `import "header.h" as c;` reads
  them from a header. `c"..."` is a C string. `-l`, `#[link]` and `.c`
  files on the command line link C code in.
- `#[repr(C)]` gives a struct C's layout; `extern "C" fn` gives a
  function C's calling convention, for callbacks and for C calling vole;
  `--emit-header` writes the C declarations.
- Wrap unsafe code in a safe type; one that owns raw memory implements
  `Drop`, which also makes it owned: moved, never copied.
- `--check-unsafe` and `--check-alloc` find out-of-bounds accesses and
  uses after free at run time.

The next chapter is about making programs fast, and about seeing what
the compiler did with your code.

## Try it yourself

- Add a `pop(inout self) -> Option<i64>` method to `Ints`. Which parts
  of it need `unsafe`?
- Call `qsort` on the `Ints` list's memory directly, with a comparison
  for `i64`s, from inside a new `sort(inout self)` method.
- Import `time.h` and print the result of C's `time(0 as *i64)`. What
  does `volec --emit-imports prog.vl -o decls.vl` show the header
  declares?
