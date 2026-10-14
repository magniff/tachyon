# A small query engine over CSV

Write a program that reads a table in CSV form from stdin, then a list of
queries in a small subset of SQL, and prints the result of each query (or
one error line for it). The program is big enough that it is worth
splitting into several modules (reading the table, a lexer, a parser,
checking a query against the table, running it, ordering the rows); the
hidden tests only look at the output.

## Input

```
<header line>
<data line>          zero or more
...
%%
<query line>         zero or more
...
```

Every line may end in `\r\n` instead of `\n`: drop one `\r` at the end of
each line before anything else. The last line may lack its newline.

### The table

The **header line** names the columns: `name:type` items separated by
commas, with no spaces, e.g. `id:int,name:str,age:int`. A name is a
letter or `_` followed by letters, digits and `_`; names are unique and
case-sensitive. A type is `int` or `str`. No column name is one of the
query keywords below, in any case.

Each **data line** is one row, with exactly one field per column. Empty
data lines are skipped. Fields are separated by commas:

- A field that starts with `"` is quoted: it runs up to the next `"` that
  is not doubled; inside it, `""` stands for one `"`, and commas are part
  of the value. The closing quote is followed by a comma or the end of the
  line. A quoted field never spans lines.
- Any other field is taken exactly as it is, up to the next comma or the
  end of the line: spaces are kept, and a `"` that is not the first
  character is an ordinary character.
- In an `int` column, a field is either empty (unquoted, nothing between
  the commas): the value **NULL**; or an optional `-` and 1 to 18 digits.
  `int` fields are never quoted.
- In a `str` column, a field is a string of bytes (possibly empty; an
  empty `str` field is the empty string, not NULL). `str` values are
  never NULL.

The line that is exactly `%%` ends the table. The input is always a valid
table as described; there may be no data rows at all.

### Queries

After `%%`, every line is one query, except lines that are empty or hold
only spaces and tabs, and lines starting with `--` (comments): those are
skipped and print nothing.

## The query language

### Tokens

Spaces and tabs separate tokens and are otherwise ignored. The tokens:

- **identifiers**: a letter or `_` followed by letters, digits and `_`.
  An identifier that equals one of the **keywords** `SELECT FROM WHERE
  GROUP BY ORDER ASC DESC LIMIT AND OR NOT IS NULL COUNT SUM MIN MAX`,
  ignoring case, is that keyword (`select`, `Select` and `SELECT` are the
  same); any other identifier is a name (a column or the table), matched
  case-sensitively.
- **integers**: one or more digits, or `-` immediately followed by one or
  more digits (a negative integer). At most 18 digits. `-` not followed by
  a digit is an unexpected character. `5abc` is the integer `5`, then the
  identifier `abc`.
- **strings**: `'` ... `'`, where `''` inside stands for one `'`. A string
  that is not closed on its line is an error (`unterminated string`).
- **symbols**: `,` `(` `)` `*` `=` `!=` `<` `<=` `>` `>=`.
- Anything else (for example `!` not followed by `=`, `;`, `"`, `.`) is an
  unexpected character.

The whole line is tokenized before it is parsed: an error in tokenizing
is reported even when the parser would have failed earlier on the line.

### Grammar

```
query    := SELECT items FROM NAME [WHERE or] [GROUP BY NAME]
            [ORDER BY oitem {, oitem}] [LIMIT INTEGER]       then the end of the line
items    := * | item {, item}
item     := NAME | agg
agg      := COUNT ( * ) | COUNT ( NAME ) | SUM ( NAME ) | MIN ( NAME ) | MAX ( NAME )
oitem    := (NAME | agg) [ASC | DESC]
or       := and {OR and}
and      := not {AND not}
not      := NOT not | atom
atom     := ( or ) | operand IS NULL | operand IS NOT NULL | operand cmp operand
operand  := NAME | INTEGER | STRING
cmp      := = | != | < | <= | > | >=
```

Clauses come in this order and each at most once. `*` is only allowed as
the whole select list. The `LIMIT` integer must not be negative (a
negative one is an unexpected token). `NULL` is not an operand: `x = NULL`
is a syntax error at `NULL`. `AND` binds tighter than `OR`; `NOT` tighter
than `AND`.

### Checking a query

A query that parses is checked against the table before it runs. The
checks happen in this order, and the first one that fails is the query's
error:

1. The table: the name after `FROM` must be `t`.
2. Unknown columns: every column name in the query, in the order they
   appear in the line (select list, `WHERE`, `GROUP BY`, `ORDER BY`), must
   be a column of the table.
3. Types, in the order they appear in the line: `SUM` needs an `int`
   column; the two sides of a comparison must have the same type (a column
   has its type, an integer is `int`, a string is `str`). `MIN`, `MAX`,
   `COUNT` and `IS [NOT] NULL` take any column.
4. Grouping. A query is **grouped** when it has `GROUP BY` or an aggregate
   in its select list. In a grouped query every plain column in the select
   list and in `ORDER BY` must be the `GROUP BY` column, and the select
   list must not be `*`. In a query that is not grouped, `ORDER BY` must
   not contain an aggregate. These are checked in the order they appear in
   the line.

### Running a query

**Values** are 64-bit signed integers, byte strings, and NULL (only in
`int` columns).

**WHERE** keeps the rows, in input order, for which the condition is
true (no `WHERE`: all rows). The logic is two-valued:

- a comparison is false when either side is NULL; otherwise integers
  compare as numbers and strings byte by byte (a proper prefix is
  smaller: `'ab' < 'abc'`, `'B' < 'a'`);
- `IS NULL` is true for NULL only, `IS NOT NULL` for everything else (an
  integer or string literal is never NULL);
