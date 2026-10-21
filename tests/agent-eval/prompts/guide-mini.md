# tachyon in brief

Rust's syntax and value semantics (moves, drops at scope end), but a
parameter takes a convention instead of a reference: `x: T` (let, the
default: read-only, called `f(x)`), `x: inout T` (changed in place,
called `f(&x)`), `x: sink T` (taken: an owned argument moves). No
lifetimes, no macros, no `char`. Each line next to the Rust it replaces:

```tach
struct P { x: i64 }

impl P {
    fn bump(inout self) { self.x += 1; }     // Rust: &mut self; &self is self
}

fn total(v: Vec<i64>) -> i64 { v.iter().sum() }   // let: read, nothing moves (Rust: &Vec)

fn main(gpa: Gpa) -> i32 {                // Rust: fn main()   gpa: the allocator; 0: exit status
    let input = read_stdin_in(gpa).unwrap();          // all of stdin, a Buf
    var sc = Scanner::new(input.as_slice());          // Rust: let mut; next_int(), next_token(), next_line()
    var v: Vec<i64> = Vec::new_in(gpa);       // Rust: Vec::new()
    v.push(sc.next_int().unwrap_or(0));
    v[0] += 1;                                // checked; v.get(0): the same i64, not an Option
    let s: [u8] = "hi";                       // Rust: &str, String: text is [u8]; 'a' is a u8
    var m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert(s, 0)[0] += 1;            // Rust: *m.entry(k).or_insert(0) += 1
    var b = Buf::new_in(gpa);                 // Rust: String::new()
    b.push_str(s);
    var p = P { x: s.len() + v.len() };       // .len() on slices, Vec, Buf, HashMap
    p.bump();                                 // lends p inout
    println(f"{b.as_slice()} {v:?} {p.x} {total(v)}");
    0
}
```

The prelude (`Vec`, `Buf`, `HashMap`, `MinHeap`, `Scanner`,
`read_line`, `parse_int`, `split_in`, `sort`, `cmp_of`, ...) needs no `use`; the rest:
`use std::{is_digit};`. Only constructors and `_in` functions take an
allocator: pass `gpa` down from main as a parameter.

As in Rust: `[u8]` and tuples compare and sort (`==`, `<`, `v.sort()`);
`v[i] = x` through an `inout Vec`; match guards; `let ... else`;
`x?`, closures, traits, `#[derive(Debug, Eq, Ord)]`. Unlike Rust:
`for x in v`, `v.iter()`, `v.get(i)`, `m.get(k)` give copies, not `&T`
(change one in place: `v[i].push(x)`); no `*` on an access (`r = v`,
not `*r = v`); `static var`, `sink ||` for `static mut`, `move ||`;
`sort_by(|a, b| a - b)` returns an
`i64`; `usize` is `i64`; integers wrap; `as` narrows; no `dyn`, `Box`.

On demand: `tachyonc guide --find WORDS` (`--find read a line`),
`tachyonc guide std` (the most used; `std#the-api`: all),
`tachyonc try 'CODE'` runs a snippet, `tachyonc check main.tach` lists
every error.
