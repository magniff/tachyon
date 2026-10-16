# A whole program (0.17)

One complete program, written the way tachyon code is written: modules
and `use`, enums with data and `match`, `Result` and `?`, `Vec`,
`HashMap`, `Buf`, text as `[u8]`, a sort closure, f-strings, the
allocator passed down from `main`, and a test case. A program of this
kind needs only what it shows: copy its patterns.

`stock` reads commands from stdin, one a line, and prints a line for
each command it rejects and the report it is asked for. It has three
files next to each other: `tachyonc main.tach -o prog` builds them all.

```tach main.tach
// stock: a ledger of items. Reads commands from stdin, one a line; prints
// the report it is asked for, and a line for each command it rejects.
mod command;
mod store;

use command::{Error, parse};
use store::Store;

fn main(gpa: Gpa) -> i32 {
    let input = read_stdin_in(gpa).unwrap();    // all of stdin, a Buf
    let mut store = Store::new(gpa);            // it allocates: give it gpa
    let mut sc = Scanner::new(input.as_slice());
    let mut line_no = 0;
    while let Some(raw) = sc.next_line() {      // a line, without its '\n'
        line_no += 1;
        let line = trim(cut_comment(raw));      // views into input: no copies
        if line.len() == 0 {
            continue;
        }
        if let Err(e) = run(&mut store, line, gpa) { // run may change store
            println(f"line {line_no}: {e}");    // Error has Display
        }
    }
    0
}                                               // store, then input, dropped (freed)

// One line: parsed, then applied; `?` passes the first Err up.
fn run(store: &mut Store, line: [u8], gpa: Gpa) -> Result<(), Error> {
    let cmd = parse(line, gpa)?;
    store.apply(cmd)
}

// s up to its first '#'.
fn cut_comment(s: [u8]) -> [u8] {
    for i in 0..s.len() {
        if s[i] == '#' {                        // '#' is a u8
            return s[..i];                      // a slice of s: s[a..b], s[a..]
        }
    }
    s
}
```

```tach command.tach
// A line of input as a Command, or the Error that rejects it.

// pub on a struct makes its fields visible with it. Clone: Vec::clone
// needs it (the derives: Eq, Ord, Hash, Debug, Clone).
#[derive(Clone)]
pub struct Item { name: [u8], count: i64, price: i64 }

// Variants carry data, tuple-like or struct-like, as in Rust.
pub enum Command {
    Add(Item),
    Sell { name: [u8], count: i64 },
    Report,
}

pub enum Error {
    Unknown([u8]),
    Arity([u8], i64),
    BadNumber([u8]),
    NoItem([u8]),
    Short([u8], i64),
}

// What `{e}` in an f-string prints.
impl Display for Error {
    fn fmt(self: &Error, f: &mut Fmt) {
        match *self {
            Error::Unknown(w) => f.write(f"unknown command {w}"),
            Error::Arity(w, n) => f.write(f"{w} takes {n - 1} arguments"),
            Error::BadNumber(w) => f.write(f"not a number: {w}"),
            Error::NoItem(name) => f.write(f"no item {name}"),
            Error::Short(name, have) => f.write(f"only {have} {name} left"),
        }
    }
}

// `add NAME COUNT PRICE`, `sell NAME COUNT` or `report`.
pub fn parse(line: [u8], gpa: Gpa) -> Result<Command, Error> {
    let words = split_whitespace_in(line, gpa); // Vec<[u8]>: views into line
    let w = words.as_slice();                   // [[u8]]
    let verb = w[0];
    if verb == "add" {                          // text is compared with ==, not matched
        arity(w, 4)?;
        let item = Item { name: w[1], count: number(w[2])?, price: number(w[3])? };
        Ok(Command::Add(item))
    } else if verb == "sell" {
        arity(w, 3)?;
        Ok(Command::Sell { name: w[1], count: number(w[2])? })
    } else if verb == "report" {
        Ok(Command::Report)
    } else {
        Err(Error::Unknown(verb))
    }
}

fn arity(w: [[u8]], n: i64) -> Result<(), Error> {
    if w.len() != n {
        return Err(Error::Arity(w[0], n));
    }
    Ok(())
}

// A count or a price: a number, not negative.
fn number(w: [u8]) -> Result<i64, Error> {
    match parse_int(w) {
        Ok(n) if n >= 0 => Ok(n),
        _ => Err(Error::BadNumber(w)),
    }
}
```

