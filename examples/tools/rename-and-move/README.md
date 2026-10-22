# Rename and move

A lending library in five files: books (`catalog.vl`), members
(`members.vl`), loans and late fees (`loans.vl`), the end-of-day
report (`report.vl`) and a scripted month in `main.vl`. About 260
lines.

The session renames a field, two functions that share a name, a local
and a parameter, then moves the fee rules into a module of their own:
the kind of change that is a search-and-replace by hand, and that a
search-and-replace gets wrong. Every command below is run by
`tests/walkthrough/run.sh` on a fresh copy of this directory, and its
output is checked against this file.

## The program

```console
$ volec main.vl -o library && ./library | tee before.txt
day 1, Ada takes Dune: lent, due on day 15
day 2, Bob takes SICP: lent, due on day 16
day 3, Ada takes SICP: no copy on the shelf
day 3, Bob takes Dune: not allowed
day 20, Bob returns SICP: fee 100 cents
day 21, Bob takes Dune: not allowed
day 21, Ada takes SICP: lent, due on day 35
shelf:
  Dune                         Frank Herbert      count 1/2
  Structure and Interpretation Abelson, Sussman   count 0/1
members:
  Ada        holds 2 of 2, owes 0 cents
  Bob        holds 0 of 1, owes 100 cents
overdue on day 30: 1
ok: built library
```

`before.txt` is kept, to compare with at the end.

## 1. A field: `Book.count` becomes `copies`

`count` is a poor name for "copies on the shelf", and it is not the only
`count` in the program: `Member` has one too (books held), the report
prints the word, and comments use it. A text search sees all of them:

```console
$ grep -n count *.vl
catalog.vl:9:    pub count: i64,
catalog.vl:25:        self.books.push(Book { id: id, title: title, author: author, count: n, owned: n });
catalog.vl:49:            if b.count == 0 {
catalog.vl:52:            b.count -= 1;
catalog.vl:64:        b.count += 1;
loans.vl:39:    m.count += 1;
loans.vl:67:                m.count -= 1;
members.vl:6:    // the count of books held now
members.vl:7:    pub count: i64,
members.vl:24:        self.list.push(Member { id: id, name: name, count: 0, limit: limit, owed: 0 });
members.vl:44:    m.count < m.limit && m.owed == 0
report.vl:10:        println(f"  {b.title:<28} {b.author:<18} count {b.count}/{b.owned}");
report.vl:17:        println(f"  {m.name:<10} holds {m.count} of {m.limit}, owes {m.owed} cents");
```

The compiler knows which ones are `Book`'s field, including the use
inside an f-string hole and the one in a struct literal:

```console
$ volec query refs Book.count
# catalog.vl
9:9	def	pub count: i64,
25:70	init	catalog::Catalog::add	self.books.push(Book { id: id, title: title, author: author, count: n, owned: n });
49:18	read	catalog::take	if b.count == 0 {
52:15	write	catalog::take	b.count -= 1;
64:11	write	catalog::put_back	b.count += 1;
# report.vl
10:59	read	report::shelf	println(f"  {b.title:<28} {b.author:<18} count {b.count}/{b.owned}");
```

So the rename changes exactly those, and leaves `Member.count`, the
comments and the report's label alone:

```console
$ volec refactor rename Book.count copies --show
renamed crate::catalog::Book.count to copies	2 files	+6 -6 lines
// catalog.vl:9
9	    pub copies: i64,
// catalog.vl:25
25	        self.books.push(Book { id: id, title: title, author: author, copies: n, owned: n });
// catalog.vl:49
49	            if b.copies == 0 {
// catalog.vl:52
52	            b.copies -= 1;
// catalog.vl:64
64	        b.copies += 1;
// report.vl:10
10	        println(f"  {b.title:<28} {b.author:<18} count {b.copies}/{b.owned}");
```

`--show` prints the lines the edit wrote, numbered, so nothing needs to
be read back. Before writing, the edit engine checked the whole program
with the change: an edit that would add an error writes nothing.

## 2. A function with a namesake

Both `catalog` and `members` have a `find`. A bare name is ambiguous,
and the tool says so, with a command for each candidate:

```console
$ volec refactor rename find book_index
error query.ambiguous: 2 definitions match 'find'; name one
try: volec refactor rename crate::catalog::find book_index
try: volec refactor rename crate::members::find book_index
[exit 1]
```

Pick one with its path. Calls are found however they are written: the
plain `book_index(cat, id)` inside `catalog.vl`, and the qualified
`crate::members::find(ms, member)` in `loans.vl`:

```console
$ volec refactor rename crate::catalog::find book_index --show
renamed crate::catalog::find to book_index	catalog.vl	+3 -3 lines
// catalog.vl:35
35	pub fn book_index(cat: Catalog, id: i64) -> Option<i64> {
// catalog.vl:46
46	    match book_index(cat, id) {
// catalog.vl:62
62	    if let Some(i) = book_index(cat, id) {
$ volec refactor rename crate::members::find member_index --show
renamed crate::members::find to member_index	2 files	+3 -3 lines
// loans.vl:28
28	    let i = match crate::members::member_index(ms, member) {
// loans.vl:65
65	            if let Some(i) = crate::members::member_index(ms, member) {
// members.vl:34
34	pub fn member_index(ms: Members, id: i64) -> Option<i64> {
```

