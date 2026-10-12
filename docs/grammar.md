# Tachyon grammar

This is the grammar of tachyon 0.4, as the compiler implements it
(`compiler/src/10_lexer.tach`, `compiler/src/21_parser.tach`; the seed
implements the language of 0.1 in `seed/src/lexer` and `seed/src/parser`).
What 0.3 added is marked *(0.3)*, what 0.4 added *(0.4)*.
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
raw_ident    = "r#" ident ;                            (* (0.4) an identifier even if a keyword: r#type *)
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
import in let loop match mut return static struct true type union use while`
(`import` and `use` since 0.4).

**Reserved** (an error if used): the keywords `trait pub mod super where
unsafe defer dyn move`, and the tokens `?` `@`. `self` and `Self` are
ordinary names, with a meaning in methods (see Items).

A token is *joint* when no whitespace follows it.
`#` starts an attribute *(0.3)*. The parser splits a joint
`&&` in prefix position into `& &`; `**` is not a token, so `**p` and `**T`
are two `*`.

## Items

```ebnf
program      = { item } EOF ;
item         = [ "pub" ] ( fn_decl | extern_item | [ attributes ] ( struct_decl | union_decl | enum_decl )
             | const_decl | static_decl | type_alias
             | import_item | use_item | mod_item )      (* pub, mod: (0.5); import, use: (0.4) *)
             | impl_block ;
import_item  = "import" string_lit [ "as" ident ] ";" ;   (* (0.4) a C header, see "Importing C headers"; as: (0.5) *)
use_item     = "use" path "::" ( "*" | "{" use_name { "," use_name } [ "," ] "}" ) ";"
             | "use" path "::" use_name ";" ;          (* (0.4) variants of an enum; (0.5) paths, as *)
use_name     = ident [ "as" ident ] ;
mod_item     = "mod" ident ";" ;                       (* (0.5) the module in ident.tach, see "Modules" *)
path         = ident { "::" ident } ;                  (* crate, self, super, std, modules, an enum *)

fn_decl      = "fn" ident [ generics ] "(" [ params ] ")" [ "->" type ] block ;
generics     = "<" ident { "," ident } [ "," ] ">" ;  (* (0.5) type parameters, see "Generics" *)
params       = param { "," param } [ "," ] ;
param        = [ "mut" ] ident ":" type ;              (* "_" ignores the argument *)

extern_item  = "extern" '"C"' "{" { [ link_name ] ( c_fn | c_static ) } "}"   (* (0.3) imports from C *)
             | "extern" '"C"' fn_decl                                 (* (0.3) C's convention, an unmangled symbol *)
             | "extern" '"C"' "static" [ "mut" ] ident ":" type "=" expr ";" ;  (* (0.3) a static C can use *)
                                       (* 0.2's `extern fn f(...);` was removed in 0.4 *)
c_fn         = "fn" ident "(" [ c_params ] ")" [ "->" type ] ";" ;
c_params     = "..." | param { "," param } [ "," [ "..." ] ] ;
c_static     = "static" [ "mut" ] ident ":" type ";" ;
link_name    = "#" "[" "link_name" "=" string_lit "]" ;   (* (0.4) the C symbol, when not the name *)

attributes   = { "#" "[" "repr" "(" repr { "," repr } ")" "]" } ;    (* (0.3) *)
repr         = "C" | "packed" [ "(" int_lit ")" ] | "align" "(" int_lit ")" | int_type ;   (* packed(N): (0.4) *)

struct_decl  = "struct" ident [ generics ] "{" [ field { "," field } [ "," ] ] "}" ;
union_decl   = "union" ident "{" [ field { "," field } [ "," ] ] "}" ;   (* (0.3) #[repr(C)] only *)
field        = [ "pub" ] ident ":" type ;              (* pub (0.5): fields are as visible as their struct *)
enum_decl    = "enum" ident [ generics ] "{" [ variant { "," variant } [ "," ] ] "}" ;   (* (0.3) *)
variant      = ident [ "(" type { "," type } [ "," ] ")" ] [ "=" expr ] ;  (* "=": fieldless enums only *)
impl_block   = "impl" [ generics ] type "{" { [ "pub" ] fn_decl } "}" ;   (* (0.3); generics, a type with arguments: (0.5) *)

const_decl   = "const" ident ":" type "=" expr ";" ;   (* integer, float, bool, fieldless enum (0.4) or C string (0.4) *)
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
type = path [ type_args ]                             (* i8 ... u64, isize, usize, f32, f64, bool, a struct, union, enum or alias, Self,
                                                         a type parameter; m::T, Vec<T> (0.5) *)
     | "*" type                                       (* raw pointer *)
     | "(" ")" | "(" type ")" | "(" type "," [ type { "," type } [ "," ] ] ")"
     | "[" type ";" expr "]"                          (* the length is a constant expression *)
     | "[" type "]"                                   (* (0.3) a slice: a pointer and a length *)
     | [ "extern" '"C"' ] "fn" "(" [ type { "," type } [ "," ] ] ")" [ "->" type ]
                                                      (* not variadic; extern "C" fn (0.3) is another type *)
     | "!" ;                                          (* never: e.g. `fn exit(c: i32) -> !` *)
type_args = "<" type { "," type } [ "," ] ">" ;       (* (0.5); `>>` closes two lists *)
```

## Patterns

```ebnf
pattern  = single { "|" single } ;                     (* (0.3) alternatives *)
single   = "_" | [ "mut" ] ident                      (* a binding, or a constant's name *)
         | literal [ "..=" literal ]                  (* (0.3) integers, chars and bools; inclusive ranges *)
         | ident "::" ident [ "(" [ pattern { "," pattern } [ "," ] ] ")" ]   (* (0.3) a variant *)
         | ident "::" ident "..=" ident "::" ident    (* (0.4) variants in declaration order *)
         | ident "(" [ pattern { "," pattern } [ "," ] ] ")"   (* (0.4) a variant brought in by `use` *)
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
            | "." ident [ "::" type_args ] "(" [ expr { "," expr } [ "," ] ] ")"   (* (0.3) method call; type arguments (0.5) *)
            | "." ident                               (* field *)
            | "." int_lit                             (* tuple field *)
            | "as" type ;                             (* cast *)
primary     = int_lit | float_lit | char_lit | string_lit | cstring_lit | "true" | "false"
            | segment { "::" segment }               (* a name; (0.3) a variant or an associated function
                                                         (T::m); (0.5) an item of a module (m::f, a::b::T::m) *)
            | segment { "::" segment } "{" [ field_init { "," field_init } [ "," ] ] "}"   (* struct (or union: one field) literal *)
            | "(" ")" | "(" expr ")" | "(" expr "," [ expr { "," expr } [ "," ] ] ")"
            | "[" "]" | "[" expr ";" expr "]" | "[" expr { "," expr } [ "," ] "]"
            | [ label ] block_like ;
segment     = ident [ "::" type_args ] ;               (* (0.5) the turbofish: max::<i64>, Vec::<u8>::new *)
field_init  = ident ":" expr ;
label       = ident ":" ;                             (* only before loop, while, for *)

if_expr     = "if" cond block [ "else" ( block | if_expr ) ] ;
match_expr  = "match" cond "{" { arm } "}" ;          (* (0.3) *)
arm         = pattern [ "if" expr ] "=>" ( block_like [ "," ] | expr ( "," | before "}" ) ) ;
loop_expr   = "loop" block ;                          (* its value comes from `break value` *)
while_expr  = "while" cond block ;
for_expr    = "for" pattern "in" ( range | expr ) block ;   (* a..b, a..=b; slices and arrays (0.4) *)
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

*(0.5)* The compiler reports several errors at once, sorted by position (up
to 50); the exit status is 1. After a syntax error the parser goes on at the
next statement of the block (past its `;`, or up to the `}` that closes the
block) or, outside a function, at the next item that starts a line; a
program with syntax errors is not type-checked. The type checker goes on at
the next statement of the function (or at the next function); the names a
failed `let` binds have the error type, and errors that follow from it are
not reported. An error in the declarations (struct fields, signatures,
constants...) ends the checking. (0.4 stopped at the first error.)

## Additions of 0.4

**Enums.** A `const` may have a fieldless enum type (`const F: Color =
Color::Green;`); in a pattern its name matches its variant. `n as E`
converts an integer to a fieldless enum, checked: a value that is no
variant's discriminant writes `invalid value V for enum E` to stderr and
exits with code 101, at every optimization level. Fieldless enums compare
with `<`, `<=`, `>` and `>=` in declaration order, which must be the order
of their discriminants (an error otherwise). `E::A..=E::C` matches the
variants from `A` to `C` in declaration order (variants without fields).
`use E::*;` and `use E::{A, B};` bring variants into scope by their own
names: as values (`A`), calls (`B(1, 2)`) and patterns (`A`, `B(x, _)`).
A local, constant, static or function of the same name wins. `use` is the
keyword modules will extend (0.5): `use path::{...};`.

**Layout queries.** `size_of(T)` and `align_of(T)` are integer constants
typed like an integer literal (`[u8; size_of(Header)]`). For a tachyon
type they are fixed per compiler, not by the language. (In 0.4 a program's
own functions named `size_of` or `align_of` won; since 0.5 they are
builtins, and no item may have those names.)

**Strings.** `c"..."` initializes a `const` or a `static` of type `*u8`:
the address of the bytes (`const PROMPT: *u8 = c"> ";`).

**Slices.** `s.len` is `i64` (it was `u64`): lengths and indices mix
without casts. Indexing takes any integer type. `for x in s` iterates a
slice or an array by value (the sequence is evaluated once; `break`,
`continue` and labels work as in other loops).

**Raw identifiers.** `r#name` is an identifier even when `name` is a
keyword (`s.r#type`); C names that are tachyon keywords are imported so.

