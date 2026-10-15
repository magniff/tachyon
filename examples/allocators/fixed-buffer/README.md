# No heap at all: `FixedBuf`

A reverse-Polish calculator (`3 4 * 5 -` is 7) that reads lines from
stdin, with all of its memory in 512 bytes on `main`'s stack. Its `main`
is `fn main()`: it takes no `Gpa`, so nothing in the program can
allocate from the heap, and the compiler can show it. The numbers'
stack and the line being read are `Vec`s on a `FixedBuf`, an allocator
that hands out the bytes of a buffer you give it; when they are used up,
the `try_` forms return an error the calculator reports, where a heap
allocation would have grown.

This is the shape of code for places without a heap, or where running
out must be handled rather than fatal: embedded targets, a signal
handler, a request with a hard memory budget.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-fixed-buffer.test` runs the program.

## Run it

```console
$ tachyonc main.tach -o rpn && ./rpn < input.txt
1 2 + = 3
3 4 * 5 - = 7
10 dup * = 100
1 +: '+' needs two numbers
2 3: 2 numbers left: an operator is missing
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ... = 20
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ...: out of memory at depth 32 (the stack has no more room)
1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 ...: out of memory: the line is longer than 160 bytes
7 x *: unknown word 'x'
9 lines, 5 failed; 416 of 512 bytes in use, room for 32 numbers
```

Five lines fail, two of them for want of memory: 32 numbers fit on the
stack, and 160 bytes in the line.

## The memory

```tach
fn main() -> i32 {
    let mut mem = [0u8; 512];
    let fb = FixedBuf::new(mem[..]);
    let mut line: Vec<u8, FixedBuf> = Vec::with_capacity_in(160, fb);
    let mut stack: Vec<i64, FixedBuf> = Vec::new_in(fb);
```

`FixedBuf::new(mem[..])` makes an allocator over the array: it keeps
its count of the bytes used in the first 16, and bumps through the
rest. Like an arena, it frees only its last block (or grows it in
place): so the line, whose room is fixed, comes first, and the stack,
which grows, comes last and grows in place: 4 numbers, 8, 16, 32. At 32
(256 bytes) the next size needs 256 bytes more, and 80 are left.

The `FixedBuf` handle is copied into each `Vec` (it is two words); the
copies share the count, which lives in `mem`. `mem` must outlive every
container on it, and nothing checks that in 0.16 (a `FixedBuf` over a
local array, returned from its function, is a dangling pointer): keep
the buffer and its containers in one function, as here.

## Running out, handled

`push` stops the program when the allocator is out of memory (the
message is "out of memory", exit 101). `try_push` returns a `Result`
instead:

```tach
fn push(stack: *Vec<i64, FixedBuf>, x: i64) -> Result<(), CalcError> {
    match stack.try_push(x) {
        Ok(()) => Ok(()),
        Err(AllocError::OutOfMemory) => Err(CalcError::TooDeep(stack.len())),
    }
}
```

`try_reserve(n)` is the same for room for `n` more. The line is read
the same way, a byte at a time with `try_push`: a line that does not fit
is read to its end and reported. (std's `read_line` would grow the line
with `push`, and it keeps its own buffer for stdin from C's `malloc`:
this program reads stdin with C's `read` into 64 bytes of its own.)
Only `Vec` has `try_` forms in 0.16; a `Buf` or a `HashMap` on a
`FixedBuf` stops the program when it is full.

## What the compiler can show

```console
$ tachyonc query effects crate
<crate::CalcError as Display>::fmt	io global panic
crate::push	alloc(FixedBuf)
crate::skip	panic
crate::pop2	panic
crate::eval	alloc(FixedBuf) panic
crate::Input::byte	io panic unsafe
crate::Input::line	alloc(FixedBuf) io panic diverge
crate::short	panic
crate::main	alloc(FixedBuf) io global panic diverge
```

No function has `alloc(Gpa)`, nor `alloc(extern)` (C's `malloc`):
every allocation is from the `FixedBuf`. `eval` makes it a promise:

```tach
#[effects(alloc(FixedBuf), panic)]
fn eval(line: [u8], stack: *Vec<i64, FixedBuf>) -> Result<i64, CalcError> {
```

The compiler checks the declaration against everything `eval` calls.
A helper three calls down that allocated from a `Gpa` (it would have to
be given one: `main` has none to give), printed, or looped with `while`
would be an error at `eval`, naming the helper. Writing the word
scanner with a `while` loop was such an error: `while` may not
terminate (the effect `diverge`), so `skip` is a counted `for` over the
line.

## Read more

- `tachyonc guide allocators`, sections "Arenas" (`FixedBuf::new`) and
  "--check-alloc" (a `FixedBuf`'s blocks are checked too).
- `tachyonc guide effects`, for `#[effects(...)]`.
- [scoped-arena](../scoped-arena/): growing memory, freed per request.
