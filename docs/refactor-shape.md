# Changing a program's shape: refactor signature, field, variant, rewrite, --script

The refactorings of 0.11's phase 2b: a change of a definition's shape
carried to every use the checker resolved, a typed search and replace,
and scripts of commands checked once. They are built on the edit engine
of [refactor.md](refactor.md): every command is atomic (the edited
program is checked before anything is written; a new error refuses the
whole edit), journaled for `undo`, takes `--dry-run` (the diff, zero
context lines), `--no-check`, `--exact`, `--root ROOT` and `--target T`,
prints one summary line, and reports problems as one line `SEVERITY
CODE: MESSAGE` with `try:` lines ([query.md](query.md)). NAME is
anything query accepts.

```
tachyonc refactor signature FN --add 'x: T = VALUE' [--at N] | --remove x
                               | --rename-param a b | --reorder b,a,c | --type x T [--default EXPR]
tachyonc refactor field STRUCT --add 'g: T = VALUE' | --remove g | --rename g h | --type g T
tachyonc refactor variant ENUM --add 'X(T, ...)' [--arm EXPR] [--arm-in SITE EXPR]... | --remove V | --rename V W
tachyonc rewrite 'PATTERN' 'REPLACEMENT' [--where '$x: T']... [--in FILE|MODULE]
tachyonc refactor extract-function FN --lines A-B --to NEW          (0.13)
tachyonc refactor inline FN [--at FILE:LINE] [--keep]                 (0.13)
tachyonc refactor --script FILE
```

Exit status: 0 done, 1 refused or failed (nothing written), 2 usage
error.

They work on the program as written: the front end keeps a copy of the
nodes as parsed (the checker turns `x.f(a)` into a call, `E::V` into a
variant literal), and takes the resolutions (which function a call
calls, the type of an expression) from the checked nodes. A generic
function's body is checked once per instance, on clones of its nodes;
its calls, literals and matches are found through its instances. Code
the checker never saw (a generic function never instantiated) is not
changed: a warning counts it.

Lists keep their layout: an element added to a list whose elements have
lines of their own gets a line of its own (with a trailing comma when the
others have one), else `, x` after the last; an element removed goes
with its separator, or with its lines and the comment lines above it.

## refactor signature

FN is a function, a method (`Point::scale`) or a trait's function
(`Shape::size`, or an impl's: `Point::size`, `<Point as Shape>::size`).
A trait's function changes with the trait's declaration and every impl's
(the parameter at the same position, whatever its name there). The calls
change with it: `f(a)`, `x.f(a)` (whose receiver is `self`), `T::f(x,
a)`, calls in generic instances, calls through a bound.

```
$ tachyonc refactor signature area --add 'scale: i64 = 1'
added parameter scale: i64 to crate::geom::area, 2 calls→2 files→+2 -2 lines
```

- `--add 'x: T = VALUE'`: the parameter, at the end or before parameter
  N (`--at N`, counting from 0, `self` included: a method's first
  position is 1); each call gets VALUE (as written; checked in each
  caller). Without `= VALUE` only when there is no call.
- `--remove x`: refused while x is used in a body (`refactor.used`); each
  call loses the argument (`warning refactor.effects` when it called a
  function: that call is gone).
- `--rename-param a b`: the parameter and its uses in the body; refused
  when b is a name there already or a is shadowed (`refactor.clash`).
  Calls are unchanged.
- `--reorder b,a,c`: every parameter once (`self` stays first); each
  call's arguments follow (`warning refactor.effects` when two that call
  functions change order: evaluation is left to right).
- `--type x T`: the parameter's type; the check says which calls no
  longer fit (the edit is refused with their errors). `--default EXPR`
  (0.13) makes each call's argument EXPR, `$x` in it standing for the
  argument it had (in parentheses unless a name, a number or a path):
  `--type k i64 --default '$k as i64'` turns `scale(b, n + 1)` into
  `scale(b, (n + 1) as i64)`; `--type full bool --default false`.

Refused for any change of the type (all but `--rename-param`): a
function used as a value (`let f = twice;`, `apply(twice, x)`:
`refactor.fn-value`, its first place, `try:` its refs), a function an
operator calls (`refactor.operator`: `a + b` calls `Add::add`), a C
function or an `extern "C" fn` (`refactor.extern`).

## refactor field

The struct, its literals (in generic instances too) and its field
accesses.

- `--add 'g: T = VALUE'`: the field after the last; each literal gets `g:
  VALUE`. `pub` is written in the text when wanted (`'pub g: i64 = 0'`).
