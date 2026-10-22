# Big integers: schoolbook and Karatsuba

Arbitrary-precision natural numbers in base 10^9, with `+`, `-` and `*`
as operators: 1000!, the Fibonacci number F(10000) two ways, and
F(1000000), a 208,988-digit number, by fast doubling in about 45 ms.
Multiplication switches from the schoolbook method to Karatsuba's
O(n^1.585) splitting above 96 limbs.

```sh
volec examples/algorithms/bigint/main.vl -o bigint && ./bigint
```

## The problem

Machine integers stop at 2^64. Exact arithmetic on larger numbers (the
1000! of combinatorics, the keys of cryptography, the digits of
constants) stores a number as an array of *limbs*, digits in a large
base, and implements the operations over those arrays.

Addition and subtraction are linear. Multiplication is the interesting
one: the schoolbook method takes n^2 limb products for two n-limb
numbers, which for F(1000000) (23,221 limbs) is about 540 million
products per multiplication, and fast doubling does several dozen of
them.

## The algorithm

**Limbs.** A number is `x = x0 + x1 B + x2 B^2 + ...` with `B = 10^9`
and each limb `0 <= xi < B` stored in a `u32`, least significant first.
Base 10^9 is the largest power of ten whose limb products (< 10^18) fit
in a `u64`; it makes printing in decimal free, since each limb is
exactly nine digits.

**Numbers are polynomials.** Read the limbs as the coefficients of a
polynomial `X(t) = x0 + x1 t + x2 t^2 + ...`: the number is `X(B)`.
Multiplying two numbers is multiplying two polynomials (a convolution
of the coefficient arrays) and then carrying, which evaluates the
product polynomial at `t = B`. Every fast multiplication method, from
Karatsuba to the FFT, is a fast polynomial multiplication; this example
is the FFT-free one.

**Schoolbook**: every limb of `a` times every limb of `b`, added at
column `i + j`. Here the columns are `u64` accumulators and the carries
wait: a product is below 10^18 and a `u64` holds about 18 of them, so 16
rows are added with no division at all, then one pass brings every
column back below `B`. The inner loop is one multiply-add.

**Karatsuba**: split each operand at `m` limbs, `a = a1 B^m + a0` and
`b = b1 B^m + b0`. Then

```text
a b = a1 b1 B^2m + (a1 b0 + a0 b1) B^m + a0 b0
a1 b0 + a0 b1 = (a0 + a1)(b0 + b1) - a0 b0 - a1 b1
```

so three half-size products (`z0 = a0 b0`, `z2 = a1 b1`,
`p = (a0 + a1)(b0 + b1)`) replace four, applied recursively:
`T(n) = 3 T(n/2) + O(n)`, which is O(n^log2(3)) = O(n^1.585). Below 96
limbs the schoolbook kernel is faster and takes over.

**Fast doubling** computes Fibonacci numbers from the top bit of `n`
down, with

```text
F(2k)     = F(k) (2 F(k+1) - F(k))
F(2k + 1) = F(k)^2 + F(k+1)^2
```

so F(n) takes O(log n) big multiplications, the last ones the largest:
the total cost is a small multiple of one full-size product.

| | time | memory |
|---|---|---|
| add, subtract | O(n) | O(n) |
| schoolbook product | O(n m) | O(n + m) |
| Karatsuba product | O(n^1.585) | O(n) (the temporaries halve at each level) |
| n!, one factor at a time | O(n^2 log n) digit operations | O(n log n) |
| F(n) by fast doubling | O(M(n)), M the cost of one product | O(n) |

## The code

**The kernels** work on slices of limbs, `[u32]`, so the recursion can
pass halves of numbers without copying them (`a[..m]` is a view). The
schoolbook kernel's inner loop is a multiply-add on a `u64` column; the
`u32` limb widens to `u64` by itself:

```tach
for row in i..end {
    let ai: u64 = a[row];
    inout out = &acc[row..row + b.len()];
    for j in 0..b.len() { out[j] += ai * b[j]; }
}
```

`out` is a writable slice of the accumulator (an `inout` access: a
plain `[T]` is read-only): indexing it is checked against its length once per row,
outside the inner loop.

**Karatsuba** writes `z0` and `z2` straight into the two halves of the
result, then makes `p`, subtracts them from it, and adds what is left in
the middle:

