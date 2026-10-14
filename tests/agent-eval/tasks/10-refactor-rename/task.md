# Rename and move: the library desk

The workspace holds a small working program: a library's front desk. It
reads commands from stdin, one per line, and prints what each one did and
the reports asked for. It is split into modules:

| file | what it holds |
|---|---|
| `main` | reading the input, one handler per command (`cmd_add`, `cmd_join`, `cmd_lend`, `cmd_return`, `cmd_pay`, `cmd_report`), the `Library` struct, and the four reports |
| `catalog` | the struct `Item` (a title: `id`, `title`, `qty` copies owned, `lent` copies out) and `Catalog`, the list of them |
| `members` | `Member` and `Members` |
| `loans` | `Loan`, `Loans`, `days_late`, and `calc`, the late fee of a loan |
| `text` | splitting lines into words, numbers, money as text |

The program is correct. Refactor it without changing its behaviour:

1. Rename the struct `Item` to `Book`, everywhere it is used.
2. Rename its field `qty` to `copies`, everywhere it is used.
3. Rename the function `calc` to `late_fee`, everywhere it is called.
4. Move the four report functions, `report_stock`, `report_members`,
   `report_overdue` and `report_summary`, out of `main` into a new module
   `report`, in a new file `report` next to `main` (the same extension as
   the other files), declared from `main` with `mod report;`. `cmd_report`
   stays in `main` and calls them there.

Rules, checked after you finish:

- The words `Item`, `qty` and `calc` must not appear anywhere in the
  source files as whole words (case-sensitive): not as names, not in
  comments, not in strings. That includes the parameters and local
  variables called `qty` (call them `copies`) and comments that mention
  the old names. Words that merely contain them (`items`, `total_qty`,
  `item`) may stay.
- `struct Book` with a field `copies`, and `fn late_fee`, exist.
- `report` defines the four report functions; no other file defines
  them; `main` still defines `cmd_report`.
- Output is byte-for-byte what it was: the hidden tests run the program
  on many inputs and compare with the original program's output.

## What the program does (for reference; do not change it)

Commands, words separated by spaces; blank lines and lines starting with
`#` are skipped; a line may end in `\r\n`. Ids, days and amounts are
non-negative integers; money is in cents and printed as dollars.

- `ADD <id> <copies> <title>`: a new title, or more copies of a known one.
- `JOIN <id> <name>`: a new member.
- `LEND <member> <book> <day>`: a member borrows a copy; refused when the
  member holds 3 books or owes more than 10.00, or no copy is on the shelf.
- `RETURN <member> <book> <day>`: the member's oldest loan of that book
  ends; a book held more than 14 days is late, and `calc` gives the fee:
  0.25 per day for the first 7 late days, 0.50 per day after, at most
  15.00. The fee is added to what the member owes.
- `PAY <member> <cents>`: pays up to what the member owes.
- `REPORT STOCK`, `REPORT MEMBERS`, `REPORT OVERDUE <day>`,
  `REPORT SUMMARY`.

Example input:

```
ADD 1 2 The Hobbit
ADD 2 1 Dune
JOIN 7 Ann Lee
LEND 7 1 0
LEND 7 2 3
REPORT STOCK
RETURN 7 1 20
REPORT MEMBERS
PAY 7 100
REPORT SUMMARY
```

Its output:

```
added 1: The Hobbit
added 2: Dune
joined 7
lent 1 to 7, due day 14
lent 2 to 7, due day 17
stock:
  1 The Hobbit: 1/2
  2 Dune: 0/1
returned 1 by 7, 6 days late, fee 1.50
members:
  7 Ann Lee: 1 on loan, owes 1.50, paid 0.00
paid 1.00, owes 0.50
summary: 2 titles, 3 copies, 1 lent, 1 members, owed 0.50, collected 1.00
```

The hidden tests cover every command and error message, the fee schedule
at its edges, the loan and debt limits, empty reports, comments, blank
lines, `\r\n` line ends, runs of spaces, and a large input (25,000
commands).
