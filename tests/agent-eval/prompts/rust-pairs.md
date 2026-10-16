# Rust -> tachyon, side by side

Tachyon looks like Rust; what differs is shown below as pairs: each
`// Rust:` comment is the Rust you would write, the line under it is the
tachyon for it. Both programs compile and run as shown (`tachyonc
main.tach -o prog && ./prog < in.txt`). There are no macros, no `String`
(text is `[u8]`, built with `std::Buf`), no lifetimes to write (`&T`,
`&mut T` and moves are checked as in Rust; values drop at scope end), and
nothing allocates without the allocator `gpa` that `main` receives.

```tach
use std::{Buf, HashMap, Scanner, read_stdin_in, sort};

// Rust: #[derive(Debug, Clone, PartialEq)] struct Item { name: String, qty: i64 }
#[derive(Debug, Clone)]
struct Item { name: [u8], qty: i64 }

// Rust: enum Cmd { Add { name: String, n: i64 }, Show }
enum Cmd { Add([u8], i64), Show }

// Rust: impl Item { fn total(&self, k: i64) -> i64 { ... } }
impl Item {
    fn total(self: &Item, k: i64) -> i64 { self.qty * k }
    // Rust: fn bump(&mut self) { self.qty += 1; }
    fn bump(self: &mut Item) { self.qty += 1; }
}

// Rust: fn parse(line: &str) -> Option<Cmd>
fn parse(line: [u8]) -> Option<Cmd> {
    // Rust: let words: Vec<&str> = line.split_whitespace().collect();
    let mut sc = Scanner::new(line);
    // Rust: match words[0] { "add" => ..., "show" => ..., _ => None }
    let w = sc.next_token()?;
    if w == "add" {
        let name = sc.next_token()?;
        // Rust: let n: i64 = words[2].parse().ok()?;
        let n = sc.next_int().ok()?;
        return Some(Cmd::Add(name, n));
    }
    if w == "show" { return Some(Cmd::Show); }
    None
}

// Rust: fn main() { let mut s = String::new(); io::stdin().read_to_string(&mut s).unwrap(); ... }
fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();
    // Rust: let mut counts: HashMap<String, i64> = HashMap::new();
    let mut counts: HashMap<[u8], i64> = HashMap::new_in(gpa);
    // Rust: let mut items: Vec<Item> = Vec::new();
    let mut items: Vec<Item> = Vec::new_in(gpa);
    // Rust: let mut out = String::new();
    let mut out = Buf::new_in(gpa);
    // Rust: for line in s.lines() {
    let mut sc = Scanner::new(input.as_slice());
    while let Some(line) = sc.next_line() {
        match parse(line) {
            // Rust: Some(Cmd::Add { name, n }) => { *counts.entry(name).or_insert(0) += n; }
            Some(Cmd::Add(name, n)) => {
                counts.get_or_insert(name, 0)[0] += n;
                items.push(Item { name: name, qty: n });
            }
            Some(Cmd::Show) => {
                // Rust: writeln!(out, "{} items, first {:?}", items.len(), items[0]);
                if items.len() > 0 {
                    out.push_fmt(f"{items.len()} items, first {items.get(0):?}\n");
                }
            }
            // Rust: None => eprintln!("bad line: {}", line),
            None => eprintln(f"bad line: {line}"),
        }
    }
    // Rust: items[0].bump();  (an element in place)
    if items.len() > 0 { items.as_mut_slice()[0].bump(); }
    // Rust: let total: i64 = items.iter().map(|it| it.qty).sum();
    let total: i64 = items.iter().map(|it| it.qty).sum();
    // Rust: let mut qs: Vec<i64> = ...; qs.sort();
    let mut qs: Vec<i64> = items.iter().map(|it| it.qty).collect_in(gpa);
    sort(qs.as_mut_slice());
    // Rust: if let Some(n) = counts.get("a") { ... }
    if let Some(n) = counts.get("a") { out.push_fmt(f"a: {n}\n"); }
    // Rust: println!("{}", total); (formatted with {:>5})
    out.push_fmt(f"total {total:>5}, smallest {qs.get(0)}\n");
    print(out.as_slice());
    0
}
```

With `add a 3`, `add b 4`, `show`, `add a 2`, `oops` on stdin it prints
`bad line: oops` on stderr and:

```out
2 items, first Item { name: "a", qty: 3 }
a: 5
total    10, smallest 2
```

