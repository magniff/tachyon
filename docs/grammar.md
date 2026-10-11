# Tachyon grammar

This is the grammar of tachyon 0.3, as the compiler implements it
(`compiler/src/10_lexer.tach`, `compiler/src/21_parser.tach`; the seed
implements the language of 0.1 in `seed/src/lexer` and `seed/src/parser`).
What 0.3 added is marked *(0.3)*.
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

**Keywords:** `as break const continue else enum extern false fn for if impl
in let loop match mut return static struct true type union while`.

**Reserved** (an error if used): the keywords `trait pub mod use super where
unsafe defer dyn move`, and the tokens `?` `@`. `self` and `Self` are
ordinary names, with a meaning in methods (see Items).

A token is *joint* when no whitespace follows it.
`#` starts an attribute *(0.3)*. The parser splits a joint
`&&` in prefix position into `& &`; `**` is not a token, so `**p` and `**T`
are two `*`.

## Items

```ebnf
program      = { item } EOF ;
item         = fn_decl | extern_item | [ attributes ] ( struct_decl | union_decl | enum_decl )
             | impl_block | const_decl | static_decl | type_alias ;

fn_decl      = "fn" ident "(" [ params ] ")" [ "->" type ] block ;
params       = param { "," param } [ "," ] ;
param        = [ "mut" ] ident ":" type ;              (* "_" ignores the argument *)

extern_item  = "extern" '"C"' "{" { c_fn | c_static } "}"            (* (0.3) imports from C *)
             | "extern" '"C"' fn_decl                                 (* (0.3) C's convention, an unmangled symbol *)
             | "extern" '"C"' "static" [ "mut" ] ident ":" type "=" expr ";"   (* (0.3) a static C can use *)
             | "extern" [ '"C"' ] c_fn ;                              (* deprecated: the 0.2 form, meaning extern "C" *)
c_fn         = "fn" ident "(" [ c_params ] ")" [ "->" type ] ";" ;
c_params     = "..." | param { "," param } [ "," [ "..." ] ] ;
c_static     = "static" [ "mut" ] ident ":" type ";" ;

attributes   = { "#" "[" "repr" "(" repr { "," repr } ")" "]" } ;    (* (0.3) *)
repr         = "C" | "packed" | "align" "(" int_lit ")" | int_type ;

struct_decl  = "struct" ident "{" [ field { "," field } [ "," ] ] "}" ;
union_decl   = "union" ident "{" [ field { "," field } [ "," ] ] "}" ;   (* (0.3) #[repr(C)] only *)
field        = ident ":" type ;
enum_decl    = "enum" ident "{" [ variant { "," variant } [ "," ] ] "}" ;   (* (0.3) *)
variant      = ident [ "(" type { "," type } [ "," ] ")" ] [ "=" expr ] ;  (* "=": fieldless enums only *)
impl_block   = "impl" ident "{" { fn_decl } "}" ;                    (* (0.3) *)

const_decl   = "const" ident ":" type "=" expr ";" ;   (* integer, float or bool; evaluated at compile time *)
static_decl  = "static" [ "mut" ] ident ":" type "=" expr ";" ;   (* constant initializer *)
type_alias   = "type" ident "=" type ";" ;
```

Items may refer to each other in any order. Constants and statics are
initialized by constant expressions: literals, other constants, unary and
binary operators, casts, enum variants, and array/tuple/struct literals of
those. Constant arithmetic wraps like run-time arithmetic.

**Enums** *(0.3)*. A fieldless enum's variants have discriminants (0, 1, ...
unless given with `= expr`); such an enum is a scalar, compared with `==`
and `!=` and cast to an integer with `as`. Variants with fields are tuple
variants. Values are written `E::V` and `E::V(a, b)`.

**Impl blocks** *(0.3)* hold the methods and associated functions of a
struct or enum. A function whose first parameter is named `self`, of type
`T` or `*T`, is a method, called as `x.m(args)`: the compiler passes `&x`
or `*x` as the method needs (a temporary of a compound type may be passed by
address too). Others are called as `T::f(args)` (methods too, with the
receiver first). Inside an impl block, `Self` names the type.

**Attributes** *(0.3)*: `#[repr(C)]` gives a struct, union or enum C's
layout; `#[repr(C, packed)]` packs a struct (or union) without padding,
`#[repr(C, align(N))]` raises its alignment to N (a power of two up to 16);
`#[repr(u8)]` (any integer type) sets the tag type of an enum. Any other
attribute is an error.

## Types

```ebnf
type = ident                                          (* i8 ... u64, isize, usize, f32, f64, bool, a struct, union, enum or alias, Self *)
     | "*" type                                       (* raw pointer *)
     | "(" ")" | "(" type ")" | "(" type "," [ type { "," type } [ "," ] ] ")"
     | "[" type ";" expr "]"                          (* the length is a constant expression *)
     | "[" type "]"                                   (* (0.3) a slice: a pointer and a length *)
     | [ "extern" '"C"' ] "fn" "(" [ type { "," type } [ "," ] ] ")" [ "->" type ]
                                                      (* not variadic; extern "C" fn (0.3) is another type *)
     | "!" ;                                          (* never: e.g. `fn exit(c: i32) -> !` *)
```

## Patterns

