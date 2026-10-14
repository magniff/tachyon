# tachyon 0.15 design: errors, conversions, formatting, less boilerplate, split for parallel work

Read from `/Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter` (branch c14-iter). Sources: `target/tachyonc query`, the guide, docs/design/closures-iterators.md and its notes, docs/roadmap.md, docs/refactor-shape.md.

## 1. Current state

- **Lexer** (`front/lexer.tach`):
  - `Tok::Question = 82` exists, but `parser/exprs::is_reserved_punct` rejects it, and `parser::reserved_error` prints "'?' is reserved for future use".
  - `lex_token` → `lex_string(start, is_c)` handles `"..."` and `c"..."`. A token is `{kind,start,end,value,suffix,joint}`.
  - `lex_range` appends tokens to `TOKS`.
- **Parser**:
  - `parse_postfix` handles `(`, `[` and `.`.
  - `parse_expr_list` parses call arguments and has no named form.
  - `parse_name_or_struct_literal` requires `name: expr` in a struct literal.
  - `items::parse_param` reads `[mut] name: type` and has no default.
  - `parse_trait` errors on `trait X<T>`: "traits cannot have type parameters (yet)".
  - `parse_attributed_item` knows only `repr` and the fn attributes, so `#[derive]` gives "unknown attribute".
  - `parse_bound` reads `Path<Name = T>` constraints only.
- **AST** (`front/ast.tach`):
  - The Node fields are uniform. Struct uses a,c,d,list,g; Enum uses a,c,d,list,g; Trait uses a,b(assoc),list. **Struct.h, Enum.h and Trait.g look free; Phase 0 must verify.**
  - Flag bits in `p` already used: 1–128, 2^16, 2^24–2^29 (`FOR_VIA_ITER`).
- **Checker**:
  - `check_mode::check_expr_inner` is the single place where an expected type meets an actual one. It ends with `coerce_closure`, then `mismatch_error`.
  - `generics::check_arg` handles arguments that were already synthesized for inference.
  - `synth_mode::synth_operands` / `literal_takes_rhs_type` handle binary operands. A `Binary` checked against a numeric expected type passes that type to both operands (`passes_expected_to_operands`).
  - `cast_node` / `type_name_node` already build implicit casts.
  - Calls go through `calls::synth_call` → `call_function` / `synth_path_call` / `synth_method` → `instantiate_call` (inference, `infer_from`) → `check_direct_call` (arity, `check_arg`).
  - `check_return` checks against `RETURN_TYPE`, which closures save and restore.
  - Nothing checks `main`'s signature; gen0 looks it up by symbol.
- **Traits** (`front/traits.tach`):
  - `TraitInfo{name,node,module}` and `ImplInfo{node,tr,ty,tpl,module}`. Coherence is one impl per (trait, type).
  - `trait_named` rejects `g != 0`.
  - `collect_method` puts trait-impl methods into the type's `METHODS`, so two impls defining the same name are a "duplicate method".
  - `intrinsic()` gives the operator traits, Eq (structural `==`) and Ord (numbers, pointers, fieldless enums) without an impl block.
  - **Generic traits do not exist.**
