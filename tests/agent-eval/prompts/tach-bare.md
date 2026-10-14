# The language

The program is written in tachyon, a compiled systems language;
`tachyonc` is its compiler, on your PATH. The entry file is `main.tach`
in the current directory; other modules sit next to it (`mod lexer;`
loads `lexer.tach`). Build it with:

```sh
tachyonc main.tach -o prog
```
