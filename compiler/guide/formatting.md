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
- The spec after `:` is `[<|>][0][width][.precision][?|x|X|b|c]`: `<`
  and `>` align (numbers go right by default, text left), `0` pads with
  zeros, `.N` gives a float N decimals, `?` is Debug, `x`/`X` hex, `b`
  binary, `c` a `u8` as its byte (a `u8` is a number otherwise).
- Floats print the shortest text that reads back as the same value
  (`2.5`, `0.1`).
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
fn next(c: *i64) -> i64 {
    *c += 1;
    *c
}

fn main() -> i32 {
    let mut c = 0;
    let line = f"{next(&c)} {next(&c)}";     // evaluated here: 1, then 2
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

## Display and Debug

```text
trait Display { fn fmt(self: &Self, f: &mut Fmt); }
trait Debug { fn fmt_debug(self: &Self, f: &mut Fmt); }
```

Write `impl Display for T` (no derive: the text is yours) with the
methods of `std::Fmt`: `f.str(s)` (a `[u8]`), `f.byte(b)`, `f.write(x)`
(any Display value, an f-string too), `f.display(&x)`, `f.debug(&x)`.
Not Rust's `fn fmt(&self, f: &mut Formatter) -> fmt::Result`: there is
no result to return. Display is in std for the numbers, `[u8]` and the
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
    fn fmt(self: &Point, f: &mut Fmt) {
        f.write(f"({self.x}, {self.y})");
    }
}

fn main(gpa: Gpa) -> i32 {
    let p = Point { x: 1, y: 2 };
    let mut q = p.clone();
    q.x = 5;
    println(f"{p} {q:?}");
    let shapes = [Shape::Circle(3), Shape::Rect(p, q), Shape::Line { from: p, len: 4 }, Shape::Empty];
    for s in shapes { println(f"{s:?}"); }
    let mut v: Vec<i64> = Vec::new_in(gpa);
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
    let mut keys = [Key { group: 2, id: 1 }, Key { group: 1, id: 9 }, Key { group: 1, id: 3 }];
    sort(&mut keys[..]);                     // by group, then id
    let mut m: HashMap<Key, i64> = HashMap::new_in(gpa);
    for k in keys { m.insert(k, k.id * 10); }
    let wanted = Key { group: 2, id: 1 };
    println(f"{keys[0]:?} {m.get(wanted):?}");
    0
}
```
```out
Key { group: 1, id: 3 } Some(10)
```