- `NOT`, `AND`, `OR` are the usual operations on true and false; so
  `NOT (age > 30)` is true for a row whose `age` is NULL.

**Not grouped**: each kept row gives one output row: the listed columns,
or for `*` all columns in table order.

**Grouped**: the kept rows are divided into groups.

- With `GROUP BY g`, rows with the same value of `g` form one group (all
  NULLs form one group). Groups are in the order of their first row. No
  kept rows: no groups.
- Without `GROUP BY` (aggregates in the select list), all kept rows form
  exactly one group, even when there are none.

Each group gives one output row: the value of `g` for the `GROUP BY`
column, and for aggregates:

- `COUNT(*)`: the number of rows in the group;
- `COUNT(c)`: the number of rows where `c` is not NULL;
- `SUM(c)`: the sum of the values of `c` that are not NULL (64-bit; the
  tests do not overflow); NULL when there are none;
- `MIN(c)`, `MAX(c)`: the smallest and largest value of `c` that is not
  NULL (numbers by value, strings byte by byte); NULL when there are none.

**ORDER BY** sorts the output rows by the first item, then by the second
on ties, and so on; `ASC` (the default) smallest first, `DESC` largest
first. The sort is **stable**: rows equal on every item keep their order
from before the sort (input order, or groups in order of their first
row), also with `DESC`. NULL is smaller than every integer: first with
`ASC`, last with `DESC`. In a query that is not grouped, `ORDER BY` may
use any column of the table, also one that is not selected. In a grouped
query it may use the `GROUP BY` column and any aggregate (also one that is
not selected).

**LIMIT n** keeps the first `n` output rows (after ordering); `LIMIT 0`
keeps none.

## Output

For each query that is not skipped:

- a header line: the select items separated by `|`; a column is its name,
  an aggregate is written in capitals with no spaces, whatever the query
  wrote: `COUNT(*)`, `COUNT(age)`, `SUM(age)`, `MIN(name)`, `MAX(name)`;
  `*` gives every column name, in table order;
- one line per output row: the values separated by `|`; an integer in
  decimal (`-5`), NULL as `NULL`, a string as its bytes, exactly (no
  quoting or escaping, even when it holds `|`);
- `(N rows)`, or `(1 row)` when there is exactly one.

A query that fails prints a single line instead, and the program goes on
with the next query:

| problem | line |
|---|---|
| tokenizing | `error: syntax error: unexpected X` with X the character; `error: syntax error: unterminated string` |
| parsing | `error: syntax error: unexpected X` with X the first token where the line stops matching the grammar, as written in the query (`From`, `'it''s'`, `-1`); `error: syntax error: unexpected end of query` when the line ends too early |
| 1 | `error: unknown table X` |
| 2 | `error: unknown column X` |
| 3 | `error: cannot compare T1 with T2` (the types of the left and right side, `int` or `str`); `error: cannot SUM str column X` |
| 4 | `error: column X must be grouped or aggregated` (`*` for a `*` select list); `error: aggregate in ORDER BY of an ungrouped query` |

The parser reads left to right, one token at a time, and fails at the
first token that cannot continue a valid query (as an LL(1) parser of the
grammar above would). For example `SELECT a b FROM t` fails at `b`,
`SELECT FROM t` at `FROM`, `SELECT a FROM t WHERE (a = 1` at the end of
the query, `SELECT a FROM t WHERE a` at the end, `SELECT a FROM t WHERE a
IS 5` at `5`, `SELECT a FROM t LIMIT 5 WHERE a = 1` at `WHERE`, and
`SELECT SUM(*) FROM t` at `*`.

## Example

Input:

```
id:int,name:str,city:str,age:int
1,Ann,Oslo,34
2,Bob,"Rome, IT",
3,"Cy ""the kid""",Oslo,19
4,Dee,Rome,34
%%
SELECT name, age FROM t WHERE age >= 20 ORDER BY age DESC
SELECT city, COUNT(*), max(age) FROM t GROUP BY city ORDER BY COUNT(*) DESC
-- a comment
select * from t where age is null or name = 'Cy "the kid"'
SELECT COUNT(*), SUM(age), MIN(name) FROM t WHERE id > 10
SELECT name FROM t WHERE height > 3
SELECT name FROM t WHERE age > 'x'
SELECT name, COUNT(*) FROM t
SELECT name FROM t LIMIT
```

Output:

```
name|age
Ann|34
Dee|34
(2 rows)
city|COUNT(*)|MAX(age)
Oslo|2|34
Rome, IT|1|NULL
Rome|1|34
(3 rows)
id|name|city|age
2|Bob|Rome, IT|NULL
3|Cy "the kid"|Oslo|19
(2 rows)
COUNT(*)|SUM(age)|MIN(name)
0|NULL|NULL
(1 row)
error: unknown column height
error: cannot compare int with str
error: column name must be grouped or aggregated
error: syntax error: unexpected end of query
```

## What the hidden tests cover

Every clause alone and together; keywords in any case; quoted fields
with commas, doubled quotes, empty quoted strings, spaces and `"` inside
unquoted fields; NULLs in comparisons, `IS [NOT] NULL`, aggregates,
grouping and ordering; aggregates over no rows; `ORDER BY` with several
items, mixed directions, columns not selected, ties (stability) and
aggregates; `LIMIT 0` and limits beyond the row count; `\r\n` line ends;
every error message, including which error wins when a query has several;
an empty table; and a large input (about 18,000 rows and 100 queries,
with groups by columns with many distinct values and sorts of every row),
which must run in well under a second: a quadratic sort or grouping is
too slow.
