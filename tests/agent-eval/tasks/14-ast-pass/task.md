# An optimizing pass for a small language

The workspace holds a working interpreter for a small statement language
over 64-bit integers. It reads a whole program from stdin and either runs
it or prints its syntax tree. It is split into modules:

| file | what it holds |
|---|---|
| `main` | reading stdin, choosing the mode, printing the result |
| `lexer` | tokens; names are interned (a name token holds an index into a name table) |
| `ast` | the tree: `Expr` and `Stmt` enums stored in vectors, children referred to by index, lists of children as runs in one `lists` vector; and the dump |
| `parser` | recursive descent from tokens to the tree |
| `eval` | the tree-walking interpreter and its run-time errors |

Extend it in two ways:

1. Add a `while` statement.
2. Add an optimizing pass, constant folding and dead-branch elimination,
   that runs after parsing and before either mode. The dump prints the
   optimized tree; running gives exactly the output it gave before.

Everything below is the language as it must behave when you are done.
What exists already behaves as described; `while` and the pass are new.

## The language

The first line selects the mode: if it is exactly `#!dump` (a `\r` before
its line end allowed), the program prints its tree; otherwise it runs.
That first line is also a comment, so it is not part of the program.

Tokens: decimal integer literals (at most 9223372036854775807), names
(`[A-Za-z_][A-Za-z0-9_]*`), the keywords `let print if else while`, and
`+ - * / % ! < <= > >= == != && || = ( ) { } ; ,`. Spaces, tabs, `\r`
and newlines separate tokens; `#` starts a comment that runs to the end
of the line. Lines are numbered from 1 (the mode line is line 1).

```
program := stmt*
stmt    := 'let' NAME '=' expr ';'          declare a variable in the current block
         | NAME '=' expr ';'                assign the nearest visible variable
         | 'print' expr (',' expr)* ';'     print values, one space apart, then a newline
         | 'if' expr block ('else' (if-stmt | block))?
         | 'while' expr block               NEW
         | block                            a nested block
block   := '{' stmt* '}'
expr    := and ('||' and)*
and     := eq ('&&' eq)*
eq      := rel (('==' | '!=') rel)*
rel     := add (('<' | '<=' | '>' | '>=') add)*
add     := mul (('+' | '-') mul)*
mul     := unary (('*' | '/' | '%') unary)*
unary   := ('-' | '!') unary | primary
primary := NUMBER | NAME | '(' expr ')'
```

Binary operators are left-associative. Every block (`{ }` of an `if`,
`else`, `while` or a bare block) is a scope: its `let`s disappear when it
ends, and a `while` body is a fresh scope on every pass. A `let` of a name
that is already visible (even in the same block) makes a new variable that
hides the old one until its block ends. Assignment evaluates the right
side first, then changes the nearest visible variable of that name.

Values are 64-bit signed integers and arithmetic wraps around (two's
complement): `9223372036854775807 + 1` is `-9223372036854775808`, and
`-9223372036854775808 / -1` is `-9223372036854775808` with remainder 0.
Division truncates toward zero and `%` takes the sign of the left operand
(`-7 / 2` is `-3`, `-7 % 2` is `-1`, `7 % -2` is `1`). Comparisons, `!`,
`&&` and `||` give 1 or 0; any non-zero value is true. `&&` and `||`
short-circuit: the right side is evaluated only when the left does not
decide. `if` and `while` take the branch / run the body when the
condition is non-zero. Operands are evaluated left to right; all
expressions of a `print` are evaluated before anything is printed.

### Errors

- A character that starts no token, or a parse error: the program prints
  only `syntax error at line N` (N: the line of the offending character
  or token; at the end of input, the line of the last token) and nothing
  else, in both modes.
- Run-time errors stop the program; what it printed before stays, then
  one line:
  - `error at line N: undefined variable NAME`, N being the line of the
    name (in an expression, or the target of an assignment);
  - `error at line N: division by zero`, for `/` and `%`, N being the
    line of the operator.

The program always exits with status 0.

## The dump

`#!dump` prints `program`, then each top-level statement, one per line,
indented by two spaces per level (top-level statements are at level 1).
Expressions are printed on one line: a number in decimal (negative ones
with a leading `-`), a name, `(OP A)` for unary operators where OP is
`neg` for `-` and `not` for `!`, and `(OP A B)` for binary ones where OP
is the operator as written (`+`, `<=`, `&&`, ...). Parentheses of the
source are not kept.