```ebnf
pattern  = single { "|" single } ;                     (* (0.3) alternatives *)
single   = "_" | [ "mut" ] ident                      (* a binding, or a constant's name *)
         | literal [ "..=" literal ]                  (* (0.3) integers, chars and bools; inclusive ranges *)
         | ident "::" ident [ "(" [ pattern { "," pattern } [ "," ] ] ")" ]   (* (0.3) a variant *)
         | "(" [ pattern { "," pattern } [ "," ] ] ")" ;
literal  = [ "-" ] int_lit | char_lit | "true" | "false" | ident ;   (* ident: a constant *)
```

`(p)` is `p`; `(p,)` is a one-element tuple pattern. An identifier that
names a constant (and no local) is that constant's value; any other is a
binding. Every alternative of an or-pattern binds the same variables, with
the same types. The patterns of `let` and `for` must match every value
(no literals, ranges, alternatives, or variants of enums with several).

## Statements and blocks

```ebnf
block       = "{" { stmt } [ expr ] "}" ;
stmt        = ";"                                      (* empty statement *)
            | "let" pattern [ ":" type ] "=" expr ";"
            | block_like [ ";" ]
            | expr ";" ;
block_like  = block | if_expr | match_expr | loop_expr | while_expr | for_expr ;
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
            | "[" expr "]"                            (* index: arrays, slices and pointers *)
            | "[" [ expr ] ( ".." | "..=" ) [ expr ] "]"   (* (0.3) slicing *)
            | "." ident "(" [ expr { "," expr } [ "," ] ] ")"   (* (0.3) method call *)
            | "." ident                               (* field *)
            | "." int_lit                             (* tuple field *)
            | "as" type ;                             (* cast *)
primary     = int_lit | float_lit | char_lit | string_lit | cstring_lit | "true" | "false"
            | ident
            | ident "::" ident                        (* (0.3) a variant or an associated function *)
            | ident "{" [ field_init { "," field_init } [ "," ] ] "}"   (* struct (or union: one field) literal *)
            | "(" ")" | "(" expr ")" | "(" expr "," [ expr { "," expr } [ "," ] ] ")"
            | "[" "]" | "[" expr ";" expr "]" | "[" expr { "," expr } [ "," ] "]"
            | [ label ] block_like ;
field_init  = ident ":" expr ;
label       = ident ":" ;                             (* only before loop, while, for *)

if_expr     = "if" cond block [ "else" ( block | if_expr ) ] ;
match_expr  = "match" cond "{" { arm } "}" ;          (* (0.3) *)
arm         = pattern [ "if" expr ] "=>" ( block_like [ "," ] | expr ( "," | before "}" ) ) ;
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

A function stored in a field is called as `(s.f)(x)`; `s.f(x)` calls a
method. A field of a struct can be reached through a pointer to it: `p.f`
is `(*p).f` *(0.3)*.

**Assignment** evaluates its right-hand side first, then the place; a
compound assignment then reads the place's old value *(0.3; before, the
place came first)*.

**match** *(0.3)* evaluates the scrutinee once, then tries the arms in
order: an arm is taken when its pattern matches and its guard (if any) is
true; its bindings are copies, made before the guard. The arms (without
guards) must cover every value, and every arm must be reachable; a missing
value is named in the error (`non-exhaustive match: 'Shape::Empty' is not
covered`). A match is an expression, typed like `if`.

**Slices** *(0.3)* `[T]` are a pointer and a length (`s.ptr`, `s.len`), made
by slicing an array or a slice (checked: `lo <= hi <= len`), or a raw
pointer (`p[lo..hi]`, unchecked). Indexing a slice is checked. Like
pointers, slices are views: writing through one needs no `mut`. A failed
check writes `index out of bounds: index I, length N` (or `slice range out
of bounds: ...`) to stderr and exits with code 101.

## Layout, conventions and C

Tachyon guarantees **nothing** about the layout of its own types (the order
and offsets of a struct's fields, the layout of tuples, enums and slices)
or about the calling convention of its own functions: the compiler is free
to choose them (0.3 orders a struct's fields to save padding), and
optimizations may rely on that freedom. C compatibility is asked for
explicitly, and then it is exact:

- `#[repr(C)]` types have C's layout: fields in order, each at its C
  offset; unions overlap their fields; `packed` and `align(N)` as with
  GCC's attributes. A fieldless `#[repr(C)]` enum is a C `int`; one with
  fields is a C struct: an `int` tag, then a union of one struct per
  variant (RFC 2195's layout). `#[repr(u8)]` (any integer type) sets an
  enum's tag type; with fields, each variant is then laid out as a struct
  starting with the tag.
- `extern "C"` functions (imported in an `extern "C" { ... }` block, or
  defined with `extern "C" fn`) and `extern "C" fn` pointers follow the C
  calling convention of the target: AAPCS64 as on macOS, or System V
  x86-64, for every argument and result (aggregates in registers or on the
  stack, homogeneous float aggregates, MEMORY class, variadic calls).
  Defined ones have an unmangled global symbol; imported statics are
  reached through the GOT; `extern "C" static` defines one C can use.
- Every type in an `extern "C"` signature, function pointer type or static
  must be **FFI-safe**: an integer or float, bool, a raw pointer (to
  anything: a pointer to a non-C type is an opaque handle), an
  `extern "C" fn` pointer, or a `#[repr(C)]` (or integer-repr enum) type
  whose fields are FFI-safe (arrays of them inside structs too). Slices,
  tuples, default-layout structs and enums, and plain `fn` pointers are
  rejected, with a hint. Variadic arguments may be any FFI-safe type
  (`f32` is passed as a double).
- A plain `fn` and an `extern "C" fn` are different types: a tachyon
  function cannot be handed to C as a callback; define the callback with
  `extern "C" fn`.

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