## 3. A local and a parameter

`d` is a short name in two functions of `loans.vl`. A local is named
`FUNCTION::local` (or by its position, `FILE:LINE:COL`); shadowing is
respected, and a parameter's name in the doc comment (written in
backquotes) follows it:

```console
$ volec refactor rename give_back::d days_late --show
renamed local d to days_late in crate::loans::give_back, 1 use	loans.vl	+2 -2 lines
// loans.vl:63-64
63	            let days_late = today - l.due;
64	            let fee = late_fee(days_late);
$ volec refactor rename late_fee::d days_late --show
renamed parameter d to days_late in crate::loans::late_fee, 2 uses	loans.vl	+4 -4 lines
// loans.vl:46-48
46	// The fee for a book returned `days_late` days after it was due.
47	pub fn late_fee(days_late: i64) -> i64 {
48	    if days_late <= 0 {
// loans.vl:51
51	    let fee = days_late * FEE_PER_DAY;
```

## 4. The fee rules move to a module of their own

`late_fee` and its two constants are policy, not lending. Make a module
(its file and its `mod` line), then move the three items into it. The
tool moves their comments with them, adds the `use` line `loans.vl`
now needs, and keeps `pub` where it is needed:

```console
$ volec refactor new-module fees
made module fees	2 files	+1 -0 lines
$ volec refactor move loans::late_fee loans::FEE_PER_DAY loans::MAX_FEE --to fees --show
moved 3 items to crate::fees	2 files	+14 -13 lines
// loans.vl:4
4	use crate::fees::late_fee;
// loans.vl:8: 4 lines removed after line 8
// loans.vl:40: 9 lines removed after line 40
// fees.vl:1-13
1	// cents per day late
2	pub const FEE_PER_DAY: i64 = 25;
3	// a fee never exceeds this, however late
4	pub const MAX_FEE: i64 = 1000;
5	
6	// The fee for a book returned `days_late` days after it was due.
7	pub fn late_fee(days_late: i64) -> i64 {
8	    if days_late <= 0 {
9	        return 0;
10	    }
11	    let fee = days_late * FEE_PER_DAY;
12	    if fee > MAX_FEE { MAX_FEE } else { fee }
13	}
$ volec query show loans::use
// crate::loans::use	loans.vl:3-5
use crate::catalog::{Catalog, put_back, take};
use crate::fees::late_fee;
use crate::members::{Members, can_borrow};
```

## 5. A rename taken back

Every edit is journaled (in `.git`, or `.volec/` outside a git
checkout). Suppose `Member` becomes `Patron`, and then the team decides
against it:

```console
$ volec refactor rename Member Patron
renamed crate::members::Member to Patron	members.vl	+4 -4 lines
$ volec query diff
# renamed crate::members::Member to Patron	members.vl	+4 -4 lines
--- a/members.vl
+++ b/members.vl
@@ -3 +3 @@
-pub struct Member {
+pub struct Patron {
@@ -14 +14 @@
-    pub list: Vec<Member>,
+    pub list: Vec<Patron>,
@@ -24 +24 @@
-        self.list.push(Member { id: id, name: name, count: 0, limit: limit, owed: 0 });
+        self.list.push(Patron { id: id, name: name, count: 0, limit: limit, owed: 0 });
@@ -43 +43 @@
-pub fn can_borrow(m: Member) -> bool {
+pub fn can_borrow(m: Patron) -> bool {
$ volec undo
undid renamed crate::members::Member to Patron	members.vl	+4 -4 lines
$ volec query refs Member --count
4
```

`query diff` shows the last edit as a diff, `undo` takes it back (run
again, it takes back the one before).

## 6. The same program

What changed, by file, and the proof that the program does the same:

```console
$ git status --short -- '*.vl'
 M catalog.vl
 M loans.vl
 M main.vl
 M members.vl
 M report.vl
?? fees.vl
$ git add -N fees.vl && git diff --stat
 catalog.vl | 16 ++++++++--------
 fees.vl    | 13 +++++++++++++
 loans.vl   | 22 +++++-----------------
 main.vl    |  1 +
 members.vl |  2 +-
 report.vl  |  2 +-
 6 files changed, 29 insertions(+), 27 deletions(-)
$ volec check && volec main.vl -o library && ./library | diff before.txt - && echo same output
same output
ok: 0 errors in main.vl
ok: built library
```

## Why not by hand

- `grep -n count` finds 13 lines, of which 6 hold `Book.count`;
  `sed -i s/count/copies/g` would also have renamed `Member.count` in
  three files, a comment, and the word `count` the report prints, and
  the program would still have compiled. The other way round, a search
  for `.count` misses the struct literal `Book { ..., count: n }`.
- Two functions named `find`: a text rename touches both, or the wrong
  one; the tool refuses until the path says which.
- A local `d` cannot be searched for at all.
- The move took one command: the items, their comments, the new file,
  its `mod` line and the `use` line in `loans.vl`. By hand that is
  five edits in three files, then a build to find what was missed.
- Every step was checked before it was written, and each one is one
  `undo` away.
