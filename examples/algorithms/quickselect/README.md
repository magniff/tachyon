# Selection: quickselect and median of medians

The k-th smallest of n values, without sorting them: quickselect, fast
in practice, and median of medians, linear even in the worst case. Both
are generic over any `T: Ord`; on 2 million values they find seven
ranks (minimum, percentiles, median, maximum) in 26 ms and 176 ms,
against 94 ms for sorting, and agree with the sorted order.

```sh
volec examples/algorithms/quickselect/main.vl -o select && ./select
```

## The problem

Given n values and a rank k (0 is the smallest, n - 1 the largest),
find the value that would be at position k if the values were sorted:
the median is k = n / 2, the 99th percentile k = 99n / 100. Sorting
answers it in O(n log n); selection does it in O(n), because it only
needs to know which side of a pivot k is on, not the order within each
side.

The input is 2 million values in 0..=999,999,999 from a seeded generator
(xorshift64*), so every run gives the same answers, plus five ordered
inputs of a million values (sorted, reversed, all equal, organ pipe,
sawtooth), the classic traps for pivot choice.

## The algorithms

**Quickselect** (Hoare, 1961) is quicksort that recurses into one side
only. Partition the values around a pivot: smaller ones to the left,
larger ones to the right. If position k is on the left, continue there;
else on the right. With pivots that split well, the work is n + n/2 +
n/4 + ... = 2n.

- The pivot is the median of the first, middle and last values. It
  splits sorted and reversed input exactly in half, where taking the
  first or last value as the pivot would split off one value per round:
  n^2 / 2 steps, 5 * 10^11 for the million-value inputs here.
