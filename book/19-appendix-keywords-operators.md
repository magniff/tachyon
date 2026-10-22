# Appendix A: keywords, operators and attributes

A page to keep open while you write code: the words, symbols and
attributes of vole, each with a line on what it means and the chapter
that teaches it. It is a reminder, not a grammar. For the exact rules,
see [docs/grammar.md](../docs/grammar.md) and `volec guide syntax`.

## Keywords

These words are reserved: you can't use them as names.

| keyword | meaning | chapter |
|---|---|---|
| `as` | converts a number, `bool` or fieldless enum (`x as i32`), a pointer, or a distinct type | 3, 15 |
| `break` | leaves a loop, optionally with a value or a label: `break n`, `break :outer` | 3 |
| `const` | a constant item: `const MAX: i64 = 100;` | 3 |
| `continue` | starts the next round of a loop: `continue :outer` | 3 |
| `defer` | runs a statement when the block exits, however it exits | `guide syntax` |
| `else` | the other branch of `if`; also in `let ... else` and a contract's message | 3, 5 |
| `enum` | a type whose value is one of several variants | 5 |
| `extern` | a C function or block of them: `extern "C" { ... }` | 15 |
| `false`, `true` | the two `bool` values | 3 |
| `fn` | a function or method | 3 |
| `for` | loops over a range, a list or an iterator: `for x in v` | 3, 10 |
| `if` | a condition; an expression, so it has a value | 3 |
| `impl` | methods for a type, or a trait for a type: `impl Drop for T` | 5, 9 |
| `import` | a C header: `import "stdio.h" as c;` | 15 |
| `in` | the `in` of a `for` loop | 3 |
| `inout` | the convention for a parameter a function may change; `inout x = &place;` | 4 |
| `let` | an immutable variable; the default parameter convention | 3, 4 |
| `loop` | repeats until a `break` | 3 |
| `match` | picks an arm by pattern | 5 |
| `mod` | a module: `mod util;` loads `util.vl` | 11 |
| `pub` | makes an item visible outside its module | 11 |
| `return` | leaves the function, with a value | 3 |
| `sink` | the convention for a parameter a function takes; `sink \|\|` for a closure that takes its captures | 4, 10 |
| `static` | a value that lives as long as the program: `static var` for one that changes | 3, 14 |
| `struct` | a type with named fields | 5 |
| `trait` | a set of methods types can provide | 9 |
| `type` | an alias, or a distinct type: `type Id = distinct i64;` | `guide types` |
| `union` | a C-style union, read only in `unsafe` code | 15 |
| `unsafe` | a block or function allowed to do what the compiler can't check | 15 |
| `use` | imports a name: `use std::io::BufReader;` | 2, 11 |
| `var` | a mutable variable | 3 |
| `while` | loops while a condition holds; `while let` while a pattern fits | 3, 5 |

`where` and `dyn` are reserved too, and are errors: vole has neither
(bounds go in the angle brackets, `<T: Ord>`, and there are no trait
objects). `mut` and `move` are Rust's spellings; each is an error whose
`try:` line gives vole's (`var` or `sink`).

### Words that are special in one place

These are ordinary names everywhere else, so you can still have a
variable called `result` or `debug`:

| word | special where | meaning | chapter |
|---|---|---|---|
| `self` | a method's first parameter | the value the method is called on | 4, 5 |
| `Self` | inside an `impl` or a trait | the type being implemented | 5, 9 |
| `crate`, `super` | at the start of a path | this program's root module; the parent module | 11 |
| `requires`, `ensures` | between a function's signature and its body | what the function needs, and what it promises | 6, 13 |
| `result`, `old` | in an `ensures` | the returned value; a value as it was at entry: `old(v.len())` | 13 |
| `debug` | before `requires`, `ensures` or `invariant` | checked only by `volec test` and `--debug-contracts` | 13 |
| `distinct` | after `type X =` | a new type with another type's representation | `guide types` |
| `invariant` | after a type | a condition its values keep | docs/grammar.md |

## Operators

### Arithmetic, bits and comparison

