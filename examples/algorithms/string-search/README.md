# String search: naive, KMP, Boyer-Moore-Horspool

Three ways to find every occurrence of a pattern in a text, run on 16
MiB of generated text with six patterns, checked against each other:
about 1 GB/s each, as fast as the same loops in C.

```sh
tachyonc examples/algorithms/string-search/main.tach -o search && ./search
```

## The problem

Given a text `t` of `n` bytes and a pattern `p` of `m` bytes, report
every position `i` where `t[i..i + m] == p`, overlapping occurrences
included (`abab` occurs twice in `ababab`).

The text is generated: words of 1 to 8 letters from `a` to `h`, from a
seeded generator (xorshift64*), so every run searches the same bytes and
prints the same counts. A small alphabet is the hard case for string
search: partial matches are frequent, and skip tables skip little.

## The algorithms

**Naive.** Try every position, compare the window with the pattern.
Usually the first byte already differs, so it is close to O(n) on text
like this one; on `aaaa...a` searched for `aaa...ab` it is O(n m).

**Knuth-Morris-Pratt.** Precompute the *failure function*: `fail[j]` is
the length of the longest proper prefix of `p[..j + 1]` that is also a
suffix of it. For `abacab`:

```text
pattern   a b a c a b
failure   0 0 1 0 1 2
```

Scan the text once, keeping `k`, the number of pattern bytes matched so
far. On a mismatch, the last `k` text bytes equal `p[..k]`, so the
longest shorter prefix that can still match is `fail[k - 1]` bytes: fall
back to it, never re-reading the text. After a full match, continue
from `fail[m - 1]`, which finds overlapping matches. Each step either
advances in the text or shrinks `k`, so the scan is O(n) whatever the
input.

**Boyer-Moore-Horspool.** Compare the *last* byte of the window first.
Whether it matches or not, slide the window so that this byte lines up
with its last occurrence in `p[..m - 1]`, or past it entirely if it does
not occur. The shift table has one entry per byte value. On a large
alphabet most windows are skipped by up to `m` bytes, so it reads a
fraction of the text; with 9 distinct bytes, as here, the shifts are
short and its advantage small.

| | preprocessing | search, worst | search, typical | memory |
|---|---|---|---|---|
| naive | none | O(n m) | O(n) | O(1) |
| KMP | O(m) | O(n) | O(n) | O(m) |
| Horspool | O(m + 256) | O(n m) | O(n / m) on large alphabets | O(256) |

## The code

**A trait for the searchers.** Each one implements `each_match`, which
calls a closure with every match position; `count` is a default method
written once on top of it. The closure parameter is generic (`F:
FnMut(i64)`), so each use is its own instance with the closure inlined:
counting compiles to a loop with an increment, no call per match.

```tach
trait Searcher {
    fn each_match<F: FnMut(i64)>(self: *Self, text: [u8], found: F);

    fn count(self: *Self, text: [u8]) -> i64 {
        let mut n = 0;
        self.each_match(text, |_| { n += 1; });   // `let mut n`: captured by reference
        n
    }
}
```

The demo collects positions with another closure, `|i| at.push(i)`, and
prints the `Vec` with `{at:?}`.

**Naive** compares the first byte, then the window as a slice: `==` on
two `[u8]` compares their bytes.

```tach
for i in 0..text.len - m + 1 {
    if text[i] == first && text[i..i + m] == pat { found(i); }
}
```

**KMP** builds the failure table in a `Vec` (`Vec::filled_in(m, 0, gpa)`) and
writes it through a slice; the search is the same loop over the text:

```tach
for i in 0..text.len {
    let b = text[i];
    while k > 0 && b != pat[k] { k = f[k - 1]; }
    if b == pat[k] { k += 1; }
    if k == m {
        found(i + 1 - m);
        k = f[m - 1];                  // overlapping matches too
    }
}
```

**Horspool** keeps its shift table as an array value, `[i64; 256]`,
inside the struct, indexed by a byte (`shift[b]`: any integer type
indexes):

```tach
let mut shift = [m; 256];
for j in 0..m - 1 { shift[pat[j]] = m - 1 - j; }
...
while i + m <= text.len {
    let b = text[i + m - 1];
    if b == last && text[i..i + m - 1] == head { found(i); }
    i += self.shift[b];
}
```

**The driver** runs each searcher on each pattern through a generic
`timed<S: Searcher>`, which adds the time to a slot of `times` (passed
as `&times[k]`, a pointer to an array element), and stops with exit
status 1 if the counts disagree. The word count is an iterator,
`t.iter().filter(|b| b == ' ').count()`.

## Output

```text
pattern   a b a c a b
failure   0 0 1 0 1 2
text      abacabacab abacab
matches   ^   ^      ^
3 matches at [0, 4, 11]

text: 16777216 bytes, 3049638 words, letters a-h
pattern       matches
bad             15520
face             1414
hhhh             1425
a bad             582
decade              5
cabbage             0
naive, kmp and horspool agree
```

and on stderr each searcher's total time over the six patterns (the
numbers vary):

```text
naive       92.1 ms    1093 MB/s
kmp        164.7 ms     611 MB/s
horspool    82.8 ms    1216 MB/s
```

## Performance

[`reference.c`](reference.c) is the same program in C (the same text,
patterns and algorithms, `memcmp` for the window comparisons). Total
time over the six patterns (100 MB searched by each), Apple M-series:

| | naive | KMP | Horspool |
|---|---|---|---|
| tachyon 0.15, `-O2` (the default) | 92 ms | 165 ms | 83 ms |
| tachyon 0.15, `-O1` | 98 ms | 160 ms | 86 ms |
| tachyon 0.15, `-O0` | 360 ms | 360 ms | 280 ms |
| C, `clang -O2` | 95 ms | 190 ms | 75 ms |

The tachyon versions check every index and slice; the C ones check
none. KMP is the slowest here although it reads each byte once: its
inner loop has a data-dependent branch per byte (the `while` and the
two `if`s), where the naive search mostly runs a predictable "first byte
differs" loop. KMP's value is its guarantee: try the pattern `aaaaab` on
a text of `a`s, where the naive search and Horspool do `m` comparisons
per position and KMP still one.

## Language features

| feature | where | guide |
|---|---|---|
| a trait with a generic method and a default method | `Searcher` | `tachyonc guide traits` |
| closures as `FnMut` arguments, capturing `let mut` by reference | `count`, `demo` | `tachyonc guide closures` |
| generic functions bounded by a trait | `timed<S: Searcher>` | `tachyonc guide generics` |
| `[u8]` slices, slicing, `==` by bytes | the searchers | `tachyonc guide types` |
| arrays as values, `[m; 256]`, indexed by a `u8` | `Horspool` | `tachyonc guide types` |
| iterators: `iter().filter(..).count()`, `fail.iter()` | `main`, `demo` | `tachyonc guide iterators` |
| f-strings: `{pat:<12}`, `{n:>8}`, `{b:c}`, `{v:?}`, `{x:>6.1}` | output | `tachyonc guide formatting` |
| `defer` inside a loop body (runs each iteration) | `main` | `tachyonc guide memory` |
| a C header for the clock | `now_ns` | `tachyonc guide c-interop` |

## Try

- Widen the alphabet in `generate_text` (`rng.range(0, 25)`): Horspool
  pulls ahead as its shifts grow.
- Search for `"aaaaab"` in a text of `a`s and compare the three times.
- Add a fourth searcher, e.g. Rabin-Karp with a rolling hash: implement
  `Searcher` and add it to the `counts` array.
