# Formatting and derive (0.15)

f-strings, the `Display` and `Debug` traits, the generic `print`
family, and `#[derive]`.

## f-strings

`f"text {expr} text"` is formatted text: each hole `{expr}` is a value
whose type has `Display` (`{expr:?}`: `Debug`). It is a value too (an
`std::Interp`), passed to anything taking `T: Display`: `print`,
`println`, `eprint`, `eprintln` (stderr), `format` (a new `Buf`, the
caller owns it), `b.push_fmt(..)` (appends to a `Buf`; 0.17:
`b.push_str(f"..")` is the same call), `f.write(..)` (inside a Display
impl). A plain `"..."` never formats: `"{x}"` is
those three bytes (a literal holding `{name}` of a local passed to
`println` gets a warning, `try: f"..."`).

- `{{` and `}}` are a brace; the text takes a string's escapes.
- A hole holds any expression but a top-level `:` (parenthesize it);
  string literals work in it (`{m.get("k"):?}`); f-strings do not nest.
- The holes are evaluated where the f-string is written, once, left to
  right; the value holds copies, so it can be stored and printed later.
- The spec after `:` is `[<|>][0][width][.precision][?|x|X|b|c|e|E]`:
  `<` and `>` align (numbers go right by default, text left), `0` pads
  with zeros, `.N` gives a float N decimals, `?` is Debug, `x`/`X` hex,
  `b` binary, `c` a `u8` as its byte (a `u8` is a number otherwise),
  `e`/`E` a float with an exponent (0.20: `1.5e3`).
