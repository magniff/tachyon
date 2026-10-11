# Tachyon grammar

This is the grammar of tachyon 1.0, as the compiler implements it
(`compiler/src/10_lexer.tach`, `compiler/src/21_parser.tach`; stage0
implements the same language in `stage0/src/lexer` and `stage0/src/parser`).
Items and statements are parsed by recursive descent, expressions by a Pratt
(binding power) parser using the table below.

Notation: `{ x }` is zero or more `x`, `[ x ]` is optional, `|` separates
alternatives, `"..."` is a literal token.

## Lexical structure

```ebnf
whitespace   = " " | "\t" | "\r" | "\n" ;
comment      = "//" { any - "\n" }
             | "/*" { any | comment } "*/" ;          (* block comments nest *)
ident        = ( "_" | ascii_letter ) { "_" | ascii_letter | digit } ;
                                                       (* "_" alone is the wildcard pattern *)
int_lit      = ( dec_digits | "0x" hex_digits | "0b" bin_digits ) [ int_suffix ] ;
float_lit    = dec_digits "." dec_digits [ exponent ] [ float_suffix ]
             | dec_digits exponent [ float_suffix ]
             | dec_digits float_suffix ;              (* 2f32 *)
exponent     = ( "e" | "E" ) [ "+" | "-" ] dec_digits ;
int_suffix   = "i8" | "i16" | "i32" | "i64" | "isize" | "u8" | "u16" | "u32" | "u64" | "usize" ;
float_suffix = "f32" | "f64" ;
char_lit     = "'" ( ascii_char | escape ) "'" ;       (* one byte, ASCII only *)
string_lit   = '"' { char | escape } '"' ;             (* a (*u8, u64) pair *)
cstring_lit  = 'c"' { char | escape } '"' ;            (* a NUL-terminated *u8; no NUL inside *)
escape       = "\n" | "\t" | "\r" | "\0" | "\\" | '\"' | "\'"
             | "\x" hex hex                            (* one byte *)
             | "\u{" hex { hex } "}" ;                 (* UTF-8 encoded; ASCII only in char_lit *)
```

`_` may separate digits (`1_000_000`, `255_u8`). After `.`, digits are a
tuple index, so `t.0.1` is `(t.0).1`. A literal must not be followed
directly by other letters (`3e` and `1foo` are errors).

**Keywords:** `as break const continue else extern false fn for if in let
loop mut return static struct true type while`.

**Reserved** (an error if used): the keywords `enum match impl trait pub mod
use self Self super where unsafe defer union dyn move`, and the tokens `::`
`=>` `#` `?` `@`.

A token is *joint* when no whitespace follows it. The parser splits a joint
`&&` in prefix position into `& &`; `**` is not a token, so `**p` and `**T`
are two `*`.

## Items

```ebnf
program      = { item } EOF ;
item         = fn_decl | extern_decl | struct_decl | const_decl | static_decl | type_alias ;

fn_decl      = "fn" ident "(" [ params ] ")" [ "->" type ] block ;
params       = param { "," param } [ "," ] ;
param        = [ "mut" ] ident ":" type ;              (* "_" ignores the argument *)

extern_decl  = "extern" [ '"C"' ] "fn" ident "(" [ ext_params ] ")" [ "->" type ] ";" ;
ext_params   = "..." | param { "," param } [ "," [ "..." ] ] ;

struct_decl  = "struct" ident "{" [ field { "," field } [ "," ] ] "}" ;
field        = ident ":" type ;

const_decl   = "const" ident ":" type "=" expr ";" ;   (* integer, float or bool; evaluated at compile time *)
static_decl  = "static" [ "mut" ] ident ":" type "=" expr ";" ;   (* constant initializer *)
type_alias   = "type" ident "=" type ";" ;
```

Items may refer to each other in any order. Constants and statics are
initialized by constant expressions: literals, other constants, unary and
binary operators, casts, and array/tuple/struct literals of those. Constant
arithmetic wraps like run-time arithmetic.

## Types

```ebnf
type = ident                                          (* i8 ... u64, isize, usize, f32, f64, bool, a struct or an alias *)
     | "*" type                                       (* raw pointer *)
     | "(" ")" | "(" type ")" | "(" type "," [ type { "," type } [ "," ] ] ")"
     | "[" type ";" expr "]"                          (* the length is a constant expression *)
     | "fn" "(" [ type { "," type } [ "," ] ] ")" [ "->" type ]   (* not variadic *)
     | "!" ;                                          (* never: e.g. `extern fn exit(c: i32) -> !` *)
```

## Patterns

```ebnf
pattern = "_" | [ "mut" ] ident | "(" [ pattern { "," pattern } [ "," ] ] ")" ;
```

`(p)` is `p`; `(p,)` is a one-element tuple pattern.

## Statements and blocks

```ebnf
block       = "{" { stmt } [ expr ] "}" ;
stmt        = ";"                                      (* empty statement *)
            | "let" pattern [ ":" type ] "=" expr ";"
            | block_like [ ";" ]
            | expr ";" ;
block_like  = block | if_expr | loop_expr | while_expr | for_expr ;
```

