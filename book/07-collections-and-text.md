# 7. Collections and text

> **Status: outline.** This file is the plan for the chapter. Replace it
> with the chapter, following [STYLE.md](STYLE.md). It is a tutorial,
> not a spec: teach the common case by example, explain the intent,
> and leave corner cases to `volec guide` and docs/grammar.md.

## Goal

The everyday containers and text. By the end the reader can:

- use `Vec<T>`: push, pop, index, slice, iterate, sort, `contains`,
  `retain`, `sort_by_key`;
- use `HashMap` and `HashSet` (`insert`, `get`, `get_or_insert`,
  `remove`, iterate), and `BTreeMap` when order matters;
- work with text: `str` (a view of UTF-8 text) and `String` (owned),
  their methods (`trim`, `split`, `lines`, `find`, `parse`, `chars`),
  and bytes (`[u8]`, `Buf`) when text isn't UTF-8;
- format values with f-strings: width, alignment, precision, hex,
  Debug.

## Running example

A word-frequency counter over stdin: read all input, split it into
words, lowercase them, count them in a `HashMap<String, i64>`, sort
the pairs by count, print the top five as an aligned table with
f-string specs. It is reused (split into modules) in chapter 11 and
grows into the final project in chapter 18.

## Sections

1. **Vec.** `Vec::new_in(gpa)` (the allocator again, one line of
   reminder, chapter 8 explains); `push`, `len`, `v[i]` (checked),
   `v[a..b]` (a slice, a view: chapter 4), `pop` returns an `Option`,
   `for x in v`, changing elements by index (`for i in 0..v.len() {
   v[i] *= 2; }`; there is no `iter_mut`), `sort`, `sort_by_key`,
   `retain`, `contains`. Passing a Vec: `v` to read, `&v` to change,
   moved into `sink`.
2. **Arrays vs Vec vs slices.** `[T; N]` is a value of fixed length;
   `Vec<T>` grows; `[T]` views either. Functions should take `[T]` when
   they only read.
3. **HashMap and HashSet.** `HashMap::new_in(gpa)`, `insert`, `get`
   (returns `Option<V>`, a copy), counting with `get_or_insert(k, 0)[0]
   += 1` (explain the one-element view honestly: it's a vole quirk),
   `iter()` order is unspecified. Keys need `Hash + Eq`; derive them for
   your own types (chapter 9). `BTreeMap` for sorted keys, `range`.
   Mention `BinaryHeap`/`MinHeap` in one paragraph.
4. **Text: str and String.** A literal is a `str`. `String::new_in(gpa)`,
   `String::from_in("..", gpa)`, `push_str`, `push_fmt(f"..")`. `&s`
   passes a String where a `str` is wanted. Methods that return views
   (`trim`, `split`, `lines`, `split_whitespace`) allocate nothing;
   methods that build text take an allocator (`to_lowercase_in(gpa)`,
   `replace_in`). UTF-8: `len()` counts bytes, `chars()` code points.
   vole has no `char` type yet: a code point is a `u32`, `'a'` is a byte.
5. **Bytes.** `[u8]` and `Buf` for bytes that aren't text; `str::from_utf8`
   to check bytes and get a `str`. When to use which.
6. **Formatting.** f-strings in depth: `{x:>6}`, `{x:<6}`, `{x:06}`,
   `{x:.3}`, `{x:x}`, `{x:?}`, `{{`; `format_in(f"..", gpa)` for a Buf,
   `to_string_in`. Display vs Debug; `#[derive(Debug)]`; `impl Display`
   is in chapter 9.
7. **Reading all of stdin.** `read_stdin_in(gpa)` or `BufReader` +
   `lines_in(gpa)`; `Scanner` for whitespace-separated numbers (one
   paragraph).

## Errors to show

- `no method 'trim' on type '[u8]'` (a byte slice where a `str` was
  meant), with its `try:`.
- `expected 'String', got '[u8]'` / a literal passed where a String is
  wanted, and the `String::from_in` fix.
- A Rust habit: `s.to_uppercase()` without an allocator is
  `alloc.explicit`-style error naming `to_uppercase_in(gpa)`.
- `own.conflict`: pushing to a Vec while iterating it (`for x in v {
  v.push(x); }`), with the index-loop fix its `try:` gives.
- Run-time: `index out of bounds` on a Vec.

## Asides

- If you know Rust: the methods are Rust's names; anything that
  allocates takes an allocator and ends in `_in`; `collect_in(gpa)`
  makes a Vec only; no `iter_mut`, no `entry` API.
- If you know Python: no list comprehensions; iterator chains (chapter
  10) fill that role.

## Sources

`volec guide std` (most used items), `guide text`, `guide formatting`,
`guide std#heaps-priority-queues`, examples/formatting.
