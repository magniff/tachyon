# Explore unknown code

`transit` plans the quickest routes across a city's train network: a
graph of stations (`graph.tach`), a binary heap (`heap.tach`), Dijkstra's
search with a cost for changing lines (`route.tach`), the timetable
(`network.tach`) and a few trips in `main.tach`. About 300 lines.

A bug report comes in: "Airport to Museum is one 16-minute ride on line
A, but the planner says 21 minutes." This session is the first look of
someone (or some agent) who has never seen the code: what is there,
where the total comes from, who touches what, what a type is, what a
piece of syntax means, all by asking the compiler instead of reading
files from the top. Then the fix, made by name. Every command below is
run by `tests/walkthrough/run.sh` on a fresh copy of this directory, and
its output is checked against this file.

## The symptom

```console
$ tachyonc main.tach -o transit && ./transit
Airport -> Museum: 21 min
  line A  Airport    -> Museum      16 min
Airport -> Market: 25 min
  line A  Airport    -> Central     12 min
  line B  Central    -> Market       3 min
Beach -> Stadium: 41 min
  line C  Beach      -> Harbor      11 min
  line B  Harbor     -> Stadium     20 min
Airport -> Moon: no such station
ok: built transit
```

Every total is 5 minutes more than the legs add up to (10 when the trip
changes lines once).

## 1. What is there

`query items` with no module lists the modules, their files and how many
items each has; with a module, its items' signatures and lines, like a
generated header:

```console
$ tachyonc query items
crate	main.tach	6
std	<std>	575
crate::graph	graph.tach	11
crate::heap	heap.tach	7
crate::network	network.tach	2
crate::route	route.tach	7
std::ops	<std>	5
std::iter	<std>	67
std::slice	<std>	37
std::slice::unstable	<std>	16
std::slice::stable	<std>	22
std::slice::search	<std>	4
std::slice::algo	<std>	12
std::collections	<std>	12
std::collections::hash_map	<std>	27
std::collections::hash_set	<std>	18
std::collections::raw_table	<std>	46
std::collections::btree_node	<std>	56
std::collections::btree_map	<std>	45
std::collections::group	<std>	20
std::io	<std>	12
std::io::error	<std>	17
std::io::buffered	<std>	37
std::fmt	<std>	82
std::num	<std>	83
std::num::tables	<std>	4
std::convert	<std>	2
std::clone	<std>	1
std::random	<std>	17
std::sys	<std>	192
std::time	<std>	40
std::hash	<std>	6
std::hash::fold	<std>	26
std::hash::sip	<std>	14
std::hash::state	<std>	18
std::str	<std>	67
std::unicode	<std>	74
std::unicode::tables	<std>	27
std::string	<std>	153
std::path	<std>	34
std::fs	<std>	59
std::env	<std>	21
std::process	<std>	36
std::arch	<std::arch>	3
std::arch::aarch64	<std::arch::aarch64>	138
std::arch::x86_64	<std::arch::x86_64>	6
std::arch::aarch64::raw	<std::arch::aarch64::raw>	110
std::arch::x86_64::raw	<std::arch::x86_64::raw>	6
$ tachyonc query items route
# crate::route	route.tach
8	const	pub const TRANSFER_MINUTES: i64 = 5
10	struct	pub struct Leg
17	struct	pub struct Route
23	struct	struct Step
30	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64
34	fn	pub fn quickest(g: Graph, from: i64, to: i64, gpa: Gpa) -> Option<Route>
68	fn	fn legs_to(how: Vec<Step>, from: i64, to: i64, gpa: Gpa) -> Vec<Leg>
```

## 2. The function that computes the total

`query context` answers in one call what takes several: the item's
source, the signatures of what it calls (the most specific first), the
types it uses and its callers, cut to a budget of tokens. What did not
fit is counted, with the commands that print it:

