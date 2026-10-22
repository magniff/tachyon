# Split a module

A shop's till: products and stock, carts, coupons and tax, receipts, and
the commands a clerk types, all in one 415-line `shop.vl` that grew
one function at a time. `main.vl` stocks the shop and replays a day at
the till.

The session asks the compiler how the module's items depend on each
other, lets it plan a split into files of at most 170 lines, applies the
plan in one edit, and checks that the program still prints the same
receipts. Every command below is run by `tests/walkthrough/run.sh` on a
fresh copy of this directory, and its output is checked against this
file.

## The program

```console
$ volec main.vl -o till && ./till > before.txt && tail -12 before.txt
subtotal                          48.00
discount                          -4.80
tax                                3.46
TOTAL                             46.66
-----------------------------------
> stock
sku  product          stock    price
1    green tea            6     4.50
2    oat biscuits         4     2.99
3    honey jar            0     8.25
4    teapot               1    24.00
takings: 99.58
ok: built till
```

## 1. Too big, by how much

`lint --max-lines` is the rule a project can put in CI; it names the
command that shows the way out:

```console
$ volec lint --max-lines 170
error lint.max-lines: shop.vl: 410 lines (at most 170)
try: volec query deps crate::shop --max-lines 170
[exit 1]
```

The file already has sections, marked with banner comments; `query items
--comments` lists them with their line ranges:

```console
$ volec query items shop --comments | grep section
7-84	section	Products and stock
86-163	section	Carts
165-240	section	Prices and discounts
242-302	section	Receipts
304-410	section	Commands
```

## 2. What uses what

`query deps` prints, for every item, its size, what it uses and what
uses it (one line each), then groups of items that use each other most
and fit the size. The groups alone:

```console
$ volec query deps shop --max-lines 170 | grep -v '^[A-Za-z_]*	'
# crate::shop	shop.vl	356 lines	39 items
group 1	164	Product Store new_store add_product find_sku product in_stock restock take_stock free_store print_stock Command number parse_command run
group 2	148	Line Cart new_cart line_index add_to_cart remove_from_cart qty_of items_in clear_cart free_cart Total subtotal total money pad_to receipt_line print_receipt checkout
group 3	44	TAX_PERMILLE Coupon parse_coupon discount round_div tax_on
```

The full table answers "can I move `money` without dragging half the
file along": `money` is 9 lines, uses nothing in the module, is used by
`receipt_line` and `print_stock`, and from 2 places outside it:

```console
$ volec query deps shop | grep '^money'
money	9	-	receipt_line print_stock	2
```

## 3. The plan

`refactor split --plan` packs the same graph into parts (finer than
the groups above: each part also leaves room for its `use` lines) and
writes each as a command, one per new module, named after the banner (or type, or common prefix) most of its
lines share, with the reason on the line above. The part most used from
outside stays in `shop` itself:

```console
$ volec refactor split shop --plan --max-lines 170
# crate::shop	410 lines	5 parts of at most 170 lines
# commands: banner '// ---- Commands ----': 4 of 4 items, 89 of 89 lines
volec refactor split crate::shop --into crate::shop::commands --items Command,number,parse_command,run
# carts: banner '// ---- Carts ----': 10 of 12 items, 67 of 88 lines
volec refactor split crate::shop --into crate::shop::carts --items Line,Cart,new_cart,line_index,add_to_cart,remove_from_cart,qty_of,items_in,clear_cart,free_cart,subtotal,checkout
# stays in crate::shop: the part most used from other modules
# receipts: banner '// ---- Receipts ----': 4 of 6 items, 47 of 60 lines
volec refactor split crate::shop --into crate::shop::receipts --items Total,total,money,pad_to,receipt_line,print_receipt
# prices_discounts: banner '// ---- Prices and discounts ----': 6 of 6 items, 44 of 44 lines
volec refactor split crate::shop --into crate::shop::prices_discounts --items TAX_PERMILLE,Coupon,parse_coupon,discount,round_div,tax_on
note refactor.plan: the same in one edit: --auto (other names: --names a,b)
try: volec refactor split crate::shop --auto --max-lines 170
```

