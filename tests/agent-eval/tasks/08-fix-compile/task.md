# Make the table formatter build

The workspace holds a small program that formats comma-separated lines
as a text table. It is split into three files: `main` (reads stdin,
prints the result), `table` (splits the input into a header and rows of
cells) and `render` (column widths, alignment, drawing). Someone wrote
it in a hurry: **it does not compile.** Make it build, then make sure it
behaves exactly as described below; the hidden tests check this
behaviour. Keep the program's structure: fix what is wrong, do not
rewrite it.

## Input (stdin)

Lines of text (ASCII), each a list of fields separated by commas.

- A line ends at `\n`; a `\r` before it is ignored, as are spaces and
  tabs at either end of every field. Spaces inside a field are kept.
- Lines that are empty or contain only spaces, tabs or `\r` are skipped.
- The first remaining line is the **header**; the others are the data
  **rows**, in order.
- The table has as many columns as the longest line has fields; a line
  with fewer fields is padded with empty cells. A trailing comma makes
  one more (empty) field.

## Output (stdout)

If there is no header (no non-blank line), print nothing. Otherwise
print a box:

```
+<border>+
| header cells |
+<border>+
| row cells |        (one line per row)
+<border>+           (only when there is at least one row)
```

- Every column has a **width**: the length of its longest cell, the
  header cell included, and at least 1.
- A border line is `+`, then for each column `-` repeated width + 2
  times followed by `+`.
- A row line is `|`, then for each column a space, the cell padded with
  spaces to the column's width, a space and `|`.
- A column is **numeric** when at least one of its data cells (not the
  header) is non-empty and every non-empty data cell is a number: an
  optional `-`, one or more digits, and optionally a `.` followed by one
  or more digits (`7`, `-0.5`, `007`; not `+3`, `1.`, `.5`, `-`).
- Cells of numeric columns, the header cell included, are padded on the
  left (right-aligned); all other cells on the right (left-aligned).

## Example

Input:

```
name, qty ,price
widget,3,2.50
longer gadget name,12,-0.5

bolt,,x
```

Output:

```
+--------------------+-----+-------+
| name               | qty | price |
+--------------------+-----+-------+
| widget             |   3 | 2.50  |
| longer gadget name |  12 | -0.5  |
| bolt               |     | x     |
+--------------------+-----+-------+
```

A header with no rows (`city,population,country`):

```
+------+------------+---------+
| city | population | country |
+------+------------+---------+
```

## Edge cases the tests cover

- empty input, and input of blank lines only (no output);
- a header and no rows; a single cell;
- rows shorter and longer than the header, trailing commas;
- headers wider than every cell of their column;
- the number rule above, including `-`, `1.`, `.5`, `-0`, `+3`,
  `1.2.3` and columns whose data cells are all empty;
- `\r\n` line endings, tabs and spaces around fields, blank lines
  between rows;
- a large input (6000 rows).
