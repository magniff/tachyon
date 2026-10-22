# Editorial review of the Vole Book (book-final)

A working file for the integrator, not part of the book. Line numbers
are book-final's as of this review.

Status: the five branches are merged, README has its full table of
contents, and the applied fixes are committed. On v0.24.0, the whole
book passes except two known cases. One is 10:155, a rejected form that
needs fix25c. The others are three ch 13 `volec test` sessions, where
the property hit `no exit after 10 s` on the overloaded machine; that's
load, not content, so rerun them on an idle machine. With the fix25c
build, chapters 4, 10, 11, 17 and 18 pass. Chapters 4 to 11, 14, 15,
18, 20 and 21 pass on the fix25b, d, e and g builds, except ch 20's
`sync.*` code list (P5).

## Counts

| type | found | applied | pending |
|---|---|---|---|
| accuracy (old behaviour, wrong claims) | 17 | 9 | 8 |
| consistency (project, terms, cross-refs) | 12 | 12 | 0 |
| clarity | 8 | 7 | 1 |
| honesty | 8 | 6 | 2 |
| compiler findings (for the compiler, not the book) | 9 | reported | |

## The worst ten

1. **Word-counter chain broken (ch 11, 17, 18).** Ch 11 said "the
   functions are the ones chapter 7 wrote", but its `count.vl` had
   dropped `trim_punct`, so `dog.` and `dog` were different words. Ch 18
   then wrote a second, different punctuation trimmer. *Applied:* ch 11
   carries chapter 7's `is_word_byte` and `trim_punct`, as private
   helpers (a better `pub` lesson). The prose now says exactly what
   changed (`count_words` → `add_words`, `sorted_counts` → `top` plus
   `truncate`). Ch 17 and ch 18 use the same files and helpers, every
   `cmp_of` is chapter 7's `a.0.cmp(b.0)`, and all their sessions were
   regenerated.
2. **`&text` passed to `str` parameters (11:30, 11:349, 17:57, 18:69,
   18:318, 18:323, 18:404, 18:488, 18:503, 18:511).** This contradicts
   ch 4: `&` marks only inout. v0.24 accepts it silently, and fix25c
   rejects it as `own.readonly` ("'&s' changes 's'"). *Applied:* every
   `&` removed; passes on both compilers.
3. **Closure captures taught by declaration (ch 10).** The table said
   capture depends "only on how the variable was declared" (copy, read,
   change). The rule is the lifetime model, by use. *Applied:* the
   section is rewritten. Let access when the closure reads, inout access
   when it writes, both from creation to last use. It has an allowed and
   a rejected example of each, and the summary and the Python aside are
   updated. The new rejected read (10:155) needs fix25c.
4. **Inout timing missing (ch 4).** *Applied:* a new subsection, "When
   the change begins", follows §3. `add_copies(&list, list.len())` is
   allowed; `add_all(&list, list[..])` is `own.conflict`. Passes on both
   compilers.
5. **"Must be a `var`" stated but unenforced (4:349, 4:604).** v0.24
   accepted `let plays; bump(&plays)` and `let mix; mix.add(..)`. Pending
   P7: show fix25c's `own.readonly`.
6. **Generic slices (9:63-95).** The section says an array can't be
   given to a generic `[T]`, and its `err` block shows that. fix25j-b
   fixes it. Pending P2.
7. **Properties can't take `gpa` (13:537, 18:311, 18:666).** fix25j-b
   lets them. Pending P3.
8. **Absolute safety claims.** "Nothing reads or writes memory it
   shouldn't" (2:298, 6:567) sat beside 30 families of soundness bugs.
   *Applied:* the claims are softened to what a check does. Ch 1 now
   says the rules are the design and the young compiler's gaps are bugs
   that releases fix.
9. **Appendix A errors.** `#[pure]` meant "no panics" (it may panic, ch
   12), `#[views]` and `#[cold]` pointed at chapters that don't teach
   them, and `as` and `&x` were incomplete. *Applied.*