The plan is plain commands: run them one by one, edit the item lists
first, or take the whole plan in one edit with `--auto`. `--names` gives
the parts other names, in the plan's order; `prices_discounts` becomes
`pricing`:

```console
$ volec refactor split shop --auto --max-lines 170 --names commands,carts,receipts,pricing
split crate::shop into 4 modules	6 files	+343 -319 lines
$ volec query stats
105	12	shop/carts.vl
99	11	shop/mod.vl
99	4	shop/commands.vl
74	6	shop/receipts.vl
54	6	shop/pricing.vl
34	1	main.vl
465	40	total
$ volec lint --max-lines 170 && echo every file fits
every file fits
```

`shop.vl` became a directory module, `shop/mod.vl`, with a file per
part. Each item went with its comments, and each banner became the
header of its new file. Every file got the `use` lines it needs, and
items another file uses became `pub` where privacy required it:

```console
$ volec query show shop::carts::use shop::carts::header
// crate::shop::carts::use	shop/carts.vl:3-5
use crate::shop::{Store, in_stock, product, take_stock};
use crate::shop::pricing::Coupon;
use crate::shop::receipts::{print_receipt, total};
// crate::shop::carts::header	shop/carts.vl:1-1
// Carts
$ volec query items shop
# crate::shop	shop/mod.vl
5	mod	pub mod commands
6	mod	pub mod carts
7	mod	pub mod receipts
8	mod	mod pricing
15	struct	pub struct Product
23	struct	pub struct Store
29	fn	pub fn new_store(gpa: Gpa) -> Store
33	fn	pub fn add_product(st: inout Store, sku: i64, name: [u8], price: i64, stock: i64)
38	fn	pub fn find_sku(st: Store, sku: i64) -> Option<i64>
47	fn	pub fn product(st: Store, sku: i64) -> Option<Product>
54	fn	pub fn in_stock(st: Store, sku: i64) -> i64
62	fn	pub fn restock(st: inout Store, sku: i64, n: i64) -> bool
75	fn	fn take_stock(st: inout Store, sku: i64, n: i64) -> i64
88	fn	pub fn free_store(st: inout Store)
92	fn	pub fn print_stock(st: Store, gpa: Gpa)
```

Code outside the module was changed too: `main.vl` imports from where
the items are now.

```console
$ git diff main.vl
diff --git a/main.vl b/main.vl
index e5a4036..09c2d7c 100644
--- a/main.vl
+++ b/main.vl
@@ -2,7 +2,10 @@
 
 mod shop;
 
-use shop::{Store, add_product, free_cart, free_store, money, new_cart, new_store, run};
+use shop::{Store, add_product, free_store, new_store};
+use shop::carts::{free_cart, new_cart};
+use shop::commands::run;
+use shop::receipts::money;
 use std::Buf;
 
 fn main(gpa: Gpa) -> i32 {
```

(`--reexport` does the opposite: it leaves the code outside as it is,
and has `shop` re-export what it uses, for a split that must not touch
other files.)

## 4. The same program

```console
$ volec main.vl -o till && ./till | diff before.txt - && echo same receipts
same receipts
ok: built till
$ volec fmt --all --check && echo formatted
formatted
```

The split was one edit: one `undo` puts `shop.vl` back whole.

```console
$ volec undo
undid split crate::shop into 4 modules	6 files	+343 -319 lines
$ ls *.vl
main.vl
shop.vl
```

## Why not by hand

Splitting a 400-line file by hand means cutting and pasting five
sections, then working out each new file's `use` lines, which private
items must become `pub`, and what `main.vl` must import from where,
mostly by compiling and reading errors, one round at a time. The tool
computed the dependency graph from resolved names and wrote all six
files in one checked edit: the program compiled after it, or the edit
would not have been written.