| statement | printed as |
|---|---|
| `let x = E;` | `let x E` |
| `x = E;` | `set x E` |
| `print E1, E2;` | `print E1 E2` |
| `{ S... }` | `block`, then each S one level deeper |
| `while C { S... }` | `while C`, then each S one level deeper |
| `if C { S... }` | `if C`, then each S one level deeper |
| `if C { S... } else { T... }` | as above, then `else` at the level of `if`, then each T one level deeper |
| `if C { S... } else if ...` | as above, then `else` at the level of `if`, then the inner `if` statement one level deeper |

An empty body prints nothing under its header line.

## The optimizing pass

It runs on the whole tree after a successful parse, before the dump and
before running. It works bottom-up.

**Constant folding.** An expression is a *literal* when it is a number.
After folding its operands:

- a unary operator on a literal becomes the literal it evaluates to
  (`-(5)` is `-5`, `!0` is `1`, `-(-9223372036854775808)` wraps to
  itself);
- a binary operator on two literals becomes the literal it evaluates to,
  with the wrapping arithmetic above, except `/` and `%` whose right
  operand is `0`: they stay as they are, so that the error still happens
  when (and if) the program runs them;
- `&&` whose left operand is the literal `0` becomes `0`, and `||` whose
  left operand is a non-zero literal becomes `1`, whatever the right
  operand is (it would never be evaluated);
- nothing else changes: no algebra (`x * 0`, `x - x`, `x + 0` stay),
  no reassociation (`x + 1 + 2` is `(+ (+ x 1) 2)` and stays; `1 + 2 + x`
  becomes `(+ 3 x)`), no constant propagation through variables, and a
  literal on the right does not decide `&&`/`||` (`x && 0` stays).

Folding applies to every expression: `let`, assignment, `print`, and the
conditions of `if` and `while`.

**Dead branches.** After its condition is folded:

- an `if` whose condition is a non-zero literal becomes a block holding
  its then-statements (`block` in the dump);
- an `if` whose condition is `0` is replaced by its else part: an `else
  { }` becomes a block statement, an `else if` becomes that inner `if`
  (optimized in turn, so it may itself become a block or disappear), and
  with no else part the statement is removed;
- in an `if` that stays, an `else if` part is optimized the same way: it
  may stay an `if`, become a block (then the dump shows its statements
  directly under `else`), or disappear (then the `if` has no else part);
- a `while` whose condition is `0` is removed; any other `while` stays;
- blocks stay blocks, even when empty; nothing else is removed.

Running the optimized tree gives exactly the output of running the
original: same lines, same errors, same line numbers.

## Example

Input:

```
#!dump
let x = 2 * (3 + 4);
let y = x + 1 + 2;
print -5, !0, x / 0, 0 && y / 0, 1 || q, x && 0;
if 1 < 2 { print 1; } else { print 2; }
if 0 { print 3; } else if x { print 4; } else if 0 { print 5; }
while 0 { print 8; }
while x > 0 { x = x - 1; }
```

Output:

```
program
  let x 14
  let y (+ (+ x 1) 2)
  print -5 1 (/ x 0) 0 1 (&& x 0)
  block
    print 1
  if x
    print 4
  while (> x 0)
    set x (- x 1)
```

The same program with `#!run` as its first line prints
`error at line 4: division by zero` (the `x / 0` in the `print`).

Another, run:

```
#!run
let a = 0;
let b = 1;
let i = 0;
while i < 10 {
    let t = a + b;
    a = b;
    b = t;
    i = i + 1;
}
print a, b;
if 0 { print missing; }
print i / (i - 10);
```

Output:

```
55 89
error at line 13: division by zero
```

## What the hidden tests cover

Both modes; the dump of every statement form, nested `else if` chains and
empty bodies; folding of every operator, nested folds, wrapping at the
64-bit limits, negative division and remainder, division by a literal
zero (not folded), the `&&`/`||` rules, and expressions that must not
fold; dead branches at every position of an `else if` chain, inside loops
and blocks; dead branches and short-circuited operands holding run-time
errors that must not happen; `while` loops (nested, with `let` in the
body, with a condition that is never true, `while 1` stopped by a
run-time error); run-time errors with their line numbers (an operator on
a different line from its operands); syntax errors (including one in a
`while`) in both modes; `\r\n` line ends and comments; a program running
about ten million loop passes; and a generated program of about 23,000
lines, dumped and run.
