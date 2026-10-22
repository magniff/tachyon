# vole, the core (vole 0.20)

Vole is a compiled systems language of values: a value has one
owner, is copied or moved, and is dropped at the end of its scope. A
function says what it does with each argument: reads it (`let`, the
default), changes it (`inout`, marked `&x` at the call) or takes it
(`sink`). There are no references to store or lifetimes to write; views
(slices, structs holding one) are checked to stay inside what they view.
Nothing allocates without an allocator, indexing is checked, and safe
code has no undefined behaviour. This page is the core; the rest is on
demand (the end). From Rust: `volec guide rust` has the mapping.

## Build and run

```sh
volec main.vl -o prog && ./prog < in.txt   # `mod x;` loads x.vl
volec check main.vl                        # every error, one line each
volec try 'parse_int("42")'                  # a snippet: its TYPE = VALUE
```

## The language in one program

```tach
import "stdio.h" as c;                 // a C header; its names under c::
use std::is_digit;                     // std items by name (never *)

struct P { x: i64 }

impl P {
    fn bump(inout self) { self.x += 1; }   // inout self: changes the caller's P
    fn get(self) -> i64 { self.x }         // self (let): reads it
}

fn total(v: Vec<i64>) -> i64 {         // let (the default): read-only, no copy
    v.iter().sum()
}

fn grow(v: inout Vec<i64>, x: i64) {   // inout: the caller writes grow(&v, x)
    v.push(x);
}

fn keep(all: inout Vec<Vec<i64>>, v: sink Vec<i64>) {   // sink: keep takes v
    all.push(v);
}

fn first(s: [u8]) -> u8 { s[0] }       // text is [u8]; 'a' is a u8; no char

fn odds(n: i64, gpa: Gpa) -> Vec<i64> {     // allocating takes an allocator
    (0..n).filter(|i| i % 2 == 1).collect_in(gpa)
}

fn main(gpa: Gpa) -> i32 {             // gpa: the program's allocator; 0 = exit status
    var v: Vec<i64> = Vec::new_in(gpa);    // var: mutable; let: not
    v.push(5);
    grow(&v, 2);                       // & marks the argument grow may change
    v[0] += 10;                        // checked (v[1..2] a slice)
    v.sort();                          // or sort(v.as_mut_slice())
    var p = P { x: 1 };
    p.bump();                          // a receiver needs no &; p must be var
    println(f"{p.get()} {v:?} {total(v)}");   // f-strings; total(v) only reads
    var all: Vec<Vec<i64>> = Vec::new_in(gpa);
    keep(&all, v);                     // v moved into keep: dead from here
    let s = "hi";
    println(s.len());                  // an i64 (slices, Vec, Buf, HashMap)
    var b = Buf::new_in(gpa);          // a text builder
    let o = odds(7, gpa);
    b.push_str("n=");
    b.push_int(o.len());
    println(b.as_slice());
    if s == "hi" && !is_digit(first(s)) { println(first(s)); }   // compared, not matched
    var m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert("k", 0)[0] += 1;   // a one-element view: [0] is the value
    let z = 0;
    println(f"{~0u8} {7 / z} {m.get("k").unwrap()}");   // ~x; no methods on numbers; x / 0 == 0
    unsafe { c::puts(c"from C"); }     // C calls need unsafe; c"..": a NUL-terminated *u8
    if z != 0 { panic("z"); }          // exit 101; unreachable()
    0
}                                      // all, o, b, m: dropped (freed) here
```
```out
2 [2, 15] 17
2
n=3
104
255 0 1
from C
```

Also: `usize` is `i64` (lengths, indices); integers wrap; `a as i32`
narrows, widening is implicit; `x?`, closures (`|x| x + k`, `sink ||`
to take what it captures), `impl Trait for T`, `T: Trait`,
`#[derive(Eq, Debug)]`; no `dyn`, `where`, `Box`. A let or inout
parameter is used as the value itself: `n + 1`, `out = acc`, `p.x`
(`*` is only for raw `*T` pointers, which need `unsafe`). `inout r =
&st;` names an access to pass on: `f(&r)`, `g(&r)`. `match e` on a let
`e: E` binds into it (`E::A(n) => n + 1`). Arguments may have defaults
and names: `fn f(a: i64, b: i64 = 2)`, `f(1, b: 3)`. The prelude (no
`use`) has `Option`, `Result`, `Vec`, `Buf`, `HashMap`, `BinaryHeap` and
`MinHeap` (priority queues: `pop` the largest, the smallest), `print`,
`println`, `format_in`, `Gpa`, `read_line`, `read_stdin_in`, `Scanner`,
`parse_int`, `trim`, `split_in`, `split_whitespace_in`, `sort`,
`sort_by`, `sort_stable_by`, `cmp_of`, `Fmt`, `panic`, `unreachable`;
the rest of std is `use std::{...}`; `use lexer::Tok;` in a module
reaches its sibling `lexer`.

