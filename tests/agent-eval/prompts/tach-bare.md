# The language

The program is written in vole, a compiled systems language;
`volec` is its compiler, on your PATH. The entry file is `main.vl`
in the current directory; other modules sit next to it (`mod lexer;`
loads `lexer.vl`). Build it with:

```sh
volec main.vl -o prog
```