```tach
let m = a.len() / 2;                // b.len > m: both halves are there
let (a0, a1) = (a[..m], a[m..]);
let (b0, b1) = (b[..m], b[m..]);
mul_karatsuba(a0, b0, &r[..2 * m], gpa);  // z0, in place
mul_karatsuba(a1, b1, &r[2 * m..], gpa);  // z2, in place
let sa = sum_of(a0, a1, gpa);
let sb = sum_of(b0, b1, gpa);
...
mul_karatsuba(sa.as_slice(), sb.as_slice(), p, gpa);
sub_from(p, r[..2 * m]);            // p - z0
sub_from(p, r[2 * m..]);            // p - z0 - z2 = a0 b1 + a1 b0
add_at(r, trimmed(p), m);
```

A lopsided product (one operand at least twice as long) is cut into
pieces of the shorter one's length first, so the halves always both
exist.

**`BigUint`** wraps the limbs. `#[derive(Eq, Clone, Debug)]` gives `==`
(by contents: a `Vec` compares its elements), a deep `clone` and the
`{x:?}` that prints `BigUint { limbs: [480000000, ...] }`. `Ord` is
written by hand, because a longer number is larger whatever its limbs
say; with it, `self < other` works:

```tach
#[derive(Eq, Clone, Debug)]
struct BigUint { limbs: Vec<u32> }

impl Ord for BigUint {
    fn cmp(self, other: BigUint) -> i64 {
        let (a, b) = (self.limbs.as_slice(), other.limbs.as_slice());
        if a.len() != b.len() { return a.len() - b.len(); }
        ...
    }
}
```

**The arithmetic** is three methods that read their operands (`let`,
the default) and return a new number, `a.plus(b)`, `a.minus(b)` and
`a.times(b)`. A
method takes no allocator, so the result is allocated where the left
operand's limbs are: a `Vec` carries its allocator
(`self.limbs.allocator()`). A number from a `u64` has no operand to ask,
so it is `BigUint::from_u64(x, gpa)` rather than `From<u64>`:

```tach
fn times(self, other: BigUint) -> BigUint {
    // (the result is allocated where self's limbs are)
    let gpa = self.limbs.allocator();
    var r = Vec::filled_in(self.limbs.len() + other.limbs.len(), 0u32, gpa);
    mul_karatsuba(self.limbs.as_slice(), other.limbs.as_slice(), r.as_mut_slice(), gpa);
    BigUint::from_limbs(r)
}
```

**The operators** are the prelude's `Add`, `Sub` and `Mul`, on top of
them. Their traits take both operands `let` (0.20), so `a * b` reads `a`
and `b` as `a.times(b)` does, and both can be used again; a temporary, as
in the product tree's `product(lo, mid, gpa) * product(mid + 1, hi, gpa)`,
is dropped after the call:

```tach
impl Mul for BigUint {
    fn mul(self, other: BigUint) -> BigUint { self.times(other) }
}
```

**Who frees what.** Nobody, by hand: a `BigUint` owns its limbs, and
each one is dropped at the end of its scope (or when it is moved into a
`sink` parameter, whose callee drops it). Fast doubling makes six numbers per step and
keeps two, with no `free` in sight:

```tach
let twice = b.plus(b);
let diff = twice.minus(a);
let sq_a = a.times(a);
let sq_b = b.times(b);
let even = a.times(diff);           // F(2k)
let odd = sq_a.plus(sq_b);          // F(2k + 1)
...
a = even;                           // the old a is dropped here
b = odd;
```

**Display** prints the top limb as it is and every other one as exactly
nine digits, with an f-string spec (`{x:09}`: zero-padded to 9):

```tach
impl Display for BigUint {
    fn fmt(self, f: inout Fmt) {
        ...
        f.write(f"{s[s.len() - 1]}");
        var i = s.len() - 2;
        while i >= 0 {
            f.write(f"{s[i]:09}");
            i -= 1;
        }
    }
}
```

and any `f"{x}"` then works, `format` included. The digit sum is an
iterator over the limbs with a closure that sums each limb's digits;
the trailing zeros of 1000! are a `fold` over the decimal text that
restarts its count at every nonzero digit:

```tach
let zeros = text.as_slice().iter().fold(0, |n, d| if d == '0' { n + 1 } else { 0 });
```

**The checks**: 1000! by a product tree (balanced halves, so the big
products go through Karatsuba) must equal 1000! one small factor at a
time; F(10000) by fast doubling must equal F(10000) by 10000 additions;
Karatsuba must equal schoolbook on 30 pairs of random numbers of up to
600 limbs and on one pair of 5000 limbs.