**C.** `#[repr(C, packed(N))]` aligns fields to at most N (GCC's
`#pragma pack(N)`); `#[link_name = "sym"]` in an extern block names the C
symbol of a declaration; a static shared with C may be an array.

## Additions of 0.5

### Generics

Functions, structs, enums and impl blocks take type parameters:

```
fn max<T>(a: T, b: T) -> T { if a > b { a } else { b } }

struct Vec<T> { ptr: *T, len: i64, cap: i64 }

impl<T> Vec<T> {
    fn push(self: *Vec<T>, x: T) { ... }
    fn map<U>(self: *Vec<T>, f: fn(T) -> U) -> Vec<U> { ... }
}

enum Option<T> { None, Some(T) }
```

A generic item is a *template*, checked when it is instantiated, not as
it is written (as in C++ and Zig: there are no bounds; `a > b` is checked
for each `T` it is used with). Each instantiation with new type arguments
makes a separate function, struct or enum (*monomorphization*): no boxing,
no dynamic dispatch, and every optimization applies to the instance.
Bounded generics (traits) may come later, as a refinement: a program that
compiles today will keep its meaning.

Type arguments are written after a type's name (`Vec<i64>`, `Option<*u8>`)
and, in expressions, after `::` (the "turbofish"): `max::<u8>(a, b)`,
`Vec::<u8>::new()`, `Pair::<i64> { a: 1, b: 2 }`, `v.map::<f64>(f)`. They
may be left out where they can be inferred: from the types of the
arguments (or of a struct literal's fields, or of a variant's fields), and
from the type the context expects (`let v: Vec<i64> = Vec::new();`,
`let n: Option<i32> = Option::None;`). Literals without a suffix are
looked at last: `max(x, 1)` with `x: u8` is `max::<u8>`. A generic
function used as a value needs its arguments: `let f = max::<i64>;`.

