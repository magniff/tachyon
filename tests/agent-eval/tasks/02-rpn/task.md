# RPN calculator

Evaluate expressions in reverse Polish notation over 64-bit signed
integers, one expression per line.

## Input

Lines of text. Each line is one expression: tokens separated by one or
more spaces (a line may also start or end with spaces). The input may end
with or without a final newline; a final newline does not start another
expression. A token is one of:

- a number: an optional `-` followed by one or more decimal digits
  (`7`, `-12`, `007`). Every number in the input is in the signed
  64-bit range, -9223372036854775808 to 9223372036854775807;
- an operator: `+`, `-`, `*`, `/`, `%`, which pops `b` (the top), then
  `a`, and pushes `a + b`, `a - b`, `a * b`, `a / b` or `a % b`;
- `dup`, which pushes a copy of the top value;
- `swap`, which exchanges the top two values.

Anything else (`+5`, `--1`, `1.5`, `x`, `DUP`) is a bad token.

Arithmetic is on signed 64-bit integers and **wraps** on overflow (two's
complement: `9223372036854775807 1 +` is `-9223372036854775808`). `/`
truncates toward zero and `%` has the sign of `a` (`-7 2 /` is `-3`,
`-7 2 %` is `-1`). The one division that overflows,
`-9223372036854775808 -1 /`, wraps to `-9223372036854775808`, and the
matching `%` gives `0`.

## Output

One line per input line: the value, in decimal, or the word `error` when

- a token is bad,
- an operator, `dup` or `swap` finds too few values on the stack,
- `/` or `%` has `b == 0`,
- the line ends with a stack that does not hold exactly one value
  (an empty or blank line is an `error` too).

Evaluate left to right; the first problem makes the line's result
`error` (the rest of the line is ignored).

## Example

Input:

```
3 4 + 2 *
5 1 2 + 4 * + 3 -
1 0 /
2 dup * dup *
1 2
10 3 swap -
-7 2 %
abc
```

Output:

```
14
14
error
16
error
-7
-1
error
```

## Notes

- Input is up to 1 MB: thousands of lines, some with thousands of tokens.
- Lines contain only printable ASCII and spaces (no tabs, no `\r`).