## std: what programs use most

```tach
struct Item { name: [u8], qty: i64 }

fn add(v: inout Vec<Item>, it: Item) { v.push(it); }   // called as add(&items, ..)

fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();   // all of stdin: Result<Buf, IoError>
    var sc = Scanner::new(input.as_slice());
    let n = sc.next_int().unwrap();            // Result<i64, ScanError>
    var items: Vec<Item> = Vec::new_in(gpa);
    var seen: HashMap<[u8], i64> = HashMap::new_in(gpa);
    for _ in 0..n {
        let name = sc.next_token().unwrap();   // Option<[u8]>: a slice of input
        let qty = sc.next_int().unwrap_or(0);
        add(&items, Item { name: name, qty: qty });
        seen.insert(name, qty);                // also contains(k), remove(k)
    }
    items.sort_by(|a, b| b.qty - a.qty);       // a, b: Item (let); < 0: a first
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

Lines one at a time: `var b = Buf::new_in(gpa); while
read_line(&b).unwrap() { ... }` (without the `'\n'`). An owned value
(`Vec`, `Buf`, `HashMap`, a struct holding one) moves into a `sink`
parameter, a `let w = v;`, a struct field or a `return`: `v` is dead
after it (`own.moved`); pass it to a let parameter to lend it, or pass
`v.clone()`. A plain value (numbers, structs of them) is copied. `&f(x)`
makes a temporary that lives to the end of the block (0.18.1); any other
owned temporary used without being moved (`f()?.read()`,
`make().len()`, `total(make())`) is dropped at the end of its statement,
or of its block when a `let` keeps a view of it (0.25). A slice
of `v` is a view: take it again after `v` grows. std's most used items:
`volec guide std`; all, a line each: `volec guide std#the-api`;
one name with its comment: `volec guide --find split_in`.

## The first errors and their fixes

| error (short form) | fix |
|---|---|
| `conv.marker: 'v' is lent inout here` | `f(&v)`: the callee may change `v` |
| `conv.marker_extra: '&' marks an argument the callee may change` | `f(v)`: a let or sink argument has no `&` |
| `conv.rust: 'let mut' is Rust's spelling` | the `try:` line's form (`var`, `x: inout T`, `self`, `&x`) |
| `cannot assign to immutable variable 'a'` | `var a`; a parameter you change: `a: inout T` |
| `own.moved: 'v' is used here after it moved into 'keep(sink v)'` | lend it (a let parameter), or `keep(v.clone())` |
| `own.conflict: ... while 'first' views them` | use the view before the change, or take it again after (`guide views`) |
| `non-exhaustive match: 'E::B' is not covered` | an arm for it, or `_ =>` |
| `calling a C function is unsafe` | `unsafe { ... }`; `volec fix --only unsafe` adds them |
| `no 'cmp' in module 'std'` | every std item is `std::name` (its most used names need no `use`) |
| `expected 'String', got '[u8]'` | `String::from_in("..", gpa)`: a String owns its text; a parameter `s: str` takes literals and a String's `&s` |
| `allocation is explicit: pass an allocator` | `Vec::new_in(gpa)`, `gpa` from `fn main(gpa: Gpa)` passed down |

Every error has a `help:`; `volec guide errors` has more.

Tests and checks (0.18): `#[test] fn` and `#[property] fn p(v: Vec<i64>)`
(inputs generated, shrunk) sit next to the code and `volec test` runs
them at -O0 and -O2; `requires`/`ensures` clauses and `assert_eq(a, b)`
are checked at run time, a failure one line `FILE:L:C: message` (`guide
testing`, `guide contracts`).

SIMD and CPU intrinsics (0.19): `std::arch`, the vendors' names (`vaddq_u8`,
`__crc32cd`) checked against the CPU: `volec guide arch`; `query arch WORDS`.
GPU compute and rendering (0.22): `std::gpu`, wgpu's objects on Metal: `volec guide gpu`.

## The loop

Write the program, then `volec check` (a check hook, where there is
one, runs it after each edit); fix the first error first. A clean check
ends with `ok: 0 errors in main.vl`, a build with `ok: built prog`. Before writing a construct
you are unsure of, `volec guide --find WORDS` (`--find read a line`)
or `volec guide TOPIC#SECTION` prints the lines on it; `volec
try 'CODE'` runs a snippet. For an unfamiliar item, ask
`volec query context NAME` first: its source, what it calls and its
callers in one call (`query context parse_args`). Edits, refactorings
and the other queries: `volec guide tools`.

Topics (`volec guide TOPIC`, `TOPIC#` lists its sections):
@TOPIC-NAMES@
