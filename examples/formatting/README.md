# formatting

Formatted text in vole: f-strings and every part of a format spec
(width, alignment, zero padding, precision, hex, binary, characters,
Debug), `Display` and `Debug` written by hand and derived, and the ways
to send formatted text somewhere (`println`, `eprintln`, `format`,
`push_fmt`). The program prints a spec cheat sheet, an aligned inventory
table, some Debug views and a hex dump.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o formatting && ./formatting
./formatting 2>/dev/null     # the report alone, without the warnings on stderr
```

## Expected output

On stdout:

```text
== format specs
{n}           [42]         Display
{n:>8}        [      42]   right-aligned: the default for numbers
{n:<8}        [42      ]   left-aligned
{n:08}        [00000042]   zero-padded
{n:x} {n:X}   [2a 2A]      hex
{n:08b}       [00101010]   binary, zero-padded
{x}           [3.14159]    the shortest text that reads back
{x:.2}        [3.14]       two decimals
{x:>9.3}      [    3.142]  width and precision
{name:>9}     [     vole]  text goes left by default
{name:?}      ["vole"]     Debug: quoted and escaped
{'A':c}       [A]          a u8 as a character
{n * 2 + 1}   [85]         any expression
{{ and }} in an f-string are literal braces: {n}
== inventory
sku    item               qty      price        value
-----------------------------------------------------
#7     hammer              12     $15.99      $191.88
#42    socket set           3     $89.50      $268.50
#108   coffee beans        40     $12.75      $510.00
#9     rubber duck        250      $1.99      $497.50
#1500  workbench            2    $649.00    $1,298.00
-----------------------------------------------------
total                                       $2,765.88
== debug
Item { sku: SKU-0007, name: "hammer", category: Tools, qty: 12, price: Money(1599) }
Food(180) SKU-0108 Money(1275)
[12, 3, 40, 250, 2] Some(2) "tab\there"
== hex dump
0000  76 6f 6c 65 20 66 6f 72  |vole for|
0008  6d 61 74 73 09 62 79 74  |mats.byt|
0010  65 73 0a                 |es.|
```

On stderr:

```text
warning: socket set (SKU-0042) is low: 3 left
warning: workbench (SKU-1500) is low: 2 left
```

## How it works

**f-strings.** `f"... {expr} ..."` is formatted text: each hole holds
any expression whose type has `Display` (with `:?`, `Debug`). A plain
`"..."` never formats; `{{` and `}}` are literal braces in an f-string.
The spec after `:` is `[<|>][0][width][.precision][?|x|X|b|c]`:

| spec | meaning |
|---|---|
| `{n:>8}` `{n:<8}` | width 8, right or left aligned (numbers go right, text left, by default) |
| `{n:08}` | zero-padded to 8 |
| `{n:x}` `{n:X}` `{n:b}` | hex, upper-case hex, binary (`{n:08b}`: padded) |
| `{x:.2}` `{x:>9.3}` | a float with 2 decimals; width 9 with 3 decimals |
| `{b:c}` | a `u8` as its character (otherwise a `u8` prints as a number) |
| `{v:?}` `{v:<26?}` | Debug, also with a width |

A float without a precision prints the shortest text that reads back as
the same value (`3.14159`, `0.1`).

**An f-string is a value.** It is passed to anything taking a
`T: Display`: `println`, `eprintln` (stderr), `format` (returns a new
`Buf`, which the caller frees), `buf.push_fmt(..)` (appends to a `Buf`)
and `f.write(..)` inside a Display impl. The cheat sheet passes
`format_in(f"...", gpa)` results to a helper that frees them; the hex dump
builds each line in a `Buf`:

```tach
var line = format_in(f"{at:04x}  ", gpa); // format: a new Buf to keep
for i in at..at + 8 {
    if i < end { line.push_fmt(f"{bytes[i]:02x} "); } else { line.push_str("   "); }
}
```

**Display by hand.** `Display` has one method, `fmt(self, f: inout
Fmt)`, which writes through the `Fmt` with `f.str`, `f.byte` and
`f.write` (any Display value, an f-string included). Unlike Rust there is
no `fmt::Result` to return. `Money` prints cents as dollars with
thousands separators, using a zero-padded spec for each group:

```tach
impl Display for Money {
    fn fmt(self, f: inout Fmt) {
        ...
        f.write(dollars / group);
        while group > 1 {
            group /= 1000;
            f.write(f",{dollars / group % 1000:03}");
        }
        f.write(f".{c % 100:02}");
    }
}
```

A width in the caller's spec applies to the whole of what the impl
writes, so `{it.price:>10}` right-aligns `$15.99` in the table just as
it would a number.

**Debug by hand and derived.** `Debug` is `fmt_debug(self, f: inout
Fmt)`. `Sku` prints `#42` for people and `SKU-0042` for programmers.
`#[derive(Debug)]` writes Rust's text for a struct or enum, calling the
fields' own Debug impls, which is how `Item`'s Debug shows
`sku: SKU-0007` and `price: Money(1599)`:

```tach
#[derive(Debug)]
enum Category { Tools, Food(i64), Toys }

#[derive(Debug)]
struct Item { sku: Sku, name: [u8], category: Category, qty: i64, price: Money }
```

std has Debug for the numbers, `[u8]` (quoted and escaped:
`"tab\there"`), `Vec` (`[12, 3, 40, 250, 2]`), `Option`, `Result` and
`HashMap`.

**A table.** Headers and cells share the same widths, and text columns
are left-aligned while numbers and money are right-aligned:

```tach
println(f"{"sku":<6} {"item":<16} {"qty":>5} {"price":>10} {"value":>12}");
...
println(f"{it.sku:<6} {it.name:<16} {it.qty:>5} {it.price:>10} {value:>12}");
```

String literals are allowed inside holes (`{"sku":<6}`).

**stdout and stderr.** The low-stock warnings go through `eprintln`, so
`./formatting 2>/dev/null` leaves the report alone. Printing goes
through a small static buffer, one `write` per call, with no heap
allocation.

## Language features

- f-strings, specs, `Display`, `Debug`, `format`, `push_fmt`, `eprintln`, `#[derive(Debug)]`: `volec guide formatting`
- `Buf`, `Vec`, `defer`/`free`: `volec guide std`, `volec guide memory`
- struct field shorthand (`Item { sku: Sku { id }, name, ... }`): `volec guide syntax`

## Going further

- Widths and precisions are literal: there is no `{x:>width$}`. For a
  computed width, pad by hand (push spaces into a `Buf`).
- No `{:+}`, `{:#x}` or `{:e}`: write the sign or `0x` yourself
  (`f"0x{n:x}"`), or call C's `printf` for exponent notation.
- Display has no derive; write the text you want.
