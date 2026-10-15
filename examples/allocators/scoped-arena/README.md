# Scratch memory per request: `arena_scope`

A small key-value store that answers one request per line of stdin
(`SET key n`, `ADD key n`, `GET key`, `SUM key...`). Every request needs
memory for a moment: its words, its keys in lowercase, the text of its
response. All of it comes from an arena made for that request and freed,
at once, when the request is answered:

```tach
let used = arena_scope(gpa, |scratch| {
    let mut out = Buf::new_in(scratch);
    answer(&store, line, scratch, &out);
    println(f"{line:<24} -> {out.as_slice()}");
    scratch.used()
});
```

What must outlive a request is allocated elsewhere, on purpose: the map
on `Gpa`, and the bytes of its keys in an `Arena` kept for the whole
run. The compiler holds the line between the two: nothing that holds the
scope's arena can leave the scope.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/allocators-scoped-arena.test` runs the program.

## Run it

```console
$ tachyonc main.tach -o store && ./store < requests.txt
SET apples 3             -> apples = 3
SET Pears 5              -> pears = 5
ADD apples 4             -> apples = 7
GET APPLES               -> apples = 7
GET plums                -> plums is not set
SUM apples pears plums   -> sum = 12 (not set: plums)
ADD pears lots           -> not a number: lots
FLY away                 -> unknown request: FLY away
8 requests, 2 keys; scratch per request at most 196 bytes
the keys' arena holds 11 bytes
```

No request frees anything it made, and none leaks: `--check-alloc`
(which lists every block not freed at exit, and traps a use of an
arena's block after its scope) has nothing to say.

```console
$ tachyonc --check-alloc main.tach -o store-checked && ./store-checked < requests.txt | tail -1
the keys' arena holds 11 bytes
```

## How it works

`arena_scope(gpa, f)` makes an arena whose memory comes from `gpa`,
calls `f` with a handle to it (a `ScopedArena`), and frees the arena
when `f` returns; it returns what `f` returns. Allocating from it is
bumping a pointer, and freeing a block inside it is nothing: the scope's
end frees everything. An 8 KB chunk is enough for every request here:
the busiest one used 196 bytes.

`answer` does not know or care what kind of allocator it is given:

```tach
fn answer<A: Allocator>(store: *Store, line: [u8], scratch: A, out: *Buf<A>)
```

Inside, every temporary is made on `scratch` and never freed:
`split_whitespace_in(line, scratch)`, `lower_in(w[1], scratch)` (a
lowercased copy), a `Vec<[u8], A>` of the missing keys of a `SUM`. The
response is written into `out`, a `Buf` on the same arena.

A new key must outlive the request, so it is copied out of the scratch
into the store's own arena before it goes into the map:

```tach
store.values.insert(intern(store.names, key.as_slice()), new);
```

`intern` copies the bytes into `names`, an `Arena` made once in `main`
(`Arena::new_in(gpa)`) and freed at the end (`unsafe { names.free_all()
}`: unsafe in 0.16 because a view into it could still be used after;
see below).

## What the effects say

```console
$ tachyonc query effects crate
crate::intern	alloc(Arena) panic
lower_in<ScopedArena>	alloc(ScopedArena) panic
answer<ScopedArena>	alloc(Gpa, Arena, ScopedArena) io global panic diverge
crate::main	alloc(Gpa, Arena) io global panic diverge unsafe
```

`answer<ScopedArena>` allocates from all three: `Gpa` (the map grows),
`Arena` (a new key is interned), `ScopedArena` (the scratch). In `main`
the `ScopedArena` is gone: everything allocated from a scope's arena is
freed when the scope ends, so `arena_scope` takes `alloc(ScopedArena)`
out of its caller's effects and puts in `alloc(Gpa)`, where the arena's
memory comes from.

## What cannot leave the scope

A container on the scope's arena is gone when the scope ends, so it
cannot be the scope's value:

```console
$ cat > escape.tach <<'EOF'
> fn main(gpa: Gpa) -> i32 {
>     let words = arena_scope(gpa, |a| {
>         std::split_whitespace_in("scratch words to keep", a)
>     });
>     println(words.len());
>     0
> }
> EOF
$ tachyonc check escape.tach
escape.tach:3:9: error[type error] this arena scope's value holds 'ScopedArena' (Vec<[u8], ScopedArena>): its memory is gone when the scope ends | help: copy it out: 'v.clone_in(gpa)', or return what is computed from it
[exit 1]
```

Return what is computed from it instead (`.len()` inside the scope), or
copy it out to a longer-lived allocator.

Nor can a scope use a container of another scope's arena, even an
enclosing one (`a.scope(|inner| ...)` makes a scope inside a scope):

```console
$ cat > capture.tach <<'EOF'
> fn main(gpa: Gpa) -> i32 {
>     let n = arena_scope(gpa, |outer| {
>         let mut seen: Vec<i64, ScopedArena> = Vec::new_in(outer);
>         seen.push(1);
>         outer.scope(|inner| {
>             seen.push(2);
>             inner.used()
>         })
>     });
>     println(n);
>     0
> }
> EOF
$ tachyonc check capture.tach
capture.tach:5:21: error[type error] an arena scope cannot use 'seen': its type holds another scope's arena | help: take a view first: 'let s = seen.as_slice();'
[exit 1]
```

(While the inner scope runs, the outer arena is lent to it: allocating
from `outer` would stop the program with "the arena is lent to a
scope". The rule makes that a compile error instead.) And no variable
outside a scope can hold its arena's containers: their type names
`ScopedArena`, and only a scope makes one.

## What the compiler does not catch yet: views

A slice is a view: it holds no allocator, so its type says nothing about
where its bytes live. A view of a scope's container returned from the
scope compiles in 0.16, and points at memory the scope's end freed:

```console
$ cat > view.tach <<'EOF'
> fn main(gpa: Gpa) -> i32 {
>     let words = arena_scope(gpa, |a| {
>         let v = std::split_whitespace_in("scratch words to keep", a);
>         v.as_slice()
>     });
>     println(words[0]);
>     0
> }
> EOF
$ tachyonc check view.tach
$ tachyonc --check-alloc view.tach -o view && ./view
use after release: block #2 (64 bytes) of an arena, allocated at view.tach:3:17, released at view.tach:2:17 (the arena's reset or scope end)
[exit 101]
```

`--check-alloc` gives every arena block pages of their own and takes
their access away when the scope ends, so the first read stops the
program, naming the block, where it was allocated and the scope that
released it. Without the flag the read may print the word, or garbage.
0.17's second-class references make this a compile error too (a view
cannot outlive what it views); [check-alloc](../check-alloc/) has the
other bugs of this kind.

## Read more

- `tachyonc guide allocators`, section "Arenas".
- [arena-parser](../arena-parser/): a whole tree in an arena, timed
  against `Gpa`.
