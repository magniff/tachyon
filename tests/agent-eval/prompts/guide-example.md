# vole by example

Rust's syntax with C's model: no borrow checker, lifetimes, destructors,
macros or `char`. The program below is compiled and tested;
`volec guide example` prints it again.

@EXAMPLE@

Also: std is one module, imported by name (`use std::{is_digit};`,
never `std::collections` or `*`; the names above need no `use`);
`usize` is `i64`; integers wrap; `as` narrows; `v[i]` is checked;
counting is `m.get_or_insert(k, 0)[0] += 1`; numbers from text are
`sc.next_int()`; C calls and raw-pointer reads need `unsafe { }`;
closures, iterators, traits are as in Rust; no `dyn`, `Box`, `where`.

A name the program does not show: `volec guide --find NAME` (`--find
read a line`, `--find split_in`), or `volec guide std` (the API, a
line per item). `volec try 'CODE'` runs a snippet, `volec check
main.vl` lists every error.
