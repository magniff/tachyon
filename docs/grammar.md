# Tachyon grammar

This is the grammar of tachyon 0.4, as the compiler implements it
(`compiler/src/front/lexer/`, `compiler/src/front/parser/`; the seed
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
string_lit   = '"' { char | escape } '"' ;             (* a [u8] slice (0.6; before, a (*u8, u64) pair) *)
cstring_lit  = 'c"' { char | escape } '"' ;            (* a NUL-terminated *u8; no NUL inside *)
escape       = "\n" | "\t" | "\r" | "\0" | "\\" | '\"' | "\'"
             | "\x" hex hex                            (* one byte *)
             | "\u{" hex { hex } "}" ;                 (* UTF-8 encoded; ASCII only in char_lit *)
```

`_` may separate digits (`1_000_000`, `255_u8`). After `.`, digits are a
tuple index, so `t.0.1` is `(t.0).1`. A literal must not be followed
directly by other letters (`3e` and `1foo` are errors).

**Keywords:** `as break const continue defer else enum extern false fn for
if impl import in let loop match mod mut pub return static struct trait true
type union unsafe use while move` (`import` and `use` since 0.4, `pub` and
`mod` since 0.5, `defer` since 0.6, `unsafe` and `trait` since 0.9, `move`
since 0.14).

**Reserved** (an error if used): the keywords `where dyn` (and `move` until
0.14, a keyword since), and the
token `@` (and `?` until 0.15, an operator since). `self` and `Self` are
ordinary names, with a meaning in methods (see Items).

A token is *joint* when no whitespace follows it.
`#` starts an attribute *(0.3)*. The parser splits a joint
`&&` in prefix position into `& &`; `**` is not a token, so `**p` and `**T`
are two `*`.

## Items

```ebnf
program      = { item } EOF ;
item         = [ "pub" ] [ attributes ] [ "pub" ]       (* (0.6) attributes may come before pub *)
               ( fn_decl | extern_item | struct_decl | union_decl | enum_decl
             | const_decl | static_decl | type_alias
             | import_item | use_item | mod_item )      (* pub, mod: (0.5); import, use: (0.4) *)
             | impl_block | trait_decl ;             (* trait, impl Trait for: (0.9) *)
import_item  = "import" string_lit "as" ident ";" ;     (* (0.4) a C header, see "Importing C headers"; as: (0.5), required (0.8) *)
use_item     = "use" path "::" "{" use_name { "," use_name } [ "," ] "}" ";"
             | "use" path "::" use_name ";" ;          (* (0.4) variants of an enum; (0.5) paths, as; no "*" (0.8) *)
use_name     = ident [ "as" ident ] ;
mod_item     = "mod" ident ";"                         (* (0.5) the module in ident.tach, see "Modules" *)
             | "mod" ident "{" { item } "}" ;          (* (0.6) an inline module *)
path         = ident { "::" ident } ;                  (* crate, self, super, std, modules, an enum *)

fn_decl      = [ "unsafe" ] "fn" ident [ generics ] "(" [ params ] ")" [ "->" type ] block ;
                                                       (* unsafe: (0.9), see "Unsafe code" *)
generics     = "<" tparam { "," tparam } [ "," ] ">" ;  (* (0.5) type parameters, see "Generics" *)
tparam       = ident [ ":" path { "+" path } ] ;       (* bounds: (0.9), see "Traits" *)
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

attributes   = { "#" "[" attribute "]" } ;
attribute    = "repr" "(" repr { "," repr } ")"        (* (0.3) structs, unions, enums *)
             | "inline" [ "(" "never" ")" ] | "cold" ;  (* (0.6) functions *)
repr         = "C" | "packed" [ "(" int_lit ")" ] | "align" "(" int_lit ")" | int_type ;   (* packed(N): (0.4) *)

struct_decl  = "struct" ident [ generics ] "{" [ field { "," field } [ "," ] ] "}" ;
union_decl   = "union" ident "{" [ field { "," field } [ "," ] ] "}" ;   (* (0.3) #[repr(C)] only *)
field        = [ "pub" ] ident ":" type ;              (* pub (0.5): fields are as visible as their struct *)
enum_decl    = "enum" ident [ generics ] "{" [ variant { "," variant } [ "," ] ] "}" ;   (* (0.3) *)
variant      = ident [ "(" type { "," type } [ "," ] ")"   (* "=": fieldless enums only *)
                     | "{" [ ident ":" type { "," ident ":" type } [ "," ] ] "}" ] [ "=" expr ] ;   (* struct-like (0.17) *)
impl_block   = "impl" [ generics ] [ path "for" ] type "{" { [ attributes ] [ "pub" ] fn_decl } "}" ;
                                                       (* (0.3); generics, a type with arguments: (0.5); a trait's: (0.9) *)
trait_decl   = "trait" ident "{" { [ attributes ] [ "unsafe" ] "fn" ident [ generics ] "(" [ params ] ")" [ "->" type ] ( ";" | block ) } "}" ;

const_decl   = "const" ident ":" type "=" expr ";" ;   (* integer, float, bool, fieldless enum (0.4) or C string (0.4) *)
static_decl  = "static" [ "mut" ] ident ":" type "=" expr ";" ;   (* constant initializer *)
type_alias   = "type" ident [ generics ] "=" type ";" ;   (* generics: (0.6) *)
```

Items may refer to each other in any order. Constants and statics are
initialized by constant expressions: literals, other constants, unary and
binary operators, casts, enum variants, and array/tuple/struct literals of
those. Constant arithmetic wraps like run-time arithmetic.

**Enums** *(0.3)*. A fieldless enum's variants have discriminants (0, 1, ...
unless given with `= expr`); such an enum is a scalar, compared with `==`
and `!=` and cast to an integer with `as`. Variants with fields are tuple
variants, `V(A, B)`, or struct-like ones (0.17), `V { a: A, b: B }`. Values
are written `E::V`, `E::V(a, b)` and `E::V { a: x, b }` (a struct literal's
form: every field once, in any order, `b` for `b: b`; the fields are
evaluated in the order written). A struct-like variant is laid out as the
tuple variant of its fields' types in declaration order; its fields are read
only through patterns (`E::V { a, .. }`), not with `.a`, and it is neither
built nor matched by position (`E::V(x, y)` is an error that names the
form to write). `#[derive]` treats it as the tuple variant, and Debug writes
`V { a: 1, b: 2 }`.

**Impl blocks** *(0.3)* hold the methods and associated functions of a
struct or enum. A function whose first parameter is named `self`, of type
`T` or `*T`, is a method, called as `x.m(args)`: the compiler passes `&x`
or `*x` as the method needs (a temporary of a compound type may be passed by
address too). Others are called as `T::f(args)` (methods too, with the
receiver first). Inside an impl block, `Self` names the type.

