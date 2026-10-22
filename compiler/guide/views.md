# Views

A *view* points into memory something else owns: a slice `[T]` (a
string literal, `v.as_slice()`, `a[1..3]`), an access field (`q: inout
Query`, `cfg: let Config`), a struct holding one (`Scanner`, `struct Tok
{ text: [u8] }`), a `Vec<[u8]>` of them, a closure that captures by
access. Views are second-class: the checker keeps each one inside what
it views, with no lifetimes to write.

## What a view may do

- Live in locals, parameters, struct fields and containers
  (`Vec<[u8]>`, `HashMap<[u8], i64>`): a parser keeps tokens that view
  its input.
- Be returned when it views a parameter: `fn first_word(s: [u8]) ->
  [u8]`, `fn as_slice(self) -> [T]` on a `Vec<T>`.
- Not outlive its owner: not returned out of the function that owns the
  memory (`own.escape`), not used after its owner changed, moved or was
  dropped (`own.conflict`).
- Statics hold only views of constant data (string literals).

`[T]` is read-only (a let access to elements); `inout [T]` is the
exclusive, writable one: `fn fill(s: inout [i64], x: i64)`, called as
`fill(&a[1..3], 0)`, `fill(&v[..], 0)` or `fill(v.as_mut_slice(), 0)`
(already an access: no `&`). A struct with an `inout` field (`struct
Parser { q: inout Query }`) is a *move-only* view: it moves, it is not
copied, and while it lives `q` is reached only through it.

## Exclusivity

While a view of `x` (or a let access, a let argument) is used later,
nothing writes, moves or drops `x`; while an inout access `&x` is used
later, `x` is reached only through it. Uses end at the last one (not at the end of the block), so a view
that is not used again is no conflict.

```text
let first = v.as_slice();   v.push(4);   first[0]     own.conflict: use first before the push
for x in v { v.push(x); }                             own.conflict: loop over 0..v.len()
f(&a, a)                                              own.conflict: f(&a.x, a.y) is fine
rng.big(1 + rng.next())                               own.conflict: let n = rng.next(); first
v.push(v.len())                                       fine: the receiver is taken after the arguments
```

Disjoint fields do not overlap; `v[i]` and `v[j]` do (`v.swap(i, j)`).

## What a function returns: its view summary

Each function has an inferred summary, like its effects (`guide
effects`): which parameters its result (and what its `inout` parameters
come to hold) points into.

| summary | meaning | e.g. |
|---|---|---|
| `views(self)` | points into what `self` points to | `Vec::as_slice`; a lexer that owns its text, returning `self.src.as_slice()[a..b]` |
| `views(*self)` | carries views `self` holds, not into `self` | a parser returning a token's `text` |
| `views(s)`, `views()` | into parameter `s`; nothing | `first_word(s)`; a function returning a Buf |
| `stores(word)` | what the `inout` parameters may come to hold | `intern(names: inout Vec<[u8]>, word: [u8])` |

`volec query views NAME --why` shows a summary and the line that
makes each part; `#[views(*self)]` on a function pins it (the body is
checked against it, callers use it).

## Parsers and lexers

A parser over tokens that view the input, and a lexer over text its
caller owns, are `views(*self)`: what they return outlives the next
call. This checks clean:

```tach
struct Tok { text: [u8], kind: i64 }
struct Parser { toks: Vec<Tok>, pos: i64 }

impl Parser {
    fn name(inout self) -> [u8] {
        let t = self.toks[self.pos];
        self.pos += 1;
        t.text                        // a view of the input, not of the parser
    }
}

fn main(gpa: Gpa) {
    var p = Parser { toks: Vec::new_in(gpa), pos: 0 };
    p.toks.push(Tok { text: "let", kind: 0 });
    p.toks.push(Tok { text: "x", kind: 1 });
    let a = p.name();
    let b = p.name();                 // a is still fine
    println(f"{a} {b}");
}
```
```out
let x
```

A lexer that *owns* its text (`src: Buf`) and returns views of it is
`views(self)`: the second call (`word(inout self)`) changes the lexer
while the first word still views it.

```text
main.vl:14:13: error[own.conflict] 'lx.word()' may change 'lx' while 'a' (main.vl:13:9) views it; 'a' is used at main.vl:15:16
  help: use the view before the change, keep an index instead of a view, or keep a copy
  try: volec query own main.vl:15:16
```

Let the lexer view text its caller owns (`src: [u8]`: `volec
refactor field Lexer --type src '[u8]'`), or copy each word into a
`Buf`.

## The diagnostics

Each is one line (`check` joins the parts with ` | `), with what
happened and both positions, a `help:` with the fix, and `try:` lines
that run as they are. `volec explain own.conflict` (and the other
codes) has each in full; `volec query own FILE:LINE:COL` shows every
local's state at a position.

```text
main.vl:10:5: error[own.conflict] 'v.push(4)' may change 'v' while 'first' (main.vl:9:9) views it; 'first' is used at main.vl:11:13
  help: use the view before the change, keep an index instead of a view, or keep a copy
  try: volec edit patch main --old 'v.as_slice()' --new 'v.clone()'
  try: volec query own main.vl:11:13

greet.vl:4:5: error[own.escape] 'greet' returns a view of 'b', which is dropped when 'greet' returns
  help: return the owner itself; a caller that wants a view takes '.as_slice()' of it
  try: volec edit patch greet --old '-> [u8]' --new '-> Buf' --old 'b.as_slice()' --new 'b'

main.vl:12:18: error[own.conflict] 'v.push(x)' may change the elements of 'v' while the 'for' at main.vl:12:5 iterates over them
  help: loop over the indexes (the loop sees the elements present when it starts), or collect the new elements and append them after the loop
  try: volec edit patch main --old 'for x in v {' --new 'for i in 0..v.len() { let x = v[i];'

main.vl:6:11: error[own.conflict] 'a' is lent inout to '&a' and inout again to '&a' in the same call
  help: pass disjoint places, copy the plain value out first, or for two elements of one Vec use 'v.swap(i, j)'
```

They are errors by default (`--values=error`). `--values=warn` makes
them warnings; `--values=report` lists them without failing
the build; `--values=off` turns the checks and the drops off (0.16's
semantics, for code not yet migrated by `volec fix --values`).