```console
$ tachyonc query context quickest --budget 600
// crate::route::quickest	route.tach:34-64	effects: alloc(Gpa) panic diverge
pub fn quickest(g: Graph, from: i64, to: i64, gpa: Gpa) -> Option<Route> {
    let n = size(g);
    var best: Vec<i64> = Vec::filled_in(n, i64::MAX, gpa);
    var how: Vec<Step> = Vec::filled_in(n, Step { from: -1, line: 0, minutes: 0 }, gpa);
    var h = new_heap(gpa);
    defer free_heap(&h);

    best.set(from, 0);
    push(&h, Entry { cost: 0, node: from, line: 0 });
    while !is_empty(h) {
        let cur = pop(&h).unwrap();
        if cur.cost > best.get(cur.node) {
            continue;
        }
        if cur.node == to {
            break;
        }
        for e in edges_from(g, cur.node) {
            let cost = cur.cost + ride_cost(cur.line, e.minutes, e.line);
            if cost < best.get(e.to) {
                best.set(e.to, cost);
                how.set(e.to, Step { from: cur.node, line: e.line, minutes: e.minutes });
                push(&h, Entry { cost: cost, node: e.to, line: e.line });
            }
        }
    }
    if best.get(to) == i64::MAX {
        return None;
    }
    Some(Route { legs: legs_to(how, from, to, gpa), total: best.get(to) })
}
// calls (14)
crate::route::ride_cost	route.tach:30:4	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64
crate::route::legs_to	route.tach:68:4	fn	fn legs_to(how: Vec<Step>, from: i64, to: i64, gpa: Gpa) -> Vec<Leg>
crate::graph::size	graph.tach:21:8	fn	pub fn size(g: Graph) -> i64
crate::heap::new_heap	heap.tach:14:8	fn	pub fn new_heap(gpa: Gpa) -> MinHeap
crate::heap::free_heap	heap.tach:63:8	fn	pub fn free_heap(h: inout MinHeap)
crate::heap::is_empty	heap.tach:18:8	fn	pub fn is_empty(h: MinHeap) -> bool
crate::heap::pop	heap.tach:35:8	fn	pub fn pop(h: inout MinHeap) -> Option<Entry>
crate::graph::edges_from	graph.tach:55:8	fn	pub fn edges_from(g: Graph, i: i64) -> [Edge]
std::Vec::filled_in	<std>:1485:12	method	pub fn filled_in(n: i64, x: sink T, a: sink A) -> Vec<T, A>
crate::heap::push	heap.tach:22:8	fn	pub fn push(h: inout MinHeap, e: Entry)
std::Vec::set	<std>:306:12	method	pub fn set(inout self, i: i64, x: sink T) requires 0 <= i && i < self.len else f"index out of bounds: index {i}, length {self.len}"
std::Option::unwrap	<std>:124:12	method	pub fn unwrap(sink self) -> T requires self.is_some() else "called unwrap on None"
// callers (1)
plan	main.tach:20:11	match quickest(g, a, b, gpa) {
note query.budget: over the budget of 600 tokens, left out: calls 2, types or uses 9
try: tachyonc query context quickest --budget 1800
```

The total is `best.get(to)`, the sum of `ride_cost(...)` along the way.
The context of `ride_cost` is small enough to print whole:

```console
$ tachyonc query context ride_cost
// crate::route::ride_cost	route.tach:29-32	effects: none
// What a ride on `e` costs, arriving at its start on `here_line`.
fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64 {
    if line != here_line { minutes + TRANSFER_MINUTES } else { minutes }
}
// uses (1)
crate::route::TRANSFER_MINUTES	route.tach:8:11	const	pub const TRANSFER_MINUTES: i64 = 5
// callers (1)
route::quickest	route.tach:52:35	let cost = cur.cost + ride_cost(cur.line, e.minutes, e.line);
```

`ride_cost` adds a transfer whenever the ride's line differs from the
line the search arrived on. What line does the search arrive on at the
start?

## 3. Who writes what

`query refs` lists every resolved use, with its kind (`def`, `read`,
`write`, `init` for a struct literal, `call`, ...) and the enclosing
function. `--kind` keeps some kinds:

```console
$ tachyonc query refs Entry.line --kind init
# route.tach
42:43	init	route::quickest	push(&h, Entry { cost: 0, node: from, line: 0 });
56:58	init	route::quickest	push(&h, Entry { cost: cost, node: e.to, line: e.line });
```

The first state is `Entry { ..., line: 0 }`. A search of the comments
says what 0 means (each hit names the item its comment documents, here
the field `Entry.line` and the function `ride_cost`):

