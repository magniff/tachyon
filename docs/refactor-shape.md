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
volec refactor signature FN --add 'x: T [= VALUE]' [--at N] [--fill-calls] | --remove x
                               | --rename-param a b | --reorder b,a,c | --type x T [--default EXPR]
volec refactor field STRUCT --add 'g: T = VALUE' | --remove g | --rename g h | --type g T
volec refactor variant ENUM --add 'X(T, ...)'|'X { a: T, ... }' [--arm EXPR] [--arm-in SITE EXPR]... | --remove V | --rename V W
volec rewrite 'PATTERN' 'REPLACEMENT' [--where '$x: T']... [--subst 'P' 'R']... [--in FILE|MODULE|ITEM]... [--list]
volec rewrite 'PATTERN' --list [--where ...] [--in FILE|MODULE|ITEM]   (0.16)
volec refactor extract-function FN --lines A-B --to NEW          (0.13)
volec refactor inline FN [--at FILE:LINE] [--keep]                 (0.13)
volec refactor --script FILE
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
$ volec refactor signature area --add 'scale: i64 = 1'
added parameter scale: i64 = 1 to crate::geom::area, 2 calls→geom.vl→+1 -1 lines
$ volec refactor signature area --add 'scale: i64 = 1' --fill-calls
added parameter scale: i64 to crate::geom::area, 2 calls→2 files→+2 -2 lines
```

- `--add 'x: T = VALUE'`: the parameter, at the end or before parameter
  N (`--at N`, counting from 0, `self` included: a method's first
  position is 1). (0.15) VALUE is the parameter's default, and the calls
  are left as they are. The calls get VALUE instead (as written; checked
  in each caller), as 0.14 did, with `--fill-calls`, for a trait's
  function (it has no defaults) and before a parameter without a default
  (defaults are on trailing parameters only): `note refactor.fill-calls`
  says why (not for --fill-calls). A call that leaves a parameter before
  x to its default gets `x: VALUE`, among its labelled arguments in
  order. Without `= VALUE` only when there is no call.
- `--remove x`: refused while x is used in a body (`refactor.used`); each
  call loses the argument, given by position or (0.15) by its label;
  a call that leaves x to its default is unchanged (`warning
  refactor.effects` when the argument called a function: that call is
  gone).
- `--rename-param a b`: the parameter and its uses in the body; refused
  when b is a name there already or a is shadowed (`refactor.clash`).
  (0.15) A label `a: value` in a call becomes `b: value`; a field
  shorthand `S { a }` in the body becomes `S { a: b }`. Calls are
  otherwise unchanged.
- `--reorder b,a,c`: every parameter once (`self` stays first); each
  call's arguments follow (`warning refactor.effects` when two that call
  functions change order: evaluation is left to right). (0.15) A call
  with a labelled argument, or one that leaves a parameter to its
  default, is written again in the new order: by position up to the
  first parameter it leaves out or labels, by label from there
  (`area(2, 3, depth: 4)` with `--reorder w,depth,h` is `area(2, depth:
  4, h: 3)`); its layout and comments are not kept. A default before a
  parameter without one is refused by the check.
- `--type x T`: the parameter's type; the check says which calls no
  longer fit (the edit is refused with their errors). `--default EXPR`
  (0.13) makes each call's argument EXPR, `$x` in it standing for the
  argument it had (in parentheses unless a name, a number or a path):
  `--type k i64 --default '$k as i64'` turns `scale(b, n + 1)` into
  `scale(b, (n + 1) as i64)`; `--type full bool --default false`. (0.15)
  A labelled argument's value is changed, a call that leaves x to its
  default is not (nor is the default).

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
- `--rename g h`: every reference (definition, literals, accesses); a
  field shorthand (0.15) `S { g }` becomes `S { h: g }`.
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
  `error refactor.non-exhaustive` and `try: query show FILE:LINE`. A
  struct-like variant (0.17), `--add 'X { a: T }'`, gets the arm
  `E::X { .. } => EXPR`.
- `--arm-in SITE EXPR` (0.14, repeatable): the arm of the matches SITE
  names, for matches of different result types: SITE is the function
  (any item) the match is in, as `query` takes a NAME, or `FILE:LINE` of
  a line of the match. The first `--arm-in` that names a match gives its
  arm; `--arm`, the others'. The refusal's last `try:` line is the
  command with an `--arm-in SITE 'EXPR'` for each match left (SITE the
  function the listing names, `FILE:LINE` when it has two), to fill in:

```
$ volec refactor variant Shape --add 'Ring(i64)'
shapes.vl:9:5→shapes::area
shapes.vl:16:5→shapes::round
error refactor.non-exhaustive: 2 matches on crate::shapes::Shape would not cover Ring; nothing written
try: volec query show shapes.vl:9
try: volec query show shapes.vl:16
try: volec refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm 'EXPR' --dry-run
try: volec refactor variant crate::shapes::Shape --add 'Ring(i64)' --arm-in shapes::area 'EXPR' --arm-in shapes::round 'EXPR' --dry-run
$ volec refactor variant Shape --add 'Ring(i64)' --arm-in area 0 --arm-in round false
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
volec rewrite 'grow($v, $n)' '$v.reserve($n)' --where '$v: &mut IntVec'
rewrote 37 sites in 9 files→9 files→+37 -37 lines
```

A typed structural search and replace over the program's expressions and
statements. PATTERN and REPLACEMENT are vole (a statement when the
pattern ends with `;` or starts with `let`, else an expression), parsed
by the compiler's parser, with holes:

| hole | matches |
|---|---|
| `$x` | any expression; in a type's place, any type (`$a as $T`); in a `let`'s binding place, any pattern (`let $v = ...;`) |
| `$x...` | any number of elements of a call's arguments, a tuple, an array (one per list): `f($first, $rest...)`; (0.15) of a block's statements, its tail included: `{ let $x = $e; $s... }` |
| `$x` written twice | the same code both times (the same tokens, spacing and comments aside) |
| `--where '$x: T'` | only where the checker typed $x's expression `T` (as messages write types: `&mut IntVec`, `[u8]`, `Vec<i64>`; spaces aside); several: `--where '$x: T, $y: U'` or `--where` again |
| `--where '$x: name'`, `--where '$x: name ~ RE'`, `$x~/RE/` | (0.16) only a name: an identifier or a path (`V`, `crate::m::V`, the name a `for` or `let` binds), not another expression (`IRFUNCS[f].blocks`); with RE, a name whose text RE matches (`^ $ . * + ? [a-z] [^...] \d \w`, anywhere unless anchored: `$v~/^v_/`) |

The pattern is matched against every node as parsed (`--in FILE|MODULE`:
the sites in that file or module, its children too; 0.17: `--in ITEM`, a
function, a type, a const...: the sites in its text; `--in` repeated: the
sites in any of them), node by node: same kind, same
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
volec rewrite 'for $i in 0..$v.count { let $x = $v.data[$i]; $s... }' \
    'for $x in $v.items() { $s... }' --where '$v: IntVec'
```