`impl<T> Vec<T> { ... }` holds the methods of every `Vec<T>`; its
parameters come first, then a method's own (`map<U>`). `impl Vec<i64> {
... }` holds methods of that instance only. In a pattern, a generic enum's
name stands for the instance being matched: `Option::Some(x)`. `size_of(T)`
and `align_of(T)` work on type parameters.

An error inside an instance is reported with the chain of instantiations
that led to it (`= note: in instantiation of 'max<bool>' at ...`). An
instantiation whose type arguments grow without end (`fn f<T>(x: T) {
f((x, x)) }`) is an error.

**Symbols.** An instance's assembly symbol is its template's, then `.G`
and a code of its type arguments that can be read back: `max.Gl` is
`max<i64>`, `Vec.Gl.push` is `Vec<i64>::push`, `Pair.GPh` is `Pair<*u8>`
(primitives by a letter as in C++'s mangling: `a` i8, `s` i16, `i` i32, `l`
i64, `h` u8, `t` u16, `j` u32, `m` u64, `f` f32, `d` f64, `b` bool, `v` (),
`z` !; then `P` pointer, `S` slice, `A<n>_` array, `T<n>_` tuple, `F<n>_`
and `C<n>_` (extern "C") function, `N<length><symbol>` struct or enum).
Instances are made in the order the checker meets them, so the output is
deterministic. `extern "C"` items cannot be generic; an `extern "C" fn` may
take or return a `#[repr(C)]` instance (`Pair<i32>`).