```console
$ tachyonc query grep start --comments
# heap.tach
6:48	comment	heap::Entry.line	// the line the state arrived on; 0 at the start
# route.tach
29:46	comment	route::ride_cost	// What a ride on `e` costs, arriving at its start on `here_line`.
```

And `query type` gives the type of the expression at a position (here
`cur`, on line 46, and the `e.minutes` passed to `ride_cost`):

```console
$ tachyonc query type route.tach:46:13
!	continue
$ tachyonc query type route.tach:54:58
()	{ best.set(e.to, cost); how.set(e.to, Step { from: cur.node, line: e.line, minutes: e.minutes }); p…
```

So at the start `cur.line` is 0, which is no line, and `ride_cost`
charges a transfer for the first ride. That is the bug.

## 4. Two side questions, answered without leaving the terminal

`main.tach` prints the line with `{l.line:c}`. What does `:c` do? The
guide answers from its own text:

```console
$ tachyonc guide --find 'spec width align' --budget 900 | head -11
# formatting#f-strings
- `{{` and `}}` are a brace; the text takes a string's escapes.
- A hole holds any expression but a top-level `:` (parenthesize it);
  string literals work in it (`{m.get("k"):?}`); f-strings do not nest.
- The holes are evaluated where the f-string is written, once, left to
  right; the value holds copies, so it can be stored and printed later.
- The spec after `:` is `[<|>][0][width][.precision][?|x|X|b|c|e|E]`:
  `<` and `>` align (numbers go right by default, text left), `0` pads
  with zeros, `.N` gives a float N decimals, `?` is Debug, `x`/`X` hex,
  `b` binary, `c` a `u8` as its byte (a `u8` is a number otherwise),
  `e`/`E` a float with an exponent (0.20: `1.5e3`).
```

And the fix's condition, tried on a snippet before it goes in (`try`
runs statements with std imported and prints the last value with its
type):

```console
$ tachyonc try 'println(f"[{65u8:c}] [{65u8}]")'
[A] [65]
$ tachyonc try 'let here: u8 = 0; let line = 65u8; here != 0 && line != here'
bool = false
```

## 5. The fix

Before changing a function, what does the change touch? `query impact`
lists the calls by file, `query callers` each call:

```console
$ tachyonc query impact ride_cost
crate::route::ride_cost	route.tach:30:4	fn	fn ride_cost(here_line: u8, minutes: i64, line: u8) -> i64	effects: none
route.tach	1	0	route::quickest
total	1	0	1 file
```

One call, in the same module. The fix is one condition, changed by name:

```console
$ tachyonc edit patch ride_cost --old 'if line != here_line' --new 'if here_line != 0 && line != here_line' --show
patched crate::route::ride_cost	route.tach	+1 -1 lines
// route.tach:31
31	    if here_line != 0 && line != here_line { minutes + TRANSFER_MINUTES } else { minutes }
$ tachyonc main.tach -o transit && ./transit
Airport -> Museum: 16 min
  line A  Airport    -> Museum      16 min
Airport -> Market: 20 min
  line A  Airport    -> Central     12 min
  line B  Central    -> Market       3 min
Beach -> Stadium: 36 min
  line C  Beach      -> Harbor      11 min
  line B  Harbor     -> Stadium     20 min
Airport -> Moon: no such station
ok: built transit
```

Airport to Museum is 16 minutes, Airport to Market 20 (12, a change, 3).

## Why not by hand

The usual first look is `ls`, `cat route.tach`, `grep -rn ride_cost`,
`grep -rn 'line: 0'`, then reading 300 lines to be sure nothing else
writes the line. Here every answer was exact and short:

- `query context` gave the function, what it calls and its callers in
  one answer of a known size, instead of three files opened to follow
  the calls;
- `query refs --kind init` found the struct literals that set the
  field, which no text search for `line` (33 matches: fields of four
  structs, two parameters, comments, a format string) separates from
  the rest;
- `query type` and `try` answered questions that a reader would
  otherwise settle by reasoning or by a throwaway program;
- the guide answered the syntax question from the compiler's own
  documentation, for this version of the language.

On a program of this size, reading it whole once is also reasonable
(`tachyonc query show route.tach` prints a file); the queries pay off as
the program grows, and they cost the same at 300 lines as at 30,000.
