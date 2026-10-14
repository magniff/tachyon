# Fix the order processor

The workspace holds a small order-processing program, split into four
files: `main` (reads the input, drives the run), `inventory` (the items,
kept sorted by SKU and looked up by binary search), `orders` (fills each
order and computes its discount and total) and `money` (prints amounts).
It builds and runs, but **the program has bugs; the hidden tests check
the behaviour described here.** Find and fix them. Keep the program's
structure: change what is wrong, not the design.

## Input (stdin)

Whitespace-separated words (line breaks are not significant, but the
tests put one record per line):

```
items N
SKU PRICE STOCK NAME        (N times)
orders M
CUSTOMER TIER K             (M times, each followed by its K lines)
SKU QTY                     (K times)
```

- SKU, PRICE, STOCK, QTY, N, M, K are non-negative decimal integers;
  QTY is at least 1. PRICE is in cents.
- NAME and CUSTOMER are single words without spaces.
- TIER is `basic`, `silver` or `gold`.
- The items may come in any order; no two items share a SKU. N, M or K
  may be 0.

## Processing

Orders are processed in input order; within an order, lines in input
order, each against the stock as it is at that moment (earlier lines and
orders have already taken their units).

- A line whose SKU is not in the inventory is rejected as `unknown`.
- A line whose QTY is more than the item's current stock is rejected as
  `short`; nothing is taken (no partial fills).
- Otherwise the line is filled: QTY units leave the stock and the line
  costs PRICE × QTY cents.

An order's **subtotal** is the sum of its filled lines' costs. Its
**discount percent** is the tier's percent (basic 0, silver 5, gold 10)
plus 5 more when the subtotal is at least 100.00 (10000 cents). The
**discount** is subtotal × percent / 100 in cents, rounded down; the
**total** is subtotal − discount. The **revenue** is the sum of all
order totals.

## Output (stdout)

For each order, numbered from 1:

```
order I CUSTOMER (TIER)
```

then one line per order line, in order, indented by two spaces:

- filled: `  SKU NAME xQTY @ PRICE = COST`
- unknown SKU: `  SKU xQTY: unknown`
- not enough stock: `  SKU NAME xQTY: short (STOCK in stock)` (the stock
  before this line)

then

```
  subtotal S, discount P% D, total T (F filled, R rejected)
```

where F and R count this order's filled and rejected lines. After all
orders, the inventory in increasing SKU order with the final stock, and
the revenue:

```
inventory
  SKU NAME STOCK
revenue V
```

Amounts (PRICE, COST, S, D, T, V) are printed as dollars and cents:
`D.CC`, at least one digit before the point and exactly two after
(`0.05`, `19.99`, `100.00`).

## Example

Input:

```
items 4
1003 250 10 widget
1001 1999 5 gadget
1010 5000 2 lamp
1002 75 100 bolt
orders 3
alice gold 3
1001 2
1003 4
9999 1
bob basic 2
1010 3
1010 2
carol silver 2
1002 10
1001 3
```

Output:

```
order 1 alice (gold)
  1001 gadget x2 @ 19.99 = 39.98
  1003 widget x4 @ 2.50 = 10.00
  9999 x1: unknown
  subtotal 49.98, discount 10% 4.99, total 44.99 (2 filled, 1 rejected)
order 2 bob (basic)
  1010 lamp x3: short (2 in stock)
  1010 lamp x2 @ 50.00 = 100.00
  subtotal 100.00, discount 5% 5.00, total 95.00 (1 filled, 1 rejected)
order 3 carol (silver)
  1002 bolt x10 @ 0.75 = 7.50
  1001 gadget x3 @ 19.99 = 59.97
  subtotal 67.47, discount 5% 3.37, total 64.10 (2 filled, 0 rejected)
inventory
  1001 gadget 0
  1002 bolt 90
  1003 widget 6
  1010 lamp 0
revenue 204.09
```

## Edge cases the tests cover

- an inventory of one item, or none; lookups of the smallest and largest
  SKU and of SKUs below, above and between the known ones;
- subtotals exactly at, just below and above 100.00, for every tier;
- orders with no lines, orders where every line is rejected, and many
  orders in a row (counts are per order);
- a line that takes exactly the remaining stock, and later lines for the
  same SKU;
- no orders at all;
- a large input: 20000 items and 6000 orders (must run in well under a
  second or two).