- **std**:
  - `compiler/std/std.tach` (1099 lines) and `iter.tach` are concatenated by `embed.sh` into `front/stdsrc.tach`.
  - `print(s: [u8])` makes one `write(1, ...)` per call. `print_int` allocates a heap `Buf`. There is no float printing (C's printf is used instead).
  - `read_line(*Buf) -> bool`, `read_stdin() -> Buf`, `parse_int -> Option<i64>`, `Scanner::{next_token, next_line, next_int} -> Option`.
  - The traits `Eq`, `Ord`, `Hash` have explicit impls per primitive and `[u8]`. There is no `Clone`, `Display`, `Debug`, `From`.
  - std is loaded by a token scan (`modules::load_std_if_named`). The prelude is `modules/lookup::prelude_name`, 18 names.
  - std's non-generic functions are checked and emitted for every program that loads std.
- **Tools**:
  - `refactor signature --add 'x: T = V'` writes V into every call. It is not a language default.
  - `rewrite` matches expression and statement patterns, but has no statement-list holes.
  - `same-output OLD` compiles the corpus (tests/run, examples, bench, compiler/src) at -O0/1/2 with both compilers and compares the output byte for byte.
- **Compiler source**: about 95k lines and 4982 functions. It uses std's `Option` (116 refs) and `Vec` (41), and mostly `base::IntVec` with statics. The common loop is `for i in 0..V.count { let x = V.data[i]; ... }` (about 900 `for i in 0..` loops).

## 2. Surface syntax and semantics

**Grammar additions** (docs/grammar.md, "Additions of 0.15"):
```ebnf
postfix   += expr "?"                                    (* POSTFIX_BP, like . ( [ *)
primary   += fstring
fstring    = 'f"' { text | "{{" | "}}" | "{" expr [ ":" spec ] "}" } '"'
spec       = [ "<" | ">" ] [ "0" ] [ digits ] [ "." digits ] [ "?" | "x" | "X" | "b" | "c" ]
arg        = expr | ident ":" expr                       (* named; after all positional *)
param     += ... [ "=" expr ]                            (* fn items and inherent methods only *)
field_init = ident ":" expr | ident                      (* shorthand *)
attr      += "#[" "derive" "(" path { "," path } [","] ")" "]"   (* before struct/enum; with repr *)
trait      = "trait" ident [ "<" ident { "," ident } ">" ] "{" ... "}"
bound      = path [ "<" ( type | ident "=" type ) { "," ... } ">" ]   (* From<U>, Iterator<Item = T> *)
```
- A hole expression cannot contain a top-level `:`; write parentheses.
- Nested f-strings are an error.
- `text` takes the normal escapes.

**`?`.**
- `e?` with `e: Option<T>` gives `T`, or does `return None`.
- With `e: Result<T, E>` it gives `T`, or does `return Err(conv(err))`.
  - `conv` is the identity when E is the function's error type F.
  - It is a widening cast when `widens(E, F)`.
  - Otherwise it is `F::from(err)` through an impl `From<E> for F`.
- The function's result type is read from `RETURN_TYPE`, so inside a closure `?` returns from the closure (an unannotated closure needs `-> T`, as `return` does).
- Defers run, as for `return`.
- Errors, each one line plus `help:`/`try:`:
  - "'?' needs 'f' to return Option or Result; it returns 'i64'", `try: -> Result<i64, E>`;
  - Option `?` in a Result function: `try: e.ok_or(Err::Missing)?`;
  - no conversion: "'?' cannot convert 'ParseIntError' into 'AppError'", `try: impl From<ParseIntError> for AppError { fn from(e: ParseIntError) -> AppError { AppError::Parse(e) } }`.
- `fn main() -> Result<(), E>` with `E: Debug` is accepted. On `Err` it prints `Error: {e:?}` to stderr and exits with 1 (Rust's behaviour).

**Widening (decided).**
- `widens(a, b)` holds for a narrower integer to a wider one of the same signedness, and for unsigned to a strictly wider signed type. `isize`/`usize` are i64/u64.
- Never between int and float, from bool, signed to unsigned, or narrowing.
- It applies to a *value* wherever check mode compares an actual integer type to an expected one: `let x: T`, assignment and compound assignment, arguments (including generic arguments after inference), `return`, block tails, struct fields, variant payloads, elements of array or tuple literals.
- It never applies inside other types (`*i32`, `[i32]`, `Vec<i32>`, `fn(i32)`, a tuple *value*).
- **Join rule:** where two integer types meet without an expected type, the result is the wider one if one widens to the other. This covers binary-operator operands (including comparisons), `if`/`match` branches, and two arguments binding one type parameter (`max(a_i32, b_i64)` gives `max::<i64>` in either order). Otherwise the existing mismatch error is kept, plus `try: (a as i64)`.
- **Expected types still flow into arithmetic**, as for literals today: `let t: i64 = n_i32 * m_i32` computes in i64. This is lossless and avoids C's overflow-before-widening bug; the guide states it.
- Literal typing is unchanged. Shift amounts are unchanged.

**From/Into (least-invasive generic traits).**
- Traits may have type parameters, with restrictions:
  - no default bodies in a generic trait;
  - operator traits stay non-generic;
  - an impl names concrete types or the impl's own parameters (`impl<T> From<T> for Wrap<T>`);
  - coherence is one impl per (trait, trait arguments, type);
  - bounds `T: From<U>` are allowed.
- Methods of generic-trait impls are **not** entered in `METHODS`. `T::from(x)` and `x.m(..)` that find no ordinary method are resolved among the type's generic-trait impls by matching the synthesized argument types against each impl's substituted parameter types. Zero matches or an ambiguity is an error that lists the impls.
- std:
```
pub trait From<T> { fn from(x: T) -> Self; }
pub trait Into<T> { fn into(self: Self) -> T; }   // provided by the compiler only
```
- `From` is intrinsic for the identity and for `widens(S, D)` (`i64::from(x_i32)` becomes a Cast).
- `Into` is intrinsic: `t: Into<U>` holds exactly when `U: From<t>`. `x.into()` becomes `U::from(x)` with U the expected type; without one the error is `try: let y: T = x.into();`. `impl Into` is an error with help "implement From<X> for Y".
- Helpers in convert.tach: `Option::{ok_or, map, and_then, unwrap_or_else}`, `Result::{map, map_err, err, unwrap_or_else}`, `std::eprint/eprintln`.

**Error and I/O convention.**
- Option means absence (end of input, not found). Result with a typed error enum means failure.
- `pub enum IoError { Read, Write }`
- `pub enum ParseIntError { Empty, InvalidDigit(i64), Overflow }` (position of the bad byte)
- `pub enum ScanError { End, Parse(ParseIntError) }`
- `read_line(line: *Buf) -> Result<bool, IoError>` (Ok(false) at the end)
- `read_stdin() -> Result<Buf, IoError>`
- `parse_int -> Result<i64, ParseIntError>`
- `Scanner::next_int -> Result<i64, ScanError>`
- `next_token`/`next_line` stay Option.
- Each error enum has Display and derived Debug.
- Migration through `tachyonc fix --only std015`: `parse_int($s)`→`parse_int($s).ok()`, `$sc.next_int()`→`.ok()`, `read_line($b)`→`.unwrap_or(false)`, `read_stdin()`→`.unwrap()`. All are exact except read_stdin on a read error.

**Formatting.**
```
pub trait Display { fn fmt(self: *Self, f: *Fmt); }
pub trait Debug { fn fmt_debug(self: *Self, f: *Fmt); }   // distinct name: trait methods share the type's namespace
pub struct Fmt { buf: *Buf, fd: i32, width: i64, prec: i64, flags: i64, mark: i64 }
impl Fmt { to_fd, to_buf, str, byte, flush, write<T: Display>(x: T),
           display<T: Display>(x: *T), debug<T: Debug>(x: *T), spec(w, p, flags), end_spec(), int, uint, float }
pub struct Interp<F> { f: F }
impl<F: Fn(*Fmt)> Display for Interp<F> { fn fmt(self: *Interp<F>, out: *Fmt) { (self.f)(out); } }
pub fn print<T: Display>(x: T)   println  eprint  eprintln   format<T: Display>(x: T) -> Buf   Buf::push_fmt
```
- **f-strings need the `f` prefix (decided).**
  - About 300 `"...{..."` literals in compiler/src (the guide texts) must mean the same under 0.14 and 0.15 for the bootstrap.
  - Every existing user string containing a brace would otherwise change silently.
  - A plain literal containing `{name}`, where name is a local passed to print/println/format, gets a warning with `try: f"..."`.
- Semantics: an f-string is evaluated where it is written. Its holes are computed then, left to right, once, and the value holds copies. The type is `std::Interp<closure>`: unnameable, passable to any `T: Display`, storable in a local.
- Desugaring, done by the checker:
```
{ let __f0 = e0; ...; std::Interp { f: move |__out: *std::Fmt| { __out.str("a "); __out.spec(w,p,fl); __out.display(&__f0); __out.end_spec(); ... } } }
```
  It reuses 0.14 closures. `move` means there are no escape errors. `?` in the spec selects `debug`.
- **Zero cost:** fd output goes to a static 4 KB std buffer (not heap, not a zeroed stack array), flushed at the end of each print call. That is one `write` per print, as today. A nested print inside a Display impl flushes everything pending in order.
- **Widths:** padding is applied by `spec`/`end_spec` on the bytes written. `spec` first flushes when there is less free space than the width, so any spill means len ≥ width.
- Numbers default to right alignment, text to left.
- `{c:c}` prints a u8 as a byte; u8 Display is a number.
- Floats go through `snprintf` with `%.15g`/`%.16g`/`%.17g`, the shortest that round-trips; `.N` gives `%.Nf`.
- `[u8]` Debug is quoted and escaped.
- `Vec<T: Debug>`, `Option`, `Result`, `HashMap` have Debug.
- Generic `[T]` has no Debug (it would conflict with the `[u8]` text impl); `std::debug_list(f, s)` is the helper.

**derive.**
- `#[derive(Eq, Ord, Hash, Debug, Clone)]` goes on structs and enums.
- On a generic type each parameter gets the trait as a bound: `impl<T: Ord> Ord for P<T>`.
- **Eq** generates nothing: structural `==` already is the derived equality. It checks that every field has `==`, else "cannot derive Eq for 'S': field 'f' of type 'X' has no ==".
- **Ord** is lexicographic over fields in declaration order. For enums it compares variant order first, then payloads. Fields are compared through `std::cmp_of(&a, &b)`, which uses `<` and so works for floats, pointers and fieldless enums.
- **Hash**: `h = std::hash_mix(h, std::hash_of(&self.f))`, with the variant index first for enums.
- **Debug**: Rust's output (`P { x: 1, y: 2 }`, `Circle(3)`), through `f.debug(&field)`.
- **Clone**: field-wise `std::clone_of(&f)`. `Clone` is in std, with impls for Vec (deep), Buf, HashMap, Option, Result, primitives and `[T]` (the view).
  - `x.clone()` on a type that is plain to copy (pointers, tuples and arrays of such, fieldless enums, fn types) is a copy (checker hook).
- Display has no derive (as in Rust).
- The prelude gains `Display, Debug, Clone, From, Into, format, eprint, eprintln`.

**Named and default arguments (decided).**
- A default may be given only on trailing parameters of fn items and inherent methods. Not on trait functions, extern fns, closures or fn types.
- A default is any expression that does not name a parameter or local. It is checked against the parameter type once at declaration, then cloned into **each call** and checked in the **callee's module**. That is C++'s rule: per call, so `Vec::new()` is a fresh value each time.
- At a call: positional arguments come first, then `name: value`.
  - **Named arguments must follow parameter order** (Swift's rule). Evaluation order is then always the written order, at zero cost. Out of order: `try:` the reordered call.
  - Each parameter is given at most once. A missing parameter without a default: `try: f(1, b: VALUE)`. An unknown name gets did-you-mean.
  - `self` cannot be named. Trait-function calls take positional arguments only.
- A function used as a value has its full signature: `let g = f; g(1)` is an error naming the arity. Generic functions get defaults per instance.
- Field shorthand `S { x, y }` is `S { x: x, y: y }` (a synthesized Ident with the field's span; flag `FIELD_SHORTHAND`).

## 3. Representation and lowering

None of the new features needs a back-end or IR change. Each node is either rewritten in place or keeps `y` = the node the back ends lower, as `Closure` does. In middle/lower/expr.tach and gen0 there is one line per kind: `Try|Interp => lower(NODES[n].y)`.

| node | parsed | checked |
|---|---|---|
| `Try` | a=operand | y=a `Match` (`std::Option::Some(__t) => __t, _ => return ...`; ARM_SYNTHETIC) |
| `Interp` | list=`Str` text nodes and `InterpHole`s | y=the block of §2; ty=`Interp<C>` |
| `InterpHole` | a=expr, b=0 Display/1 Debug, c=width(-1), d=prec(-1), p=`FMT_*` flags | — |
| `NamedArg` | a=name, b=value; in a Call/MethodCall list after the positional args | `normalize_args` rewrites the list into parameter order, appends default clones, sets `CALL_ARGS_DONE` |
| widened value | — | node n becomes `Cast{a=copy of n, b=type node}` with `p |= NODE_IMPLICIT`; tools report the inner node's type |
| `Param.h` | the default expr (0: none) | checked once in `resolve_signature` |
| `Struct.h`/`Enum.h` | holder (Generics node) of the derive TyNames | expanded before `collect_names` into `Impl` items appended to PROGRAM (fn `p |= FN_DERIVED`), spans = the derive attribute |
| `Trait.g` | the trait's params | `TraitInfo.params`; `ImplInfo.targs` (a TLISTS index) |

- **Lexer:**
  - `f"` lexes as `Tok::FHead=92` (text up to the first hole), then the hole's tokens lexed normally while depth is tracked, then `Tok::FMid=93` (value=text up to the next hole, suffix=spec string id), ..., then `Tok::FTail=94`.
  - `{{`/`}}` become text.
  - Holes are real tokens, so fmt and query see them.
- **Derived bodies are syntactic.** They need no types: generic std helpers (`cmp_of`, `hash_of`, `clone_of`, `Fmt::debug`) dispatch per instance. That is why expansion can run before name collection.
- **Generic-trait dispatch** (`convert::generic_trait_call`) chooses an impl and rewrites to `Call` with `x=f+1`, as `synth_method` does.
- **Flags:** `NODE_IMPLICIT=1<<30` (Cast), `FIELD_SHORTHAND=1<<31` (FieldInit), `FN_DERIVED=1<<32`, `CALL_ARGS_DONE=1<<33`.

## 4. Work split

**Phase 0 (lead, serial, about 1 day).** Everything parses and checks with stubs, and the suite passes unchanged.
1. **Lexer and parser** for all of §2:
   - FHead/FMid/FTail, with spec parsing into `InterpHole`;
   - `?` un-reserved; NamedArg; `Param.h`; shorthand;
   - derive (with repr; only before struct/enum);
   - `trait X<T>`; bounds with type arguments.
2. **AST:** NodeKinds `Try, Interp, InterpHole, NamedArg` appended; the flags above. `clone_node` copies Try.a, Interp list, InterpHole.a, NamedArg.b, Param.h, Trait.g. Verify that Struct.h, Enum.h and Trait.g are unused.
3. **Stubs and hooks** (stubs report `... not implemented yet (check.unimplemented)` through `closures::unimplemented`):

| module | stub functions | hooks that call them |
|---|---|---|
| `front/check/try_op.tach` | `check_try(n, expected) -> i64` | `synth_expr_inner`/`check_expr_inner` |
| `front/convert.tach` | `collect_trait_params(tr)`, `impl_trait_args(i)`, `generic_trait_call(n, t, member) -> i64` (-1), `into_call(n, expected) -> i64`, `error_conversion(value, from, to, pos) -> i64`, `implements_with(tr, t, targs) -> bool`, `main_result_wrapper()` | `trait_named` (g≠0 goes to the stub), `collect_impl` (after the coherence check), `satisfies` (bound with g), `synth_path_call` before `path_member_error`, `synth_method` before its no-method error, `check_program` (`main`) |
| `front/check/widen.tach` | `widens(a, b)` and `widen_node(n, to)` are **real**; `try_widen(n, actual, expected) -> bool` and `join_int(a, b) -> i64` are stubs returning false/0 | `check_expr_inner` before `coerce_closure`; `check_arg`'s synthesized branch; `synth_operands`; `synth_if`/`synth_match` joins; `unify` when a param is bound twice |
| `front/check/args.tach` | `normalize_args(n, f, first_param)` (no-op unless NamedArg/defaults are present, then the stub error), `check_param_defaults(f)` | `call_function`, `synth_path_call`, `synth_method`, all before `instantiate_call`/`check_direct_call`; `resolve_signature` |
| `front/check/interp.tach` | `check_interp(n, expected) -> i64` | the expression dispatch |
| `front/derive.tach` | `expand_derives()` (error if a derive is present) | after module loading, before `collect_names` |

4. **std:**
   - Split std.tach into `std.tach` (core), `io.tach` (stdin, parse_int, split, trim, Scanner), `fmt.tach` (print, println, print_int, print_cstr, plus a skeleton Fmt with real `to_fd/to_buf/str/byte/flush/display/debug`, the Display/Debug traits, Interp, and Display/Debug for i64 and `[u8]` only), `convert.tach` (From, Into), `clone.tach` (the Clone trait, `hash_mix`).
   - embed.sh concatenates std, iter, io, fmt, convert, clone.
   - Prelude gains its new names.
   - The std trigger also fires on FHead, `?` and `derive`.
5. **Tests and docs:**
   - tests/run/err_015_{try,interp,named,derive,generic_trait}_stub;
   - tests/query/syntax015 (a transcript);
   - grammar.md "Additions of 0.15" skeleton;
   - guide errors.md: the "'?' reserved" row replaced.

| task | owns | consumes | provides |
|---|---|---|---|
| **T1 Errors and conversions** | try_op.tach, convert.tach, the generic-trait lines in traits.tach/collect.tach, std/convert.tach, tests/run/try_*, conv_* | P0; `widens` | `?`, generic traits, From/Into, `main -> Result` |
| **T2 Widening and arguments** | widen.tach, args.tach, the join lines in synth_mode/body/instantiate, std/io.tach, tests/run/widen_*, args_*, io_* | P0 | coercions, joins, named/default args, shorthand checks, the I/O Result API, the patterns for `fix --only std015` |
| **T3 Formatting** | interp.tach, std/fmt.tach, tests/run/fmt_*, bench/fmtloop | P0 skeleton; T1 not needed | f-strings, Display/Debug for std types, specs, generic print/format, the brace warning |
| **T4 derive** | derive.tach, std/clone.tach, the `clone` copy hook in synth_method, tests/run/derive_* | P0 Fmt skeleton (full Debug after T3) | derived impls, Clone |
| **T5 Tools and guide** | tools/* except tools/rewrite, compiler/guide/*.md, guide/, docs/{grammar,query,refactor*,fmt}.md, tests/{query,refactor,fmt,guide} | P0 shapes | fmt, query, refactor, fix std015, guide, explain |
| **T6 Self-host migration** | middle/, back/, gen0/, base/, tools/rewrite/, std/iter.tach additions | 0.14 only | compiler/src on closures and iterators |

**T1.**
1. `?` as a Match desugar, with `RETURN_TYPE` checks and the three errors.
2. Generic traits: parameters, `ImplInfo.targs`, coherence, `check_impl_signatures` under `env_enter(trait params, targs)`, an error for defaults in a generic trait, bounds through `implements_with`.
3. `generic_trait_call` (choosing an impl by argument types; untyped literals left for last, ambiguity → `try: 3i32`); intrinsic From and Into; `into_call`; `impl Into` refused.
4. `error_conversion` used by `?`.
5. The main wrapper (`std::main_error<E: Debug>`), tested with E = i64 before T3.
6. The convert.tach helpers.

Acceptance:
- `?` in Option and Result functions, in a closure, with defer;
- two `From` impls on one enum;
- `T: From<U>` in a generic function; `i64::from(x_i32)`; `let y: Big = x.into()`;
- `main -> Result` exits 1 with `Error: ...`;
- each error case;
- a CHECK test: `?` in a loop produces the same IR as the hand-written match;
- the same output at -O0/1/2.

**T2.**
1. `try_widen` at all check sites; `join_int` in operands, if/match and `unify`.
2. `query type` and fmt unaffected (tested by T5).
3. `normalize_args`: matching, Swift order, default clones checked in the callee's module (`CUR_MOD` switched), errors with `try:`.
4. Field shorthand: an unknown local gets `help: write 'x: VALUE'`.
5. io.tach: the new API, error enums with Display impls (as plain `Fmt::str` calls, so no T3 dependency), the migration patterns written down in the task's notes for T5.
6. Migrate tests/run and examples by hand.

Acceptance:
- every widening site, plus the negative cases (u32→i32, i32→u64, int→float, `*i32`);
- `max(a_i32, b_i64)` in both orders;
- arithmetic computed in the destination type (documented example);
- named and default arguments on functions, methods and generic functions; a default naming a const of the callee's private module;
- all argument errors;
- I/O tests for each function.

**T3.**
1. `check_interp`: synthesize each hole once, bind the hidden lets by hand (as 0.14 T3 did for `for`), build the move closure and the Interp literal, check it.
2. fmt.tach: the static buffer, padding, int/uint (hex, bin, zero, char), float via snprintf, `[u8]` Debug escapes, Debug for Option/Result/Vec/HashMap, `debug_list`.
3. print/println/eprint/eprintln/format/push_fmt made generic.
4. The plain-literal brace warning.
5. Recommended: std's non-generic items become lazy (`FN_LAZY` extended to std items), since std grows by about 40%.

Acceptance:
- every spec; `{{`; holes evaluated left to right once; an f-string stored, then printed;
- `f.write(f"..")` inside an impl;
- errors: `println!` → `try: println(f"...")`; a Rust-style `fn fmt(&self, f: &mut Formatter) -> fmt::Result` → the tachyon signature; missing Display → the impl text;
- CHECK-NOT `malloc` and no indirect call for `println(f"{a} {b:?}")`;
- bench/fmtloop: 10^6 f-string lines at most as slow as print_int chains;
- compile time of a 500-f-string program measured.

**T4.**
1. Parse-time validation of derive names (did-you-mean; the type must be a struct or enum).
2. AST builders for each trait (helpers in the style of equality.tach's `eq_*`); generic bounds.
3. std/clone.tach: impls, `cmp_of`, `hash_of`, `hash_mix`, `clone_of`; the copy hook.
4. Conflicts: derive plus a hand impl gives the coherence error with `help: remove Ord from #[derive]`.

Acceptance:
- each trait on a struct, an enum and a generic struct;
- a HashMap keyed by a derived struct; `sort` by derived Ord;
- Clone of a Vec field is deep;
- Debug matches Rust's text;
- `derive(Hash)` with an f64 field names the field.

**T5.**
1. fmt: f-strings (text untouched, holes formatted), `?`, `name: v`, `= default`, shorthand, derive.
2. query: types inside holes; refs through named-argument labels and shorthand; `FN_DERIVED` items and `NODE_IMPLICIT` skipped in refs/unused/stats; `def S::cmp` → "derived at file:line".
3. refactor:
   - `--rename-param` and `--reorder` update named labels;
   - field and local rename expand shorthand;
   - `--add 'x: T = V'` declares a default, leaving calls untouched; `--fill-calls`, or a function used as a value or a trait function, gives 0.14's behaviour with a note;
   - extract-function refuses ranges containing `?`.
4. `fix --only std015`.
5. Guide: topics `conversions` (widening, From/Into, `?`) and `formatting` (f-strings, Display/Debug, derive); core.md rows (`x?`, `println!`, implicit i32→i64, `#[derive]`, `format!`); the std listing; errors.md; explain codes.
6. grammar.md completed.

Acceptance: `.q`/`.t`/fmt cases for all syntax; `fmt --all --check` clean; guide examples run; std015 migrates the 0.14-API fixtures to identical output.

**T6 (mechanical, tool-driven; only middle, back, gen0 and base, leaving front and tools to the feature tasks).**
1. Extend `rewrite`:
   - `$s...` holes over a block's statements;
   - automatic refusal when a binding hole dropped by REPLACEMENT is used in the site;
   - walkers descend into the new node kinds.
2. base: `IntVec::items(self: *IntVec) -> IntVecItems {v, i, n}`. It snapshots `count` at the start and reads `data[i]` fresh, which is **exactly** `for i in 0..V.count { V.data[i] }`, so pushes and reallocation in the body behave the same. It implements Iterator with `exact_len`/`at`. Plus `kids(n)` for middle/lower's AST walks.
3. iter.tach: `any`, `all`, `position`, `find` (next-based, short-circuit).
4. Idioms, run module by module with `--dry-run` first:
   - I1: `rewrite 'for $i in 0..$v.count { let $x = $v.data[$i]; $s... }' 'for $x in $v.items() { $s... }'`;
   - I2: the same with `child($n, $i)` → `kids($n)`;
   - I3: found-flag searches → `.any(|..| ..)` via `edit patch` (only bodies free of side effects);
   - I4: sum and count accumulators → `.fold`/`.sum`/`.count`.
5. Per module, measured against the Phase 0 compiler:
   - `same-output` against the Phase 0 compiler;
   - self-compile time at -O2 within +2% (else revert that idiom family in that module);
   - `tests/run.sh`.

Acceptance: same-output clean, `gate.sh --quick`, migrated sites per idiom reported, no new `unsafe` outside base.

**Merging.** Shared files get only Phase 0's one-line hooks. Resolve `stdsrc.tach` conflicts by rerunning `embed.sh`.
1. T2 first (it changes what checks).
2. T1.
3. T3.
4. T4.
5. T5 throughout, final pass last.
6. T6 at any time (disjoint directories); rerun its same-output after rebasing.

Then `bootstrap/gate.sh --quick`. Each task appends a "Tn notes" section to docs/design/errors-formatting.md, as in 0.14. New front/tools code may use 0.14 closures and iterators. The compiler source adopts 0.15's own features in 0.16, as the roadmap says.

## 5. Risks

- **Compile time of f-strings.** Each one costs a closure function, an env struct, `Interp<C>`, a Display instance and a print instance. Fallback: when an f-string is the immediate argument of print/println/format/push_fmt, expand it inline with no closure.
- **The in-place Cast for widening.** Node identity used by `SYNTHED`, `HINT_NODE` and the tools' position→node maps must follow the copy. `query type` must report the inner type.
- **Generic-trait dispatch with untyped literals**, and query mode's `TY_ERROR` instances.
- **The std API break** touches tests, guide, examples and the eval task texts (data only); the std015 fix must be exact.
- **The generic `print` changes code for every program.** `print("lit")` copies into the static buffer; slices over 4 KB must write directly.
- **Static-buffer reentrancy and interleaving** of stdout and stderr: flush whenever the fd changes.
- **T6 performance:** next-based `for` over `IntVecItems` relies on 0.14's threading and SROA. Measure per module, and keep counted loops where they regress.
- **std growth:** compile time for small programs (hence lazy std items).
- **`?`/return desugars inside `defer` blocks** produce the defer message. T1 should special-case the wording.

## 6. Open questions, with recommendations

1. **`f"..."` or bare strings?** `f"..."`, for the bootstrap and silent-change reasons in §2, plus the brace warning.
2. **Widening in binary ops?** Yes, by the join rule. Expected types flow into arithmetic.
3. **Named-argument order?** Parameter order (Swift), with an exact `try:`.
4. **What may a default be?** Any expression without parameters or locals, evaluated per call in the callee's module.
5. **Generic traits in general, or only `From`?** General, but restricted as in §2. A `From` special case would cost about the same and teach the wrong model.
6. **`main -> Result`?** Yes. It is the place Rust habits use `?` most.
7. **Debug for generic slices?** No in 0.15 (it conflicts with `[u8]` as text); use `debug_list`.
8. **u8 Display?** A number, as in Rust; `{c:c}` prints the byte.
9. **Buffer stdout across prints?** No. Flush per print, as 0.14 does. Revisit with 0.16's effects and an exit hook.
10. **Make std's non-generic items lazy?** Yes, in T3, measured.
11. **What does `refactor signature --add 'x: T = V'` mean now?** It declares a default. `--fill-calls` gives the old behaviour.
12. **Order of the compiler migration?** T6 does middle/back/gen0/base in 0.15. front and tools move in 0.16, together with 0.15's features.

### Critical files for implementation
- /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/check/check_mode.tach (`check_expr_inner`) and /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/check/synth_mode.tach (`synth_operands`, `cast_node`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/check/calls.tach (`call_function`, `synth_path_call`, `synth_method`, `check_direct_call`) and /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/generics/instantiate.tach (`instantiate_call`, `infer_from`, `unify`, `clone_node`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/traits.tach (`trait_named`, `collect_impl`, `satisfies`, `intrinsic`, `check_impl_signatures`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/lexer.tach (`lex_token`, `lex_string`) and /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/parser/exprs.tach and /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/parser/items.tach (`parse_postfix`, `parse_name_or_struct_literal`, `parse_param`, `parse_trait`, `parse_attributed_item`)
- /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/std/std.tach with /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/std/embed.sh and /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/modules/lookup.tach (`prelude_name`), /Users/magniff/workspace/tachyon/.claude/worktrees/c14-iter/compiler/src/front/modules/mod.tach (`load_std_if_named`)

## Phase 0 notes (the interface commit, for T1–T6)

What Phase 0 made, where it differs from or adds to §3–§4:

- **Lexer.** `Tok::FHead = 92`, `FMid = 93`, `FTail = 94`. `value` is the text piece (a string id, `{{`/`}}` unescaped, escapes and line continuations as in a string literal); FMid/FTail carry the spec of the hole they close in `suffix` (a string id of the bytes after `:`, **-1 when there is none**); FHead's `suffix` is **1 when the f-string has no hole** (the token is the whole literal `f"..."`), else 0. Spans: FHead `f"text{`, FMid `:spec}text{` (or `}text{`), FTail `:spec}text"`. A hole ends at its `}` at brace depth 0, or at a `:` outside any bracket that is not `::`. **String literals are allowed in holes** (they are tokens of the hole: `f"{m.get("k")}"`). Errors: an empty hole, a nested `f"`, a single `}` in the text, an unterminated f-string or spec. `--tokens` prints `fhead/fmid/ftail <hex> [spec <hex>]`. `Tok::text` gives `f"` and `}` for messages. lex_string's line continuation is a helper, `line_continuation()`, shared with the f-string text. **front/lexer.tach is now front/lexer/** (mod.tach, and strings.tach with the string, f-string and character functions, re-exported: `lint --max-lines 1000`; the lexer's statics are `pub` for it).
- **Parser.** `Interp`: list = Str nodes (the non-empty texts, each with its token's span) and InterpHole nodes in order. `InterpHole`: a = expr (span = the expression), b = 1 for `?`, c = width, d = precision (-1: none), p = `FMT_*` (ast.tach: LEFT 1, RIGHT 2, ZERO 4, HEX 8, UPPER 16, BIN 32, CHAR 64; std/fmt.tach has the same values as private consts). Spec errors are parser errors with a help. `Try` (a = operand, span to the `?`) is made in `parse_infix` at POSTFIX_BP. `NamedArg` (a = name, b = value) in `parse_expr_list` (only calls and method calls use it); a positional argument after a named one is a parser error. **Deviation:** `f(label: loop { .. })` is now a named argument, no longer a labelled loop argument. Shorthand: FieldInit with `FIELD_SHORTHAND`, b = a new Ident with the name's span; it **works already** (the checker sees `x: x`), tested by tests/run/struct_literal_shorthand. `Param.h` = the default; the parser rejects defaults on trait functions, trait-impl functions and extern functions (`items::no_param_defaults`); the trailing-only rule is left to `check_param_defaults`. Derive: `Struct.h`/`Enum.h` = a Generics node (start = the first `#[derive`) of the written paths (TyName via parse_type), several derive attributes add to one holder; derive goes with repr, not with fn attributes, not before a union. `trait X<T>`: `Trait.g` = parse_generic_params (bounds allowed). Bounds: `parse_bound` takes type arguments and `Name = T` constraints mixed in one `<...>`: the types go to the TyName's `g`, the constraints to `h` (each holder made only when non-empty; for a pure constraint list the holder node is now made after its AssocType nodes, not before).
- **Struct.h, Enum.h, Trait.g are free** (verified with `query refs Node.h`/`Node.g`): nothing read or wrote them; the readers of `g` on items (collect_impls' bounds, finish_program, has_impl) only look at Fn/Struct/Enum/Impl; clone_node already copies `g` and every non-Fn `h`, so Param.h and Trait.g are copied without new code (Try.a, InterpHole.a, NamedArg.b were added to node_field_a/b and clone_node's list; Interp's list is generic).
- **Flags.** As designed: `NODE_IMPLICIT = 1 << 30`, `FIELD_SHORTHAND = 1 << 31`, `FN_DERIVED = 1 << 32`, `CALL_ARGS_DONE = 1 << 33` (ast.tach).
- **Stubs** (exact names of §4): `check/try_op.tach::check_try`, `check/interp.tach::check_interp`, `check/args.tach::{normalize_args, check_param_defaults}`, `check/widen.tach::{widens, widen_node}` (real; `widen_node` copies n, makes n a `Cast` of the copy with a TyName of the primitive, `ty` set, `p = NODE_IMPLICIT`) and `{try_widen, join_int}` (false/0), `front/convert.tach::{collect_trait_params, impl_trait_args, generic_trait_call, into_call, error_conversion, implements_with, main_result_wrapper}`, `front/derive.tach::expand_derives`. Errors are "`... are not implemented yet (check.unimplemented)`" through `closures::unimplemented`, except where a hard error would stop the whole check: `expand_derives`, `check_param_defaults` and `main_result_wrapper` report softly (err_end_soft) and go on (so a default is reported at its declaration and again at a call that leaves it out). `check/widen` is a `pub mod`; try_op, interp, args are private to `check`.
- **Signatures added where §4 named none.** `TraitInfo.params` (the trait's Generics node, 0: none; set for real by `collect_trait_params`, called from `add_trait`) and `ImplInfo.targs` (0 until T1 sets it; meaningful only when the trait has parameters). `convert::bound_args(b) -> i64` (real): bound `b`'s type arguments resolved in its module under the current env, pushed to TLISTS; its index. `generic_trait_call` and `into_call` return the call's **type** (the node rewritten and checked), -1 when they do not apply. `implements_with` stub returns `tr < 0` (no type implements a generic trait yet), so an instance of `fn f<T: From<i64>>` gets the ordinary "the trait 'From' is not implemented for 'T'" error from check_bounds.
- **Hooks.** `synth_expr_inner`: `Try => check_try(n, 0)`, `Interp => check_interp(n, 0)`, `NamedArg` => unimplemented "named arguments" (a named argument where no function call takes it, e.g. a variant's or a closure's call). `check_expr_inner`: `Try`, `Interp` with `expected`; a `MethodCall` named `into` without arguments asks `into_call(n, expected)` first; `try_widen(n, actual, expected)` right before `coerce_closure`. `check_arg`'s synthesized branch: `try_widen` before `mismatch_error`. `synth_if`: `join_int(then, else)` before each `branch_types_error`. `unify`: a parameter bound twice to different types asks `join_int` (and rebinds to the join). `normalize_args(n, f, first)`: `call_function` (0), `synth_path_call`'s two paths (template `Vec::new()` and `method_of`, 0), `synth_method` (1, after the `is_method` check, before instantiation); all before `instantiate_call`/`check_direct_call`. `generic_trait_call`: `synth_path_call` before `path_member_error`, `synth_method` before its "no method" error. `check_param_defaults(f)`: end of `resolve_signature` (not for a failed signature). `trait_named`: a TyName with type arguments now names its trait (the arguments are the callers'); `add_trait` → `collect_trait_params`; `collect_impl` → `impl_trait_args(me)` after the coherence check, before `collect_impl_assoc`; `satisfies` and `check_bounds`: a bound with `g` goes to `implements_with(tr, t, bound_args(b))`, others to `implements`. `check_program`: `expand_derives()` then `lazy_std_inline(program)` before the collect phases, `main_result_wrapper()` after them. Back ends: `Try | Interp => lower_expr(NODES[n].y)` / `gen_expr(NODES[n].y)`.
- **Hooks not made** (no one-line hook can be neutral there; T2 restructures them): the join in `synth_operands` (the rhs is checked against the lhs's type, so `i32 + i64` fails inside `check_expr`; the join needs the rhs synthesized first when it is not an untyped literal) and in `check_match` (later arms are checked against the first arm's type).
- **std.** std.tach keeps the core (Option, Result, Vec, Buf, the operator traits and their impls, sort, HashMap); io.tach has the Reading stdin and Text sections (stdin, read_line, read_stdin, is_space, is_digit, trim, parse_int, split, split_whitespace, Scanner), fmt.tach the Printing section (print, println, print_int, print_cstr) then the skeleton: `Display { fn fmt(self: *Self, f: *Fmt) }`, `Debug { fn fmt_debug(self: *Self, f: *Fmt) }`, `Fmt { buf, fd, width, prec, flags, mark }` with `to_fd`, `to_buf`, `str`, `byte`, `flush`, `display<T: Display>`, `debug<T: Debug>` (a Fmt to an fd writes at once, `flush` does nothing; T3 adds the static buffer, `write`, `spec`/`end_spec`, `int`/`uint`/`float`), a private `fmt_int` (decimal), `Interp<F> { f }` with `impl<F: Fn(*Fmt)> Display`, and Display/Debug for i64 and `[u8]` (`[u8]` Debug is quoted, not yet escaped); convert.tach `From<T>`, `Into<T>`; clone.tach `Clone` and `hash_mix(h, x)`. embed.sh concatenates std, iter, io, fmt, convert, clone.
- **Lazy std items (addition).** Every non-generic function std adds would be emitted in every program that loads std (at -O0/-O1), changing their output. So `assoc::lazy_std_inline` makes std's **non-generic `#[inline]` functions** `FN_LAZY` (checked and emitted only when used, as 0.14's lazy defaults); no std function of 0.14 was `#[inline]` and non-generic. The new skeleton's functions are all `#[inline]`. When release-0.14's "std's non-generic items lazy" lands, this rule becomes a special case of it (merge: keep theirs, drop `lazy_std_inline` and its call in `check_program`).
- **The prelude** gains Display, Debug, Clone, From, Into, format, eprint, eprintln (`format`, `eprint`, `eprintln` are not in std yet: T3, T1). **Deviation (std trigger):** these 8 names load std only when they name std's item (`modules::uses_prelude015`): not after `fn struct enum trait type let mut const static for mod union` or `.`, not before `:` (a parameter, field or named argument: `printf(format: *u8, ...)` is in about 40 tests), and not when the program declares the name itself (examples/httpd.tach's `fn eprint`). Loading std for them changed the output of those programs. std also loads on FHead, `?` and the `derive` of `#[derive` (`needs_std015`, which compares the symbol's text, interning nothing).
- **Guide.** errors.md: the `?` entry shows the stub error, the derive entry too; the shorthand entry (`P { x, y: 0 }`, now valid) and `trait Conv<T>` (now valid) are removed; core.md's `?` row and syntax.md's reserved list updated. **The core guide's std listing leaves out** the items under a banner ending in `(0.15) ----` (fmt.tach's Display/Debug/Fmt section, convert.tach, clone.tach), with one line pointing to `tachyonc guide std` (`stdapi::std_api(out, core)`; `guide std` lists everything): with them the core guide was 29343 bytes, over its 28672 budget. T5 decides the final shape (and drops the `(0.15)` rule).
- **fmt.** No space inside an f-string's hole braces (`layout::space_rule`); everything else of fmt for 0.15 is T5's.
- **Tests.** tests/run/err_015_{try,interp,named,default,derive,generic_trait}_stub (the owning task replaces its case; `default` is an addition), struct_literal_shorthand, err_rust_habits (the `?` message), tests/query/syntax015 (a transcript: items, show, grep, refs, type; update with `tests/query/run.sh -u` when error counts change — note `-u` also moves the `##` comments of text.q: check it out again), clash.q (std line numbers).
- **same-output.** Against the base compiler (d2adf68), 520 of 5148 compilations differ: 496 are the programs that load std, whose std functions (and statics, string labels, label numbers) come in another order because io's and fmt's sections moved after HashMap and iter.tach; 24 are the changed messages (err_rust_habits' `?`, err_unknown_attribute's list of attributes now naming `derive`); err_assoc_lazy_default's `<std>` line number moved. Against the base built with std.tach reordered the same way (std = core, then iter, io, print): only the 3 message changes (36 compilations), no assembly. So the split changes the order of emitted functions only, and the new items change nothing for programs that do not use them.

## T4 notes (derive, Clone, tuples, stable sort)

What T4 made, where it differs from or adds to §2–§4:

- **Expansion is textual.** `derive::expand_derives` writes each derive's impl as tachyon text into one buffer, parses it as a source file `<derive>` (`add_source`, `lex_range`, the new `parser::parse_items_fragment`, which is `parse_program`'s loop from a token), then gives every new node the span of the derive's trait name (`Ord` in `#[derive(Eq, Ord)]`) or, for the code of one field, the field's (a table of (offset in the text, node) change points, `span_at`). So `module_of` puts the impl in the type's module, errors point at the attribute or the field, and the tokens of `<derive>` are the only trace of the text. The impls and their functions get `FN_DERIVED` (the Impl node too) and are appended to PROGRAM's list (a new list: the old one plus them). The paths are `std::Ord`, `std::cmp_of`, ... so a user's own trait named `Debug` is never derived. A generic parameter's bounds are copied from the source (`SRC[bounds]`) with the trait added: `impl<K: Hash + Eq + std::Ord> std::Ord for Keyed<K>`. cmp, hash, eq and clone are `#[inline]`; fmt_debug is not.
- **Deviation: Eq makes an impl.** `#[derive(Eq)]` writes `fn eq` comparing every field with `std::eq_of(&a.f, &b.f)` (`*a == *b`). Structural `==` rejects a struct holding a `[u8]` (and anything whose `==` comes from an impl), which is the common derive (a record with a name); with the impl, `==` on the type is the derived eq (an impl wins over the structural `==`), a `[u8]` field compares its bytes. For fields that have the structural `==` the code is the same after inlining. A fieldless enum compares `(*self as i64)` (never `==` on itself: that would call eq).
- **Ord** of a fieldless enum without written discriminants is `(*self as i64)` compared; otherwise the variant index is a `match` (declaration order, as designed: `Low = 9, High = 2` orders Low first; Rust orders by discriminant). Then `match (*self, *other)` over the variants with fields, `_ => 0` when there are other variants. **Hash** starts from 0 (`hash_mix(0, index)` for an enum's variant), a fieldless struct hashes to 0. **Debug** is Rust's text (`P { x: 1, y: "a" }`, `P` without fields, `V(1, 2)`, `V`), through `__f.debug(&field)`/`__f.str`; it needs Debug on every field, which before T3 only i64, `[u8]` and derived types have (tests use only those; Vec, Option, ... come with T3). **Clone**: `P::<T> { f: std::clone_of(&self.f) }`, an enum's match, a fieldless enum `*self`.
- **check_derives** (a new one-line hook in `check_program`, after the collect phases, before `main_result_wrapper`): for a non-generic derived type, every field type must have the trait (`implements`; Eq: `==` structural or through an impl). Else, at the field: `cannot derive Hash for 'B': field 'w' of type 'f64' has no Hash` (an enum's: `field 1 of 'D::V'`), with a help (floats: no Hash, NaN), and the impl's functions get `FN_BODY_FAILED` so no second error comes from their bodies. A generic type's fields are checked in its instances (`the trait 'Hash' is not implemented for 'Vec<i64>'` at the field, `in instantiation of 'G<i64>::hash'`).
- **Names.** Eq, Ord, Hash, Debug, Clone, or `std::` one of them. Otherwise `cannot derive 'X' (derivable: Eq, Ord, Hash, Debug, Clone)` with a help: PartialEq → derive Eq, PartialOrd → Ord, Copy → every type copies, Display → the impl to write (with the type's name), Default → `fn new()`, else did-you-mean (edit distance ≤ 2). A trait derived twice: `'Ord' is derived twice`. A derive that is not a name: `#[derive] takes trait names`. (Reported in expand_derives, before the collect phases: the parser has no list of traits.)
- **Conflicts**: the derived impl comes after every written one, so it is the one coherence reports; `traits::impl_type_error` calls `derive::derive_conflict_help(node)`: `help: remove Ord from #[derive], or the impl written by hand`.
- **std/clone.tach**: `eq_of`, `cmp_of` (`a.cmp(b)`, not `<`: `<` twice would compare twice per nesting level), `hash_of`, `clone_of`; Clone for Vec (deep, `T: Clone`), Buf (`#[inline]`, so lazy), HashMap (`K: Hash + Eq + Clone, V: Clone`), Option, Result. No Clone impls for primitives: see below.
- **Intrinsic Clone, Eq, Ord, Hash** (`derive/intrinsic.tach`; addition from the eval findings). `traits::intrinsic`: Clone for the types that copy (`is_plain`: numbers, bool, (), pointers, slices — the view —, fn types, fieldless enums, vectors, tuples and arrays of them) and for tuples of Clone types; Eq, Ord, Hash for tuples of 2 to 6 elements of Eq, Ord, Hash types (`tuple_implements`). Their methods: a hook in `synth_method` (`intrinsic_method(n, t, name)` when no method is found, before generic_trait_call) makes `x.clone()`, `x.cmp(&y)`, `x.eq(&y)`, `x.hash()` a call of the instance of a private std function: `copy_clone<T>` (`*self`), `scalar_cmp<T>` (floats, pointers, fieldless enums: `<` twice), `tupleN_{eq,cmp,hash,clone}<A, B, ..>` (written per arity in clone.tach, made with `fn_instance` and the tuple's element types). The pointer test at the top of synth_method also goes through a pointer when the pointee has such a method (`has_intrinsic_method`), as for a real one, so `x.clone()` with `x: *T` (std's `clone_of`) clones the T. `traits::binary_op_trait`: `<` on a tuple of Ord types, and `==` on a tuple of Eq types that the structural `==` rejects (a `[u8]` element), are calls of its cmp/eq (`tuple_operator`). So `sort` sorts tuples, `HashMap<(i64, [u8]), V>` works, `(1, "a") == (1, "a")` compares bytes.
- **Stable sort** (std.tach, under a `(0.15)` banner, so the core guide leaves it out): `sort_stable<T: Ord>(s)` and `sort_stable_by(s, f)`: insertion-sorted runs of 16, then bottom-up merges through a Vec of s.len elements (written before read), the left run first on ties. No methods (`[T]::sort_stable_by`) yet.
- **Tests**: tests/run/derive_{struct,enum,generic,tuples}, err_derive_{names,fields,conflict,generic}, std_sort_stable; err_015_derive_stub removed. errors.md's derive entry is now the PartialEq error (T5: the rest of the guide); clash.q and syntax015.q updated (std line numbers, one error fewer).
- **For T3**: Debug of std types makes more derives check (a `Vec<i64>` field of a `#[derive(Debug)]` type is an error until then). Derived Debug ignores width/flags: `{p:>10?}` pads nothing unless Fmt's spec wraps the whole value (it should, via `spec`/`end_spec` around the call). Tuples have no Debug (could be `tupleN_debug` helpers the same way: `intrinsic_helper` and `traits::intrinsic`).
- **For T5**: the derived items have spans in user files but come from `<derive>`; `query refs P` lists their uses at the derive attribute (`init crate #[derive(...)]`); `query show P::cmp` does not find them (they are impls of traits). Guide: core.md's `#[derive]` row, rust.md's derive rows, traits.md ("no #[derive]"), the std listing (clone.tach, sort_stable), conversions/formatting topics: derive, Clone, tuple ordering and hashing, sort_stable.