## Output

```text
30! = 265252859812191058636308480000000
    33 digits, digit sum 117
    as limbs: BigUint { limbs: [480000000, 58636308, 859812191, 265252] }
1000! = 40238726007709377354...00000000000000000000
    2568 digits, digit sum 10539
    249 trailing zeros
    product tree (Karatsuba) == one at a time: true
F(10000) = 33644764876431783266...66073310059947366875
    2090 digits, digit sum 9123
    fast doubling == additions: true
F(1000000) = 19532821287077577316...68996526838242546875
    208988 digits, digit sum 941172
karatsuba == schoolbook on 30 of 30 random pairs
5000 x 5000 limbs (45000 digits each): equal true, digit sum 404784
```

and on stderr (the times vary):

```text
F(1000000) by fast doubling: 44.5 ms
5000 x 5000 limbs: schoolbook 7.4 ms, karatsuba 2.5 ms
```

The F(1000000) digits and digit sum agree with Python's `int`.

## Performance

[`reference.c`](reference.c) is the same arithmetic in C: the same
base, kernels, threshold, fast doubling and random operands. On an Apple
M-series machine:

| | F(1000000) | 5000 x 5000 schoolbook | 5000 x 5000 Karatsuba |
|---|---|---|---|
| vole 0.15, `-O2` | 44 ms | 7.4 ms | 2.5 ms |
| vole 0.15, `-O1` | 71 ms | 11 ms | 4.2 ms |
| C, `clang -O2` | 24 ms | 4.4 ms | 1.4 ms |
| CPython 3.9 `int` (base 2^30, Karatsuba) | 36 ms | | 2.5 ms (45000 digits) |

The whole program runs in about 60 ms.

The gap with C is one loop: clang vectorizes the schoolbook kernel's
multiply-add (`umlal`, a 32 x 32 -> 64-bit multiply-accumulate on two
lanes), and vole 0.15 compiles it to unrolled scalar `madd`s. The
rest (the carries, the bounds checks, which vole hoists out of the
inner loop) costs little.

What mattered more than the language: the first version carried after
every limb product (`cur % BASE`, `cur / BASE`, compiled to a multiply
by a reciprocal, but still on the critical path) and took 110 ms for
F(1000000) and 47 ms for the 5000-limb schoolbook; deferring the carries
to every 16th row made the kernel five times faster. Raising the
Karatsuba threshold from 40 to 96 limbs, once the kernel was fast, gave
another 10%.

## Language features

| feature | where | guide |
|---|---|---|
| operator traits `Add`, `Sub`, `Mul` (operands `let`); `Ord` by hand gives `<` | `impl ... for BigUint` | `volec guide traits` |
| `let` parameters (the default), `inout [u32]` for slices that are written | `plus`/`minus`/`times`, the kernels | `volec guide memory`, `guide views` |
| `#[derive(Eq, Clone, Debug)]`, `{x:?}` | `BigUint` | `volec guide formatting` |
| `impl Display`, `f.write(f"...")`, `{x:09}` | `Display for BigUint` | `volec guide formatting` |
| a `Vec` carries its allocator: `self.limbs.allocator()` | `BigUint::times` | `volec guide allocators` |
| widening: `u32` limbs into `u64` arithmetic | the kernels | `volec guide conversions` |
| slices as views, sub-slices `a[..m]`, written through | the kernels | `volec guide types`, `guide memory` |
| drops: every number freed at the end of its scope | everywhere | `volec guide memory` |
| closures and iterators: `map`, `sum`, `fold` | `digit_sum`, `main` | `volec guide iterators`, `guide closures` |
| `panic("...")` for a broken precondition, `self < other` from `Ord` | `BigUint::minus` | `volec guide errors` |
| a C header: `import "time.h" as c;` | `now_ns` | `volec guide c-interop` |

## Try

- Change `KARATSUBA_MIN` and watch the 5000-limb Karatsuba time; set it
  to a huge value to get the schoolbook method everywhere.
- Add a squaring kernel: in `a * a` the cross products `a[i] a[j]` and
  `a[j] a[i]` are equal, so half of them suffice. Fast doubling does two
  squares per step.
- Compute F(10^7) (2,089,877 digits); add Toom-3 (five products of a
  third of the size) and compare.
- Add a signed `BigInt` around `BigUint` with `impl Neg`.
