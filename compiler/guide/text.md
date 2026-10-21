# text

## str and String

`str` is UTF-8 text, a view (`&str` is `str`, as `&[T]` is `[T]`); a
string literal is one where a `str` goes, and a `str` goes where a `[u8]`
does, for free. `String` owns its text, on an allocator:
`String::new_in(gpa)`, `String::from_in("x", gpa)`, `s.push_str("..")`,
`s.push(c)` (a code point, a `u32`: tachyon has no `char` yet),
`s.push_fmt(f"{x}")`, `to_string_in(f"..", gpa)`. A String has its
`str`'s methods (`s.trim()`), and `&s` goes where a `str` or `[u8]` does.
The methods are Rust's, and what they return views the text: `len`,
`chars()` (code points; `.rev()`), `char_indices()`, `bytes()`,
`lines()`, `split(p)`, `splitn(n, p)`, `split_once(p)`, `rsplit_once`,
`split_whitespace()`, `trim()` (and `_start`, `_end`, `_matches`),
`strip_prefix(p)`, `starts_with(p)`, `ends_with`, `contains`, `find(p)`
(an `Option<i64>`, a byte index), `rfind`, `matches(p)`, `parse::<T>()`
(numbers, `bool`), `width()` (terminal columns), `graphemes(true)`. A
pattern `p` is a `str` (`", "`), a byte (`','`) or a code point (`0x4e16
as u32`). What allocates takes an allocator, Rust's name with `_in`:
`to_uppercase_in(gpa)`, `to_lowercase_in`, `replace_in(a, b, gpa)`,
`repeat_in(n, gpa)`, `to_string_in(gpa)`, `.collect_in(gpa)`; the Rust
forms are errors naming them. Bytes become a `str` checked:
`str::from_utf8(b)?`, `String::from_utf8(v)?` (a `Vec<u8>`),
`String::from_buf(b)?`, `String::from_utf8_lossy_in(b, gpa)`; back:
`s.as_bytes()`, `s.into_bytes()`, `s.into_buf()`.

```tach
fn initials(name: str, gpa: Gpa) -> String {
    var out = String::new_in(gpa);
    for w in name.split_whitespace() {
        out.push(w.chars().next().unwrap());
    }
    out
}

fn main(gpa: Gpa) -> i32 {
    let line: str = "  ada lovelace, 1815 ";
    let (name, year) = line.trim().split_once(", ").unwrap();
    let born = year.parse::<i64>().unwrap();
    let up = name.to_uppercase_in(gpa);
    let short = initials(name, gpa);
    println(f"{up} {short} {2026 - born} {name.contains('l')}");
    let parts: Vec<str> = "a,b,,c".split(',').collect_in(gpa);
    println(f"{parts:?} {parts.len()}");
    0
}
```
```out
ADA LOVELACE al 211 true
["a", "b", "", "c"] 4
```
