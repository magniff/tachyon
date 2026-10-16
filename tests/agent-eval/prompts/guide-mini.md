# tachyon in brief

Rust's syntax and value semantics (moves, drops at scope end, checked
`&T`/`&mut T`), but no lifetimes to write, no macros, no `char`. Each
line next to the Rust it replaces:

```tach
struct P { x: i64 }

impl P {
    fn bump(self: &mut P) { self.x += 1; }   // Rust: &mut self; &self is self: &P
}

fn total(v: &Vec<i64>) -> i64 { v.iter().sum() }  // a Vec (or a struct with one) moves

fn main(gpa: Gpa) -> i32 {                // Rust: fn main()   gpa: the allocator; 0: exit status
    let input = read_stdin_in(gpa).unwrap();          // all of stdin, a Buf
    let mut sc = Scanner::new(input.as_slice());      // next_int(), next_token(), next_line()
    let mut v: Vec<i64> = Vec::new_in(gpa);   // Rust: Vec::new()
    v.push(sc.next_int().unwrap_or(0));
    v[0] += 1;                                // checked; v.get(0): the same i64, not an Option
    let s: [u8] = "hi";                       // Rust: &str, String: text is [u8]; 'a' is a u8
    let mut m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert(s, 0)[0] += 1;            // Rust: *m.entry(k).or_insert(0) += 1
    let mut b = Buf::new_in(gpa);             // Rust: String::new()
    b.push_str(s);
    let mut p = P { x: s.len() + v.len() };   // .len() on slices, Vec, Buf, HashMap
    p.bump();                                 // passes &mut p
    println(f"{b.as_slice()} {v:?} {p.x} {total(&v)}");
    0
}
```

The prelude (`Vec`, `Buf`, `HashMap`, `Scanner`, `read_line`,
`parse_int`, `split_in`, `sort`, `cmp_of`, ...) needs no `use`; the rest:
`use std::{is_digit};`. Only constructors and `_in` functions take an
allocator: pass `gpa` down from main as a parameter.

As in Rust: `[u8]` and tuples compare and sort (`==`, `<`, `v.sort()`);
`let (a, b) = f();`; `for b in s` yields bytes; `v[i] = x` through
`&mut Vec`; `&&` short-circuits; `/` truncates; `if` is an expression;
match guards; `{v[i]}` in f-strings; `for (k, x) in m.iter()`; `x?`,
closures, traits, `#[derive(Debug, Eq, Ord)]`. Unlike Rust: no `let
... else`; match a `&E` as `match *e`; `&f()` needs a `let`;
`sort_by(|a, b| *a - *b)` returns an `i64`; `usize` is `i64`; integers
wrap; `as` narrows; no `dyn`, `Box`, `where`.

On demand: `tachyonc guide --find WORDS` (`--find read a line`),
`tachyonc guide std` (the most used; `std#the-api`: all),
`tachyonc try 'CODE'` runs a snippet, `tachyonc check main.tach` lists
every error.