- Floats print the shortest text that reads back as the same value
  (`2.5`, `0.1`), byte for byte as Rust prints them (#numbers).
- (0.17) Passed straight to `print`, `println`, `eprint`, `eprintln`,
  `format_in` or `b.push_fmt`, an f-string is written in place: no
  closure, no `Interp`, no copy of the function, at every `-O` level.
  Through a function of your own taking `T: Display`, each f-string is
  a new copy of that function (and of what it calls).

```tach
fn main(gpa: Gpa) -> i32 {
    let name = "tachyon";
    let n = 42;
    let x = 2.5;
    println(f"{name} has {n} and {x}");
    println(f"[{n:>6}] [{n:<6}] [{n:06}] [{n:x}] [{n:X}] [{n:b}]");
    println(f"[{name:>9}] [{x:.3}] [{'A':c}] {{braces}} {n * 2 + 1}");
    let s = format_in(f"{n}-{n + 1}", gpa);       // a Buf, dropped at the end
    eprintln(f"to stderr: {s.as_slice()}");
    0
}
```
```out
tachyon has 42 and 2.5
[    42] [42    ] [000042] [2a] [2A] [101010]
[  tachyon] [2.500] [A] {braces} 85
to stderr: 42-43
```

```tach
fn next(c: inout i64) -> i64 {
    c += 1;
    c
}

fn main() -> i32 {
    var c = 0;
    let line = f"{next(&c)} {next(&c)}";             // evaluated here: 1, then 2
    c = 100;
    println(line);
    println(line);
    std::print_int(c);
    println("");
    0
}
```
```out
1 2
1 2
100
```

Printing writes through a static 4 KB buffer, one `write` per call, no
heap. Rust's `println!("{}", x)` is `println(f"{x}")`, `format!` is
`format_in(f"...", gpa)`; there are no macros.

## Numbers

(0.20) A float's `{}`, `{:?}`, `{:e}` and `{:E}` are Rust's text, byte for
byte: the shortest digits that read back as the value (Schubfach), `{}`
never with an exponent, `{:?}` with one below 1e-4 and from 1e16 on.
`std::num` reads text back, as Rust's `s.parse()` does, and writes it
without a Fmt:

| call | is |
|---|---|
| `parse_f64(s) -> Result<f64, ParseFloatError>`, `parse_f32` | Rust's `f64::from_str`: `-1.5e3`, `.5`, `inf`, `NaN`; no spaces; correctly rounded |
| `parse_i64_radix(s, 16) -> Result<i64, ParseIntError>`, `parse_u64_radix` | Rust's `from_str_radix` (radix 2 to 36) |
| `write_f64(v, FloatFmt::Debug, out) -> i64`, `write_f32` | the text into `out` (`FLOAT_TEXT_MAX` bytes always fit): its length |
| `fmt_u64(v, &out) -> i64`, `fmt_i64` | the digits at the end of a `[u8; 20]`: where they start |
| `f64_to_bits(v)`, `f64_from_bits(u)`, `f32_...` | the IEEE bits (Rust's `to_bits`) |

```tach
use std::num::{FloatFmt, parse_f64, parse_i64_radix, write_f64};

fn main() -> i32 {
    let x = parse_f64("0.1").unwrap() + parse_f64("2e-1").unwrap();
    println(f"{x} {x:?} {x:e} {1e16:?} {1e-7} {0.1f32}");
    var out: [u8; 32] = [0; 32];
    let n = write_f64(1234.5, FloatFmt::LowerExp, out[..]);
    println(out[0..n]);
    println(f"{parse_i64_radix("-ff", 16):?} {parse_f64("1,5").is_err()}");
    0
}
```
```out
0.30000000000000004 0.30000000000000004 3.0000000000000004e-1 1e16 0.0000001 0.1
1.2345e3
Ok(-255) true
```

## Display and Debug

```text
trait Display { fn fmt(self, f: inout Fmt); }
trait Debug { fn fmt_debug(self, f: inout Fmt); }
```

Write `impl Display for T` (no derive: the text is yours) with the
methods of `std::Fmt`: `f.str(s)` (a `[u8]`), `f.byte(b)`, `f.write(x)`
(any Display value, an f-string too), `f.display(x)`, `f.debug(x)`.
`self` is read (let), `f` is changed (inout); there is no result to
return. Display is in std for the numbers, `[u8]` and the
error enums; Debug for those (a `[u8]` quoted and
escaped: `"a\n"`), `Vec<T>`, `Option`, `Result` and `HashMap` (`[1, 2]`,
`Some(5)`, `{1: 2}`). A slice `[T]` has no Debug (it would clash with
`[u8]`'s): `std::debug_list(f, s)` writes one from a Debug impl.

```tach
#[derive(Debug, Clone)]
struct Point { x: i64, y: i64 }

#[derive(Debug)]
enum Shape { Circle(i64), Rect(Point, Point), Line { from: Point, len: i64 }, Empty }

impl Display for Point {
    fn fmt(self, f: inout Fmt) {
        f.write(f"({self.x}, {self.y})");
    }
}

fn main(gpa: Gpa) -> i32 {
    let p = Point { x: 1, y: 2 };
    var q = p.clone();
    q.x = 5;
    println(f"{p} {q:?}");
    let shapes = [Shape::Circle(3), Shape::Rect(p, q), Shape::Line { from: p, len: 4 }, Shape::Empty];
    for s in shapes { println(f"{s:?}"); }
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    println(f"{v:?} {v.last():?} {"hi":?}");
    0
}
```
```out
(1, 2) Point { x: 5, y: 2 }
Circle(3)
Rect(Point { x: 1, y: 2 }, Point { x: 5, y: 2 })
Line { from: Point { x: 1, y: 2 }, len: 4 }
Empty
[1, 2] Some(2) "hi"
```

## derive

`#[derive(Eq, Ord, Hash, Debug, Clone)]` before a struct or an enum
(with `#[repr]` if it has one) writes the impls:

| trait | what it is |
|---|---|
| `Eq` | the structural `==` it already has; an error if a field has no `==` |
| `Ord` | field by field, in declaration order; an enum by variant order, then payload |
| `Hash` | the fields' hashes mixed (`std::hash_mix`), an enum's variant first |
| `Debug` | Rust's text: `P { x: 1, y: 2 }`, `Circle(3)`, `Empty` |
| `Clone` | field by field (`std::clone_of`): a `Vec` field is copied deep |

On a generic type each parameter gets the trait as a bound: `#[derive(Ord)]
struct P<T>` is `impl<T: Ord> Ord for P<T>`. Display has no derive. A
derived trait and a hand-written impl of it clash: remove one.
`x.clone()` of a plain value (numbers, pointers, fieldless enums,
tuples of them) is a copy. `Clone` is in std for `Vec` (deep), `Buf`,
`HashMap`, `Option`, `Result` and the primitives.

```tach
#[derive(Eq, Ord, Hash, Debug)]
struct Key { group: i64, id: i64 }

fn main(gpa: Gpa) -> i32 {
    var keys = [Key { group: 2, id: 1 }, Key { group: 1, id: 9 }, Key { group: 1, id: 3 }];
    sort(&keys[..]);                         // by group, then id
    var m: HashMap<Key, i64> = HashMap::new_in(gpa);
    for k in keys { m.insert(k, k.id * 10); }
    let wanted = Key { group: 2, id: 1 };
    println(f"{keys[0]:?} {m.get(wanted):?}");
    0
}
```
```out
Key { group: 1, id: 3 } Some(10)
```