**Statement rule.** A statement that *starts* with a block-like expression
ends at its closing `}`: it needs no `;` and is never continued by an
operator (`{ 1 } - 1` is two statements). A `;` directly after it belongs to
it. Without the `;`, a block-like statement that is not the block's tail must
have type `()` (or `!`). The last block-like expression before `}` is the
block's value.

Bindings are immutable unless declared `mut`; this covers assignment to the
variable and to its fields and elements. Raw pointers are unchecked, as in
C: `*p = v` and `p[i] = v` need no `mut`, and `&x` may be taken of an
immutable `x`.

## Expressions

```ebnf
expr        = pratt(0) ;
prefix      = ( "-" | "!" | "~" | "*" | "&" ) pratt(25)
            | "return" [ expr ]
            | "break" [ ":" ident ] [ expr ]
            | "continue" [ ":" ident ]
            | primary ;
postfix     = "(" [ expr { "," expr } [ "," ] ] ")"     (* call *)
            | "[" expr "]"                            (* index: arrays and pointers *)
            | "." ident                               (* field *)
            | "." int_lit                             (* tuple field *)
            | "as" type ;                             (* cast *)
primary     = int_lit | float_lit | char_lit | string_lit | cstring_lit | "true" | "false"
            | ident
            | ident "{" [ field_init { "," field_init } [ "," ] ] "}"   (* struct literal *)
            | "(" ")" | "(" expr ")" | "(" expr "," [ expr { "," expr } [ "," ] ] ")"
            | "[" "]" | "[" expr ";" expr "]" | "[" expr { "," expr } [ "," ] "]"
            | [ label ] block_like ;
field_init  = ident ":" expr ;
label       = ident ":" ;                             (* only before loop, while, for *)

if_expr     = "if" cond block [ "else" ( block | if_expr ) ] ;
loop_expr   = "loop" block ;                          (* its value comes from `break value` *)
while_expr  = "while" cond block ;
for_expr    = "for" pattern "in" range block ;        (* range: a..b or a..=b, integers *)
cond        = expr ;                                  (* without struct literals at the top level *)
```

In conditions (`if`, `while`) and `for` ranges, `Name {` starts the body, not
a struct literal; inside parentheses, brackets, braces and call arguments
struct literals are allowed again (`if f(P { x: 1 }) { ... }`).

`return`, `break` and `continue` are expressions of type `!`, which coerces
to every type (`let d = if ok { v } else { return -1 };`). A `loop` has the
type of its `break` values, `()` for a plain `break`, and `!` without any
`break`. `break value` is only allowed in `loop`. Ranges `a..b` and `a..=b`
are only allowed as `for` bounds; the bounds are evaluated once, and the
loop variable is a fresh copy in every iteration.

A function stored in a field is called as `(s.f)(x)`; `s.f(x)` is reserved
for methods.

### Binding powers

Higher binds tighter. A *non-associative* level reports an error when chained
(`a < b < c`: "comparison operators cannot be chained; use parentheses").

| level | operators                                     | assoc     | left bp | right bp |
|-------|-----------------------------------------------|-----------|---------|----------|
| 1     | `=` `+=` `-=` `*=` `/=` `%=` `&=` `\|=` `^=` `<<=` `>>=` | right | 2 | 1 |
| 2     | `..` `..=`                                    | non-assoc | 4       | 5        |
| 3     | `\|\|`                                        | left      | 6       | 7        |
| 4     | `&&`                                          | left      | 8       | 9        |
| 5     | `==` `!=` `<` `>` `<=` `>=`                   | non-assoc | 10      | 11       |
| 6     | `\|`                                          | left      | 12      | 13       |
| 7     | `^`                                           | left      | 14      | 15       |
| 8     | `&`                                           | left      | 16      | 17       |
| 9     | `<<` `>>`                                     | left      | 18      | 19       |
| 10    | `+` `-`                                       | left      | 20      | 21       |
| 11    | `*` `/` `%`                                   | left      | 22      | 23       |
| 12    | `as` type                                     | left      | 24      | —        |
| 13    | prefix `-` `!` `~` `*` `&`                    | prefix    | —       | 25       |
| 14    | call `()`, index `[]`, field `.f`, tuple `.0` | postfix   | 27      | —        |

`return`, `break` and `continue` take the rest of the expression (right bp
0). Assignment is an expression of type `()`; whether its left side is
assignable is checked by the type checker. Examples:

```
-x as i64        ==  (-x) as i64
a * b as f64     ==  a * (b as f64)
*p.x             ==  *(p.x)
a | b == c       ==  (a | b) == c
x as u64 < n     ==  (x as u64) < n
a = b = c        ==  a = (b = c)
```

There is no exponentiation operator; use `pow`/`powf` from libm or a
function.

## Error recovery

The parser reports every independent syntax error. After an error it skips
to the end of the statement (`;`), the end of the block (`}`), or the next
`let` or item keyword, replaces the broken statement by an error node, and
continues. An item keyword inside a block ends the block (a missing `}`).