### Modules

A file is a module. The files named on the command line make the root
module (the *crate*); `mod name;` in a module's file loads the child module
`name` from `name.tach`, or `name/mod.tach`, next to the file (from a
module's file `a.tach`, in the directory `a/`: `a/name.tach`). There are
no inline modules.

```
// main.tach
mod geometry;                     // geometry.tach
use geometry::shapes::{Shape, area};
use geometry::Rect as Box;

// geometry.tach
pub mod shapes;                   // geometry/shapes.tach
pub struct Rect { pub w: i64, pub h: i64 }
fn helper() { ... }               // private to geometry (and its children)
```

Every item is private to its module (and the modules inside it) unless
declared `pub`; a module declared `pub mod` can be reached from outside
its parent. A struct's fields are as visible as the struct (`pub` on a
field is allowed and changes nothing). Methods are visible wherever their
type is.

Paths name items through modules: `geometry::shapes::area(s)`,
`geometry::Rect { w: 1, h: 2 }`, `shapes::Shape::Rect(r)` (a variant),
`util::Vec::<u8>::new()` (an associated function). A path starts with a
name in scope (an item, a child module, an import), `crate` (the root
module), `self` (this module), `super` (the parent module) or `std`.

`use` brings names into scope: `use a::b::c;`, `use a::b::c as d;`, `use
a::b::{c, d as e};`, `use a::b::*;` (every public item of module `a::b`,
or every variant of an enum). Names declared in a module win over those a
`*` brings in. `pub use` re-exports: the module's users see the name as
one of its items. Imports are resolved on demand, so their order does not
matter; an import that depends on itself is an error.

`import "stdio.h";` *(0.4)* makes the declarations of C headers visible in
the importing module; `import "stdio.h" as c;` names them instead
(`c::printf(...)`). All the imported headers of a program share one module
of C declarations. They see the root module's names: a type the program
declares replaces the header's type of the same name (as in 0.4), while the
program's functions and constants of the same names coexist with the
imported ones (`c::abs` and the program's `abs`).

Items of the root module keep their names as symbols; an item of module
`a::b` has the symbol `a.b.name` (`extern "C"` items and `#[link_name]`
keep their C names). `tachyonc a.tach b.tach` still compiles several files
as one root module.

### The standard library

The module `std` is built into the compiler, read when a program names it
(`std::Vec<i64>`, `use std::*;`): `Option<T>` and `Result<T, E>` (`is_some`,
`unwrap`, `unwrap_or`, `ok`...), `Vec<T>` (`new`, `with_capacity`, `push`,
`pop`, `get` and `set` checked like a slice's index, `len`, `as_slice`,
`clear`, `free`), `Buf` (a byte buffer: `push`, `push_str`, `push_cstr`,
`push_int`, `as_slice`), and `print`, `println`, `print_int`, `print_cstr`.
Failures (`unwrap` of `None`, an index out of bounds) write a message to
stderr and exit with 101. Its source is `compiler/std/std.tach`.

### Keywords

`pub` and `mod` are keywords; `super` is no longer reserved.

## Importing C headers

`import "stdio.h";` *(0.4)* reads a C header and adds its declarations to
the program; `import "./mylib.h";` (a path starting with `./` or `../`)
is relative to the importing file; `-I DIR` adds include directories. All
imports of a program are read as one translation unit, as the target's C
compiler reads them: its predefined macros and its include path come
from `cc -dM -E -v` (`$TACHYON_CC` instead of `cc`), so headers need the
target's C compiler on the host (a macOS host for both macOS targets, an
x86-64 Linux host for `x86_64-linux`).

