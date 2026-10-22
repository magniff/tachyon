# Signatures, fields and variants

A small bank in five files: accounts (`account.vl`), events read from
lines like `deposit 500` (`event.vl`), the ledger that applies them
(`ledger.vl`), statements (`report.vl`), and a scripted week in
`main.vl`. About 220 lines.

The session changes the program's shape: parameters reordered, removed
and added, a field renamed and one added, and a new kind of event that
every `match` must handle. Each is one command that changes the
definition and every use together, so the program compiles after every
step. Every command below is run by `tests/walkthrough/run.sh` on a
fresh copy of this directory, and its output is checked against this
file.

## The program

```console
$ volec main.vl -o bank && ./bank
day 1: #1 + deposit of 12000: ok
day 2: #2 - withdrawal of 3000: ok
day 3: #1 - transfer of 4500 to #2: ok
day 4: #2 - withdrawal of 9000: refused
day 5: #1 + interest at 15 per mille: ok
day 6: #1 - withdrawal of 99999: refused
day 7: #2 cannot read 'lend 7'
#0 the bank   balance  99888, may go to -0
#1 Ada        balance   8612, may go to -0
#2 Grace      balance    500, may go to -5000
ok: built bank
```

## 1. Parameters

### Reorder

`transfer(l, amount, from, to)` reads badly at its calls:
`transfer(&l, 1000, 2, 1)`. Its calls, by kind:

```console
$ volec query refs transfer --kind call
# ledger.vl
75:35	call	ledger::apply	Event::Transfer(to, n) => transfer(&l, n, who, to),
81:13	call	ledger::apply	transfer(&l, b * permille / 1000, 0, who)
# main.vl
45:5	call	main	transfer(&l, 1000, 2, 1);
```

`--reorder` takes every parameter once. Forget one and the error lists
them:

```console
$ volec refactor signature transfer --reorder from,to,amount
error refactor.usage: --reorder lists each parameter once: (l, amount, from, to)
[exit 2]
$ volec refactor signature transfer --reorder l,from,to,amount --show
reordered the parameters of crate::ledger::transfer, 3 calls	2 files	+4 -4 lines
// main.vl:45
45	    transfer(&l, 2, 1, 1000);
// ledger.vl:49
49	pub fn transfer(l: inout Ledger, from: i64, to: i64, amount: i64) -> bool {
// ledger.vl:75
75	        Event::Transfer(to, n) => transfer(&l, who, to, n),
// ledger.vl:81
81	            transfer(&l, 0, who, b * permille / 1000)
```

The three calls were rewritten with it, including the one inside a
`match` arm and the one whose argument is an expression.

### Remove

`apply` takes a `day` it never uses. Removing a parameter that is still
used is refused, with the place that uses it:

```console
$ volec refactor signature apply --remove who
error refactor.used: parameter who is used in crate::ledger::apply at ledger.vl:71:24
try: volec query show ledger.vl:71
[exit 1]
$ volec refactor signature apply --remove day --show
removed parameter day of crate::ledger::apply, 1 call	2 files	+2 -2 lines
// main.vl:36
36	                let ok = apply(&l, who, e);
// ledger.vl:65
65	pub fn apply(l: inout Ledger, who: i64, e: Event) -> bool {
```

### Add, with a default

New parameters get a default value, so no call has to change
(`--fill-calls` writes the value into every call instead):

```console
$ volec refactor signature open --add 'opening: i64 = 0' --show
added parameter opening: i64 = 0 to crate::account::open, 2 calls	account.vl	+1 -1 lines
// account.vl:11
11	pub fn open(id: i64, owner: [u8], limit: i64, opening: i64 = 0) -> Account {
$ volec edit patch open --old 'balance: 0' --new 'balance: opening'
patched crate::account::open	account.vl	+1 -1 lines
$ volec edit patch main --old 'open(2, "Grace", 5000)' --new 'open(2, "Grace", 5000, opening: 800)' --show
patched crate::main	main.vl	+1 -1 lines
// main.vl:16
16	    l.accounts.push(open(2, "Grace", 5000, opening: 800));
```

