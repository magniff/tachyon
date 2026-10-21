## query context (0.15): an item's source with its section's title, the
## signatures of what it calls and of the types it uses, its callers; a
## module's items and its most used bodies; --budget cuts it, with a note
## and the commands that print the rest. --budget on any query.
$ context report
// crate::report	context/main.tach:9-15	section: Reports	effects: panic
// The total, after restocking the empty items.
fn report(items: inout Vec<Item>) -> i64 {
    for i in 0..items.len() {
        restock(&items, i, 5);
    }
    total(items)
}
// calls (3)
crate::stock::restock	context/stock.tach:10:8	fn	pub fn restock(items: inout Vec<Item>, i: i64, n: i64)
crate::stock::total	context/stock.tach:19:8	fn	pub fn total(items: Vec<Item>) -> i64
std::Vec::len	../../compiler/std/std.tach:204:12	method	pub fn len(self) -> i64
// types (2)
crate::stock::Item	context/stock.tach:4:12	struct	pub struct Item { pub name: [u8], pub count: i64 }
std::Vec	../../compiler/std/std.tach:189:12	struct	pub struct Vec<T, A: Allocator = Gpa> { ptr: *T, len: i64, cap: i64, alloc: A }
// callers (2)
main	context/main.tach:21:13	let n = report(&items);
main	context/main.tach:24:13	let m = report(&items);
$ context restock total
// crate::stock::restock	context/stock.tach:9-16	effects: panic
// Sets item i's count to n when it is empty.
pub fn restock(items: inout Vec<Item>, i: i64, n: i64) {
    var it = items.get(i);
    if it.count == 0 && n <= MAX {
        it.count = n;
        &items.set(i, it);
    }
}
// calls (2)
std::Vec::set	../../compiler/std/std.tach:311:12	method	pub fn set(inout self, i: i64, x: sink T) requires 0 <= i && i < self.len else f"index out of bounds: index {i}, length {self.len}"
std::Vec::get	../../compiler/std/std.tach:304:12	method	pub fn get(self, i: i64) -> T requires 0 <= i && i < self.len else f"index out of bounds: index {i}, length {self.len}"
// types (2)
crate::stock::Item	context/stock.tach:4:12	struct	pub struct Item { pub name: [u8], pub count: i64 }
std::Vec	../../compiler/std/std.tach:189:12	struct	pub struct Vec<T, A: Allocator = Gpa> { ptr: *T, len: i64, cap: i64, alloc: A }
// uses (1)
crate::stock::MAX	context/stock.tach:7:11	const	pub const MAX: i64 = 100
// callers (1)
report	context/main.tach:12:9	restock(&items, i, 5);
// crate::stock::total	context/stock.tach:18-25	effects: panic
// The sum of the counts.
pub fn total(items: Vec<Item>) -> i64 {
    var t = 0;
    for i in 0..items.len() {
        t += items.get(i).count;
    }
    t
}
// calls (2)
std::Vec::get	../../compiler/std/std.tach:304:12	method	pub fn get(self, i: i64) -> T requires 0 <= i && i < self.len else f"index out of bounds: index {i}, length {self.len}"
std::Vec::len	../../compiler/std/std.tach:204:12	method	pub fn len(self) -> i64
// types (2)
crate::stock::Item	context/stock.tach:4:12	struct	pub struct Item { pub name: [u8], pub count: i64 }
std::Vec	../../compiler/std/std.tach:189:12	struct	pub struct Vec<T, A: Allocator = Gpa> { ptr: *T, len: i64, cap: i64, alloc: A }
// callers (1)
report	context/main.tach:14:5	total(items)
$ context Item
// crate::stock::Item	context/stock.tach:3-4
// One kind of item.
pub struct Item { pub name: [u8], pub count: i64 }
// used by (6)
report	context/main.tach:10:28	fn report(items: inout Vec<Item>) -> i64 {
main	context/main.tach:18:20	var items: Vec<Item> = Vec::new_in(gpa);
main	context/main.tach:19:16	items.push(Item { name: "bolt", count: 0 });
main	context/main.tach:20:16	items.push(Item { name: "nut", count: 3 });
stock::restock	context/stock.tach:10:33	pub fn restock(items: inout Vec<Item>, i: i64, n: i64) {
stock::total	context/stock.tach:19:25	pub fn total(items: Vec<Item>) -> i64 {
$ context stock
# crate::stock	context/stock.tach
4	struct	pub struct Item
7	const	pub const MAX: i64 = 100
10	fn	pub fn restock(items: inout Vec<Item>, i: i64, n: i64)
19	fn	pub fn total(items: Vec<Item>) -> i64
// crate::stock::restock	context/stock.tach:9-16	used 0 times in the module, 1 outside
// Sets item i's count to n when it is empty.
pub fn restock(items: inout Vec<Item>, i: i64, n: i64) {
    var it = items.get(i);
    if it.count == 0 && n <= MAX {
        it.count = n;
        &items.set(i, it);
    }
}
// crate::stock::total	context/stock.tach:18-25	used 0 times in the module, 1 outside
// The sum of the counts.
pub fn total(items: Vec<Item>) -> i64 {
    var t = 0;
    for i in 0..items.len() {
        t += items.get(i).count;
    }
    t
}
$ context report --budget 120
// crate::report	context/main.tach:9-15	section: Reports	effects: panic
// The total, after restocking the empty items.
fn report(items: inout Vec<Item>) -> i64 {
    for i in 0..items.len() {
        restock(&items, i, 5);
    }
    total(items)
}
// calls (3)
crate::stock::restock	context/stock.tach:10:8	fn	pub fn restock(items: inout Vec<Item>, i: i64, n: i64)
crate::stock::total	context/stock.tach:19:8	fn	pub fn total(items: Vec<Item>) -> i64
note query.budget: over the budget of 120 tokens, left out: calls 1, types or uses 2, callers 2
try: tachyonc query callers report
try: tachyonc query context report --budget 360
$ context nothing_here
error query.no-match: no definition 'nothing_here'
try: tachyonc query items
[exit 1]
$ show report --budget 40
// crate::report	context/main.tach:9-15	effects: panic
// The total, after restocking the empty items.
fn report(items: inout Vec<Item>) -> i64 {
note query.budget: cut at about 40 tokens: 3 of 8 lines (about 58 tokens in all)
try: tachyonc query show report --budget 100
$ refs restock --budget 20
# context/main.tach
5:19	use	crate	use stock::{Item, restock, total};
note query.budget: cut at about 20 tokens: 2 of 5 lines (about 50 tokens in all)
try: tachyonc query refs restock --budget 100