10. **Ch 3, "numbers have no methods".** `3.cmp(4)` works, and ch 7 and
    ch 9 use `cmp`. *Applied:* "few methods".

## Applied (besides the ten)

- README: complete table of contents with one line per chapter; no
  "(outline)" marks; the reading-order note now says that ch 11, 17 and
  18 build on ch 7.
- ch 7: the intro mentions ch 17; "no loop yet that changes elements in
  place" (`for inout` isn't implemented); "two more containers are in
  the prelude".
- ch 9: `.clone()` dropped on the plain `Version`, with a sentence on
  why; a note that `cmp` by subtraction wraps near the ends of `i64`.
- ch 12: `alloc(Arena)` → `alloc(ScopedArena)` for `arena_scope`.
- ch 13: the fuzz session is robust. The checked session elides the
  output with `...`, and one run's output is shown as a text block
  labelled as one run.
- ch 15: "move-only" → "owned" (ch 4's word), in the prose and the
  summary.
- ch 16: ch 17 is called "an agent", as its title says.
- ch 17: a `rows` typo for `top`, a run-on sentence, and `CLAUDE.md`
  dropped from the `AGENTS.md` line. The `min_len` patch now reads
  `if w.len() < min_len`.
- ch 18: "with none of the risk" → "without the risk of a pointer to
  memory that is gone".
- Appendix B: the `try:` example doesn't depend on the generic-slice
  bug; `profile` points to `guide tools`.
- Appendix C: chapter columns (receivers 4, 5; Drop 4, 15; `defer` →
  guide); templates row; "checked everywhere" softened; "a fast
  compiler" → "a compiler that cares about its own speed".

## Pending (apply when the fixer branches merge)

- **P1 (fixer3, fix25c): 10:155** passes on fix25c as is. Fixer3 will
  send the final wording of the closure conflict, in vole's words rather
  than "borrows it mutably". Then paste it into 10:155 and 10:133, and
  reword "The message calls the closure a *view*" (10:141) and
  "'Borrows it mutably' is the compiler's way of saying" (10:174) to
  match.
- **P2 (fix25j-b): ch 9.** Delete "Arrays and generic slices" and its
  `err` block. Write `largest(scores)`, `largest(words)`,
  `largest::<f64>([1.5, 0.5])` and `largest(points)` (9:33-35, 9:334)
  without `[..]`, and drop `[..]` from 21:231-232 where no longer
  needed.
- **P3 (fix25j-b): properties take `gpa: Gpa`.** In 13:413, write
  `fn pop_gives_back_what_push_put(xs: Vec<i64>, gpa: Gpa)` and drop
  `let gpa = xs.allocator();`, both there and in the excerpt at 13:497.
  Replace 13:537-539 with "A property may take `gpa: Gpa`, as a test
  can; it's the test's allocator, not a generated input." Do the same
  at 18:311 (`counts_add_up(bytes: Vec<u8>, gpa: Gpa)`), and drop the
  parenthesis at 18:666-668.
- **P4 (fix25j-b, fix25k): rerun the sessions.** `volec test` summaries
  (13:449-563, 18:672, 18:691); 13:669 may become `volec check
  doubles.vl` (check now reports `test.signature`). The effects outputs
  at 2:543, 8:61, 8:536, 12:107-155, 14:572, 17:232 and 18:704.
- **P5 (fix25b, e, g): 20:121-147.** Paste the new `own.*` list
  (`own.drop_call`) and `sync.*` list (`sync.view_item`,
  `sync.scope_escape`).
- **P6 (fix25c): 15:219-223.** The aside says "the call takes an
  exclusive loan of `xs`". Replace with: "where a raw pointer is
  wanted, `&place` is the place's address. It takes no inout access,
  and writing through it to a `let` would be unsafe code's mistake."
- **P7 (fix25c): ch 4, show `own.readonly`.** After 4:349-350, add the
  `let plays` version with its error (fix25c's output):
  `error[own.readonly]: '&plays' changes 'plays', a let binding: it is
  read-only` / ` --> main.vl: line 7, column 10` / `  = help: declare
  it \`var\` to change it` / `  = try: var plays = ...`. Optionally add
  the receiver case after 4:604 (`'mix.add(..)' changes 'mix', a let
  binding`).
- **P8 (fix25d): ch 10, iterators.**
  - After 10:378, add that `any`, `all`, `find` and `position` stop at
    the item that decides and leave the rest in the iterator (they take
    it `inout`), while the other consumers use it up (`sink self`).
  - After 10:274, add that `v.iter()`'s items are the container's own
    elements, read in place, so keeping an owned one takes `.clone()`
    (as 7:960 already does).
- **P9 (fix25b): temporaries and partial drops.** Optional, in ch 4's
  drops section: "a temporary, a value no variable holds, is dropped at
  the end of the statement that made it". Use a `Noisy` example
  generated on the merged compiler. Nothing in the book relies on the
  old order: all of chapters 4 to 8 and 15 pass on fix25b.
- **P10 (fix25, fix25e): conservative view origins.** No example
  breaks. Optionally add to 4:792 "when the compiler can't tell, it
  assumes a call's result views everything the call was given".
- **P11 (honesty, needs an idle machine).** Re-measure the timings at
  10:570-600, 16:141-145, 16:401-406 and 18:750-766. At 10:556-594,
  consider 5 M elements × 100 rounds instead of a 400 MB `Vec`.

`println` taking `let` (fix25j-a) and Iterator's `sink self` (fix25d)
need no book change: nothing relied on `println` consuming, and every
chain in the book passes on fix25d.

## Decisions (settled by the coordinator)

- Chapter 17's agent section stays. What it said about how vole was
  made is cut: 17:590-596 (that agents built the tools) and 17:644-650
  (the repository's own setup); the hooks are now offered as tools
  to use. `CLAUDE.md` is dropped. The other "AI assistant" mentions
  (ch 1, 11, 12) are about using the tools, and stay.

## Compiler findings (for the compiler, not the book)

1. **Soundness.** `FixedBuf::new(mem: [u8])` writes through a `let`
   slice, and its result doesn't view `mem`. Safe code can overwrite a
   live `Vec`'s elements through `mem` (v0.24 and fix25c; repro sent to
   the coordinator).
2. **Rust-era words in diagnostics.**
   - `own.conflict`: "borrowed mutably by '&list'" (4:429, 4:new),
     "borrows it mutably" (10:155).
   - `sync.global`: "static mut", plus a help showing
     `AtomicI64 { v: 0 }` internals (14:523).
   - The type-error help in 7:318 and 7:481 mentions "`fn f(s: &str)`"
     and "`&str` parameters".
   - `explain` entries use `&mut` and `move`.
3. **`&s` for a `String` given to a `str` parameter.** v0.24 accepts
   it silently, while `&v` given to `[T]` is `conv.marker_extra`.
   fix25c reports it as `own.readonly` "'&s' changes 's'", which
   misleads; it should be `conv.marker_extra` (pass `s`).
4. **`for inout x in &v`** gives a parser error, "'inout' is a keyword
   ... a name cannot be spelled so". It should say it isn't
   implemented yet and suggest an index loop.
5. 11:650: `no method 'output_in' on type '()'` suggests "the nearest:
   'fmt_debug'".
6. 14:258: the help carries a release number, "(0.21.0)".
7. 9:89: `try: largest::<T>(...)` is unhelpful (fix25j-b removes the
   case).
8. A temporary `Vec` isn't coerced to `[T]` on fix25c (`add_all(&list,
   list.clone())`); fix25j-b fixes it.
9. 13: the property's 10 s timeout fires under load. It's a flaky test
   on a busy machine; consider scaling the timeout or reporting it as
   load.
