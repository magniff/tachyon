# tachyonc query

`tachyonc query` answers questions about a program from the compiler's
front end: where a name is defined, its source, every reference the
checker resolved to it, and a module's items. It replaces reading the
source with `grep`, `sed -n 'N,Mp'` and `head` (see
[agent-tool-usage.md](agent-tool-usage.md)). Output is plain text, one
fact per line, with no colour or decoration, sorted by file (by path; the
compiler's own `<std>` and `<C import>` last), then line, then column.

```
tachyonc query def NAME [ROOT] [--exact]
tachyonc query show NAME [ROOT] [--exact]
tachyonc query refs NAME [ROOT] [--count] [--exact]
tachyonc query callers NAME [ROOT] [--count] [--exact]
tachyonc query items [MODULE] [ROOT]
```

`ROOT` is the program's root file. Without it: `$TACHYON_ROOT`, else
`./main.tach`, else `./compiler/src/main.tach`. Positions are
`file:line:col`, 1-based, with the file as the module loader names it
(relative to the current directory when ROOT is).

Exit status: 0 answered, 1 nothing matches NAME (stderr has the nearest
names), 2 usage error or no root.

## Paths

Every definition has a fully qualified path, printed first wherever a
definition is named, and accepted back as NAME:

| definition | path |
|---|---|
| item of the root module | `crate::main` |
| item of a module (a file, or an inline `mod m { }`) | `crate::gvn::run_gvn`, `crate::sys::SockaddrIn` |
| the standard library | `std::Vec`, `std::HashMap` |
| a C header's declaration (`import "h.h" as c;`) | `crate::c::printf` (the importing module's path and the `as` name of the first such import) |
| function of an `impl T { }` block | `crate::geom::V2::len`, `std::Vec::push` |
| function of an `impl Trait for T` block | `<crate::geom::V2 as Add>::add` (the trait by its path when two traits share its name) |
| function a trait declares (with or without a default) | `crate::shapes::Area::twice`, `std::Add::add` |
| enum variant | `crate::ast::NodeKind::Fn` |
| struct field | `crate::ir::Inst.op` |
| module | `crate::gvn` |

## Matching NAME

- A full path matches that definition.
- A partial path matches every path it ends, by whole segments:
  `run_gvn`, `gvn::run_gvn`, `V2::len`, `NodeKind::Fn`, `Inst.op`.
- A bare name (`push`) matches every function, type, variant, constant,
  static, trait, alias and module of that name, in any module, type or
  trait. Fields match only with a dot: `Inst.op`, or `.op` for every
  field named `op`.
- A trait impl's function also answers to `Type::f` (`V2::add`), and to
  `<Type as Trait>::f` with each part full or partial
  (`<V2 as Add>::add`).
- `--exact`: only a full path matches.
- Import aliases are not definitions: `use a::f as g;` makes `g` a
  reference to `crate::a::f`, but `query def g` finds nothing (its
  error names what `g` imports).
- No match: exit 1, and stderr lists the definitions whose names are
  within a small edit distance of NAME's last segment ("did you mean").

## def

One line per matching definition:

```
crate::gvn::run_gvn  compiler/src/gvn.tach:721:8  fn  pub fn run_gvn(fi: i64) -> bool
```

`path  file:line:col  kind  signature`. The position is the name's.
Kinds: `fn`, `impl method` (in an impl block, of a type or of a trait
impl), `trait method`, `struct` (also unions), `enum`, `variant`,
`field`, `trait`, `const`, `static`, `type alias`, `mod`. The signature
is the source up to the body or the `{`, its whitespace collapsed, with
`pub` when the item is public; a long constant's value is cut to `...`.

## show

Each matching definition's exact source: a header, then whole lines from
the comments and attributes directly above it through its end.

```
// crate::gvn::run_gvn  compiler/src/gvn.tach:721-796
pub fn run_gvn(fi: i64) -> bool {
    ...
}
```

A struct or enum shows its whole declaration (not its impl blocks);
`Type::method` shows the method. When more than 5 definitions match,
`show` prints only their paths and positions, and asks for a qualified
name.

## refs and callers

Every resolved reference, one per line:

```
compiler/src/gvn.tach:721:8  def  |  pub fn run_gvn(fi: i64) -> bool {
compiler/src/opt.tach:17:17  in crate::opt  |  use crate::gvn::run_gvn;
compiler/src/opt.tach:533:13  in crate::opt::simplify_function  |  run_gvn(fi);
```

`file:line:col  in ENCLOSING  |  trimmed source line`. ENCLOSING is the
innermost definition holding the reference (a function, or the struct,
constant, trait... whose declaration it is in), else the module (a
`use`, an `impl` header). The definition itself is the line marked `def`.

References are what the compiler resolved, never text: calls, functions
used as values, constants and statics, types (in signatures, fields,
casts, `impl` headers, struct literals, patterns, paths `T::f`), field
accesses and the fields of struct literals, variants (constructed or
matched), method calls (resolved through the receiver's type, and
through a bound's impl in generic code), operator calls of trait impls
(`a + b` calls `<T as Add>::add`; at the start of the operation),
module paths, and `use` imports. A local that shadows a function,
another module's item of the same name, comments and strings are never
references.

- When NAME matches several definitions, each one's references come in
  a group headed `// PATH`, and every line names its target:
  `file:line:col  in ENCLOSING  -> TARGET  |  line`.
- A trait's function (`Area::area`, `std::Add::add`) also counts the
  references to the impl functions that implement it (each line
  `-> <T as Trait>::f`); the functions of a trait impl that do not
  override a default are the default's references.
- Generic code is checked once per instance; a reference in it is
  listed once per position (and target).
- `--count` prints the number of lines refs would print (the definition
  included); for several definitions, `N  PATH` per definition.
- `callers` is `refs` restricted to calls (method and operator calls
  included; no definition line).

## items

`items MODULE` lists a module's items in order, without bodies:

```
// crate::geom  clash/geom.tach
4  fn  pub fn Point(x: i64) -> i64
8  struct  pub struct V2
13  impl  impl V2
15  impl method  pub fn len(self: *V2) -> i64
20  impl  impl Add for V2
21  impl method  fn add(self: V2, o: V2) -> V2
```

`line  kind  signature`; an impl block is its header line followed by its
functions. MODULE is a module path, matched like NAME (`gvn`,
`crate::gvn`, `crate`, `std`). `items` alone lists the module tree:
`path  file  N items` per module.

## Programs with errors

The query runs the front end as a compilation would, with its error
recovery, and answers from what it got: definitions come from the parsed
program, references from what the checker resolved. The errors are
printed (to stderr) only when nothing matches NAME, or when the program
could not be parsed at all.

## Known limits

- A generic function that is never instantiated is never checked: the
  references in its body are missing (its definition is found).
- A function whose body has a syntax error is not checked (no references
  in it); in a function with a type error, the references after the
  error in the failing statement or expression may be missing.
- Operator calls are placed at the start of the operation, not at the
  operator.
- `Self` in a struct literal or a type is not a reference to the type.
- Import aliases (`use a::f as g`) are not names of definitions;
  module references are the `mod` item, `use` and paths (`m::f`), not
  the module's file.
- Items the parser skipped after a syntax error are not defined.
- The C headers' declarations are shown as the compiler writes them out
  (`<C import>`), not as the header has them.
