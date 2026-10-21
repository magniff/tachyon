# tachyon by example

Values with one owner, passed by convention: a parameter reads its
argument (`x: T`), changes it (`x: inout T`, called `f(&x)`) or takes
it (`x: sink T`); `var` is a mutable local. No lifetimes, macros or
`char`. The program below is compiled and tested; `tachyonc guide
example` prints it again.

@EXAMPLE@

Also: std is one module, imported by name (`use std::{is_digit};`,
never `std::collections` or `*`; the names above need no `use`);
`usize` is `i64`; integers wrap; `as` narrows; `v[i]` is checked;
counting is `m.get_or_insert(k, 0)[0] += 1`; numbers from text are
`sc.next_int()`; C calls and raw-pointer reads need `unsafe { }`;
closures (`sink ||`), iterators, traits; no `dyn`, `Box`, `where`.

A name the program does not show: `tachyonc guide --find NAME` (`--find
read a line`, `--find split_in`), or `tachyonc guide std` (the API, a
line per item). `tachyonc try 'CODE'` runs a snippet, `tachyonc check
main.tach` lists every error.