- Hoare's partition scans from both ends and stops on values *equal*
  to the pivot from both sides, so a run of equal values (the "all
  equal" input) is split in half too, instead of all going to one side.
- Inputs built to defeat median-of-three exist ("median-of-3 killers",
  Musser 1997): quickselect stays O(n^2) in the worst case. A random
  pivot makes that unlikely for any input; median of medians makes it
  impossible.

**Median of medians** (Blum, Floyd, Pratt, Rivest, Tarjan, 1973)
chooses a pivot that is guaranteed to be good. Split the values into
groups of five, take each group's median, and find the median of those
n/5 medians by calling the selection itself. At least half of the
groups have a median no larger than the pivot, and each of them has 3
values no larger than its median: at least 3/10 of all values are no
larger than the pivot, and as many no smaller. Each round keeps at most
7/10 of the values, so

    T(n) <= T(n/5) + T(7n/10) + O(n) = O(n),   since 1/5 + 7/10 < 1.

The constant is large (sorting the groups, the recursive call, the
three-way partition), which is why it is slower than quickselect here,
and slower than sorting for seven ranks; its value is the guarantee,
and libraries use it as a fallback: C++'s `std::nth_element` is an
*introselect*, quickselect that switches to a linear method when the
recursion goes too deep.

| | time, average | time, worst | memory |
|---|---|---|---|
| sort, then index | O(n log n) | O(n log n) | in place |
| quickselect, median-of-three | O(n) | O(n^2) | in place, O(1) |
| median of medians | O(n) | O(n) | in place, O(log n) stack |

## The code

**Quickselect** narrows a window `lo..=hi` that holds position k. The
median of three is sorted into `s[lo]`, `s[mid]`, `s[hi]` with three
compare-and-swaps; the partition is Hoare's, with `loop` and `while`
standing in for C's `do ... while`:

```tach
fn quickselect<T: Ord>(s: inout [T], k: i64) -> T {
    var lo = 0;
    var hi = s.len() - 1;
    while lo < hi {
        let mid = lo + (hi - lo) / 2;
        if s[mid] < s[lo] { swap(s, mid, lo); }
        if s[hi] < s[lo] { swap(s, hi, lo); }
        if s[hi] < s[mid] { swap(s, hi, mid); }
        let pivot = s[mid];
        var i = lo - 1;
        var j = hi + 1;
        loop {
            i += 1;
            while s[i] < pivot { i += 1; }
            j -= 1;
            while pivot < s[j] { j -= 1; }
            if i >= j { break; }
            swap(s, i, j);
        }
        if k <= j { hi = j; } else { lo = j + 1; }
    }
    s[k]
}
```

`<` on a `T: Ord` is `cmp`; for `i64` it compiles to one compare
instruction. `s` is an `inout [T]`, a writable view, so `swap(s, i, j)`
writes the caller's values.

**Median of medians** keeps its window as a slice and narrows it by
re-slicing, `w = &w[..lt]` or `w = &w[gt..]` (`&`: the view stays
writable): no index bookkeeping. The
groups' medians are swapped to the front, and the recursive call
selects their median in place:

```tach
let groups = w.len() / 5;
for g in 0..groups {             // each group's median to the front
    let a = 5 * g;
    insertion_sort(&w[a..a + 5]);
    swap(w, g, a + 2);
}
let pivot = median_of_medians(&w[..groups], groups / 2);
let (lt, gt) = partition3(w, pivot);
if k < lt {
    w = &w[..lt];
} else if k < gt {
    return pivot;
} else {
    w = &w[gt..];
    k -= gt;
}
```

`partition3` is Dijkstra's three-way ("Dutch national flag") partition
and returns a tuple, destructured by the `let`. Separating the values
equal to the pivot guarantees progress when many values are equal.

**The driver** runs the three methods through one generic function,
which takes the selection as a closure, `F: FnMut(inout [i64], i64) -> i64`,
and collects the seven answers with an iterator:

```tach
let found = ks.iter().map(|k| select(work.as_mut_slice(), k)).collect_in(gpa);
```

The sorting "method" is a closure too; it sorts on its first call and
then only reads. Its flag is a `var` outside the closure, which the
closure captures and changes in place:

```tach
var sorted = false;
var by_sort = ranks("sort", data.as_slice(), ks[..], |s, k| {
    if !sorted {
        std::sort(s);
        sorted = true;
    }
    s[k]
});
```

The answers are compared as whole `Vec`s (`by_quick != by_sort`
compares contents). The ordered inputs are built with ranges as
iterators, `(0..m).map(|i| m - 1 - i).collect_in(gpa)`, kept in a
`Vec<([u8], Vec<i64>, i64)>` of (name, values, expected median), and
each is checked on two `clone()`s, since both algorithms reorder their
input.

## Output

```text
2000000 values in 0..=999999999 from a seeded generator
rank           k      value
min            0        456
p1         20000    7097249
p10       200000   71497697
median   1000000  462476623
p90      1800000  892412622
p99      1980000  989173028
max      1999999  999999515
quickselect, median of medians and sort agree

sorted         median  500000 ok
reversed       median  500000 ok
all equal      median       7 ok
organ pipe     median  250000 ok
sawtooth       median     500 ok
```

and on stderr the time each method took for the seven ranks (they
vary):

```text
quickselect          26.15 ms
median of medians   175.95 ms
sort                 94.34 ms
```

## Performance

[`reference.c`](reference.c) is the same program in C: the same values
and algorithms (written for `int64_t`), and `qsort` for the sorted
baseline. The seven ranks of 2 million values, Apple M-series:

| | quickselect | median of medians | sort |
|---|---|---|---|
| vole 0.15, `-O2` (the default) | 26 ms | 176 ms | 94 ms (`std::sort`) |
| vole 0.15, `-O1` | 24 ms | 213 ms | 95 ms |
| vole 0.15, `-O0` | 87 ms | 921 ms | 302 ms |
| C, `clang -O2` | 24 ms | 154 ms | 137 ms (`qsort`) |

The generic vole functions, instantiated for `i64`, are within 1.15x
of the hand-specialized C, with every index checked. `std::sort` beats
`qsort` because it is generic too: the comparison is inlined, where
`qsort` calls a function pointer per comparison.

## Language features

| feature | where | guide |
|---|---|---|
| generic functions with a bound: `<T: Ord>`, `<` through `cmp` | `quickselect`, `median_of_medians`, `partition3` | `volec guide generics`, `guide traits` |
| `inout [T]` views, written through, re-sliced: `w = &w[gt..]` | `median_of_medians` | `volec guide types`, `guide memory` |
| tuples returned and destructured, in a `Vec` and in `for` | `partition3`, `main` | `volec guide syntax` |
| closures as `FnMut` arguments, a `var` captured and changed | `ranks`, `main` | `volec guide closures` |
| iterators: ranges as values, `map`, `collect`, `enumerate` | `ranks`, `main` | `volec guide iterators` |
| `clone()` of a `Vec`, `==` / `!=` on `Vec` contents | `check_median`, `main` | `volec guide formatting`, `guide std` |
| `defer` in a loop body | `main` | `volec guide memory` |
| f-strings with alignment, an `if` inside a hole | output | `volec guide formatting` |

## Try

- Replace the median of three with `let pivot = s[lo];` and run the
  "sorted" input with a smaller `m` (say 20,000): watch quickselect go
  quadratic while median of medians does not notice.
- Write `introselect`: quickselect that counts its rounds and calls
  `median_of_medians` on the window after 2 log2(n) of them.
- Select on another type: `quickselect` works unchanged on a slice of
  `#[derive(Eq, Ord)]` structs, or on `[u8]` text.
