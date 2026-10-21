# tachyon in brief

A value has one owner, moves or copies, and is dropped at scope end. A
parameter reads its argument (`x: T`, the default), changes it (`x:
inout T`, called `f(&x)`) or takes it (`x: sink T`). No lifetimes,
macros or `char`.

```tach
struct P { x: i64 }

impl P {
    fn bump(inout self) { self.x += 1; }  // or self, sink self
}

fn total(v: Vec<i64>) -> i64 { v.iter().sum() }      // reads v
fn add(v: inout Vec<i64>, x: i64) { v.push(x); }     // changes it

fn main(gpa: Gpa) -> i32 {                // gpa: the allocator
    let input = read_stdin_in(gpa).unwrap();          // all of stdin, a Buf
    var sc = Scanner::new(input.as_slice());          // next_int(), next_token(), next_line()
    var v: Vec<i64> = Vec::new_in(gpa);   // var: mutable; let: not
    add(&v, sc.next_int().unwrap_or(0));  // &: the callee may change v
    v[0] += 1;                            // checked; v.get(0): the same i64, not an Option
    let s: [u8] = "hi";                   // text is [u8]; 'a' is a u8
    var m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert(s, 0)[0] += 1;        // a one-element view: [0] is the value
    var b = Buf::new_in(gpa);
    b.push_str(s);
    var p = P { x: s.len() + v.len() };   // .len() on all of them
    p.bump();                             // a receiver needs no &
    println(f"{b.as_slice()} {v:?} {p.x} {total(v)}");
    0
}
```

The prelude (`Vec`, `Buf`, `HashMap`, `MinHeap`, `Scanner`,
`read_line`, `parse_int`, `split_in`, `sort`, `cmp_of`, ...) needs no
`use`; the rest: `use std::{is_digit};`. Only constructors and `_in`
functions take an allocator: pass `gpa` down from main.

An access is used as its value: `out = acc`, `n + 1` (`*` is for raw
pointers only); `inout r = &x;` names one, passed on as `f(&r)`. A sink
argument or `let w = v;` moves an owned `v` (`Vec`, `Buf`, ...);
`.clone()` copies. `[u8]` and tuples compare and sort;
`match e` on a let `E` binds into it; `x?`, closures
(`sink ||`), traits, `#[derive(Debug, Eq, Ord)]`. `for x in v`,
`v.get(i)`, `m.get(k)` give copies (in place: `v[i].push(x)`);
`sort_by(|a, b| a - b)` returns an `i64`; `usize` is `i64`; integers
wrap; `as` narrows; no `dyn`, `Box`.

On demand: `tachyonc guide --find WORDS` (`--find read a line`),
`tachyonc guide std` (the most used; `std#the-api`: all),
`tachyonc try 'CODE'` runs a snippet, `tachyonc check main.tach` lists
every error.
