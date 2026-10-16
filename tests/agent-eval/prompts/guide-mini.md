# tachyon in brief

Rust's syntax and value semantics (moves, drops at scope end, checked
`&T`/`&mut T`), but no lifetimes to write, no macros, no `char`. The differences that matter most, each next to the Rust
it replaces:

```tach
use std::{Buf, HashMap, Scanner, read_stdin_in};   // Rust: use std::collections::HashMap;

struct P { x: i64 }

impl P {
    fn bump(self: &mut P) { self.x += 1; }   // Rust: &mut self   (self written out)
    fn get(self: &P) -> i64 { self.x }       // Rust: &self
}

fn total(v: &Vec<i64>) -> i64 { v.iter().sum() }  // a Vec passed by value moves, as in Rust

fn main(gpa: Gpa) -> i32 {                // Rust: fn main()   gpa: the allocator; 0: exit status
    let input = read_stdin_in(gpa).unwrap();          // all of stdin, a Buf
    let mut sc = Scanner::new(input.as_slice());      // next_int(), next_token(), next_line()
    let n = sc.next_int().unwrap_or(0);
    let mut v: Vec<i64> = Vec::new_in(gpa);   // Rust: Vec::new()   allocating takes an allocator
    v.push(n);
    v[0] += 1;                                // as Rust: checked; v.get(0), v.set(0, x) too
    let s: [u8] = "hi";                       // Rust: &str, String: text is [u8]; 'a' is a u8
    let k = s.len + v.len();                  // a slice's .len is a field; Vec's .len() a method
    let mut m: HashMap<[u8], i64> = HashMap::new_in(gpa);
    m.get_or_insert(s, 0)[0] += 1;            // Rust: *m.entry(k).or_insert(0) += 1
    let mut b = Buf::new_in(gpa);             // Rust: String::new()
    b.push_str("k=");
    b.push_int(k);
    let mut p = P { x: 1 };
    p.bump();                                 // passes &mut p
    if s == "hi" {                            // strings are compared with ==, not matched
        println(f"{b.as_slice()} {v:?} {p.get()} {total(&v)}");   // Rust: println!(..): f-strings
    }
    0
}
```

Also: std is one module, imported by name (`use std::{HashMap};`, never
`std::collections` or `*`); `usize` is `i64`; integers wrap; `as` narrows;
C calls and raw-pointer reads need `unsafe { }`; `x?`, closures,
iterators, traits, `#[derive(Debug)]` are as in Rust; no `dyn`, `Box`,
`where`.

Everything else is on demand: `tachyonc guide --find WORDS` (`--find read
a line`, `--find split_in`), `tachyonc guide TOPIC` (`std`: the API, a
line per item; `errors`, `rust`, ...), `tachyonc try 'CODE'` runs a
snippet, `tachyonc check main.tach` lists every error.