- `--remove g`: refused while the field is read or written anywhere
  (`refactor.used`, the number of references and the first, `try:`
  `query refs Struct.g`); else from the struct and every literal.
- `--rename g h`: every reference (definition, literals, accesses).
- `--type g T`: the field's type; the check says what no longer fits.

A `#[repr(C)]` struct's layout changes with --add, --remove and --type:
`warning refactor.layout` (C code sharing it must change too).

## refactor variant

- `--add 'X(T, ...)'`: the variant after the last. A `match` on the enum
  without a catch-all arm (`_`, a binding, an or with one) would no
  longer be exhaustive: with `--arm EXPR` each gets the arm `E::X(_, ...)
  => EXPR` after its last arm (the enum written as that match's arms
  write it; else by its full path); without, the command is refused and
  lists them, `FILE:LINE:COL→FUNCTION` on stdout, then
  `error refactor.non-exhaustive` and `try: query show FILE:LINE`.
- `--arm-in SITE EXPR` (0.14, repeatable): the arm of the matches SITE
  names, for matches of different result types: SITE is the function
  (any item) the match is in, as `query` takes a NAME, or `FILE:LINE` of
  a line of the match. The first `--arm-in` that names a match gives its
  arm; `--arm`, the others'. The refusal's last `try:` line is the
  command with an `--arm-in SITE 'EXPR'` for each match left (SITE the
  function the listing names, `FILE:LINE` when it has two), to fill in:

```
$ tachyonc refactor variant Shape --add 'Ring(i64)'
shapes.tach:9:5→shapes::area
shapes.tach:16:5→shapes::round
error refactor.non-exhaustive: 2 matches on crate::shapes::Shape would not cover Ring; nothing written
try: tachyonc query show shapes.tach:9
try: tachyonc query show shapes.tach:16
try: tachyonc refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm 'EXPR' --dry-run
try: tachyonc refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm-in shapes::area 'EXPR' --arm-in shapes::round 'EXPR' --dry-run
$ tachyonc refactor variant Shape --add 'Ring(i64)' --arm-in area 0 --arm-in round false
```

  A SITE that names no match needing an arm: `error refactor.no-site`,
  and the matches listed.
- `--remove V`: refused while V is constructed (`refactor.constructed`),
  matched inside another pattern (`refactor.nested`) or by an `if let` /
  `while let` (`refactor.if-let`); else the arms matching V alone go, an
  or loses its alternative, a `use` loses the name, and the enum the
  variant. `warning refactor.discriminant` when the enum is cast to an
  integer and later variants change their numbers.
- `--rename V W`: every reference (definition, constructions, patterns,
  imports).

## rewrite

```
tachyonc rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: *IntVec'
rewrote 37 sites in 9 files→9 files→+37 -37 lines
```

A typed structural search and replace over the program's expressions and
statements. PATTERN and REPLACEMENT are tachyon (a statement when the
pattern ends with `;` or starts with `let`, else an expression), parsed
by the compiler's parser, with holes:

| hole | matches |
|---|---|
| `$x` | any expression; in a type's place, any type (`$a as $T`); in a `let`'s binding place, any pattern (`let $v = ...;`) |
| `$x...` | any number of elements of a call's arguments, a tuple, an array (one per list): `f($first, $rest...)`; (0.15) of a block's statements, its tail included: `{ let $x = $e; $s... }` |
| `$x` written twice | the same code both times (the same tokens, spacing and comments aside) |
| `--where '$x: T'` | only where the checker typed $x's expression `T` (as messages write types: `*IntVec`, `[u8]`, `Vec<i64>`; spaces aside); several: `--where '$x: T, $y: U'` or `--where` again |

The pattern is matched against every node as parsed (`--in FILE|MODULE`:
the sites in that file or module), node by node: same kind, same
operator, same names, and a part without holes matches code with the
same tokens; parentheses do not count (`$a + $b` matches `(x + y)`). A
site's replacement is REPLACEMENT with each hole replaced by the exact
text it matched; a hole's text is parenthesized when the operators
around it in REPLACEMENT need it, and the whole replacement when the
operators around the site need it (`double($x)` to `$x + $x` makes `3 *
double(n)` `3 * (n + n)`). `$x...` that matched nothing goes with a comma
next to it. Sites inside a rewritten site are left for another run
(`note rewrite.nested`).

