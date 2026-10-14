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
                               | --rename-param a b | --reorder b,a,c | --type x T
tachyonc refactor field STRUCT --add 'g: T = VALUE' | --remove g | --rename g h | --type g T
tachyonc refactor variant ENUM --add 'X(T, ...)' [--arm EXPR] | --remove V | --rename V W
tachyonc rewrite 'PATTERN' 'REPLACEMENT' [--where '$x: T']... [--in FILE|MODULE]
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
  longer fit (the edit is refused with their errors).

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
| `$x...` | any number of elements of a call's arguments, a tuple, an array (one per list): `f($first, $rest...)` |
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

Nothing matches: `note rewrite.none`, exit 0; when sites matched but for
--where, `note rewrite.types` gives the first one's type and place, and
`try:` the command with that type; sites whose type the checker never
computed (a generic function never instantiated) are left,
`note rewrite.untyped`.

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
`#` starts a comment; `< PATH` gives the command its stdin), run in turn
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

The commands come from one table, `compiler/src/commands.tach`:
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
| `refactor.non-exhaustive` | error | 1 | --add without --arm, and matches need an arm (listed) | `query show FILE:LINE` |
| `refactor.constructed`, `refactor.nested`, `refactor.if-let` | error | 1 | a variant to remove is constructed, matched inside a pattern, by an if let | `query refs`, `query show` |
| `refactor.effects` | warning | 0 | an argument that calls a function is removed or moved | |
| `refactor.layout` | warning | 0 | a `#[repr(C)]` struct's layout changes | |
| `refactor.discriminant` | warning | 0 | a removed variant renumbers the ones after it, and the enum is cast | |
| `refactor.unchecked` | warning | 0 | calls in code the checker did not see are not changed | |
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
- `refactor variant --add --arm` binds no fields (`X(_, _)`); an arm
  using them is written by hand (`edit`).