A site where the replacement drops a hole bound to a name (`for $i`,
`let $x =`) that the code it keeps still uses is left as it is: `note
rewrite.dropped` counts them and names the first, `try: query show` it.
The imports the replacement's names need are added (`note edit.imports`).
(0.17) The names of `use` lines that the rewrite leaves unused (the last
calls of a helper in a file rewritten away) are removed in the same edit
(`note rewrite.imports`).

(0.17) A rewrite refused because it breaks the program (`edit.breaks`,
nothing written) whose holes have several types at the sites gets a
`note rewrite.where` naming each type and its number of sites, and a
`try:` per type with its `--where` (three at most), before the
`--no-check` one: the replacement may fit only some of them
(`$v.is_empty()` for a `Vec`, not a `*Buf`).

(0.16) **New names, substitutions.** A hole of the replacement that the
pattern lacks is a new name, which the replacement must bind (`for $x
in`, `let $x =`; else `error rewrite.unbound`): at each site it is its
own name (`$x` is `x`), or `x2`, `x3`... when the item holding the site
already has an `x`. `--subst 'P' 'R'` (repeatable, expressions) replaces
each match of P inside the code a hole of the site matched and the
replacement keeps (the statements of a `$s...` above all) by R: P's holes
that the pattern has match only the code they matched at the site
(`$v.data[$i]` is the site's `$v` and `$i`), its other holes match
anything (`--where` holds for them too), and R may use either and the
new names. A site where a dropped binding is still used after the
substitutions is left (`note rewrite.dropped`):

```
volec rewrite 'for $i in 0..$v.count { $s... }' 'for $x in $v.items() { $s... }' \
    --subst '$v.data[$i]' '$x' --where '$v: name'
```

turns `for i in 0..BLOCKS.count { f(BLOCKS.data[i]); }` into `for x in
BLOCKS.items() { f(x); }`, and leaves a loop that uses `i` otherwise.

(0.16) **Layout.** A block of the replacement written on one line takes
the site's lines when the site had them (a statement a line, the `}` on
its own, indented from the site's line; with a `$s...`, as that block's
statements were); a replacement written on several lines keeps its
lines, each indented from the site's line as it was from the
replacement's first.

(0.16) **`--list`** prints a line per site instead of rewriting:
`FILE:LINE:COL`, then each hole of the pattern and what it matched,
TAB-separated (spaces and lines made one space, cut at 60 bytes). With a
REPLACEMENT, the sites that would be rewritten (not those left by
`rewrite.dropped`); without one, every site PATTERN matches:

```
$ volec rewrite 'for $i in 0..$v.count { $s... }' --list
loops.vl:8:5→$i=i→$v=w→$s...=t += w.data[i] * 2; if w.data[i] > 2 { t += w.data[i]; }
loops.vl:18:5→$i=j→$v=w→$s...=t -= w.data[j];
```

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
$ volec refactor extract-function mean_to --lines 40-43 --to add_all --show
extracted lines 40-43 of crate::calc::mean_to into add_all(i, n, acc) -> i64→calc.vl→+6 -1 lines
// calc.vl:40-44
40→    i = add_all(i, n, &mut acc);
...
44→fn add_all(mut i: i64, n: i64, acc: &mut Acc) -> i64 {
```

- **Parameters**: the locals of FN the lines use and do not declare, in
  the order of their first use, typed as declared (`x: T` as written,
  else as the checker has it): by value; `mut` and given back when the
  lines assign them (or use their value and take their address); by
  reference (`acc: &mut Acc`, called with `&mut acc`, 0.18.1; it was
  `acc: *Acc`; the lines' `&acc` then `acc`) when they only take their address or write their fields
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
- `?` (0.15): it may return from FN (None or Err), which NEW cannot do
  for its caller: lines holding one are refused (`refactor.escapes`),
  but a `?` inside a closure of the lines, which returns from the
  closure.

## refactor inline (0.13)

`refactor inline FN`: every call of FN replaced by its body, then FN,
when nothing else uses it, deleted with the names of the `use` lines
importing it (`--keep` keeps it); `--at FILE:LINE`: the call on that
line only, FN kept.

```
$ volec refactor inline quad
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
- Named and default arguments (0.15): each parameter's argument is the
  one given by position or by label; one left to its default gets the
  default as written in FN (checked where the call is). A parameter
  put in for a field shorthand `S { x }` writes `S { x: ARG }`.
- (0.17) A call in an f-string's hole gets the body on one line (`f"{if
  b == 0 { 0 } else { a / b }}"`), a body with a `//` comment its lines.
- Refused: a body with a `return` or (0.15) a `?` (`refactor.escapes`), a call of FN in
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
refactor signature area --add 'scale: i64 = 1' --fill-calls   # the calls get 1
rewrite 'area($p, 1)' 'area($p, 2)'
edit replace twice < twice.vl
```

```
$ volec refactor --script steps.txt
renamed field y to height of crate::geom::Point, 6 uses→2 files→+6 -6 lines
added parameter scale: i64 to crate::geom::area, 2 calls→2 files→+2 -2 lines
rewrote 2 sites in 1 file→main.vl→+1 -1 lines
replaced crate::geom::twice→geom.vl→+1 -1 lines
script steps.txt: 4 commands→2 files→+9 -9 lines
```

A file of `refactor`, `rewrite`, `edit` and `fix` commands, one per line
as typed after `volec` (words as sh splits them: `'...'`, `"..."`;
`#` starts a comment; `< PATH` gives the command its stdin, and 0.14,
`<<WORD` the lines after it up to a line `WORD`, as sh's here-document:
`<<'WORD'` and `<< WORD` too, the text taken as it is), run in turn
in one invocation, each on the program the ones before left, and checked
once, at the end: all or nothing. Each command runs in a copy of the
process (fork) that reads the copies the commands before it wrote
(`FILE.vole-edit~`, as --overlay) and writes its own, unchecked
(edit.vl's STEP_REPORT), printing its summary line. A command that
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

The text goes to a file next to the root (`ROOT.vole-stdin~`) while
the command runs. A `<<WORD` without its line `WORD`: `error
refactor.script: FILE:LINE: no line 'WORD' ends the text of <<WORD`.
`--pairs FILE` works in a script as on the command line.

The commands come from one table, `compiler/src/tools/commands.vl`:
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
| `refactor.escapes` | error | 1 | extract-function: a return, break, continue, defer or (0.15) `?` leaves the lines; inline: FN returns early or has a `?` | the lines before it; `query show FILE:LINE` |
| `refactor.fill-calls` | note | 0 | signature --add (0.15): the calls get VALUE, not a default (a trait's function, a later parameter without a default) | |
| `refactor.results` | error | 1 | extract-function: results NEW cannot give back | `query show FILE:LINE` |
| `refactor.closure` | error | 1 | extract-function (0.14): a parameter or result of NEW would be a closure, whose type has no name | the lines from the closure's `let`; `query show FILE:LINE` |
| `refactor.self`, `refactor.receiver` | error | 1 | self in a trait impl's function; a borrowed receiver used as `self` | |
| `refactor.generic`, `refactor.recursive` | error | 1 | a generic or bodiless function; inline: FN calls itself | |
| `refactor.no-call`, `refactor.ambiguous` | error | 1 | inline: no call (on the line of `--at`), several there | `query refs` |
| `refactor.nested` | note | 0 | inline: calls left in the arguments of others | |
| `refactor.script` | error | 1, 2 | a line is no command, a command failed: nothing written | |
| `rewrite.pattern`, `rewrite.unbound` | error | 2 | the pattern or replacement does not parse, a hole alone, `$x...` outside a list, a hole of the replacement not in the pattern and bound by it nowhere, a bad `~/RE/` | |
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
  _)`, `X { .. }`); an arm using them is written by hand (`edit`).
- `refactor field` takes a struct; a struct-like variant's fields (0.17)
  are changed with `edit` (the variant, its literals and patterns).