## 2. Fields

`limit` is an overdraft. The rename reaches the struct, its three
literals (one in `main.vl`), the accesses and the f-string hole in
`report.vl`:

```console
$ volec refactor field Account --rename limit overdraft --show
renamed field limit to overdraft of crate::account::Account, 5 uses	3 files	+6 -6 lines
// main.vl:19
19	    l.accounts.set(0, account::Account { id: 0, owner: "the bank", balance: 100000, overdraft: 0 });
// account.vl:8
8	    pub overdraft: i64,
// account.vl:12
12	    Account { id: id, owner: owner, balance: opening, overdraft: limit }
// account.vl:17
17	    Account { id: 0, owner: "the bank", balance: 0, overdraft: 0 }
// account.vl:21
21	    a.balance + a.overdraft >= amount
// report.vl:25
25	    println(f"#{a.id} {a.owner:<10} balance {a.balance:>6}, may go to -{a.overdraft}");
```

`open`'s parameter is still called `limit`; a parameter rename changes
its uses in the body (a call that labels it, `limit: 5`, would change
too):

```console
$ volec refactor signature open --rename-param limit overdraft --show
renamed parameter limit to overdraft of crate::account::open	account.vl	+2 -2 lines
// account.vl:11-12
11	pub fn open(id: i64, owner: [u8], overdraft: i64, opening: i64 = 0) -> Account {
12	    Account { id: id, owner: owner, balance: opening, overdraft: overdraft }
```

A new field gets its value in every literal:

```console
$ volec refactor field Account --add 'pub fees_paid: i64 = 0' --show
added field pub fees_paid: i64 to crate::account::Account, 3 literals	2 files	+5 -3 lines
// main.vl:19-20
19	    l.accounts.set(0,
20	        account::Account { id: 0, owner: "the bank", balance: 100000, overdraft: 0, fees_paid: 0 });
// account.vl:9
9	    pub fees_paid: i64,
// account.vl:13
13	    Account { id: id, owner: owner, balance: opening, overdraft: overdraft, fees_paid: 0 }
// account.vl:18
18	    Account { id: 0, owner: "the bank", balance: 0, overdraft: 0, fees_paid: 0 }
```

## 3. A new event: a fee

The bank starts charging fees: `Event` gets a variant `Fee(i64)`. Three
`match`es cover every event and would no longer be exhaustive; asked
without arms, the tool lists them and refuses, with the command to fill
in:

```console
$ volec refactor variant Event --add 'Fee(i64)'
ledger.vl:66:5	ledger::apply
report.vl:8:5	report::describe
report.vl:18:5	report::is_credit
error refactor.non-exhaustive: 3 matches on crate::event::Event would not cover Fee; nothing written
try: volec query show ledger.vl:66 report.vl:8 report.vl:18
try: volec refactor variant crate::event::Event --add 'Fee(i64)' --arm 'EXPR' --dry-run
try: volec refactor variant crate::event::Event --add 'Fee(i64)' --arm-in ledger::apply 'EXPR' --arm-in report::describe 'EXPR' --arm-in report::is_credit 'EXPR' --dry-run
[exit 1]
```

The matches return different types (`bool`, a `Buf`, `bool`), so each
gets its own arm with `--arm-in FUNCTION EXPR`: first a placeholder that
compiles, so the variant and all three arms land in one checked edit:

```console
$ volec refactor variant Event --add 'Fee(i64)' --arm-in apply false --arm-in describe 'format_in("a fee", gpa)' --arm-in is_credit false --show
added variant Fee(i64) to crate::event::Event, an arm in 3 matches	3 files	+4 -0 lines
// event.vl:12
12	    Fee(i64),
// ledger.vl:83
83	        Event::Fee(_) => false,
// report.vl:13
13	        Event::Fee(_) => format_in("a fee", gpa),
// report.vl:22
22	        Event::Fee(_) => false,
```

Now the behaviour. The parser learns the word `fee`, the week gets two
fees, and the ledger a `charge` function:

```console
$ volec edit insert --in event::parse --before 'None' --show <<'EOF'
> if w.len == 2 && w[0] == "fee" {
>     return Some(Event::Fee(number(w[1])));
> }
> EOF
inserted in crate::event::parse	event.vl	+3 -0 lines
// event.vl:34-36
34	    if w.len == 2 && w[0] == "fee" {
35	        return Some(Event::Fee(number(w[1])));
36	    }
$ volec edit insert --in main --after '(1, "withdraw 99999"),' <<'EOF'
> (1, "fee 250"),
> (2, "fee 250"),
> EOF
inserted in crate::main	main.vl	+2 -0 lines
$ volec edit insert --after ledger::transfer <<'EOF'
> // A fee from account `who` to the house, counted in its fees_paid.
> fn charge(l: inout Ledger, who: i64, n: i64) -> bool {
>     if !transfer(&l, who, 0, n) {
>         return false;
>     }
>     if let Some(i) = index_of(l, who) {
>         var a = l.accounts.get(i);
>         a.fees_paid += n;
>         l.accounts.set(i, a);
>     }
>     true
> }
> EOF
inserted after crate::ledger::transfer	ledger.vl	+13 -0 lines
```

The placeholders become real arms, and the statement shows the fees:
one `edit patch` with a target per item (`--in NAME` starts the next
target's pairs), checked and written as one edit:

```console
$ volec edit patch ledger::apply --old 'Event::Fee(_) => false' --new 'Event::Fee(n) => charge(&l, who, n)' --in report::describe --old 'Event::Fee(_) => format_in("a fee", gpa)' --new 'Event::Fee(n) => format_in(f"fee of {n}", gpa)' --in report::summary --old 'may go to -{a.overdraft}' --new 'may go to -{a.overdraft}, fees {a.fees_paid}' --show
patched crate::report::describe, crate::report::summary, crate::ledger::apply	2 files	+4 -3 lines
// ledger.vl:96
96	        Event::Fee(n) => charge(&l, who, n),
// report.vl:13
13	        Event::Fee(n) => format_in(f"fee of {n}", gpa),
// report.vl:27-28
27	    println(
28	        f"#{a.id} {a.owner:<10} balance {a.balance:>6}, may go to -{a.overdraft}, fees {a.fees_paid}");
```

## 4. The new program

```console
$ volec main.vl -o bank && ./bank
day 1: #1 + deposit of 12000: ok
day 2: #2 - withdrawal of 3000: ok
day 3: #1 - transfer of 4500 to #2: ok
day 4: #2 - withdrawal of 9000: refused
day 5: #1 + interest at 15 per mille: ok
day 6: #1 - withdrawal of 99999: refused
day 7: #1 - fee of 250: ok
day 8: #2 - fee of 250: ok
day 9: #2 cannot read 'lend 7'
#0 the bank   balance 100388, may go to -0, fees 0
#1 Ada        balance   8362, may go to -0, fees 250
#2 Grace      balance   1050, may go to -5000, fees 250
ok: built bank
$ git diff --stat
 account.vl | 11 ++++++-----
 event.vl   |  4 ++++
 ledger.vl  | 22 ++++++++++++++++++----
 main.vl    | 11 +++++++----
 report.vl  |  5 ++++-
 5 files changed, 39 insertions(+), 14 deletions(-)
```

## Why not by hand

- A reordered parameter is the change a text edit gets silently wrong:
  `transfer(&l, n, who, to)` and `transfer(&l, who, to, n)` both compile,
  with every amount and account id swapped. The tool moves each call's
  arguments with the parameters, by position or by label.
- A removed parameter is checked against its uses first; a removed
  argument is removed at every call, wherever it is written.
- A renamed field is found in literals, accesses, and f-string holes,
  and not in other structs' fields of the same name.
- A new variant is the change that breaks every `match` far away from
  the enum. The tool finds them (`refactor variant` without arms is a
  free list of them), and adds the arms in the same checked edit as the
  variant, so the program never stops compiling.
