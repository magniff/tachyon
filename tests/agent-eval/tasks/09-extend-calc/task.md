# Extend the calculator

The workspace holds a line calculator over 64-bit signed integers, in
four files: `lexer` (splits a line into tokens), `parser` (recursive
descent; builds a tree whose nodes live in one vector and refer to each
other by index), `eval` (computes a tree's value) and `main` (reads
stdin line by line and prints one result per line). It builds and works.
Today it understands this grammar:

```
expr    := term (('+' | '-') term)*
term    := primary (('*' | '/') primary)*
primary := NUMBER | '(' expr ')'
```

**Extend it** with unary minus, the remainder operator `%`, comparison
operators, and variables set by `let` lines, exactly as specified below.
Keep the existing design (lexer, parser, tree, evaluator); extend it
rather than replace it. The hidden tests check the whole behaviour below,
old and new.

## The language after the change

Each line of input is handled on its own, in order. The grammar, from
the loosest-binding level to the tightest:

```
line       := 'let' NAME '=' expr  |  expr
expr       := relational (('==' | '!=') relational)*
relational := additive (('<' | '<=' | '>' | '>=') additive)*
additive   := term (('+' | '-') term)*
term       := unary (('*' | '/' | '%') unary)*
unary      := '-' unary  |  primary
primary    := NUMBER  |  NAME  |  '(' expr ')'
```

- All binary operators are left-associative: `3 > 2 > 1` is
  `(3 > 2) > 1`, which is `1 > 1`, which is `0`.
- A comparison (`< <= > >= == !=`) is 1 when it holds and 0 otherwise.
  `==` and `!=` bind more loosely than the other four, so
  `1 < 2 == 3 > 2` is `(1 < 2) == (3 > 2)`, which is 1.
- Unary minus binds tighter than every binary operator: `-2 + 3` is 1;
  `2--3` is 5; `--3` is 3.
- `/` truncates toward zero; `%` is the remainder of that division, with
  the sign of the left operand (`-7 % 3` is -1, `7 % -3` is 1).
- NUMBER is one or more decimal digits. NAME is a letter (`a`-`z`,
  `A`-`Z`) or `_`, followed by letters, digits and `_`; names are
  case-sensitive. `let` is a keyword, not a NAME (but `letter` is a
  NAME).
- Spaces, tabs and `\r` between tokens are ignored; `#` starts a comment
  that runs to the end of the line (as today).
- No test overflows 64 bits, in a literal or in any intermediate value.

## Output

One line per input line, except that a line with no tokens (empty,
whitespace only, or only a comment) prints nothing:

- an `expr` line: its value, in decimal (`-5`);
- a `let NAME = expr` line: `NAME = VALUE`; NAME then holds VALUE for
  the following lines (setting it again replaces the value);
- a line that does not match the grammar (including a character that
  starts no token, like `$` or a lone `!`): `error: syntax`;
- a division or remainder by zero: `error: division by zero`;
- a NAME that has not been set by an earlier successful `let`:
  `error: unknown variable NAME`.

A line that does not parse is a syntax error even if it would also
divide by zero. Otherwise evaluation goes left operand before right
operand and stops at the first error, which is the one printed; both
operands of every operator are evaluated (there is no short-circuit). A
`let` whose expression fails prints the error and sets nothing (the
variable keeps its previous value, or stays unset).

## Example

Input:

```
let price = 250
let qty = 4
price * qty - -50
-price % 7
qty >= 4 == 1
let total = price * qty / (qty - 4)
total + 1
1 + 2 * 3 < 10
let = 4
```

Output:

```
price = 250
qty = 4
1050
-5
1
error: division by zero
error: unknown variable total
1
error: syntax
```

## Edge cases the tests cover

- chains of unary minus, with and without spaces, before numbers, names
  and parentheses; `-0`;
- `%` with negative operands and by zero; mixed `* / %` chains;
- chained and mixed comparisons, comparisons inside arithmetic
  (`1 + (2 < 3) * 10`);
- reassignment, `let x = x + 1`, names with digits, `_` and capitals,
  a failed `let` keeping the old value;
- malformed lines: `let`, `let x`, `let x =`, `let 5 = 3`, `x = 3`,
  `let let = 1`, `2x`, `1 2`, `1 <> 2`, `=<`, unbalanced parentheses;
- which error wins when there are several on one line;
- comments, blank lines, tabs and `\r\n` line endings;
- values near the 64-bit limits (without overflow);
- deep nesting (hundreds of parentheses or minus signs) and a large
  input of 20000 lines.
