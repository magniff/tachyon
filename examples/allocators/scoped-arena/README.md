# Scratch memory per request: `arena_scope`

A small key-value store that answers one request per line of stdin
(`SET key n`, `ADD key n`, `GET key`, `SUM key...`). Every request needs
memory for a moment: its words, its keys in lowercase, the text of its
response. All of it comes from an arena made for that request and freed,
at once, when the request is answered:

```tach
let used = arena_scope(gpa, |scratch| {
    var out = Buf::new_in(scratch);
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
8 requests, 2 keys; scratch per request at most 104 bytes
the keys' arena holds 11 bytes
ok: built store
```

No request frees anything by hand, and none leaks: `--check-alloc`
(which lists every block not freed at exit, and traps a use of an
arena's block after its scope) has nothing to say.

```console
$ tachyonc --check-alloc main.tach -o store-checked && ./store-checked < requests.txt | tail -1
the keys' arena holds 11 bytes
ok: built store-checked
```

## How it works

`arena_scope(gpa, f)` makes an arena whose memory comes from `gpa`,
calls `f` with a handle to it (a `ScopedArena`), and frees the arena
when `f` returns; it returns what `f` returns. Allocating from it is
bumping a pointer, and freeing a block inside it is nothing (but for
the last one, which the pointer gives back): the scope's end frees
everything. An 8 KB chunk is enough for every request here: the busiest
one used 104 bytes.

`answer` does not know or care what kind of allocator it is given:

```tach
fn answer<A: Allocator>(store: inout Store, line: [u8], scratch: sink A, out: inout Buf<A>)
```

Inside, every temporary is made on `scratch`:
`split_whitespace_in(line, scratch)`, `lower_in(w[1], scratch)` (a
lowercased copy), a `Buf` listing the missing keys of a `SUM`. Each is
dropped at the end of its scope, which on an arena frees nothing: the
scope's end frees it all. The response is written into `out`, a `Buf`
on the same arena.

A known key's value changes in place, through `get_mut`. A new key must
outlive the request, so it is copied out of the scratch into the store's
own arena before it goes into the map:

```tach
match store.values.get_mut(key.as_slice()) {
    // A known key: its value changes in place.
    Some(v) => v[0] = new,
    // A new key: its bytes go where the map's keys live.
    None => {
        store.values.insert(intern(store.names, key.as_slice()), new);
    }
}
```

`intern` copies the bytes into `names`, an `Arena` made once in `main`
(`Arena::new_in(gpa)`) and freed at the end (`unsafe { names.free_all()
}`: unsafe because a view into it could still be used after). The view
it returns lives as long as the arena, not as long as the `Vec` that
copied the bytes there, which 0.17's safe code cannot say (a view of a
`Vec` ends when the `Vec` is dropped; arena references are 0.17.1's).
So `intern` forgets the `Vec` and makes the view from its pointer, in
`unsafe`:

```tach
fn intern(names: Arena, s: [u8]) -> [u8] {
    var v: Vec<u8, Arena> = Vec::with_capacity_in(s.len(), names);
    v.extend_from_slice(s);
    let p = v.as_slice().ptr;
    std::forget(v);
    unsafe { p[0..s.len()] }
}
```

## What the effects say

```console
$ tachyonc query effects crate
crate::intern	alloc(Arena) panic unsafe
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
>         var seen: Vec<i64, ScopedArena> = Vec::new_in(outer);
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

## Nor can a view of it

A slice is a view: it holds no allocator, so its type says nothing about
where its bytes live. A view of a scope's container returned from the
scope would point at memory the scope's end freed (0.16 compiled it, and
only `--check-alloc` caught the read). The view cannot outlive the `Vec`
it views, which is dropped when the scope's closure returns:

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
view.tach:4:9: error[own.escape] 'closure(ScopedArena) -> [[u8]] at view.tach:2:34' returns a view of 'v', which is dropped when 'closure(ScopedArena) -> [[u8]] at view.tach:2:34' returns | help: return the owner itself; a caller that wants a view takes '.as_slice()' of it | try: tachyonc edit patch closure(ScopedArena) -> [[u8]] at view.tach:2:34 --old '-> [[u8]]' --new '-> Vec<[u8], ScopedArena>' --old 'v.as_slice()' --new 'v'
[exit 1]
```

[check-alloc](../check-alloc/) has the other bugs of this kind, and how
`--check-alloc` catches them at run time in code built with
`--values=off`.

## Read more

- `tachyonc guide allocators`, section "Arenas".
- [arena-parser](../arena-parser/): a whole tree in an arena, timed
  against `Gpa`.
