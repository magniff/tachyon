# The language

The program is written in Rust (edition 2021, the standard library only:
no Cargo, no crates). The entry file is `main.rs` in the current
directory; other modules sit next to it (`mod lexer;` loads `lexer.rs`).
Build it with:

```sh
rustc -O --edition 2021 main.rs -o prog
```
