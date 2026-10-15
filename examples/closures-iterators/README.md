# closures-iterators

A log-file analyzer: reads a web server's access log on stdin and prints
a report (levels, status codes, latency, the slowest requests, traffic
per service). Nearly every step is a chain of iterator adapters with
closures, the way it would be written in Rust, and the program defines
an iterator of its own.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o closures-iterators
./closures-iterators < access.log
```

`access.log` is a sample. A line is `TIME LEVEL SERVICE STATUS MILLIS
PATH`; blank lines and `#` comments are skipped, and lines that do not
parse are counted:

```text
09:00:02 WARN api 429 3 /users
09:00:03 ERROR db 500 950 /orders
```

## Expected output

```text
14 requests, 1 malformed line(s) skipped
levels: 2 errors, 2 warnings
status: 10 ok, 4 failed
latency: min 2 ms, max 1200 ms, mean 200 ms
any 5xx: true, all under a second: false
first error: request #6 at 09:00:03, db /orders (500)
slow requests (over 100 ms): 5, the top 3:
  1. 1200 ms  api   /reports
  2.  950 ms  db    /orders
  3.  220 ms  api   /orders
requests per service:
  api      6  ######  mean 277 ms
  auth     3  ###     mean 12 ms
  web      3  ###     mean 4 ms
  db       2  ##      mean 545 ms
back-to-back requests in the same second: 5
```

## How it works

**An iterator of our own.** `Iterator` is a prelude trait with one
required method, `next`, and an associated type, `Item`. `Lines` yields
the lines of a text as views into it (slices, no copies); once it
implements `next` it has every adapter (`filter`, `map`, `for_each`...)
for free:

```tach
struct Lines { text: [u8], pos: i64 }

impl Iterator for Lines {
    type Item = [u8];

    fn next(self: *Lines) -> Option<[u8]> {
        if self.pos >= self.text.len { return None; }
        let start = self.pos;
        while self.pos < self.text.len && self.text[self.pos] != '\n' { self.pos += 1; }
        let line = self.text[start..self.pos];
        self.pos += 1; // past the '\n'
        Some(line)
    }
}
```

**Closures that change their surroundings.** Parsing is a `filter` and a
`for_each`. The second closure pushes onto `entries` and counts `bad`
lines: both are `let mut`, so the closure captures them *by reference*
and its changes are seen after the chain. (A plain `let` is captured by
value, a copy; `move |..|` copies everything.)

```tach
let mut entries: Vec<Entry> = Vec::new();
defer entries.free();
let mut bad = 0;
Lines::new(input.as_slice())
    .filter(|l| l.len > 0 && l[0] != '#')
    .for_each(|l| {
        match parse_entry(l) {
            Some(e) => entries.push(e),
            None => bad += 1,
        }
    });
```

`parse_entry` returns an `Option<Entry>` and uses `?` on each field, so
any missing or malformed field makes the whole line `None`
(`parse_int(..).ok()?` turns the `Result` into an `Option` first).

**Consumers** reduce a chain to a value: `count`, `sum`, `min`, `max`
(an `Option`, empty for no items), and `fold`, here with a tuple
accumulator destructured in the closure's parameter list:

```tach
let total_ms = all.iter().map(|e| e.millis).sum();
let slowest = all.iter().map(|e| e.millis).max().unwrap_or(0);
let (ok, failed) = all.iter().fold((0, 0), |(ok, failed), e| {
    if e.status < 400 { (ok + 1, failed) } else { (ok, failed + 1) }
});
```

`any`, `all` and `position` answer questions, stopping at the first
item that decides them.

**Generic functions take closures** through `Fn`/`FnMut` bounds. Each
closure has its own unnamed type, so `count_where` is instantiated once
per closure and the call is direct, usually inlined:

```tach
fn count_where<F: Fn(Entry) -> bool>(entries: [Entry], pred: F) -> i64 {
    entries.iter().filter(pred).count()
}

let errors = count_where(all, |e| e.level == Level::Error);
```

Inside the call the closure's parameter type comes from the bound. A
closure kept in a `let` has no bound to learn from, so its parameter is
annotated: `let is_slow = |e: Entry| e.millis > limit;`.

**collect, sort_by, enumerate, take.** `collect()` makes a `Vec` of the
items (freed with `defer`); `sort_by` sorts it in place by a comparison
of two pointers returning negative, zero or positive, so `b.cmp(a)`
sorts descending:

```tach
let mut slow = all.iter().filter(is_slow).collect();
defer slow.free();
slow.sort_by(|a, b| b.millis.cmp(&a.millis)); // slowest first
for (rank, e) in slow.iter().enumerate().take(3) {
    println(f"  {rank + 1}. {e.millis:>4} ms  {e.service:<5} {e.path}");
}
```

**Counting with a HashMap.** `get_or_insert(key, 0)` is Rust's
`entry(key).or_insert(0)`: it returns the value in place, as a
one-element slice, so `[0] += 1` increments it. The map's `(key, value)`
pairs are then collected and sorted by count, then by name:

```tach
for e in all { per_service.get_or_insert(e.service, 0)[0] += 1; }
let mut ranked = per_service.iter().collect();
defer ranked.free();
ranked.sort_by(|a, b| {
    let (name_a, n_a) = *a; // a and b point into the Vec: *([u8], i64)
    let (name_b, n_b) = *b;
    if n_a != n_b { n_b - n_a } else { name_a.cmp(&name_b) }
});
```

**zip** walks two iterators in step, ending with the shorter one;
zipping the entries with `all[1..]` pairs each request with the next.

## Language features

- closures, captures by value and by reference, `Fn`/`FnMut` bounds: `tachyonc guide closures`
- `Iterator`, `type Item`, adapters and consumers, `sort_by`: `tachyonc guide iterators`
- `Option` and `?`, `.ok()`: `tachyonc guide conversions`
- `HashMap`, `split_whitespace`, `parse_int`, `read_stdin`: `tachyonc guide std`
- f-string specs (`{n:>3}`, `{service:<6}`): `tachyonc guide formatting`
- `#[derive(Eq, Debug)]` on an enum: `tachyonc guide formatting`

## Going further

What Rust has that tachyon does not (yet), and what to write instead:

- `iter_mut`: loop over indices, `v.set(i, v.get(i) * 2)`.
- `rev`, `step_by`, `chain`, `flat_map`, `peekable`: write the loop, or
  an iterator of your own like `Lines`.
- `collect::<HashMap<..>>()`: `collect` always makes a `Vec`; fill a map
  with a `for` loop.
- `a.1` on a pointer to a tuple: write `(*a).1` or destructure `*a`.
- Returning a closure or an iterator built from one (`impl Fn`,
  `impl Iterator`): pass closures *in* through generic parameters.
