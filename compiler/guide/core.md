# tachyon, the core (tachyon 0.17)

Tachyon is a compiled systems language with Rust's syntax and value
semantics (0.17: moves, drops, `&T`/`&mut T`, checked views) but no
lifetimes to write, no macros; nothing allocates without an allocator;
indexing is checked; safe code has no undefined behaviour. This page is the core; the rest is on demand (the end).

## Build and run

```sh
tachyonc main.tach -o prog && ./prog < in.txt   # `mod x;` loads x.tach
tachyonc check main.tach                        # every error, one line each
tachyonc try 'parse_int("42")'                  # a snippet: its TYPE = VALUE
```

## Looks like Rust, means something else

Each `// Rust:` line is followed by the tachyon for it.

```tach
import "stdio.h" as c;                 // a C header; its names under c::
use std::is_digit;                     // Rust: use std::collections::*;  (never *)

struct P { x: i64 }

impl P {
    // Rust: fn bump(&mut self)
    fn bump(self: &mut P) { self.x += 1; } // self written out
    // Rust: fn get(&self) -> i64
    fn get(self: &P) -> i64 { self.x }     // (self: P: a copy, a move if owned)
}

// Rust: fn first(s: &str) -> char
fn first(s: [u8]) -> u8 { s[0] }       // text is [u8]; 'a' is a u8; no char

// Rust: fn odds(n: i64) -> Vec<i64>
fn odds(n: i64, gpa: Gpa) -> Vec<i64> {     // allocating takes an allocator
    (0..n).filter(|i| i % 2 == 1).collect_in(gpa)
}

// Rust: fn main()
fn main(gpa: Gpa) -> i32 {             // gpa: the program's allocator; 0 = exit status
    // Rust: let mut v = Vec::new();
    let mut v: Vec<i64> = Vec::new_in(gpa);  // dropped at scope end, as in Rust
    v.push(5);
    v.push(2);
    v[0] += 10;                        // as Rust: checked (v[1..2] a slice)
    v.sort();                          // as Rust; or sort(v.as_mut_slice())
    // Rust: let mut p = P { x: 1 }; p.bump();
    let mut p = P { x: 1 };
    p.bump();                          // passes &mut p
    // Rust: println!("{} {:?}", p.get(), v);
    println(f"{p.get()} {v:?}");       // no macros: f-strings
    let s = "hi";
    println(s.len());                  // an i64; or the field, s.len
    // Rust: let mut b = String::new(); b.push_str("n="); ...
    let mut b = Buf::new_in(gpa);
    let o = odds(7, gpa);
    b.push_str("n=");
    b.push_int(o.len());
    println(b.as_slice());
    // Rust: match s { "hi" => ..., _ => ... }
    if s == "hi" && !is_digit(first(s)) { println(first(s)); }   // compared, not matched
    // Rust: *m.entry(k).or_insert(0) += 1;
    let mut m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert("k", 0)[0] += 1;
    // Rust: !x on an integer; x.abs(); 7 / 0 panics
    let z = 0;
    println(f"{~0u8} {7 / z} {m.get("k").unwrap()}");   // ~x; no methods on numbers; x / 0 == 0
    // Rust: libc::puts(...) in unsafe -- the same: C calls need unsafe
    unsafe { c::puts(c"from C"); }     // c"..": a NUL-terminated *u8
    if z != 0 { panic("z"); }          // Rust: panic!("z"): exit 101; unreachable()
    0
}
```
```out
2 [2, 15]
2
n=3
104
255 0 1
from C
```

Also: `usize` is `i64` (lengths, indices); integers wrap; `a as i32`
narrows, widening is implicit; `x?`, closures, `impl Trait for T`, `T:
Trait`, `#[derive(Eq, Debug)]` are Rust's; no `dyn`, `where`, `Box` (a
`Vec` or `*T`); `&x` and `&mut x` are references (`&T`, `&mut T`,
0.17), and `p.0`, `p.x` reach through a reference or a pointer. Arguments may have defaults and names: `fn f(a: i64, b: i64 =
2)`, `f(1, b: 3)`. The prelude (no `use`) has `Option`, `Result`, `Vec`,
`Buf`, `HashMap`, `print`, `println`, `format_in`, `Gpa`, `read_line`,
`read_stdin_in`, `Scanner`, `parse_int`, `trim`, `split_in`,
`split_whitespace_in`, `sort`, `sort_by`, `sort_stable_by`, `cmp_of`, `Fmt`, `panic`,
`unreachable`; the rest of std is `use std::{...}`; `use lexer::Tok;`
in a module reaches its sibling `lexer`.

