# Views

A *view* points into memory something else owns: a slice `[T]` (a
string literal, `v.as_slice()`, `a[1..3]`), a reference `&T` or `&mut
T`, a struct holding one (`Scanner`, `struct Tok { text: [u8] }`), a
`Vec<[u8]>` of them, a closure capturing by reference. Views are
second-class (0.17): the checker keeps each one inside what it views,
with no lifetimes to write.

## What a view may do

- Live in locals, parameters, struct fields and containers
  (`Vec<[u8]>`, `HashMap<[u8], i64>`): a parser keeps tokens that view
  its input.
- Be returned when it views a parameter: `fn first_word(s: [u8]) ->
  [u8]`, `fn as_slice(self: &Vec<T>) -> [T]`.
- Not outlive its owner: not returned out of the function that owns the
  memory (`own.escape`), not used after its owner changed, moved or was
  dropped (`own.conflict`).
- Statics hold only views of constant data (string literals).

`[T]` is read-only; `&mut [T]` (`v.as_mut_slice()`, `&mut a[..]`) is the
exclusive, writable one: `fn fill(s: &mut [i64], x: i64)`.

## Exclusivity

While a view or a `&` of `x` is used later, nothing writes, moves or
drops `x`; while a `&mut x` is used later, `x` is reached only through
it. Uses end at the last one (not at the end of the block), so a view
that is not used again is no conflict.

```text
let first = v.as_slice();   v.push(4);   first[0]     own.conflict: use first before the push
for x in v { v.push(x); }                             own.conflict: loop over 0..v.len()
f(&mut a, &a)                                         own.conflict: f(&mut a.x, &a.y) is fine
rng.big(1 + rng.next())                               own.conflict: let n = rng.next(); first
v.push(v.len())                                       fine: the receiver is taken after the arguments
```

Disjoint fields do not overlap; `v[i]` and `v[j]` do (`v.swap(i, j)`).

## What a function returns: its view summary

Each function has an inferred summary, like its effects (`guide
effects`): which parameters its result (and what its `&mut` parameters
come to hold) points into.

| summary | meaning | e.g. |
|---|---|---|
| `views(self)` | points into what `self` points to | `Vec::as_slice`; a lexer that owns its text, returning `self.src.as_slice()[a..b]` |
| `views(*self)` | carries views `self` holds, not into `self` | a parser returning a token's `text` |
| `views(s)`, `views()` | into parameter `s`; nothing | `first_word(s)`; a function returning a Buf |
| `stores(word)` | what the `&mut` parameters may come to hold | `intern(names: &mut Vec<[u8]>, word: [u8])` |

`tachyonc query views NAME --why` shows a summary and the line that
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
    fn name(self: &mut Parser) -> [u8] {
        let t = self.toks[self.pos];
        self.pos += 1;
        t.text                        // a view of the input, not of the parser
    }
}

fn main(gpa: Gpa) {
    let mut p = Parser { toks: Vec::new_in(gpa), pos: 0 };
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
`views(self)`: the second call changes the lexer while the first word
still views it, which Rust rejects too.

```text
main.tach:12:13: error[own.conflict] 'lx.word()' borrows 'lx' mutably while 'a' (11:13) views it; 'a' is used at 13:16
  help: 'Lexer::word' is views(self): it returns 'self.src.as_slice()[a..b]' (lex.tach:9:5), a view of the Buf the lexer owns. Let the lexer view text its caller owns ('src: [u8]'), or copy each word
  try: tachyonc refactor field Lexer --type src '[u8]' --default '$src.as_slice()'
  try: tachyonc edit patch main.tach:11 --old 'lx.word()' --new 'Buf::from(lx.word())'
```

## The diagnostics

Each is one line (`check` joins the parts with ` | `), with what
happened and both positions, a `help:` with the fix, and `try:` lines
that run as they are. `tachyonc explain own.conflict` (and the other
codes) has each in full; `tachyonc query own FILE:LINE:COL` shows every
local's state at a position.

```text
main.tach:5:5: error[own.conflict] 'v.push(4)' may move v's elements while 'first' (4:17) views them; 'first' is used at 6:16
  help: use 'first' before the push, keep an index instead of a view, or keep a copy
  try: tachyonc edit patch main.tach:4 --old 'v.as_slice()' --new 'v.clone()'
  try: tachyonc query own main.tach:6:16

greet.tach:3:5: error[own.escape] 'greet' returns a view of 'b', which is dropped when 'greet' returns
  help: return the Buf itself; a caller that wants a view takes '.as_slice()' of it
  try: tachyonc edit patch greet --old '-> [u8]' --new '-> Buf' --old 'b.as_slice()' --new 'b'

main.tach:7:30: error[own.conflict] 'v.push' may move v's elements while the 'for' at 7:1 iterates over them
  help: loop over the indexes, or collect the new elements and append them after the loop
  try: tachyonc edit patch main.tach:7 --old 'for x in v {' --new 'for i in 0..v.len() { let x = v[i];'
```

`--values=warn` (0.17 only) makes them warnings; `--values=report`
lists them without failing the build.