What a header declares becomes tachyon declarations
(`tachyonc --emit-imports file.tach -o decls.tach` shows them):

| C | tachyon |
|---|---|
| `char` (plain), `signed char`, `unsigned char` | `u8`, `i8`, `u8` (`c"..."` strings are `*u8`) |
| `short`, `int`, `long`, `long long`, and the unsigned ones | `i16`, `i32`, `i64`, `i64`, and `u16` ... `u64` |
| `_Bool`, `float`, `double` | `bool`, `f32`, `f64` |
| `long double` | `f64` on aarch64-macos; not imported on x86-64 |
| `void *`, `T *` | `*u8`, `*T` |
| function pointers | `extern "C" fn(...) -> R` (variadic ones: `*u8`) |
| `struct`, `union` | `#[repr(C)]` types with C's exact layout: bit-fields become byte arrays (`_bitfield0`); `aligned`, `packed` and `#pragma pack` become `align(N)`, `packed(N)` or padding fields (`_pad0`); anonymous members are fields `_anon0` of types `<Struct>_anon0` |
| `typedef` | a `type` alias; a typedef of an anonymous struct names it |
| `enum` | `type E = u32;` (`i32` with negative values, the smallest with `packed`) and a `const` of type `E` per enumerator (`i32` for anonymous enums) |
| object-like macros of integer or float constants | a `const` of their C type (`#define SIZE ((size_t)-1)` is `const SIZE: size_t`) |
| macros naming a variable or a function (`#define stdin __stdinp`) | the same symbol under the macro's name |
| functions, `extern` variables | an `extern "C"` block; asm labels (`realpath` as `_realpath$DARWIN_EXTSN`) become `#[link_name]` |

Tags and ordinary names share tachyon's type namespace: a tag whose name
a different typedef takes is renamed `struct_<tag>`. A record whose C
layout tachyon cannot express (alignment above 16; packed and aligned at
once), or that holds such a record or a type left out, is imported as an
opaque struct, usable through pointers. Left out, and named with the
reason when a program uses them: `long double` (x86-64), `_Complex`,
`__int128`, vector types, thread-local variables, `static` and `inline`
functions, variables defined in the header, function-like macros, string
macros, `errno` (a macro around a call: `*__error()` on macOS,
`*__errno_location()` with glibc). The program's own declarations win
over imported ones of the same name (a program may declare
`extern "C" { fn printf(...) -> i32; }` and import `stdio.h`). Imported
names are global; 0.5's modules will give them a namespace.

## C headers of a program

`tachyonc --emit-header prog.tach -o prog.h` *(0.4)* writes the C view of
a program: its `extern "C" fn` definitions and `extern "C"` statics, and
the `#[repr(C)]` and integer-repr types they need, in dependency order,
with an include guard, `extern "C"` for C++, and a `_Static_assert` of
each type's layout. A fieldless enum is its integer type with constants
`E_V`; an enum with fields is RFC 2195's struct (`tag`, then a union `u`
of `struct { _0; _1; } V`), an integer-repr one a union of structs that
start with the tag; `packed(N)` is `#pragma pack(N)`. Types of default
layout appear only behind pointers, as incomplete structs. A name that is
a C keyword is an error.