```tach
// Rust: use std::collections::HashMap; use std::io::*;
use std::{Buf, parse_int, trim};

// Rust: extern "C" { fn abs(x: i32) -> i32; }  (calls in unsafe, as in Rust)
extern "C" { fn abs(x: i32) -> i32; }

enum Op { Push(i64), Pop, Neg }

// Rust: fn apply(stack: &mut Vec<i64>, op: &Op) -> Result<(), String>
fn apply(stack: &mut Vec<i64>, op: Op) -> Result<(), [u8]> {
    // Rust: match op { ... }  (every variant covered, or `_ =>`)
    match op {
        Op::Push(n) => stack.push(n),
        // Rust: let x = stack.pop().ok_or("empty")?;
        Op::Pop => { stack.pop().ok_or("empty")?; }
        Op::Neg => {
            let x = stack.pop().ok_or("empty")?;
            stack.push(-x);
        }
    }
    Ok(())
}

// Rust: fn first_word(s: &str) -> &str
fn first_word(s: [u8]) -> [u8] {
    // Rust: for (i, b) in s.bytes().enumerate() { if b == b' ' { return &s[..i]; } }
    for (i, b) in s.iter().enumerate() {
        if b == ' ' { return s[..i]; }
    }
    s
}

fn main(gpa: Gpa) -> i32 {
    let mut st: Vec<i64> = Vec::new_in(gpa);
    // Rust: apply(&mut st, &Op::Push(5)).unwrap();
    apply(&mut st, Op::Push(5)).unwrap();
    apply(&mut st, Op::Neg).unwrap();
    // Rust: if let Err(e) = apply(...) { eprintln!("{}", e); }
    if let Err(e) = apply(&mut st, Op::Pop) { println(f"error: {e}"); }
    if let Err(e) = apply(&mut st, Op::Pop) { println(f"error: {e}"); }
    // Rust: let n: i64 = " 42 ".trim().parse().unwrap();
    let n = parse_int(trim(" 42 ")).unwrap();
    // Rust: let a = (-7i32).abs();  (no methods on numbers: C's, or write it)
    let a = unsafe { abs(-7) };
    // Rust: let s = format!("{}-{}", n, a);
    let s = format_in(f"{n}-{a}", gpa);
    // Rust: s.len(), &s[0..2], s.as_bytes()[0] == b'4'
    println(f"{s.as_slice()} {s.len()} {s.as_slice()[0..2]} {s.as_slice()[0] == '4'}");
    println(first_word("hello world"));
    // Rust: let x: u8 = 250u8.wrapping_add(10);  (tachyon integers always wrap)
    let x: u8 = 250 + 10;
    // Rust: let q = 7 / 0;  panics; here 0, and 7 % 0 == 7
    let z = 0;
    println(f"{x} {7 / z} {7 % z} {~0}");
    0
}
```
```out
error: empty
42-7 4 42 true
hello
4 0 7 -1
```

More pairs, one line each:

- `use std::collections::HashMap;` -> `use std::HashMap;` (std is one
  module: `use std::{Buf, HashMap, Scanner};`); `use a::*;` -> name each item.
- `String::from("x")`, `&str` -> `"x"` (a `[u8]`); `s.len()` -> `s.len`
  (a field) on a `[u8]`, `v.len()` on a `Vec` or `Buf`.
- `v[i]` on a `Vec` -> `v.get(i)`, `v.set(i, x)`, `v.as_slice()[i]`.
- `Box<T>`, `Rc<T>` -> a `Vec<T>` and indices; `&x`, `&mut x`, `&T`,
  `&mut T` as in Rust (a reference is not returned: return an index or the
  owner); `&mut v[..]` / `v.as_mut_slice()` to write a slice.
- `impl Display` / `{:?}` -> `#[derive(Debug)]` and `f"{x:?}"`; `println!`
  -> `println(f"...")`; `format!` -> `format_in(f"...", gpa)` (a `Buf`).
- `panic!("m")` -> `unsafe { std::panic(c"m") }`; `process::exit(n)` ->
  `return n;` from `main`.
- `(0..n).rev()` -> `while i > 0 { i -= 1; ... }`; `match s { "a" => .. }`
  -> `if s == "a" { .. }` (strings are not patterns).
- `char` -> `u8` (`'a'`); `usize` -> `i64` for lengths and indices.

`tachyonc guide rust` has the full table; `tachyonc guide TOPIC` the rest.