(0.14) A pattern matches inside closures' bodies too; a closure in the
pattern matches one with the same parameters, result type and `move` as
written, its body matched (`apply(|y| $b, $x)`); holes do not stand for
a closure's parameters. A closure put where an operand or a callee is
gets parentheses, since its body takes all that follows (`apply($f,
$x)` to `$f($x)` makes `(|y| y + 1)(2)`).

(0.15) `$s...` among a block's statements (as the tail, or as a
statement `$s...;`) matches the statements there, with the comments
between them; in the replacement they keep their lines and indentation
when the site's block was written on several lines (each statement of
the replacement's block, and its `}`, on a line of its own; a block nested
deeper in the replacement than in the site keeps the site's indentation).
A pattern also matches `for` loops, `match` arms (patterns with holes:
`Option::Some($y)`), `e?`, named arguments and f-string holes; --where's
types are checked once the whole pattern matched.

```
tachyonc rewrite 'for $i in 0..$v.count { let $x = $v.data[$i]; $s... }' \
    'for $x in $v.items() { $s... }' --where '$v: IntVec'
```

A site where the replacement drops a hole bound to a name (`for $i`,
`let $x =`) that the code it keeps still uses is left as it is: `note
rewrite.dropped` counts them and names the first, `try: query show` it.
The imports the replacement's names need are added (`note edit.imports`).

Nothing matches: `note rewrite.none`, exit 0; when sites matched but for
--where, `note rewrite.types` gives the first one's type and place, and
`try:` the command with that type; sites whose type the checker never
computed (a generic function never instantiated) are left,
`note rewrite.untyped`.

## refactor extract-function (0.13)

`refactor extract-function FN --lines A-B --to NEW`: the statements of
lines A to B of FN's file (whole statements of one block of FN, the
comments among them too) become a new function NEW, right after FN,
called where they were:

```
$ tachyonc refactor extract-function mean_to --lines 40-43 --to add_all --show
extracted lines 40-43 of crate::calc::mean_to into add_all(i, n, acc) -> i64→calc.tach→+6 -1 lines
// calc.tach:40-44
40→    i = add_all(i, n, &acc);
...
44→fn add_all(mut i: i64, n: i64, acc: *Acc) -> i64 {
```

- **Parameters**: the locals of FN the lines use and do not declare, in
  the order of their first use, typed as declared (`x: T` as written,
  else as the checker has it): by value; `mut` and given back when the
  lines assign them (or use their value and take their address); by
  pointer (`acc: *Acc`, called with `&acc`, the lines' `&acc` then
  `acc`) when they only take their address or write their fields
  (`acc.add(i)`, `p.x = 0`; an array indexed is passed by value).
- **Result**: the locals the lines declare and FN uses after them (`let
  x = NEW(...);`, several: `let (a, b) = NEW(...);`, `mut` where they
  change after), or the one local declared before them that they assign
  (`x = NEW(...);`), or the value they end the block with.
- In unsafe code (an `unsafe { }` around the lines, an `unsafe fn`),
  NEW's body is an `unsafe { }` block; in a method whose lines use
  `self`, NEW is a method of the same impl (`self.NEW(...)`); else a
  function after FN (after its impl block, for a method).
- Refused, nothing written: lines that cut a statement or are not in
  FN's body (`refactor.range`, `try:` the whole statements' lines);
  control flow leaving them, a `return`, a `break` or `continue` of a
  loop around them, a `defer` (`refactor.escapes`, `try:` the lines
  before it); several results of which one was declared before them, or
  results with the block's value (`refactor.results`); `self` in a trait
  impl's function (`refactor.self`); a generic FN (`refactor.generic`);
  NEW taken (`refactor.collision`).