## std: what programs use most

```tach
struct Item { name: [u8], qty: i64 }

fn add(v: &mut Vec<Item>, it: Item) { v.push(it); }   // called as add(&mut items, ..)

fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();   // all of stdin: Result<Buf, IoError>
    let mut sc = Scanner::new(input.as_slice());
    let n = sc.next_int().unwrap();            // Result<i64, ScanError>
    let mut items: Vec<Item> = Vec::new_in(gpa);
    let mut seen: HashMap<[u8], i64> = HashMap::new_in(gpa);
    for _ in 0..n {
        let name = sc.next_token().unwrap();   // Option<[u8]>: a slice of input
        let qty = sc.next_int().unwrap_or(0);
        add(&mut items, Item { name: name, qty: qty });
        seen.insert(name, qty);                // also contains(k), remove(k)
    }
    items.sort_by(|a, b| b.qty - a.qty);       // a, b: &Item; < 0: a first
    for (i, it) in items.iter().enumerate() { print(f"{i}:{it.name} "); }
    let line = trim(sc.next_line().unwrap());  // the rest of the line
    let total = split_in(line, ',', gpa).iter()
        .map(|w| parse_int(trim(w)).unwrap_or(0)).sum();
    match seen.get("pen") {                    // Option<i64>
        Some(q) => println(f"pen={q} total={total}"),
        None => println("no pen"),
    }
    let text = format_in(f"{items.len()} {seen.len()}", gpa);   // a Buf
    println(text.as_slice());                  // text, seen, items, input: dropped at the end
    0
}
```
```in
3 pen 2 ink 5 cap 1 1,2, 3
```
```out
0:ink 1:pen 2:cap pen=2 total=6
3 3
```

Lines one at a time: `let mut b = Buf::new_in(gpa); while
read_line(&mut b).unwrap() { ... }` (without the `'\n'`). An owned
value (`Vec`, `Buf`, `HashMap`, a struct holding one) moves: after `let
w = v;` or `f(v)`, `v` is dead (`own.moved`); take `v: &Vec<T>` (`&mut`
to change it) and pass `&v` (`&mut v`), or `.clone()`. A reference kept
in a local (`let p = &mut st;`) is passed on as `p`, any number of
times. A slice of `v` is a view: take it again after `v` grows. std's most used items: `tachyonc guide std`; all, a line each:
`tachyonc guide std#the-api`; one name
with its comment: `tachyonc guide --find split_in`.

## The first errors and their fixes

| error (short form) | fix |
|---|---|
| `non-exhaustive match: 'E::B' is not covered` | an arm for it, or `_ =>` |
| `calling a C function is unsafe`; `dereference of a raw pointer is unsafe` | `unsafe { ... }`; `tachyonc fix --only unsafe` adds them |
| `no 'collections' in module 'std'`; `unknown type 'String'` | std is one module: `use std::name;` (its most used names need none); text is `[u8]`, built in a `Buf` |
| `allocation is explicit: pass an allocator` | `Vec::new_in(gpa)`, `gpa` from `fn main(gpa: Gpa)` passed down |
| `expected '&mut P', got '&P'` | `&mut x` at the call |
| `own.moved: 'v' is used here after it moved into 'f(v)'` | `f(&v)` with `v: &Vec<T>`, or `f(v.clone())` (the `try:`) |
| `own.conflict: ... while 'first' views them` | use the view before the change, or take it again after (`guide views`) |

Every error has a `help:`; `tachyonc guide errors` has more.

Tests and checks (0.18): `#[test] fn` and `#[property] fn p(v: Vec<i64>)`
(inputs generated, shrunk) sit next to the code and `tachyonc test` runs
them at -O0 and -O2; `requires`/`ensures` clauses and `assert_eq(a, b)`
are checked at run time, a failure one line `FILE:L:C: message` (`guide
testing`, `guide contracts`).

## The loop

Write the program, then `tachyonc check` (a check hook, where there is
one, runs it after each edit); fix the first error first. A clean check
ends with `ok: 0 errors in main.tach`, a build with `ok: built prog`. Before writing a construct
you are unsure of, `tachyonc guide --find WORDS` (`--find read a line`)
or `tachyonc guide TOPIC#SECTION` prints the lines on it; `tachyonc
try 'CODE'` runs a snippet. For an unfamiliar item, ask
`tachyonc query context NAME` first: its source, what it calls and its
callers in one call (`query context parse_args`). Edits, refactorings
and the other queries: `tachyonc guide tools`.

Topics (`tachyonc guide TOPIC`, `TOPIC#` lists its sections):
@TOPIC-NAMES@