```tach store.tach
// The items in stock, in the order they were first added.

use command::{Command, Error, Item};

pub struct Store {
    items: Vec<Item>,
    index: HashMap<[u8], i64>,                  // name -> its position in items
}

impl Store {
    pub fn new(gpa: Gpa) -> Store {
        Store { items: Vec::new_in(gpa), index: HashMap::new_in(gpa) }
    }

    // No free: a Store drops its fields (items, then index) when it is dropped.

    pub fn apply(self: &mut Store, cmd: Command) -> Result<(), Error> {
        match cmd {
            Command::Add(item) => match self.index.get(item.name) {
                Some(i) => {
                    self.items[i].count += item.count;
                    self.items[i].price = item.price;
                }
                None => {
                    self.index.insert(item.name, self.items.len());
                    self.items.push(item);
                }
            },
            Command::Sell { name, count } => {
                let i = self.index.get(name).ok_or(Error::NoItem(name))?;
                let have = self.items[i].count;
                if have < count {
                    return Err(Error::Short(name, have));
                }
                self.items[i].count = have - count;
            }
            Command::Report => self.report(),
        }
        Ok(())
    }

    // The items by value, highest first, ties by name; then the total.
    fn report(self: &Store) {
        let gpa = self.items.allocator();       // a Vec's allocator, to allocate with
        let mut order = self.items.clone();     // a copy (in that allocator)
        order.sort_by(|a, b| {                  // a, b: &Item; < 0: a goes first
            let d = value(*b) - value(*a);
            if d != 0 { d } else { cmp_of(&a.name, &b.name) }   // cmp_of takes references
        });
        let mut out = Buf::new_in(gpa);         // Rust's String
        let mut total = 0;
        for it in order {
            out.push_fmt(f"{it.name:<5}{it.count:>3} x {it.price:>2} = {value(it)}\n");
            total += value(it);
        }
        out.push_str("total ");
        out.push_int(total);
        println(out.as_slice());
    }
}

fn value(it: Item) -> i64 {
    it.count * it.price
}
```

A test case is two files: the input in `tests/basic.in`, the expected
output in `tests/basic.out`. `tachyonc test` builds the program and runs
every case (`test main.tach: 1 passed (tests/)`, or the first lines that
differ):

```in
# a day at the shop
add pen 10 3
add ink 4 12
add cap 6 8   # caps arrived
sell pen 3
sell hat 1
add pen x 2
sell ink 9
add ink 1 12
refund pen 1
sell cap
report
```
```out
line 6: no item hat
line 7: not a number: x
line 8: only 4 ink left
line 10: unknown command refund
line 11: sell takes 2 arguments
ink    5 x 12 = 60
cap    6 x  8 = 48
pen    7 x  3 = 21
total 129
```

## What differs from Rust here

- Text is `[u8]`, a view: `trim`, `split_whitespace_in`, `s[a..b]`
  copy nothing. A name stays valid while the buffer it views lives,
  here `input`, until `main` returns. Text is compared with `==` and `<`;
  `match` has no string patterns.
- Enum variants are tuple-like or struct-like; patterns as in Rust, with
  guards (`Ok(n) if n >= 0`), `if let`, `while let`. Matching a
  reference matches what it points to: `match self` binds references
  into it (0.18.1, `n: &i64`, read as `*n`), `match *self` copies.
- `#[derive(Eq, Ord, Hash, Debug, Clone)]` (no `PartialEq`, no `Copy`
  derive: a struct of numbers and views, as `Item`, copies; one holding a
  `Vec`, `Buf` or `HashMap`, as `Store`, moves). `Display` is written by
  hand, with `f.write(f"..")`; its `self: &Self` is a reference.
- Nothing allocates without an allocator. `main` gets `gpa` and passes
  it down. A function that allocates takes `gpa: Gpa`; one holding a
  `Vec` can use `v.allocator()`. Nothing is freed by hand: a value is
  dropped at the end of its scope (`tachyonc guide memory`).
- `self: &T` and `self: &mut T` are `&self` and `&mut self`; `&x` and
  `&mut x` give `&T` and `&mut T`; fields are reached through them with `.`.
- Comparators return an `i64` (negative: `a` first) and take
  references: `sort_by(|a, b| ..)`, `cmp_of(&x, &y)`.
- `Buf` is Rust's `String`: `push_str`, `push_int`, `push_fmt(f"..")`,
  `as_slice()`.