**Attributes** *(0.3)*: `#[repr(C)]` gives a struct, union or enum C's
layout; `#[repr(C, packed)]` packs a struct (or union) without padding,
`#[repr(C, align(N))]` raises its alignment to N (a power of two up to
4096; above 16 since 0.5, with stack frames realigned where needed);
`#[repr(u8)]` (any integer type) sets the tag type of an enum. Functions
take `#[inline]`, `#[inline(never)]` and `#[cold]` (0.6). Any other
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
         | [ ident "::" ] ident "{" [ fpat { "," fpat } ] [ "," ".." ] [ "," ] "}"   (* (0.17) a variant's fields by name *)
         | "(" [ pattern { "," pattern } [ "," ] ] ")" ;
literal  = [ "-" ] int_lit | char_lit | "true" | "false" | ident   (* ident: a constant *)
         | ident "::" ident { "::" ident } ;          (* (0.17) a constant's path: i8::MIN, m::TOP *)
fpat     = [ "mut" ] ident | ident ":" pattern ;       (* `a` is `a: a` *)
```

`(p)` is `p`; `(p,)` is a one-element tuple pattern. A path matched
against an integer is a constant (0.17): `i8::MIN..=-1`, `0..=m::TOP`,
`i64::MAX` alone; against an enum, `E::A..=E::C` is a variant range. A
variant's pattern by name (0.17) names each field once, in any order; with
`..` (last) the fields it leaves out match anything, without it every
field is named (`E::V { .. }` matches the variant whatever its fields, a
tuple variant's too). The enum's path may have module segments (`m::E::V {
.. }`). An identifier that names a constant (and no local) is that
constant's value; any other is a binding. Every alternative of an
or-pattern binds the same variables, with the same types. The patterns of
`let` and `for` must match every value (no literals, ranges, alternatives,
or variants of enums with several).

Patterns on references (0.18.1, Rust's default binding modes): a pattern
other than a binding or `_`, matched against a value of type `&T` or
`&mut T` (T not itself a reference), matches the T the reference points
to, and the bindings inside it are references into that T: `&U` for a
field of type U, `&mut U` when every reference matched through is `&mut`.
A field of slice type `[U]` binds a copy (a slice is a view already). A
binding under a reference cannot be `mut`, nor an alternative of an
or-pattern. `match e { E::A(n) => *n, E::B(v) => v.len(), E::C => 0 }`
with `e: &E`; `match *e` matches a copy of the value (its owned fields
bound so may be read, not changed or moved). There is no `&pat` pattern.

## Statements and blocks

```ebnf
block       = "{" { stmt } [ expr ] "}" ;
stmt        = ";"                                      (* empty statement *)
            | "let" pattern [ ":" type ] "=" expr ";"
            | "defer" ( block [ ";" ] | expr ";" )    (* (0.6) *)
            | block_like [ ";" ]
            | expr ";" ;
block_like  = block | "unsafe" block | if_expr | match_expr | loop_expr | while_expr | for_expr ;
                                                       (* unsafe block: (0.9) *)
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
immutable `x`; using a raw pointer is unsafe code (0.9, see "Unsafe code").

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
            | segment { "::" segment } "{" [ field_init { "," field_init } [ "," ] ] "}"   (* struct (or union: one field) literal; (0.17) a struct-like variant's *)
            | "(" ")" | "(" expr ")" | "(" expr "," [ expr { "," expr } [ "," ] ] ")"
            | "[" "]" | "[" expr ";" expr "]" | "[" expr { "," expr } [ "," ] "]"
            | [ label ] block_like ;
segment     = ident [ "::" type_args ] ;               (* (0.5) the turbofish: max::<i64>, Vec::<u8>::new *)
field_init  = ident ":" expr ;
label       = ident ":" ;                             (* only before loop, while, for *)

if_expr     = "if" [ "let" pattern "=" ] cond block [ "else" ( block | if_expr ) ] ;   (* if let: (0.6) *)
match_expr  = "match" cond "{" { arm } "}" ;          (* (0.3) *)
arm         = pattern [ "if" expr ] "=>" ( block_like [ "," ] | expr ( "," | before "}" ) ) ;
loop_expr   = "loop" block ;                          (* its value comes from `break value` *)
while_expr  = "while" [ "let" pattern "=" ] cond block ;   (* while let: (0.6) *)
for_expr    = "for" pattern "in" ( range | expr ) block ;   (* a..b, a..=b; slices and arrays (0.4) *)
cond        = expr ;                                  (* without struct literals at the top level *)
```

In conditions (`if`, `while`) and `for` ranges, `Name {` starts the body, not
a struct literal; inside parentheses, brackets, braces and call arguments
struct literals are allowed again (`if f(P { x: 1 }) { ... }`). (0.17)
`Name { a: ...` (a field name and its colon, not a labelled loop) is a
literal there too: `match E::V { a: 1 } { ... }`.

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

**Indexing** *(0.14)*: in `a[i]`, `a[lo..hi]` and a vector `load` or
`store` of `a`, the base `a` is evaluated first, to its location when it
is a place (a variable, a static, a field, an element, `*p`), without
reading it; then the index or the bounds, left to right; and only then
is what `a` holds read: a slice's pointer and length (for the check and
the access), a pointer's value. An index whose evaluation changes `a`
(a call that grows the table `a` views and stores the new view in `a`)
is seen, and nothing reads the old storage; before 0.14, slicing and
indexing a pointer read `a` before the bounds. With the assignment rule,
`a[i] = e` and `a[i] += e` evaluate `e`, then `a`'s location, `i`, and
then read `a`. A base that is not a place (`f()[i]`, `v.as_slice()[i]`)
is a value, computed before the index; and in `a[i][j]` the location of
`a[i]` is computed before `j`, and only the inner slice is read after
it.

**match** *(0.3)* evaluates the scrutinee once, then tries the arms in
order: an arm is taken when its pattern matches and its guard (if any) is
true; its bindings are copies, made before the guard. The arms (without
guards) must cover every value, and every arm must be reachable; a missing
value is named in the error (`non-exhaustive match: 'Shape::Empty' is not
covered`). A match is an expression, typed like `if`.

**Slices** *(0.3)* `[T]` are a pointer and a length (`s.ptr`, `s.len`), made
by slicing an array or a slice (checked: `lo <= hi <= len`), or a raw
pointer (`p[lo..hi]`, unchecked). Indexing a slice is checked, and so is
indexing a fixed array *(0.7)*. Like
pointers, slices are views: writing through one needs no `mut`. A failed
check writes `index out of bounds: index I, length N` (or `slice range out
of bounds: ...`) to stderr and exits with code 101.

## Undefined behaviour

The principle: a tachyon program means one thing, the same at every
optimization level and on every target, so that it can be reasoned about
(by people and by agents) from what it says. Where C leaves behaviour
undefined, tachyon defines it, or checks it and stops with a message.
Since 0.9 there is none at all in safe code: the operations that can
have it (all of them through raw pointers, unions or C) are allowed only
in unsafe code, `unsafe { ... }` and `unsafe fn`.

**Defined** (each case checked at -O0 and -O2, on AArch64 and x86-64, at
run time and in constant folding, which agree):

- Integer overflow of `+`, `-`, `*` and unary `-` wraps at the type's
  width (two's complement): `i32::MAX + 1 == i32::MIN`,
  `-i64::MIN == i64::MIN`.
- Division and remainder by zero: `x / 0 == 0`, `x % 0 == x`.
  `MIN / -1 == MIN` and `MIN % -1 == 0`.
- Shifts: the amount is taken modulo 64 for 64-bit operands, and modulo
  32 for narrower ones, which are shifted as 32-bit values and then
  truncated (`1u8 << 9 == 0`, `1u8 << 33 == 2`); a negative amount is a
  large one (`1 << -1 == 1 << 63`). `>>` is arithmetic on signed types,
  logical on unsigned ones.
- Float to integer conversion (`as`): NaN becomes 0; a signed target
  saturates at its own bounds (`1e30 as i64 == i64::MAX`,
  `3e9 as i32 == i32::MAX`); `u64` saturates at its maximum above it and
  wraps below zero (`-5.0 as u64 == 2^64 - 5`, as through `i64`);
  narrower unsigned targets take the low bits of the `i64` conversion
  (`300.0 as u8 == 44`).
- Floating point is IEEE 754 double and single precision, without
  reassociation or contraction (no fast-math); comparisons with NaN are
  false, except `!=`, which is true.
- Evaluation order: operands left to right, the right-hand side of an
  assignment before its place, the index of `a[i]` (the bounds of
  `a[lo..hi]`) before what the place `a` holds is read (0.14), each
  operand of `==` on aggregates once.
- Indexing a slice or a fixed array, and slicing an array or a slice, is
  checked: a failure writes `index out of bounds: index I, length N` (or
  `slice range out of bounds: ...`) to stderr and exits with 101 (arrays
  since 0.7). A cast of an integer to an enum is checked (0.4), as are
  std's `unwrap`s.
- There is no uninitialized variable: `let` and `static` require an
  initializer; aggregates are written in full by their literals.
- There is no type-based aliasing rule: memory read through a pointer of
  another type is that memory's bytes, reinterpreted (when the pointer is
  valid; see below). `#[repr(C)]` unions read their bytes the same way.
- Runaway recursion exhausts the stack and the operating system stops
  the program (a guard page); it never corrupts memory. It is not yet a
  panic with a message.

**Safe code has no undefined behaviour** *(0.9)*. Everything that can
have undefined behaviour is an *unsafe operation*, allowed only in unsafe
code: inside an `unsafe { ... }` block or the body of an `unsafe fn` (see
"Unsafe code" below for the rules, including raw pointer
parameters). The unsafe operations, and what they promise:

- Dereferencing a raw pointer (`*p`, `p.f`, a method called through `p`)
  that does not point to live memory of its type and alignment: null,
  dangling (freed, or a returned local's address), out of bounds or
  misaligned. A *borrow* (`&T` / `&mut T`: `&place`, a reference
  parameter) is not a raw pointer: dereferencing it is safe. Every `*T`
  is raw, a parameter too (0.18.1).
- Indexing a raw pointer, `p[i]` (unchecked by design: a pointer has no
  length), and slicing one, `p[lo..hi]` (the slice is only as valid as
  the memory behind it). On a raw pointer to a Vec, a Buf or a slice they
  index the pointee, checked (0.17), and are unsafe as `*p` is.
- Casting an integer to a pointer (other than the literal `0`, a null
  pointer, which safe code cannot dereference). Pointer-to-pointer and
  pointer-to-integer casts are safe; tachyon has no pointer arithmetic
  (cast to an integer and back, in unsafe code).
- Calling C: an `extern "C"` declaration (also the ones `import` makes)
  or an `extern "C" fn` pointer. Everything C leaves undefined stays so
  (including a declaration that does not match the C definition, and
  `longjmp` past frames that need cleanup).
- Calling an `unsafe fn`, whose contract the caller keeps.
- Reading a field of a union (its bytes, reinterpreted). Writing one, and
  taking its address, are safe.
- Using an `unsafe fn` as a value. (Until 0.18.0 also passing a raw
  pointer to a pointer parameter, and using a function with pointer
  parameters as a value; 0.18.1: a `*T` parameter is raw, so both are
  safe.)

What unsafe code must keep, so that the safe code around it stays
defined, is the same list: every pointer it hands to safe code as a
borrow points to live memory of its type, and every slice it makes is
valid for its length while it is used. The same holds for memory a
slice views: a slice of an array is valid while the array lives, and one
from `Vec::as_slice` until the vector grows or is freed. Until 0.17,
using a view after its storage was gone was the one way safe code could
still reach undefined behaviour; from 0.17 the own pass rejects it under
`--values=error`, the default (its opt-outs `warn`, `report` and `off`
do not; std's types also assume their fields are changed by their
methods only, as tachyon has no private fields yet). A view need not have a name: a slice argument (or a
receiver taken by value) is a copy made before the later arguments run
(`take(v.as_slice(), grow(&v))`); the base of an index that is not a
place, before its index (`v.as_slice()[grow(&v)]`); and `for x in v`,
`v.iter()` and the iterators made from them view `v` for the whole loop,
so growing `v` in it reads freed memory. A view stored in a place and
taken again after each growth is read when it is used: `S[grow()]`, with
`grow` pushing and then setting `S = V.as_slice()`, is defined (the
indexing rule above).

Reading memory nobody wrote (from `malloc`, or a struct's padding read as
bytes, both through raw pointers) gives an unspecified value, which the
optimizer may take to be any value. Statics, `static mut` included, are
safe to use: tachyon has no threads of its own (threads started through
C are C's business). Runaway recursion still exhausts the stack, which
the operating system stops (a guard page) without corrupting memory.

**Errors.** An unsafe operation outside unsafe code is an error
(`error[unsafe]`, from 0.10; 0.9 reported it as a warning).
`tachyonc --fix-unsafe` wraps such operations in unsafe blocks.

**Checking unsafe code** (0.10). `tachyonc --check-unsafe` (at `-O1` or
`-O2`) checks unsafe code's raw-pointer accesses at run time: every
dereference of a raw pointer (`*p`, the whole pointee), index (`p[i]`,
the element), field through one (`p.f`, the field) and slice made from
one (`p[a..b]`, its bytes). The heap blocks the program allocates
through C's `malloc`, `calloc`, `realloc` and `free` (std's included)
are recorded; an access that starts in a live block and runs past its
end, starts just past the end of one, runs into a block from below, or
falls in one of the last 4096 blocks freed, stops the program with
`unsafe access <what>: N bytes at offset K of a block of M bytes` and the
access's place in the source (exit code 101), as do freeing a freed
block. What it does not see is not checked: the stack and statics, memory
C allocates, pointers C code dereferences, a function pointer to
`malloc`. Programs run tens of times slower.

## Layout, conventions and C

Tachyon guarantees **nothing** about the layout of its own types (the order
and offsets of a struct's fields, the layout of tuples, enums and slices)
or about the calling convention of its own functions: the compiler is free
to choose them (0.3 orders a struct's fields to save padding; 0.5 has a
convention of its own for plain functions at -O1 and -O2, with more
argument registers and aggregates of up to four pieces passed and returned
in registers), and optimizations may rely on that freedom. A plain `fn`
value only ever holds a plain function, and `fn` and `extern "C" fn` do not
convert into each other (casting one to the other through a raw pointer
calls with the wrong convention). C compatibility is asked for explicitly,
and then it is exact:

- `#[repr(C)]` types have C's layout: fields in order, each at its C
  offset; unions overlap their fields; `packed` and `align(N)` as with
  GCC's attributes. Values aligned above 16 are aligned wherever tachyon
  places them (frames, statics, arguments it copies onto the stack); the
  heap is the allocator's business (`malloc` aligns to 16). A fieldless `#[repr(C)]` enum is a C `int`; one with
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
block) or, outside a function, at the next item that starts a line. The
type checker goes on at the next statement of the function (or at the next
function); the names a failed `let` binds have the error type, and errors
that follow from it are not reported. (0.4 stopped at the first error.)

*(0.10)* One compilation reports every error (up to 50), from every file
of the program:

- A program with syntax errors is type-checked too: every item that
  parsed is checked, except the body of a function that had a syntax
  error (its signature is). An item the parser skipped is unknown, and so
  is what it declared: the errors saying so are not reported.
- The declarations recover item by item, and within an item part by part
  (a field's, a parameter's, the result's type...): a type that names
  nothing is the error type; a duplicate (item, field, variant,
  parameter, import, conflicting impl) is left out; a constant whose
  initializer fails is 0; a cycle of fields is reported once and broken.
  An import that fails, or a module whose file is missing, imports
  nothing, and errors about its names are not reported. A function whose
  impl block fails (an unknown trait or type) is left out.
- An error in a C header is reported with the program's errors (at its
  first `import`), and the program is checked without the headers.
- An error in an instance of a generic function is reported once, with
  the instantiation chain of the first instance that has it.
- Errors print sorted by position (the files in the order they are
  loaded); the same message at the same position is printed once. Only a
  tokenizer error still ends the compilation at once.

## Additions of 0.4

**Enums.** A `const` may have a fieldless enum type (`const F: Color =
Color::Green;`); in a pattern its name matches its variant. `n as E`
converts an integer to a fieldless enum, checked: a value that is no
variant's discriminant writes `invalid value V for enum E` to stderr and
exits with code 101, at every optimization level. Fieldless enums compare
with `<`, `<=`, `>` and `>=` in declaration order, which must be the order
of their discriminants (an error otherwise). `E::A..=E::C` matches the
variants from `A` to `C` in declaration order (variants without fields).
`use E::{A, B};` (and, until 0.8, `use E::*;`) brings variants into scope
by their own names: as values (`A`), calls (`B(1, 2)`) and patterns (`A`,
`B(x, _)`).
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
Bounded generics (traits) came in 0.9 as a refinement (see "Traits"): a
program that compiled before keeps its meaning.

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
a::b::{c, d as e};` (until 0.8 also `use a::b::*;`, every public item of
module `a::b`, or every variant of an enum). `pub use` re-exports: the
module's users see the name as one of its items. Imports are resolved on
demand, so their order does not matter; an import that depends on itself
is an error.

`import "stdio.h" as c;` names the declarations of C headers in the
importing module (`c::printf(...)`; until 0.8, `import "stdio.h";` made
them visible by their own names). All the imported headers of a program share one module
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
(`std::Vec<i64>`, `use std::{Buf, Vec};`): `Option<T>` and `Result<T, E>` (`is_some`,
`unwrap`, `unwrap_or`, `ok`...), `Vec<T>` (`new`, `with_capacity`, `push`,
`pop`, `get` and `set` checked like a slice's index, `len`, `as_slice`,
`clear`, `free`), `Buf` (a byte buffer: `push`, `push_str`, `push_cstr`,
`push_int`, `as_slice`), and `print`, `println`, `print_int`, `print_cstr`.
Failures (`unwrap` of `None`, an index out of bounds) write a message to
stderr and exit with 101. Its source is `compiler/std/std.tach` (0.15:
with the files `compiler/std/embed.sh` appends to it); the
whole API, from that source: `tachyonc guide std` (0.17: a line per
item; with the comments, `guide std#every-item`; one name, `guide --find
NAME`).

0.14 adds reading stdin without `unsafe` (`read_line(&mut buf)`, a line
without its `'\n'`, false at the end of input; `read_stdin()`, all of
it), text helpers (`parse_int` to an `Option<i64>`, `trim`, `split`,
`split_whitespace`, `is_space`, `is_digit`, and `Scanner`: `next_token`,
`next_int`, `next_line`), `Vec`'s `last`, `swap`, `insert`, `remove`,
`truncate`, and `HashMap`'s `contains_key`, `get_mut` and
`get_or_insert`. The last two give the value in place as a one-element
slice (`m.get_or_insert(k, 0)[0] += 1`): a slice is safe to index, and
like `as_slice()` it is valid until the map's next insert, remove or
free.

### Keywords

`pub` and `mod` are keywords; `super` is no longer reserved. (0.6: `defer`
too.)

## Additions of 0.6

**String literals** are `[u8]` slices of their bytes, without a
terminator (they were `(*u8, u64)` tuples, with the same layout: `.0` and
`.1` become `.ptr` and `.len`). The standard library's `[u8]` functions
take them directly: `println("hello")`. `c"..."` is still a `*u8` to a
NUL-terminated copy, for C.

**`if let` and `while let`.** `if let P = e { A } else { B }` is
`match e { P => { A }, _ => { B } }`: P may be refutable, its bindings are
in scope in A only; `else if` and `else if let` chain. Without `else` it
has type `()`, like `if`. `while let P = e { body }` is
`loop { match e { P => { body }, _ => break } }`, labels, `break` and
`continue` included.

**`defer`.** `defer expr;` or `defer { ... }` in a block runs the deferred
statement when control leaves the block: at its end, or by `return`,
`break` or `continue` (labelled ones too, running the deferred statements
of every block left). Deferred statements run last first. A value that
leaves the block (its tail, a returned value, a `break` value) is computed
before they run, so a deferred statement assigning a variable does not
change the value already taken from it. A deferred statement sees the
bindings made before it; it may not `return`, nor `break`/`continue` out
of itself (loops inside it are fine). Deferred statements do not run when
the program ends by a failed check (exit 101), `exit`, or a `longjmp` past
them.

**Function attributes.** `#[inline]`, `#[inline(never)]` and `#[cold]`
(rarely called) before a function, also in impl blocks: hints for the
optimizer, which never change what a program does. `#[inline]` and
`#[inline(never)]` together are an error. Attributes may now come before
`pub` (`#[repr(C)] pub struct`) as well as after it.

**Structural equality.** `==` and `!=` work on structs, tuples, arrays,
slices (0.14: the lengths, then the elements; std or not) and enums with
fields whose parts all have `==`: they compare field by field
(for enums, the variant, then its fields), floats as floats (so a value
holding a NaN is not equal to itself). Each operand is evaluated once.
A part whose type has an `impl Eq` is compared by it, as `==` on it alone
is (0.14). Unions have no `==`; comparing a type that holds one (a slice
of them too) is an error naming it. std's `Vec`, `Buf` and `HashMap` compare
their contents (0.15, through their `impl Eq`): Vecs element by element, a
Buf by bytes, maps by length and each key's value, in any order; `==` on a
`Vec<T>` needs `==` on `T`. Whether two are the same Vec is a comparison
of pointers, `a.as_slice().ptr == b.as_slice().ptr`.

**The prelude.** Every module sees `Option`, `Some`, `None`, `Result`,
`Ok`, `Err`, `Vec`, `print` and `println` (from `std`) without `use`. The
prelude comes last: the module's own items, its imports (and, until 0.8,
its `*` imports) and local bindings all shadow it, so programs defining these names keep
their meaning. The standard library is loaded when a program names one of
them (or `std`).

**Variants of generic enums by name.** `use Opt::{Som, Non};` (and the
prelude's `Some`, `None`, `Ok`, `Err`) brings the variants of a generic enum into
scope, in expressions, calls and patterns; their type arguments are
inferred as for `Opt::Som(x)`.

**Name resolution.** A name in a module is, in order: a local binding, the
module's own item, a name imported by name (`use a::b;`), a name brought
by a `*` import, the prelude. Two `*` imports may bring different things
under one name; using that name is then an error (import it by name, or
write its path), where 0.5 silently took the first. (0.8 removed `*`
imports.)

**Inline modules.** `mod name { items }` declares a child module in place,
with the same rules as a module in its own file (privacy, `use`, `super`).
`mod name;` cannot appear inside an inline module.

**Generic type aliases.** `type Pair<T> = (T, T);` takes type arguments
where it is used (`Pair<i64>`), and generic functions infer theirs through
it (`fn swap<T>(p: Pair<T>) -> Pair<T>`).

Not in 0.6 (moved to 0.7): const generic lengths (`[T; N]` with `N` a
parameter); `errno` and other macros that expand to expressions in C
headers.

## Additions of 0.8

**No wildcard imports.** Every name a file uses is declared in it,
imported by name, or written with its path, so what a name means can be
traced from where it is used to a declaration or an explicit import,
without knowing what another module happens to contain (or will contain
later). Gone:

- `use a::b::*;` and `use E::*;`: write `use a::b::{c, d};` and `use
  E::{A, B};`, or the paths (`a::b::c`, `E::A`);
- `import "stdio.h";`, which brought every declaration of a header into
  scope: write `import "stdio.h" as c;` and `c::printf(...)`. All headers
  share one module of C declarations, so one name serves them all
  (`import "stdio.h" as c; import "stdlib.h" as c;`). In a pattern, where
  a path names a variant, import the constant by name: `use c::EOF;`.

The prelude stays: a fixed, documented list of names (`Option`, `Some`,
`None`, `Result`, `Ok`, `Err`, `Vec`, `print`, `println`), not a wildcard. (0.9 adds
the traits `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord` and `Hash`.)

The errors for the removed forms name their replacement, from what the
program uses through them: `wildcard imports are not allowed: write 'use
util::{double, half};'`.

**`tachyonc --fix-imports FILE...`** rewrites a program written for 0.7 or
earlier, in place: every file of it (the files of its modules too). It
checks the program as for compiling it, resolving the old forms as 0.7
did, then:

- each `use X::*;` becomes `use X::{names};` (or `use X::name;`), listing,
  sorted, the names the program finds through it (a name the module
  declares itself, or imports by name, is not among them, as it was not
  found through the `*`); a `*` nothing is found through is removed. Long
  lists are wrapped, one line of names after the other;
- each `import "h.h";` becomes `import "h.h" as c;` (`c` unless the module
  has another `c`), and each use of a declaration found through it is
  written `c::name` (a `*` that led to such a declaration, as `use
  super::*;` from an inline module, imports `c` instead; an import by name
  through another module, `use io::printf;`, is left for you to rewrite);
- nothing else changes, byte for byte.

A program the tool cannot rewrite is one 0.7 rejects as well (a name two
`*` imports bring, for instance); then it reports the errors and changes
nothing. A second run finds nothing to do.

## Additions of 0.9

### Unsafe code

```ebnf
fn_decl      = [ "unsafe" ] "fn" ident ... ;          (* also in impl blocks, after pub and attributes *)
unsafe_block = "unsafe" block ;                        (* an expression, block-like *)
```

An `unsafe { ... }` block is a block whose statements are *unsafe code*:
the operations listed in "Undefined behaviour" (dereferencing, indexing
and slicing raw pointers, integer-to-pointer casts, calling C or an
`unsafe fn` or using one as a value, reading a union's field) are allowed in it. Like any block, it is an
expression (`let x = unsafe { *p };`) and a block-like statement. The
body of an `unsafe fn` is unsafe code; calling one is an unsafe
operation, so its callers take on its contract (document it next to the
function). Nesting changes nothing: unsafe code inside unsafe code.

```
extern "C" { fn strlen(s: *u8) -> u64; }

// The caller promises a NUL-terminated string.
unsafe fn length(s: *u8) -> i64 { strlen(s) as i64 }

fn main() -> i32 {
    let n = unsafe { length(c"four") };
    n as i32
}
```

**Borrows and raw pointers** *(0.18.1)*. A *borrow* is a reference,
`&T` or `&mut T`: `&place` (the address of a local, a static, a field or
a checked element) and the receiver a method call takes that way
(`v.push(1)`), kept in a parameter, a local or a field. Dereferencing a
borrow (`*p`, `p.f`, `p.m()`) is safe; indexing one is safe when it
points to a Vec, a Buf or a slice (0.17: it indexes the pointee,
checked).

Every `*T` is a raw pointer, as in Rust: a parameter too, `mut` or not
(before 0.18.1 a non-`mut` `*T` parameter of a safe function was
checked as `&mut T`: the legacy rule, gone). Dereferencing, indexing,
field access and a method call through a `*T` need `unsafe`, except a
method whose own `self` is `*T`, which takes the pointer as it is.
Passing a pointer on to a `*T` parameter, comparing and casting one are
safe, and so is using a function with pointer parameters as a value;
`&x` and `&mut x` convert to a `*T`. The error is `dereference of a raw
pointer is unsafe: `p` is a `*T` parameter`, with `try: tachyonc fix
--values` (parameters to `&T` / `&mut T`, with their calls; it keeps raw
a pointer that is indexed, compared, cast, stored or given to C) and
`try: tachyonc fix --only unsafe`.

**Diagnostics.** An unsafe operation outside unsafe code is an error,
`error[unsafe]` (each place once, in source order, with the other
errors; 0.9 reported it as a warning). Options:

- `--deny-warnings`: warnings are errors. There are no warnings at the
  moment (0.9's unsafe warnings are errors now); the option stays for
  future ones, and the test suite compiles every case with it.
- `--diagnostics=short` (0.11): every error and warning on one line,
  `FILE:LINE:COL: error[KIND] MESSAGE | help: HELP | note: NOTE`, for
  tools and agents (`--diagnostics=human`, the default, is the form
  above). An unknown name's help is the `use` line that imports it from
  another module (``add `use crate::m::name;` ``), else the nearest name in
  scope (`did you mean 'total'?`).
- `tachyonc --fix-unsafe FILE...`: rewrites the program in place, putting
  each unsafe operation outside unsafe code in an unsafe block: the
  statement around it (consecutive statements share one block), a
  `let`'s value, a condition, a match arm or a block's tail. Nothing else
  changes; a second run finds nothing to do.

0.9's `--allow-unsafe` (no unsafe warnings, for the compiler's own source,
which 0.10 migrated) is gone: 0.10 rejects it.

**std.** `panic`, `Buf::push_cstr` and `print_cstr` take C strings, which
must end with a NUL: they are `unsafe fn` now (breaking). Everything else
in std is safe and uses unsafe blocks inside.

### Traits

```
trait Shape {
    fn area(self: &Self) -> i64;
    fn describe(self: &Self) {            // a default
        print("area ");
        std::print_int(self.area());
    }
}

struct Square { side: i64 }

impl Shape for Square {
    fn area(self: &Square) -> i64 { self.side * self.side }
}

fn total<T: Shape>(items: [T]) -> i64 { ... }   // bounds
struct Map<K: Hash + Eq, V> { ... }              // on structs and enums too
impl<T: Hash> Hash for Pair<T> { ... }           // a generic impl, with bounds
```

A **trait** declares functions, with `Self` standing for the implementing
type; a function may have a default body. An **impl** `impl Trait for
Type { ... }` defines them for a type, any type (`impl Hash for i64`,
`impl Eq for [u8]`): its functions become the type's methods and
associated functions, in one namespace with the type's own (a name may
not be defined twice), and visible wherever the trait is. A function the
impl leaves out is the trait's default, copied into the impl and checked
there (in the impl's module, with `Self` the impl's type); one without a
default must be written. Each function of an impl must be one of the
trait's, with the trait's signature (`Self` replaced by the type). A
generic impl, `impl<T: Hash> Hash for Pair<T>`, is for a generic struct or
enum with the impl's parameters as its arguments, and covers each
instance whose arguments satisfy its bounds.

**Coherence.** There is at most one impl per trait and type (a generic
impl counts for all its instances); a second one is an error.

**Bounds.** A type parameter may be bounded, `T: Hash + Eq`, on functions,
impl blocks, structs and enums. Each instance's type arguments must
implement the bounds (`the trait 'Hash' is not implemented for 'Thing'`,
naming the bound). Generic code is still checked per instance (as in
0.5), and a parameter's bounds also limit it: a function called on a
value declared with a bounded parameter's type (`x: T`, `p: *T`) or as
`T::f(...)` must be one of the bounds' (`no function 'hash' in the bounds
of 'T'`). Unbounded parameters keep 0.5's meaning, so no program written
for 0.5 to 0.8 changes. Dispatch is static (monomorphization); there are
no trait objects: a trait is not a type (`dyn` stays reserved), nor are
there supertraits, associated types or generic traits yet.

**Operators** go through std's traits, in the prelude: `a + b`, `a - b`,
`a * b`, `a / b` call `add`, `sub`, `mul`, `div` (`Add`, `Sub`, `Mul`,
`Div`: `fn add(self: Self, other: Self) -> Self`), `-a` calls `neg`
(`Neg`), `a == b` and `a != b` call `eq(&a, &b)` (`Eq`: `fn eq(self:
&Self, other: &Self) -> bool`), and `<`, `<=`, `>`, `>=` compare `cmp`'s
result with 0 (`Ord`: `fn cmp(self: &Self, other: &Self) -> i64`,
negative, zero or positive). Each operand is evaluated once, left to
right. A type's own impl takes precedence over 0.6's structural `==`
(for structs, enums, tuples, arrays and slices); the builtin scalars
(numbers, `bool`, pointers, functions) always keep their own operators.
Builtin types implement the operator traits intrinsically, for bounds:
numbers all of them, every type with `==` `Eq`, numbers, pointers and
fieldless enums `Ord`. Compound assignment (`+=`) stays numeric.

**std** (0.9): the traits `Add`, `Sub`, `Mul`, `Div`, `Neg`, `Eq`, `Ord`,
`Hash` (`fn hash(self: &Self) -> u64`; 0.17: `&Self`; an impl spells it, 0.18.1: `self: *Self`
is an error), in the prelude; impls of `Eq`,
`Ord` and `Hash` for the integer types, `bool` and `[u8]` (byte strings:
by bytes, lexicographically, FNV-1a); `sort<T: Ord>(s: [T])` (in place,
not stable; a heapsort, an introsort from 0.14); and `HashMap<K: Hash + Eq, V>` (open addressing
with linear probing): `new`, `insert` (returns the old value),
`get`, `contains`, `remove`, `len`, `is_empty`, `free`, and iteration by
slot: `slots()`, `key_at(i)` and `value_at(i)` (`None` for an empty
slot).

### Smaller changes

- **Array constants**: `const PRIMES: [i64; 4] = [2, 3, 5, 7];` (elements
  are constant expressions, other constants included). An array constant
  is an immutable static: memory holding its elements, indexed like any
  array (it is not usable where an integer constant is needed, nor in a
  pattern).
- **Strings in constant aggregates**: a static's initializer may hold
  string literals (`[u8]`) and C strings inside structs, tuples and
  arrays (`static OPS: [Op; 2] = [Op { name: "add", ... }, ...];`); their
  addresses are relocated when the program loads.
- **Line continuation**: in a string literal (`"..."` or `c"..."`), a
  backslash at the end of a line leaves out the line break and the next
  line's leading whitespace (spaces, tabs and further line breaks), as in
  Rust.
- **`if` and generic variants**: `if c { Some(x) } else { None }` (either
  way round, and for any generic enum's variant named without type
  arguments) takes its type from the other branch.
- **Importing C headers when cross-compiling** (see below): `$TACHYON_CC`
  may name a C compiler for another system, e.g. `TACHYON_CC="clang
  --target=x86_64-linux-gnu --sysroot=DIR"` on macOS for `--target
  x86_64-linux`; without it, the error says so.

## Additions of 0.10

### Vector types

Six types of 16 bytes (aligned to 16) hold several values ("lanes") of
one scalar type, computed together (SIMD: NEON on AArch64, SSE2 on
x86-64):

| type | lanes | | type | lanes |
|---|---|---|---|---|
| `v2f64` | 2 × `f64` | | `v4i32` | 4 × `i32` |
| `v4f32` | 4 × `f32` | | `v8i16` | 8 × `i16` |
| `v2i64` | 2 × `i64` | | `v16i8` | 16 × `i8` |

Their names are reserved like the primitive types' (no item may take
one; a local of that name shadows the constructor). A vector is a value:
it is copied by `=`, passed and returned like a struct; lane `i` lives
at byte `i × size_of(lane)` (`[T; N]`'s layout), and a vector in memory
may be read lane by lane through a pointer. Integer lanes are signed;
there are no unsigned vector types (0.19 adds them, and 64- and 256-bit
vectors: [below](#additions-of-019-vector-types-and-stdarchs-types)).

**Making vectors.**

- `v4f32(a, b, c, d)`: one argument per lane, of the lane type, in order
  (the lane count must match);
- `v4f32::splat(x)`: every lane `x`;
- `v4f32::load(s, i)`: lanes `s[i]`, `s[i + 1]`, ... `s[i + N - 1]` of `s`,
  a slice or an array of the lane type; `i` is an `i64`. Checked: unless
  `0 <= i` and `i + N <= len(s)`, the program stops with `slice range out
  of bounds: i..i+N, length len` (exit code 101), as a bad slicing does.

**Operations** (lane by lane, `a` and `b` of one vector type):

- `a + b`, `a - b`, `a * b`, `-a`: on every vector type. Integer lanes
  wrap at their width (two's complement, as the scalar operators); float
  lanes follow IEEE 754 (binary64 or binary32, round to nearest even, one
  rounding per operation: no fused multiply-add), NaN propagating.
  `-a` on floats flips the sign bit (`-0.0` from `0.0`).
- `a / b`: float vectors only (IEEE). **Integer vectors have no
  division** (none of the targets has an instruction for it; write the
  loop over the lanes).
- `a & b`, `a | b`, `a ^ b`: integer vectors only, on the bits.
- `a == b`, `a != b`, `a < b`, `a <= b`, `a > b`, `a >= b`: a **mask**,
  the integer vector of the lanes' width (`v2i64` for `v2f64`, `v4i32`
  for `v4f32`, the type itself for the integer vectors), each lane `-1`
  (all bits set) where the comparison holds and `0` where it does not.
  Integer comparisons are signed. Float comparisons are IEEE: with a NaN
  lane, `==`, `<`, `<=`, `>`, `>=` are false and `!=` is true. (So
  `a == b` is not a `bool`: `if a == b` is a type error.)
- `m.select(a, b)`, for a mask `m` (an integer vector) and vectors `a`,
  `b` whose mask type is `m`'s: `(a & m) | (b & ~m)` on the bits, so a
  lane of `a` where `m`'s is `-1` and of `b` where it is `0`.
- `+=`, `-=`, `*=`, `/=`, `&=`, `|=`, `^=`: as the operators, on a
  vector place.

**Lanes.**

- `v.lane(i)`: lane `i` (an `i64`), of the lane type. Checked: unless `0
  <= i < N`, the program stops with `index out of bounds: index i, length
  N`.
- `v.with_lane(i, x)`: `v` with lane `i` replaced by `x` (checked the
  same way, before `x` is evaluated).
- `v.sum()`: the sum of the lanes, of the lane type. Integer sums wrap.
  Float sums are pairwise, which fixes the rounding: `l0 + l1` for two
  lanes, `(l0 + l1) + (l2 + l3)` for four.
- `v.store(s, i)`: writes the lanes to `s[i]` ... `s[i + N - 1]`, of a
  slice or an array place (assigned, so a mutable one) of the lane type;
  checked as `load`.

A static (or a constant aggregate) may hold vectors made by `vNtT(...)`
or `vNtT::splat(x)` of constant lanes.

Operands are evaluated left to right, the receiver of a method first;
each vector operand's value is taken when it is evaluated. Nothing about
vectors is undefined behaviour.

**C.** Vectors are not FFI-safe: an `extern "C"` signature, function
pointer type or static cannot hold one (C's vector types and their
conventions are not supported; pass a pointer to the lanes or an array).
In tachyon's own convention a vector is passed like a struct of its
lanes.

## Additions of 0.14

(The design is [design/closures-iterators.md](design/closures-iterators.md).)

```ebnf
prefix     += [ "move" ] ( "||" | "|" [ cparam { "," cparam } [ "," ] ] "|" )
              ( "->" type block | expr )
cparam      = single_pattern [ ":" type ]   (* no `|` alternatives *)
tparam      = ident [ ":" bound { "+" bound } ]
bound       = path [ "<" ident "=" type { "," ident "=" type } ">" ]
            | ( "Fn" | "FnMut" ) "(" [ type { "," type } ] ")" [ "->" type ]
trait_item += "type" ident ";"
impl_item  += "type" ident "=" type ";"     (* in an impl of a trait *)
type       += path "::" ident               (* T::Item, Self::Item, F::Output *)
```

`move` is a keyword (it was reserved). A closure's body has binding power
0, as in Rust: `|x| x + 1` is `|x| (x + 1)`; with a written result type
the body is a block. `Fn` and `FnMut` are bounds, not traits (and not
keywords): `F: FnMut(i64) -> i64`.

### Closures

```tach
fn apply<F: Fn(i64) -> i64>(f: F, x: i64) -> i64 { f(x) }
let k = 10;
apply(|x| x + k, 1);                 // 11: x's type from the bound
let mut n = 0;
let mut bump = || n += 1;            // FnMut: it assigns n
let add = |a: i64, b: i64| a + b;    // types written: no context needed
let g: fn(i64) -> i64 = |x| x * 2;   // captures nothing: a plain fn
```

- **Types.** Each closure expression (in each instance of the generic
  function it is in) has its own anonymous type, shown as
  `closure(i64) -> i64 at f.tach:4:15`; it cannot be written, so a closure
  is passed to a generic `F` or kept in a local or a generic struct.
- **Parameters** take their types from the annotation, else from the
  expected `fn(..)` type or the `Fn`/`FnMut` bound of the parameter the
  closure is passed for; otherwise "cannot infer the type of closure
  parameter 'x'". A parameter may be a pattern: `|(a, b): (i64, i64)|`.
  The result is the written type (`|x| -> T { ... }`, needed when the body
  has a `return`), else the expected one, else the body's. `return`
  returns from the closure; `break` and `continue` cannot leave it; an
  `unsafe` block around it covers its body.
- **Captures**, decided per variable: an immutable binding by value (a
  copy; by reference above 32 bytes, or when the closure takes its
  address, `&x` or the receiver of a `self: *T` method, so that
  `|| v.push(1)` changes `v`); a `let mut` binding by reference (the
  closure sees changes and makes them); with `move`, everything by value
  (assignments change the closure's own copy).
- **Calls.** `f(x)` of a closure value calls its function directly
  (`(h.f)(x)` for a field). A closure that captures nothing coerces to a
  plain `fn` type with its signature; one that captures is an error there
  (take a generic `F: Fn(..)` instead).
- **Bounds.** A type satisfies `FnMut(A..) -> R` if it is a closure with
  exactly that signature or the plain `fn(A..) -> R`; `Fn(A..) -> R` also
  asks that a closure assigns none of the variables it captures. There is
  no `FnOnce`. A bound's types, as far as they are known, type the
  closure's parameters; its result binds what it names (`B` of
  `F: FnMut(A) -> B`).
- **Escape.** A value whose type holds a closure that borrows a variable
  (captures it by reference) cannot leave the block, `match` arm or
  `loop` (`break` value) that variable is declared in: "write `move`, or
  declare 'j' outside the block". Borrowed variables keep their frame
  slot for the whole function, so a borrow cannot dangle.

### Associated types

```tach
trait Source {
    type Item;                                  // declared: no default, no bounds
    fn get(self: &Self) -> Self::Item;
}
impl Source for Counter {
    type Item = i64;                            // every declared name is defined
    fn get(self: &Counter) -> i64 { self.n }
}
fn first<I: Source>(it: I) -> I::Item { ... }
fn total<I: Iterator<Item = T>, T: Add>(it: I) -> T { ... }
```

- A trait declares `type Name;` and each impl of it defines `type Name =
  T;` (an impl lacking one is an error: "the impl of trait 'Iterator' is
  missing 'type Item'"). A generic impl's definition may use its
  parameters and their projections (`type Item = (I::Item, I::Item);`).
- `X::Name` (a *projection*) is written with `X` a type parameter or
  `Self`. Generic code is checked per instance, where `X` is a concrete
  type: `X::Name` is the type its impl defines. Two traits defining the
  same name for a type make `X::Name` ambiguous (an error); there is no
  `<T as Tr>::Name`.
- `F::Output`, built in, is the result type of a fn type or a closure.
- A bound may constrain the trait's associated types, `I: Iterator<Item
  = i64>`: checked when an instance is made ("'Small::Item' is 'u8', but
  the bound 'I: Iterator<Item = i64>' of 'f' requires 'i64'"), and used to
  infer the parameters it names (`T` above, from `I`'s `Item`).
- A trait's default function copied into a non-generic impl is checked,
  and compiled, only when the program uses it: `sum`, which needs `0 as
  Self::Item`, is no error for an iterator of `[u8]` that never sums. Its
  errors note where it was first used. A default is checked in the
  trait's module (0.13: the impl's).

**Impls for slices.** `impl<T> [T] { ... }` gives methods to every slice
type, and `impl<T> Tr for [T] { ... }` implements a trait for them (the
impl's only parameter is the element type): `s.second()` on a `[i64]`.

### Iterators

`for p in e body`, where `e` is not a range literal, iterates `e` by its
type; `e` is evaluated once, into a hidden `let`:

| `e` | the loop |
|---|---|
| a slice, an array | `for i in 0..len { let p = e[i]; body }` (0.4) |
| `Vec<T>`, `std::SliceIter<T>` (`v.iter()`) | the same over `e.as_slice()`: a counted loop, no `next` call |
| `std::Range<T>`, `std::RangeInclusive<T>` (`a..b`, `a..=b` as values) | `for p in e.start..e.end body` (`..=`; nothing once `e.done`) |
| a type implementing `Iterator` | `label: loop { match e.next() { Some(p) => body, _ => break } }` |
| a type with an `iter()` method (`HashMap`, user types) | `for p in e.iter() body` |
| `*T` of any of these | the same through the pointer (`for x in &v`; `for x in &it` advances `it`) |

Anything else is the error `'for' iterates over ranges, slices, arrays,
iterators and types with an 'iter' method, got 'T'`. The pattern is
irrefutable (a `let`'s); labels, `break`, `continue` and `defer` in the
body behave as in any loop. Items are copies.

`a..b` and `a..=b` outside a `for` head, a slicing and a pattern are
values: `std::Range { start: a, end: b }` and `std::RangeInclusive {
start: a, end: b, done: false }`, both ends of one type (`0..=255u8` is a
`RangeInclusive<u8>`, which ends without overflow). A program that uses a
range as a value loads std.

The `Iterator` trait (in the prelude):

```
pub trait Iterator {
    type Item;
    fn next(self: &mut Self) -> Option<Self::Item>;
    fn exact_len(self: &Self) -> i64                 // items left, or -1 (default)
    fn at(self: &Self, k: i64) -> Self::Item         // k-th left: k = 0, 1, 2, ... while exact_len > k
    fn map, filter, enumerate, zip, take             // adapters: Map, Filter, Enumerate, Zip, Take
    fn fold, for_each, count, sum, min, max, collect // consumers (collect: a Vec)
}
```

std's sources implement it: `Range`, `RangeInclusive`, `SliceIter`
(`v.iter()`, `s.iter()` on a slice, and `as_slice()`: the items left;
0.16: an array place has its slice's methods, `a.iter()` is `a[..].iter()`),
`HashMapIter` (`m.iter()`, items `(K, V)` in slot order), `Keys`
(`m.keys()`) and `Values` (`m.values()`); each overrides `fold` with a
counted loop, and all but the HashMap ones have an indexed `at`.
`std::sort_by(s, f)`, `s.sort_by(f)` and `v.sort_by(f)` sort by `f(a: *T,
b: *T) -> i64` (negative: `a` first; a heapsort). Every std iterator
method is `#[inline]`, so that a chain becomes one loop.

```
let v: Vec<i64> = ...;
let total = v.iter().filter(|x| x % 2 == 0).map(|x| x * x).sum();
let mut w = v.iter().enumerate().map(|(i, x)| i * x).collect();   // a Vec: free it
w.sort_by(|a, b| b.cmp(a));
for (x, k) in v.iter().zip(0..10).take(3) { ... }
```

### Literals, constants, names, errors

**The type of an unsuffixed literal from its neighbours.** An integer
or float literal without a suffix (`0`, `-1`, `2.5`, a character) whose
type no expected type gives takes the type of what stands beside it:

- an `if`/`else` with one branch such a literal (or a block of only one,
  or an `else if` chain of them) and the other of a numeric type: that
  type (`if c { line[i] } else { 0 }` is a `u8`);
- a `match` whose arm is such a literal: the type of the first other
  arm (`match i { 0 => 0, _ => b[i] }`);
- an array literal: the type of its first element that is not such a
  literal (`[0, 1, b[2]]` is a `[u8; 3]`).

Where nothing gives a type the rules are as before: `i64` (`f64`). The
literal must fit (`if c { 300 } else { b[0] }` is an error). Binary
operators, ranges, arguments and annotated `let`s already gave their
type (0.4).

**String constants.** `const S: [u8] = "text";`: a constant of type
`[u8]` initialized by a string literal; each use is the literal. Other
types still need a `static` (the error says so).

**A module and an item of the same name.** Where a module has a child
module `m` and imports an item named `m` (`mod eval; use eval::eval;`),
the name is the item where a value or a type is wanted (`eval(x)`,
`let t: token = token { .. }`) and the module where a path goes on
(`eval::other`), as in Rust.

**Errors.** After an error in an `if`'s or `while`'s condition, a
`match`'s scrutinee or a `for` loop's sequence, the code that depends on
it is checked too (its bindings of the error type), so its errors come in
the same compilation. Unknown methods, fields, associated functions,
variants and module items get `help: did you mean 'x'?` with the nearest
name of that kind (the same but for case and underscores, else an edit
distance up to a third of the length); an unknown name std has gets
its `use std::...;` line, or the nearest std name, even when the program
does not name std; a private item gets the help
`make it public: `pub fn f` at FILE:LINE:COL`; Rust habits (`&self`,
`&str`, `&mut x`, `println!` and the other macros, `?`, `String`,
`s.len()`, `.chars()`, `.iter_mut()`) get a help naming what tachyon writes.

## Additions of 0.15

The design is [design/errors-formatting.md](design/errors-formatting.md);
the guide's topics are `tachyonc guide conversions` and `tachyonc guide
formatting`.

```ebnf
postfix    += expr "?"                                   (* as tight as . ( [ *)
primary    += fstring
fstring     = 'f"' { text | "{{" | "}}" | "{" expr [ ":" spec ] "}" } '"'
spec        = [ "<" | ">" ] [ "0" ] [ digits ] [ "." digits ] [ "?" | "x" | "X" | "b" | "c" ]
args        = [ arg { "," arg } [ "," ] ]
arg         = expr | ident ":" expr                      (* named: after every positional one *)
param      += ... [ "=" expr ]                           (* fn items and inherent methods only *)
field_init  = ident ":" expr | ident                     (* `ident` alone: shorthand *)
attr       += "#[" "derive" "(" path { "," path } [ "," ] ")" "]"   (* before struct, enum *)
trait       = "trait" ident [ "<" tparam { "," tparam } ">" ] "{" { trait_item } "}"
bound       = path [ "<" ( type | ident "=" type ) { "," ( type | ident "=" type ) } ">" ]
```

### Errors and `?`

`e?` is a postfix operator (it was reserved before 0.15), binding as
tightly as a call: `parse(s)?.len` is `(parse(s)?).len`, `-x?` is
`-(x?)`.

- On `e: Option<T>` it is a `T`, or the function returns `None`.
- On `e: Result<T, E>` it is a `T`, or the function returns `Err(c)`,
  where `c` is the error itself when `E` is the function's error type
  `F`, the error widened when `E` widens to `F` (below), else
  `F::from(err)` through an `impl From<E> for F`.
- The function's result type decides: `?` in a function returning
  neither is an error, and so is `?` on an Option in a function returning
  a Result (`try: e.ok_or(VALUE)?`). Inside a closure `?` returns from the
  closure, whose result type must then be known (`|x| -> Option<i64>
  {..}`, as for `return`). `defer` blocks run, as for `return`.
- `fn main() -> Result<(), E>` with `E: Debug`: on `Err(e)` the program
  prints `Error: ` and `e`'s Debug text on stderr and exits with 1.

### Widening and conversions

`widens(A, B)` holds for integer types when `B` is wider with the same
signedness (`i8 < i16 < i32 < i64`, `u8 < u16 < u32 < u64`), or `A` is
unsigned and `B` signed and strictly wider (`u32` to `i64`); `isize` and
`usize` are `i64` and `u64`. Nothing else widens: not int and float,
not `bool`, not signed to unsigned, never narrower.

- Wherever a value of type `A` meets an expected type `B` with
  `widens(A, B)` (`let x: B = v`, assignment and compound assignment,
  arguments, `return`, a block's tail, struct fields, variant payloads,
  array and tuple elements), the value is converted. A value only: an
  `*i32` never becomes an `*i64`, nor `[i32]`, `Vec<i32>`, `fn(i32)`, a
  tuple value.
- Where two integer types meet without an expected type, the binary
  operators' operands (comparisons included), the branches of `if` and
  `match`, two arguments binding one type parameter, the result is the
  wider type if one widens to the other; else the types must be equal.
- An expected type flows into arithmetic as for literals: in `let t: i64
  = a * b` with `a, b: i32`, the multiplication is done in `i64`.

`INT::MAX` and `INT::MIN`, for `INT` a primitive integer type (`i64::MAX`,
`u8::MIN`), are constants of that type: the literal of the value
(`-9223372036854775808i64` for `i64::MIN`), so they fold and may stand in
constant expressions. They are the only associated constants: there are
none in general, nor for floats (std's `I64_MAX`, ... are the same values).

Traits may have type parameters (`trait From<T>`), with these
restrictions: no default bodies in a generic trait, the operator traits
have none, an impl's trait arguments are concrete types or the impl's
own parameters (`impl<T> From<T> for Wrap<T>`), and there is one impl
per trait, trait arguments and type. A bound may pass arguments
(`T: From<U>`) and constrain associated types (`I: Iterator<Item = T>`)
in one list. A call `T::f(x)` or `x.f()` that finds no ordinary method
chooses among `T`'s impls of generic traits by the argument types; none
or several is an error listing them.

std's `From<T>` is there without an impl for the identity and for
widening; `Into<T>` cannot be implemented: `x.into()` is `U::from(x)`
with `U` the expected type, and `t: Into<U>` holds when `U: From<t>`.

### Formatting

An f-string `f"..."` is an expression of an unnameable type (an
`std::Interp` of a closure) implementing `std::Display`. Its text takes
the escapes of a string literal; `{{` and `}}` are braces; `{expr}` is a
hole, `{expr:spec}` one with a spec. The lexer reads it as pieces:
`f"text{` (FHead), the hole's tokens, `:spec}text{` or `}text{` (FMid),
..., `:spec}text"` (FTail); an f-string without holes is one FHead. A
hole ends at its `}` at bracket depth 0 or at a `:` outside brackets
that is not `::`, so an expression with a top-level `:` needs
parentheses; string literals may appear in holes; f-strings do not
nest; a hole may not be empty, and a lone `}` in the text is an error.

The spec: `<` or `>` aligns (numbers right, text left by default), `0`
pads with zeros, the digits are the width, `.N` the precision (floats:
N decimals), and the last character picks Debug (`?`), hex (`x`, `X`),
binary (`b`) or a byte (`c`, a `u8` written as the byte).

The holes are evaluated where the f-string is, once each, left to
right; the value holds copies of them. Its Display writes the text and
each hole's `Display` (or `Debug`) in turn.

### Named arguments, defaults, shorthand

A trailing run of a function's parameters may have defaults, `b: i64 =
2`, on `fn` items and inherent methods; not on trait functions (nor the
functions of trait impls), extern functions, closures or `fn` types. A
default may not name a parameter or a local; it is checked against the
parameter's type once, and evaluated at each call that leaves it out, in
the callee's module (a fresh `Vec::new()` each time).

At a call, the positional arguments come first, then `name: value`
arguments, in the order of the parameters (so arguments are evaluated
in the written order). Each parameter is given once; `self` cannot be
named; calls of trait functions take positional arguments only. A
function used as a value has its whole signature (its defaults do not
come with it). `f(label: loop { .. })` is a named argument: an argument
cannot be a labelled loop (parenthesize it).

In a struct literal, a field written alone, `P { x, y: 0 }`, is `x: x`.

### derive

`#[derive(Trait, ...)]` goes before a `struct` or an `enum` (with
`#[repr]`, not with function attributes, not before a union); several
derive attributes add up. The traits are `Eq`, `Ord`, `Hash`, `Debug`
and `Clone`; each is an impl the compiler writes:

- `Eq`: none (structural `==` is the derived equality); every field must
  have `==`.
- `Ord`: lexicographic over the fields in declaration order; for enums
  the variant's order first, then the payload.
- `Hash`: the fields' hashes mixed with `std::hash_mix`, the variant's
  index first for enums.
- `Debug`: Rust's text, `P { x: 1, y: 2 }`, `Circle(3)`, `Empty`.
- `Clone`: field by field with `std::clone_of`.

On a generic type every parameter gets the trait as a bound
(`impl<T: Ord> Ord for P<T>`). A derived trait and a written impl of
the same trait for the type are a coherence error.

## Additions of 0.16

The design is [design/effects-allocation.md](design/effects-allocation.md).
(Phase 0: the syntax and std's allocator interface; what is marked
"to come" is checked or implemented by the 0.16 tasks.)

```ebnf
attr       += "#[" effect_attr "]"                       (* before fn, trait fn, impl fn, extern fn *)
            | "#[" ( "sealed" | "scoped" ) "]"           (* before struct *)
effect_attr = "effects" "(" [ effect { "," effect } [ "," ] ] ")"
            | "pure" | "no_alloc" | "no_io" | "no_panic"
effect      = "alloc" [ "(" alloc_src { "," alloc_src } ")" ]
            | "io" | "global" | "panic" | "diverge" | "unsafe"
alloc_src   = type | "extern"
bound      += "effects" "(" [ effect { "," effect } ] ")"   (* F: Fn(i64) -> i64 + effects(panic) *)
tparam      = ident [ ":" bound { "+" bound } ] [ "=" type ]   (* defaults: structs and enums, trailing *)
```

### Effects

Every function has an inferred effect set: `alloc(A, ...)`, `io`,
`global`, `panic`, `diverge`, `unsafe` (to come: the inference). A
declaration is an upper bound of it, checked (to come); on a C function
it is trusted. `#[pure]` is no `alloc`, `io` or `global`; `#[effects()]`
is the empty set. Several declarations intersect. `tachyonc
--print-effects` and `tachyonc query effects NAME` show the sets.

### Default type parameters

A struct's or an enum's type parameters may end with defaults: `struct
Vec<T, A: Allocator = Gpa>`. A type leaves out trailing arguments that
have defaults (`Vec<i64>` is `Vec<i64, Gpa>`; `Buf` is `Buf<Gpa>`); in
an expression the omitted arguments are inferred, the default when
nothing binds them (`Vec::new()`). Messages and symbols leave out the
trailing arguments equal to their defaults. An impl block writes every
argument: `impl<T, A: Allocator> Vec<T, A>`.

### Allocators

std's containers take their memory from an allocator, a type parameter:
`Vec<T, A: Allocator = Gpa>`, `Buf<A>`, `HashMap<K, V, A>`. Allocation
is explicit: nothing allocates without being given an allocator
(`Vec::new_in(a)`, `with_capacity_in(n, a)`, `filled_in(n, x, a)`,
`Buf::new_in(a)`, `HashMap::new_in(a)`, `collect_in(a)`, `format_in(x,
a)`, `read_stdin_in(a)`, `split_in(s, sep, a)`, `split_whitespace_in(s,
a)`, `sort_stable_in(s, a)`, `sort_stable_by_in(s, f, a)`,
`v.clone_in(b)`); 0.15's forms (`Vec::new()`, `collect()`,
`format(x)`...) are errors naming the `_in` form. A program's `Gpa` (C's
malloc) is its main's parameter, passed down:

```ebnf
main = "fn" "main" "(" [ "gpa" ":" "Gpa" ] ")" [ "->" type ] block
     | "fn" "main" "(" "argc" ":" "i32" "," "argv" ":" "**u8" [ "," "gpa" ":" "Gpa" ] ")" [ "->" type ] block
```

(any parameter names; the `Gpa` parameter is last). `Allocator`, `Gpa`,
`Arena`, `ScopedArena`, `arena_scope` and `format_in` are in the prelude
(arenas: to come). `tachyonc fix --only alloc016` moves a 0.15 program
over: the calls become their `_in` forms and `gpa: Gpa` is threaded
from `main` to them ([refactor.md](refactor.md)).

### sealed, scoped

`#[sealed]` (to come: checked) hides a struct's fields not marked `pub`,
and its literals, outside its module; `#[scoped]` (to come) keeps values
of the type from outliving the scope that made them.

## Additions of 0.17: familiar forms

Forms a Rust reader writes first, with tachyon's meaning unchanged
(nothing here allocates, and every index stays checked). The measure
behind them is `.claude/briefs/research/familiar-names.md`.

```ebnf
unary += "&" "mut" unary          (* an exclusive reference *)
type  += "&" type | "&" "mut" type  (* "&" "[" type "]" is the slice type itself *)
```

**References** (value semantics, Phase 0;
[design/value-semantics.md](design/value-semantics.md) §2.3). `&T` is a
shared reference and `&mut T` an exclusive one: `&x` and `&mut x` take
them, and reading through one is safe (`let r = &p; r.x`), but
not through a `*T`. `&[T]` is `[T]`; `&mut [T]` is the exclusive slice
(`&mut a[..]`). A reference converts where a raw `*T` is wanted, `&mut T`
where `&T` is, `&mut [T]` where `[T]` is, and a reference to a slice where
the slice is (`f(&s)`). `&x` and `&mut x` both convert to a `*T`
parameter, which is raw (0.18.1). `&x` where `&mut T`
is wanted is an error naming `&mut x`. A place reached through a raw
pointer still gives a raw pointer (`&*p` gives a reference). Function
attributes `#[views(a, *b)]` and `#[stores(c)]` declare a view summary.
(Phase 0: what the own pass checks of them comes with its tasks.)

**Moves, drops and the checks** (value semantics, T1–T3, T7;
[design/value-semantics.md](design/value-semantics.md) §2). A value of
an owned type (a `Vec`, `Buf`, `HashMap`, a type with `Drop`, a struct
holding one) moves on `=`, a by-value argument and `return`, and is
dropped at the end of its scope; views (slices, references) cannot
outlive or alias against what they view. These checks and the drops are
on by default: `--values=error` (the default since T7, which moved the
tests, examples and evals over with `tachyonc fix --values`).
`--values=warn` and `--values=report` keep 0.16's semantics (no drops)
and only warn or list; `--values=off` turns the pass off. They are
opt-outs for 0.17 only. `defer v.free()` stays legal (`free` frees now
and leaves the container empty) and is no longer needed.

**The prelude** gains `Buf`, `HashMap`, `read_line`, `read_stdin_in`,
`Scanner`, `parse_int`, `trim`, `split_in`, `split_whitespace_in`,
`sort`, `sort_by`, the stable sorts (`sort_stable`, `sort_stable_by`,
`sort_stable_in`, `sort_stable_by_in`), `cmp_of`, `eq_of`, `Fmt`, `panic` and `unreachable`
(and `read_stdin`, `split`, `split_whitespace`, whose use is the error
naming their `_in` form). As before it comes last (a program's own
`trim` hides it), and std is loaded only for a program that uses one of
its names: a name the program declares itself (`fn trim`, `let split`),
a field, a parameter or a member (`.trim`) does not load it. std's own
source sees the prelude too (`None`, `Ok(x)` inside std).

`panic(message: [u8]) -> !` prints the message on stderr and exits with
101, as a failed check does; `unreachable()` the same with "entered
unreachable code". Both are safe; their effect is
`panic`. `std::panic` is still the `unsafe fn` taking a C string.

**Indexing a Vec or a Buf.** `v[i]`, `v[i] = x`, `v[i] += x` and
`v[a..b]` on std's `Vec` and `Buf` are `v.as_slice()[i]` (and so on):
checked, a place to assign without `mut` (as a slice's element is); the
slice is valid until the Vec grows or is freed. A `HashMap` is not
indexed (`m.get(k)` is an Option: Rust's `m[k]` panics). On any pointer
to a Vec, a Buf or a slice, `p[i]`, `p[i] = x`, `&p[i]` and `p[a..b]`
index the pointee (`p.as_slice()[i]`, `(*p)[i]`), checked, as `p.get(i)`
is: the type decides what they mean. Whether the pointer is a borrow
decides only safety: through a borrow (`&T` / `&mut T`, `&v`) they
are safe; through a raw pointer (a `*T` parameter, a local, a field, a
static) they read through it, so they are `unsafe` (the error's try: is
`fix --only unsafe`, or `v[i]` for a local `let p = &v;`). The type is
the one written in the source, not an instance's: where p points, as
written, to a type parameter (`p: *T`, a field `*T` of a generic struct,
`x as *T`, the `ptr` of an `s: [T]`, a call to a function declared
`-> *T` with T its own or its impl's parameter, a local from one of
these), `p[i]`
is pointer arithmetic for every `T`, a Vec too, so a generic body means
one thing in every instance (std's Vec indexes its `ptr: *T` so); only a
pointee written as a Vec, a Buf or a slice (`*Vec<T>`) is indexed
(decided 2026-10-16, for the user's review). `p[0]` on a pointer to anything
else is pointer arithmetic; through a borrow its error names `*p`, the
value it points to (`try: *out = acc` for `out[0] = acc`).

**std on values** (value semantics, T4). `v[i] = x`, `v[i] += x`,
`v[i].f = x` and `&mut v[a..b]` go through `v.as_mut_slice()` (an
exclusive view; reads through `v.as_slice()`). Until 0.18 a `[T]` is
accepted where `&mut [T]` is wanted (`sort(v.as_slice())`, `sort(s)`):
the call takes the exclusive loan. A closure parameter annotated `*T`
where the bound wants `&T` is an error (0.18.1; `fix --suggested`
writes `&T`); a function with pointer parameters is a value like any. A
struct or enum that owns nothing (no Vec, Buf, HashMap or Drop in it)
is `Clone` without an impl, by copying, as numbers are. A method may
take `self: &mut [T]`, called on a slice (`s.swap(i, j)`, `s.sort()`).

**Through a pointer.** `p.0` on a `*(A, B)` is `(*p).0`, as `p.x` on a
`*S` is `(*p).x`: safe when `p` is a borrow (`&T`, `&mut T`, `&x`),
`unsafe` on a raw pointer.

**`len()`.** `s.len()` on a slice is its field `s.len`; `a.len()` on
an array (a variable, constant, static or a field of one) is its
length, an `i64`. The field stays. The other way round, `a.len` on such
an array is its length, and `v.len` on std's `Vec`, `Buf` and `HashMap`
(whose `len` field is sealed, or which have none) is `v.len()`: a read
only; `v.len = n` and `&v.len` are still errors.

**Paths.** A path's first segment that is not `crate`, `self`, `super`,
`std` nor a name of the module it is written in is looked up beside that
module (a child of its parent), then at the root: `use lexer::{Tok,
next};` in `parser.tach`, where `main.tach` has `mod lexer; mod parser;`,
is `use crate::lexer::{Tok, next};`. A path in code starts the same way
(0.17): `lexer::next(..)`, `fn f(t: lexer::Tok)`, `lexer::Tok { .. }` and
`lexer::Kind::Ident` in a pattern are `crate::lexer::...` there, as the
`use` line would be; a name in scope in the module (an item, an import)
still comes first. When both are modules and differ (`crate::a::lexer`
beside `crate::a::parser`, and `crate::lexer`), it is an error,
`ambiguous module`, whose `try:` lines are the two `crate::` paths (the
`use` line, or the path in code, so written). A module elsewhere
(`crate::b::lexer`) is `unknown module 'lexer'`, whose `try:` is the
`use` line with its path from the root.
`use m::{self, X};` is not supported: its error's `try:` is `use m;`.

## Additions of 0.18: contracts and tests (phase 0)

The design is [design/contracts-verification.md](design/contracts-verification.md).
Phase 0 reads this syntax and keeps it (front/contracts's tables); the
checks, the tests and distinct types come with the tasks named there.

```ebnf
fn_item    = signature { clause } ( block | ";" ) ;            (* fns, trait fns, impl fns *)
clause     = [ "debug" ] ( "requires" | "ensures" ) expr [ "else" expr ] ;
type_inv   = [ "debug" ] "invariant" expr [ "else" expr ] [ ";" ] ;   (* after a struct's or enum's "}" *)
alias      = "type" ident [ generics ] "=" [ "distinct" ] type [ type_inv ] ";" ;
attribute += "test" | "property" | "fuzz" | "cfg" "(" "test" ")" ;
```

- `requires`, `ensures`, `invariant`, `debug` and `distinct` are not
  reserved: they are read as such only where a clause (or a distinct
  type) may stand, so a variable may still be called `result` or `debug`.
  In an `ensures`, `result` is the returned value and `old(e)` is `e` at
  the function's entry (T1).
- A clause's condition is an expression in which `{` ends it, as in an
  `if`'s condition. The message after `else` is a string or an f-string.
- `#[cfg(test)]` marks the item after it (all of a module's items);
  `#[test]`, `#[property]` and `#[fuzz]` mark a function. Phase 0
  compiles them as ordinary items (T2 leaves them out of builds that are
  not tests).
- Phase 0 checks a distinct type as a transparent alias (T4 makes it a
  type of its own) and ignores the invariants and clauses (T1 checks
  them).

## Additions of 0.18.1

```ebnf
let_stmt += "let" pattern "=" expr "else" block ";" ;     (* let-else *)
```

- **let-else.** `let PAT = e else { ... };` binds PAT's variables for the
  rest of the block when e matches; else the block runs and must not end
  normally (`return`, `break`, `continue`, a call that never returns). It
  is `let (a, b) = match e { PAT => (a, b), _ => { ... } };`, so a
  binding is a name that starts with a lower-case letter or `_` (others
  name constants and variants). The pattern takes no type.
- **Patterns on references** (Rust's default binding modes): see
  [Patterns](#patterns).
- **Temporaries.** `&e` of a value (a call's result, a literal, an
  operator's) takes a temporary: a local named by e's text, declared
  before the statement and dropped at the end of the block (Rust's
  lifetime extension for `let r = &f(x);`). It is made where nothing
  evaluated before it in the statement (a call, an assignment, an index)
  could tell the difference; a literal of literals anywhere. Where it is
  evaluated or not (the other side of `&&`/`||`, a match arm's value, a
  closure's body), its temporaries go in a block made for that
  expression. A loop's condition makes none. Elsewhere `&e` is
  `cannot take address of non-lvalue expression`, whose `try:` names the
  value first. `&e` of a slice value is still the slice; where `&[T]` is
  expected, the temporary's reference (`cmp_of(&a.text(), &b.text())`).
- **An index** may be a reference to an integer (`keys[a]` with `a:
  &i64`, a `sort_by` closure's parameter): it is read through.
- **References where values are expected, and back.** A place (a
  local, a field) where `&T` is expected is borrowed, as a `self: &T`
  receiver is: `f(it)` for `f(x: &Item)`. A reference to a plain value
  (a number, a bool, a struct of them) where the value is expected is
  read through, a copy: an operator's operand (`n + 1`, `3 < n`), an
  argument, a typed `let`. A `&&T` where `&T` is expected is read
  through once, and a method's receiver through every reference (`tr.f()`
  for `tr: &&T`, `s.len()` for `s: &[u8]`). A view taken through a
  reference local or a pattern's reference binding views what it points
  to, not the reference: it may be returned or kept after the binding's
  scope when that is alive.

## Additions of 0.19: vector types, std::arch, target features

The design is docs/design/arch.md; `tachyonc guide arch` teaches it.

### More vector types

0.10's six vector types become thirty: unsigned lanes, and 64-bit and
256-bit vectors. Each is aligned to its size, and its names are reserved
as 0.10's are.

| size | signed | unsigned | float |
|---|---|---|---|
| 8 bytes | `v8i8 v4i16 v2i32 v1i64` | `v8u8 v4u16 v2u32 v1u64` | `v2f32 v1f64` |
| 16 bytes | `v16i8 v8i16 v4i32 v2i64` | `v16u8 v8u16 v4u32 v2u64` | `v4f32 v2f64` |
| 32 bytes | `v32i8 v16i16 v8i32 v4i64` | `v32u8 v16u16 v8u32 v4u64` | `v8f32 v4f64` |

Every 0.10 operation applies to every one of them, with these rules:

- **Unsigned lanes** wrap at their width and compare unsigned. A mask of
  an unsigned vector is the vector itself, each lane all ones (`MAX`) or
  `0`. `-a` on unsigned lanes is `0 - a`, wrapping.
- **The mask of a float vector** is the signed vector of its lanes'
  width (`v8i32` for `v8f32`, `v1i64` for `v1f64`).
- **Float sums** stay pairwise: the sum of the first half's lanes plus
  the sum of the second half's, so `((l0 + l1) + (l2 + l3)) + ((l4 + l5)
  + (l6 + l7))` for eight lanes.
- **Placement.** A 64-bit vector lives in the low half of a vector
  register. A 256-bit vector is computed as its two 128-bit halves on
  every target in 0.19 (no function uses 256-bit registers yet), so the
  same program runs everywhere.

**`T::from_bits(v)`** reinterprets the bytes of a vector `v` of the same
size as vector type `T` (lane `i` of `T` is the bytes at `i × size_of`
its lane). It costs no instruction. A size mismatch is a type error, and
a type error between two vectors of the same size suggests it.

### std::arch's types

`std::arch::aarch64` and `std::arch::x86_64` name the vendors' vector
types (docs/design/arch.md).

- **ACLE's types are aliases** of the vector types: `int8x16_t = v16i8`,
  `uint8x16_t = v16u8`, `uint16x4_t = v4u16`, `float32x4_t = v4f32`,
  `float64x1_t = v1f64`, and so on for every lane type and both sizes.
  The polynomial types are unsigned (`poly8x16_t = v16u8`, `poly64x2_t =
  v2u64`, `p8 = u8`, `p64 = u64`, `p128 = v2u64`). Each has its tuples:
  `uint8x16x2_t = (v16u8, v16u8)`, `...x3_t`, `...x4_t`. Through an
  alias, a vector type's associated functions apply as they are:
  `uint8x16_t::from_bits(v)`, `uint8x16_t::splat(0)`.
- **Intel's types are distinct and opaque:** `__m128i`, `__m128`,
  `__m128d` (16 bytes), `__m256i`, `__m256`, `__m256d` (32 bytes). They
  have no operators, no lanes, no `splat` or `load`: their intrinsics
  make, read and combine them, and `T::from_bits(v)` converts them both
  ways (`v16u8::from_bits(m)`, `__m128i::from_bits(v)`).

### Intrinsics

An intrinsic is a function of `std::arch`, `std::arch::aarch64` or
`std::arch::x86_64`, under its vendor's name, called as any function.

- **Immediates are arguments.** A shift count, lane number or shuffle
  mask is an `i64` argument in the vendor's position, which must be a
  constant expression (literals, constants, operators and casts of them)
  in the range the intrinsic gives (`arch.const_arg`):
  `vextq_u8(a, b, 3)`. Rust's `vextq_u8::<3>(a, b)` is an error
  (`arch.rust_form`) whose `try:` line writes this form.
- **Memory intrinsics take a slice and an index**, checked as
  `v.load(s, i)` is: `vld1q_u8(s, i)`, `vst1q_u8(s, i, v)`,
  `_mm_loadu_si128(s, i)`. Given a pointer instead (C's and Rust's
  signature) the call is an error (`arch.raw_form`) naming both forms.
- **The pointer forms** are in the `raw` submodule of each architecture's
  module, with the vendor's signature, `unsafe`:
  `std::arch::aarch64::raw::vld1q_u8(p: *u8)`,
  `std::arch::x86_64::raw::_mm_loadu_si128(p: *__m128i)`.
- `is_x86_feature_detected!("f")` and its AArch64 twin are
  `std::arch::detect("f")` (`arch.rust_form`).
- **The portable module `std::arch`** holds `has`, `detect` and the bit
  operations every target has an instruction for (`count_ones`; std's
  `count_ones`, `leading_zeros` and `trailing_zeros` are one instruction
  where the target has it).
- **The modules are virtual**: their declarations are made from the
  intrinsic tables (`compiler/arch/*.def`) for the names a program uses,
  so a program that names none pays nothing. `tachyonc query show NAME`
  prints one's declaration with its features, instruction, what it
  computes and its other architecture's equivalent; `tachyonc query
  arch WORDS` searches the tables (docs/query.md).
- **Effects.** A register intrinsic has none; a checked memory form is
  `panic`; a `raw` form is `unsafe`; `has` and `detect` have none. So
  `#[pure]` functions may use them.

### Target features

Every intrinsic needs target features (`neon`, `crc`, `sha2`, `avx2`,
...; the lists are in `tachyonc explain arch.feature_name`). A call is
legal only where its features are *known*:

- **The build's features**: the target's baseline (aarch64-macos:
  `apple-m1`, which has neon, fp, crc, aes, sha2, sha3, dotprod, rdm,
  lse, fp16; aarch64-linux: `generic`, neon and fp; x86_64-linux:
  `x86-64`, sse and sse2; x86_64-macos: `core2`, up to ssse3), changed by
  `-C target-cpu=NAME|native` and `-C target-feature=+f,-g` on every
  command that checks. A feature implies what it needs (`avx2` implies
  `avx`, ... `sse2`; `sha3` implies `sha2` and `neon`). Removing one the
  ABI needs (`-neon`, `-fp`, `-sse2`) is `arch.baseline`; an unknown CPU
  `arch.cpu`.
- **A declaration**: `#[target_feature(enable = "crc,aes")]` on the
  enclosing function. Its body is checked against it (`arch.declared`),
  and its callers must know what it declares.
- **A guard**: the then branch of `if G`, where G is
  `std::arch::detect("f")` or `std::arch::has("f")` or a `&&` of them;
  the else branch of `if !G`; the rest of a block after `if !G { ... }`
  whose block diverges (`return`, `break`, `continue`, a panic); the
  rest of a block after `assert(G)`. `||`, a negation elsewhere and a
  `bool` kept in a local give nothing.

`std::arch::has("f")` is the constant answer of that known set at its
point (never inferred). Both take the feature's name as a string
literal (`arch.feature_literal`); an unknown name is `arch.feature_name`.
`aes` names both architectures' feature: unqualified it is the target's,
and `aarch64.aes` / `x86_64.aes` name one (`arch.feature_ambiguous`
where the reading matters).

**Requirements are inferred**, as effects are: a function needs what its
calls need beyond what is known at each call, generic instances and
closures each their own. A declaration pins a function's requirement.
Where nothing above can know a feature, a requirement is an error
(`arch.feature`, at the call that brings it in, with the intrinsic):
`main`, an `extern "C"` function, a test or property, and a function
taken as a plain `fn` value (`arch.fn_pointer`; a closure passed as
itself is followed, and a `#[multiversion]` function's address may be
taken).

**Another architecture's intrinsics** type-check everywhere. Their
features are never known, so `has` and `detect` of them are the constant
`false`, a branch under them is dead (checked, never generated), and a
call of one outside such a branch is `arch.feature`. One source holds
both architectures' code; there is no `cfg`.

### Run-time detection and `#[multiversion]` (0.19)

- **`std::arch::detect("f")`** is a constant where f is known (the
  build's features, a `#[target_feature]` declaration, a guard around
  it) or of another architecture; otherwise it tests one bit of a word
  std fills once: on AArch64 macOS from `sysctl` (`hw.optional.arm.FEAT_*`,
  only for what the build does not assume), on AArch64 Linux from
  `getauxval(AT_HWCAP)` and `AT_HWCAP2`, on x86-64 from `cpuid` and
  `xgetbv` (the avx family only when the system saves the ymm registers).
  A program's `main` fills the word before its first statement; code
  entered from C with no tachyon `main` fills it at its first detect.
  The test is pure: repeated tests merge, and one in a loop is hoisted
  out of it.
- **`TACHYON_ARCH_DISABLE=crc,aes`** (or `all`) in the environment of a
  running program clears those features from the word (and the features
  that need them: sha3 with sha2), so its detects take the fallback
  paths. It only clears: no setting makes a missing instruction run.
  `tests/run.sh` runs every case that uses `detect` or `#[multiversion]`
  a second time with `all`, and expects the same output.
- **`#[multiversion("f", "g,h", ...)]`** on a function compiles its body
  once per listed set of the target's architecture, each version knowing
  that set (`has("f")` is true in it), plus the baseline version, and
  makes the function a dispatcher: the first listed set the CPU has
  (`detect`) picks its version, else the baseline. A set of another
  architecture makes no version; one the build already has ends the list.
  The dispatcher needs only the baseline, so its address may be taken.
  An intrinsic call that a version lacks the feature for is an error
  (`arch.multiversion`, naming that version): put it under
  `if std::arch::has("f")`.

## Importing C headers

`import "stdio.h" as c;` *(0.4; `as`: 0.5, required since 0.8)* reads a C
header and adds its declarations to the program, named through `c`
(`c::printf`); `import "./mylib.h" as c;` (a path starting with `./` or `../`)
is relative to the importing file; `-I DIR` adds include directories. All
imports of a program are read as one translation unit, as the target's C
compiler reads them: its predefined macros and its include path come
from `cc -dM -E -v` (`$TACHYON_CC` instead of `cc`), so headers need the
target's C compiler on the host (a macOS host for both macOS targets, an
x86-64 Linux host for `x86_64-linux`), unless `$TACHYON_CC` names a C
compiler for the target (0.9: `clang --target=x86_64-linux-gnu
--sysroot=DIR` with a Linux system's headers in DIR, or a cross gcc),
which is then trusted for its headers and predefined macros. Another
way: `tachyonc --emit-imports` on a host of the target's system writes
the declarations as tachyon source, to use in place of the `import`.

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
names live in the C module, named by `as`.

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