| operator | meaning |
|---|---|
| `+ - * /` | arithmetic; integers wrap, `x / 0` is 0 |
| `%` | remainder, with the sign of the left side; `x % 0` is `x` |
| `-x` | negation |
| `& \| ^` | bitwise and, or, xor (on integers) |
| `~x` | bitwise not |
| `<< >>` | shifts; `>>` keeps the sign of a signed integer |
| `== !=` | equal, not equal: numbers, `bool`, text, structs, enums, tuples, arrays |
| `< <= > >=` | ordering; they don't chain (`a < b < c` is an error) |
| `&& \|\|` | `bool` and, or; the right side runs only if needed |
| `!x` | `bool` not; only on `bool` (on integers, use `~`) |

There's no `**` (power), no `++` or `--`, and no `?:` (an `if` is an
expression).

### Assignment

`=` assigns, and `+= -= *= /= %= &= |= ^= <<= >>=` combine an operator
with assignment. An assignment's value is `()`, so `a = b = 1` is not
allowed.

### Everything else

| operator | meaning | chapter |
|---|---|---|
| `a..b`, `a..=b` | a range, excluding or including `b`: `for i in 0..n`; a slice: `v[1..3]` | 3, 7 |
| `a[i]` | an element of an array, a slice, a `Vec` or a `Buf`; checked | 3, 7 |
| `x.f`, `t.0` | a field; a tuple's part | 3, 5 |
| `x.m()` | a method call | 5 |
| `T::f` | an associated function or a variant: `Player::new()`, `Option::None` | 5 |
| `f::<T>()` | a function told its type (the *turbofish*): `s.parse::<i64>()` | 2 |
| `e?` | the value in an `Ok` or `Some`; else return the error or `None` | 6 |
| `&x` | at a call, marks an argument the function may change (inout); where a raw pointer is wanted, the address of `x` | 4, 15 |
| `*p` | reads or writes through a raw pointer, in `unsafe` code only | 15 |
| `\|x\| e` | a closure | 10 |
| `=>` | separates a `match` arm's pattern from its value | 5 |
| `->` | a function's result type | 3 |

### Precedence

From the loosest to the tightest. Operators on one line bind equally
and group left to right, except assignment, which groups right to left.

| operators | note |
|---|---|
| `=` `+=` `-=` ... | assignment |
| `\|\|` | |
| `&&` | |
| `==` `!=` `<` `>` `<=` `>=` | not chained |
| `\|`, then `^`, then `&` | `a \| b == c` is `(a \| b) == c` |
| `<<` `>>` | |
| `+` `-` | |
| `*` `/` `%` | |
| `as` | `-x as f64` is `(-x) as f64`; `a * b as f64` is `a * (b as f64)` |
| prefix `-` `!` `~` `*` `&` | |
| `f()` `a[i]` `x.f` `x.0` `x.m()` `e?` | |

Note that `&`, `|` and `^` bind looser than `+` and `<<` but tighter
than `==`. That's the other way round from C, where `a & b == c` means
`a & (b == c)`. When in doubt, add parentheses.

Here's a program that exercises the table:

```vole
fn main() {
    let a = 6;
    let b = 4;
    println(f"{a + b * 2} {(a + b) * 2} {a - b - 1} {a / b} {a % b}");
    println(f"{a & b} {a | b} {a ^ b} {~a} {1 << 4} {-16 >> 2}");
    println(f"{a | b == 6} {a + 1 << 1} {-a as f64 / 4.0}");
    println(f"{a > b && b > 0 || false} {!(a == b)} {a != b}");
    var x = 1;
    x += 2;
    x *= 5;
    x -= 1;
    x <<= 1;
    x %= 10;
    println(f"{x}");
}
```

```out
14 20 1 1 2
4 6 2 -7 16 -4
true 14 -1.5
true true true
8
```

## Literals

| literal | type | example |
|---|---|---|
| integer | `i64`, or what the context needs | `42`, `1_000_000`, `0xff`, `0b1010` |
| integer with a suffix | the suffix's | `255u8`, `7i32`, `1_000_u64` |
| float | `f64`, or what the context needs | `2.5`, `1e10`, `1.5e-3` |
| float with a suffix | `f32` | `2.5f32` |
| `bool` | `bool` | `true`, `false` |
| byte | `u8` | `'a'`, `'\n'`, `'\x41'`, `'\''` |
| string | `str` where one is wanted, else `[u8]` | `"hello\n"` |
| C string | `*u8`, NUL-terminated | `c"for C"` |
| f-string | formatted text | `f"{name} is {age:>3}"` |
| unit | `()` | `()` |