- Closures (0.14): the lines may hold closures, or be lines of a
  closure's block body. A local a closure captures is the local itself
  (a parameter of NEW when declared before the lines; a `move`
  closure's assignments change its copy, not the local); a closure's
  parameters and the locals of its body are its own; its `return` and
  `defer` stay in it. A parameter or result whose type holds a closure
  (a closure made before the lines and used in them, one used after
  them, `Map<I, F>`) has no name to write: refused (`refactor.closure`,
  `try:` the lines from the closure's `let`).

## refactor inline (0.13)

`refactor inline FN`: every call of FN replaced by its body, then FN,
when nothing else uses it, deleted with the names of the `use` lines
importing it (`--keep` keeps it); `--at FILE:LINE`: the call on that
line only, FN kept.

```
$ tachyonc refactor inline quad
inlined crate::calc::quad at 1 call, deleted it→2 files→+10 -12 lines
```

- An argument is put in for its parameter when it is a name (not one
  the body declares) or a literal, or when the body is one expression
  using the parameter once and the argument is the only one that is
  neither; else it is bound first, in order: `let x = ARG;` (`let mut`
  when the body changes the parameter; renamed `x_2` when an argument
  names `x`). A method's receiver is `self`: the receiver itself when
  the method takes its address (`v.m()`) and its body uses `self` only
  as `self.f` or `self.m(...)`.
- The body becomes the call's value: its expression (in parentheses
  when it binds looser than the call's place: `twice(1) * k` is `(1 +
  1) * k`), else a block (`{ let x = ARG; ...; tail }`); a call that is
  a statement of its own (`f(x);`) of a body with no locals and nothing
  bound gets the body's statements in its place.
- Into another module: the items the body names that are private
  there are made `pub`, the imports of FN's module it needs are copied
  (`use crate::ir::Op::Const;`), then rounds of `fix --only imports,pub`
  and the imports tidied.
- Calls inside closures are calls (0.14): inlined, renamed, given a new
  argument by `refactor signature`, like any other; a `return` inside a
  closure of the body is the closure's.
- Refused: a body with a `return` (`refactor.escapes`), a call of FN in
  its body (`refactor.recursive`), a generic or bodiless FN
  (`refactor.generic`), an `extern "C"` one (`refactor.extern`), a name
  of the body hidden by a local where it is called (`refactor.clash`),
  a borrowed receiver the body uses as `self` otherwise
  (`refactor.receiver`), no call (`refactor.no-call`), several on the
  line of `--at` (`refactor.ambiguous`). A call in another call's
  arguments is left (`note refactor.nested`: run it again).

On a copy of the compiler's source (0.13), 66 extractions of random
lines (the refusals' `try:` commands run as they are) and 70 inlines of
small functions: none added an error, the copy built, and `same-output`
against the compiler was identical (4668 compilations).

## refactor --script

```
# steps.txt: the edit, then the calls it made
refactor field Point --rename y height
refactor signature area --add 'scale: i64 = 1'   # the calls get 1
rewrite 'area($p, 1)' 'area($p, 2)'
edit replace twice < twice.tach
```

```
$ tachyonc refactor --script steps.txt
renamed field y to height of crate::geom::Point, 6 uses→2 files→+6 -6 lines
added parameter scale: i64 to crate::geom::area, 2 calls→2 files→+2 -2 lines
rewrote 2 sites in 1 file→main.tach→+1 -1 lines
replaced crate::geom::twice→geom.tach→+1 -1 lines
script steps.txt: 4 commands→2 files→+9 -9 lines
```

A file of `refactor`, `rewrite`, `edit` and `fix` commands, one per line
as typed after `tachyonc` (words as sh splits them: `'...'`, `"..."`;
`#` starts a comment; `< PATH` gives the command its stdin, and 0.14,
`<<WORD` the lines after it up to a line `WORD`, as sh's here-document:
`<<'WORD'` and `<< WORD` too, the text taken as it is), run in turn
in one invocation, each on the program the ones before left, and checked
once, at the end: all or nothing. Each command runs in a copy of the
process (fork) that reads the copies the commands before it wrote
(`FILE.tachyon-edit~`, as --overlay) and writes its own, unchecked
(edit.tach's STEP_REPORT), printing its summary line. A command that
fails ends the script: `error refactor.script: FILE:LINE: the command
failed (exit N): ...; nothing written`. After the last, the copies are
one edit: checked, written, journaled (one `undo` takes the whole script
back), or with --dry-run, the diff; then the total line. The script's
options (--dry-run, --no-check, --root, --target) are the script's; a
line may not give `--root` or `--target`.

A command's stdin can be in the script (0.14), so that a script of
patches of several lines, or of new items, is one file:

```
# pairs of several lines, as edit patch reads them from stdin
edit patch area <<END
<<<<<<< OLD
    p.x * p.height
=======
    // (the rectangle's)
    p.x * p.height
>>>>>>> NEW
END
edit insert --after area <<'EOF'
pub fn half_area(p: Point) -> i64 {
    area(p) / 2
}
EOF
```

The text goes to a file next to the root (`ROOT.tachyon-stdin~`) while
the command runs. A `<<WORD` without its line `WORD`: `error
refactor.script: FILE:LINE: no line 'WORD' ends the text of <<WORD`.
`--pairs FILE` works in a script as on the command line.

The commands come from one table, `compiler/src/tools/commands.tach`:
`run_tool` (the commands a script may run: `edit`, `fix`, `rewrite`,
`refactor`) and `run_refactor` (a `refactor` subcommand, one row each). A
command added there works from the command line and in scripts, as long
as it changes the program through the edit engine (`edit_replace`,
`edit_new_file`, then `apply_edit`, or `prepare_edit` and
`finish_edit`).

## Diagnostics

| code | severity | exit | when | try |
|---|---|---|---|---|
| `refactor.usage`, `rewrite.usage` | error | 2 | a usage error | an example |
| `refactor.kind` | error | 1 | NAME is no function / struct / enum | `query def` |
| `refactor.no-param`, `refactor.no-member` | error | 1 | no such parameter, field or variant (the ones there are listed) | `query def`, `query show` |
| `refactor.clash` | error | 1 | the new name is taken | `query show` |
| `refactor.no-default` | error | 2 | --add without a value, and calls or literals need one | the command with `= 0` |
| `refactor.used` | error | 1 | a parameter or field to remove is used | `query show FILE:LINE`, `query refs` |
| `refactor.fn-value` | error | 1 | the function is used as a value; its type would change | `query refs` |
| `refactor.operator`, `refactor.extern`, `refactor.trait` | error | 1 | an operator calls it; C's; an impl's parameters differ | |
| `refactor.non-exhaustive` | error | 1 | --add without --arm, and matches need an arm (listed) | `query show FILE:LINE`, the command with `--arm` or an `--arm-in` per match |
| `refactor.no-site` | error | 1 | an `--arm-in` SITE holds no match that needs an arm (0.14; the matches listed) | |
| `refactor.constructed`, `refactor.nested`, `refactor.if-let` | error | 1 | a variant to remove is constructed, matched inside a pattern, by an if let | `query refs`, `query show` |
| `refactor.effects` | warning | 0 | an argument that calls a function is removed or moved | |
| `refactor.layout` | warning | 0 | a `#[repr(C)]` struct's layout changes | |
| `refactor.discriminant` | warning | 0 | a removed variant renumbers the ones after it, and the enum is cast | |
| `refactor.unchecked` | warning | 0 | calls in code the checker did not see are not changed | |
| `refactor.range` | error | 1 | extract-function: the lines cut a statement, or are not in FN's body | the whole statements' lines |
| `refactor.escapes` | error | 1 | extract-function: a return, break, continue or defer leaves the lines; inline: FN returns early | the lines before it; `query show FILE:LINE` |
| `refactor.results` | error | 1 | extract-function: results NEW cannot give back | `query show FILE:LINE` |
| `refactor.closure` | error | 1 | extract-function (0.14): a parameter or result of NEW would be a closure, whose type has no name | the lines from the closure's `let`; `query show FILE:LINE` |
| `refactor.self`, `refactor.receiver` | error | 1 | self in a trait impl's function; a borrowed receiver used as `self` | |
| `refactor.generic`, `refactor.recursive` | error | 1 | a generic or bodiless function; inline: FN calls itself | |
| `refactor.no-call`, `refactor.ambiguous` | error | 1 | inline: no call (on the line of `--at`), several there | `query refs` |
| `refactor.nested` | note | 0 | inline: calls left in the arguments of others | |
| `refactor.script` | error | 1, 2 | a line is no command, a command failed: nothing written | |
| `rewrite.pattern`, `rewrite.unbound` | error | 2 | the pattern or replacement does not parse, a hole alone, `$x...` outside a list, a hole of the replacement not in the pattern | |
| `rewrite.bad-in` | error | 1 | `--in` names no file or module | |
| `rewrite.none` | note | 0 | nothing matches | |
| `rewrite.types` | note | 0 | sites match but for --where | the command with the type found |
| `rewrite.nested`, `rewrite.untyped` | note | 0 | sites left inside rewritten ones, in unchecked code | |

## Known limits

- A pattern's names match by name (`grow` matches any function or
  variable named `grow`); holes do not stand for names of functions,
  fields or methods, nor for patterns other than a `let`'s.
- Parenthesizing knows the operators' binding powers; a replacement
  placed where a struct literal is not allowed (an `if`'s condition) is
  not parenthesized for it: the check refuses it.
- `--remove` of a variant matched inside a nested pattern, or by an
  `if let`, is refused rather than rewritten.
- A struct field added by `refactor field --add` is not `pub` unless the
  text says so.
- `refactor variant --add --arm` (and `--arm-in`) binds no fields (`X(_,
  _)`); an arm using them is written by hand (`edit`).