Strings take the escapes `\n`, `\t`, `\r`, `\0`, `\\`, `\"`, `\'`,
`\xNN` (a byte) and `\u{NNNN}` (a Unicode character, as UTF-8). A
backslash at the end of a line continues the string on the next line,
without the line break and the next line's indentation.

A plain string literal is bytes, `[u8]`, unless it's used where a
`str` is expected, as a `str` parameter or a `let s: str = "...";`.
Then it's a `str`, which has the text methods (`trim`, `split`,
`find`, ...). Chapter 7 explains the difference.

In an f-string, `{expr}` is replaced by the value's text, and a *spec*
after a colon shapes it: `{x:>8}` (right-aligned in 8 columns), `{x:<8}`
(left), `{x:08}` (zero-padded), `{x:.2}` (2 decimals), `{x:x}` (hex),
`{x:b}` (binary), `{b:c}` (a byte as a character), `{v:?}` (the Debug
form). `{{` and `}}` are literal braces. Chapter 7 has more.

## Attributes

An attribute is written `#[name]` or `#[name(...)]` on the line before
an item.

| attribute | on | meaning | chapter |
|---|---|---|---|
| `#[derive(Debug, Eq, Ord, Hash, Clone)]` | struct, enum | generates those traits from the fields | 5, 9 |
| `#[repr(u8)]` (or another integer) | enum | stores the enum as that integer; variants can have `= N` | 5 |
| `#[repr(C)]` | struct, union | C's layout, for passing to C | 15 |
| `#[test]` | function | a test, run by `volec test` | 13 |
| `#[property]` | function | a property test, run with generated inputs | 13 |
| `#[fuzz]` | function | a fuzz target | 13 |
| `#[cfg(test)]` | item | compiled only for `volec test` | 13 |
| `#[pure]` | function | checked: no allocation, I/O or globals (it may still panic) | 12 |
| `#[no_alloc]`, `#[no_io]`, `#[no_panic]` | function | checked: the function never allocates, does I/O, or panics | 12 |
| `#[effects(io, global, ...)]` | function | checked: the function does at most these | 12 |
| `#[views(s)]` | function | states its view summary, checked against its body | `guide views` |
| `#[inline]`, `#[inline(never)]` | function | asks the optimizer to inline it, or not to | 16 |
| `#[cold]` | function | rarely called: the optimizer keeps it out of the way | `guide syntax` |
| `#[target_feature(...)]`, `#[multiversion(...)]` | function | compiled for particular CPU features | 16 |
| `#[thread_local]` | `static var` | one copy per thread | 14 |
| `#[link(...)]`, `#[link_name = "..."]` | `extern` block, function | which C library to link, and a function's C name | 15 |

You'll also see `#[sealed]` in the standard library's source, which
marks a trait only the standard library may implement.

## The prelude

These names are available in every file without a `use`:

- **Option and Result:** `Option`, `Some`, `None`, `Result`, `Ok`, `Err`.
- **Printing:** `print`, `println`, `eprint`, `eprintln`, `format`,
  `format_in`, `Fmt`.
- **Text and input:** `str`, `String`, `to_string_in`, `Buf`,
  `read_line`, `read_stdin_in`, `read_stdin`, `Scanner`, `parse_int`,
  `trim`, `split`, `split_in`, `split_whitespace`,
  `split_whitespace_in`.
- **Collections and sorting:** `Vec`, `HashMap`, `BinaryHeap`,
  `MinHeap`, `sort`, `sort_by`, `sort_stable`, `sort_stable_by`,
  `sort_stable_in`, `sort_stable_by_in`, `cmp_of`, `eq_of`.
- **Memory:** `Allocator`, `Gpa`, `Arena`, `ScopedArena`, `arena_scope`,
  `Drop`, `drop`, `forget`, `needs_drop`, `Copy`.
- **Traits:** `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`, `Hash`,
  `Iterator`, `Display`, `Debug`, `Clone`, `From`, `Into`.
- **Checks:** `panic`, `unreachable`, `assert`, `assert_eq`,
  `assert_ne`, `debug_assert`.

Everything else in the standard library is imported by name, `use
std::io::BufReader;`, or written as a path, `std::io::stdin()`. Your
own items hide prelude names of the same spelling. `volec query items
std` lists the whole library.
