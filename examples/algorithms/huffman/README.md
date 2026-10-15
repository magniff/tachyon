# Huffman coding

A complete Huffman coder: byte counts, the tree built with a min-heap,
canonical codes, a bit-packing encoder and a table-driven decoder, with
a round-trip check. 4 MiB of generated text compresses to 47.7% at
about 500 MB/s and decodes at 300 MB/s, within 1.2x of C.

```sh
tachyonc examples/algorithms/huffman/main.tach -o huffman && ./huffman
```

## The problem

Give each byte value a string of bits (its *code*) so that no code is a
prefix of another (the stream can then be cut back into codes without
separators) and the encoded text is as short as possible. Frequent bytes
should get short codes, rare ones long codes.

Huffman's algorithm gives the optimal such code for a known
distribution: no prefix code that codes one byte at a time is shorter.
The bound is the distribution's *entropy*, `-sum p log2 p` bits per
byte, which the program prints next to the result: Huffman is always
within 1 bit per byte of it, and usually much closer (3.817 against
3.799 here).

The inputs are the classic sentence "this is an example of a huffman
tree", whose code table is printed, and 4 MiB of sentences made of 24
common words, picked with a skew toward the first ones by a seeded
generator (xorshift64*), so every run compresses the same bytes.

## The algorithm

1. **Count** each byte value: one pass, 256 counters.
2. **Build the tree.** Every byte that occurs is a one-node tree whose
   weight is its count. Repeatedly take the two lightest trees out of a
   min-heap and put back a tree with both as children, weighing their
   sum, until one tree is left. Each byte's code length is its leaf's
   depth.
3. **Assign canonical codes.** Only the lengths matter; sort the bytes
   by (length, value) and give them consecutive binary numbers, shifting
   left whenever the length grows. With the example's lengths:

   ```text
   ' ' 000   a 001   e 010          length 3: 000, 001, 010
   f 0110   h 0111   ...  t 1100    then (010 + 1) << 1 = 0110, ...
   l 11010  ...  x 11111            then (1100 + 1) << 1 = 11010, ...
   ```

   A decoder rebuilds the same codes from the 256 lengths, so a file
   format stores the lengths, not the tree (DEFLATE does this).
4. **Encode**: append each byte's code to a bit stream.
5. **Decode with a table**: with `L` the longest code, the next `L` bits
   of the stream always start with exactly one code. A table of `2^L`
   entries maps every `L`-bit value to (byte, length): look up, emit the
   byte, consume `length` bits. One lookup per byte, no tree walking.

| step | time | memory |
|---|---|---|
| count | O(n) | 256 counters |
| tree | O(k log k) for k distinct bytes (k <= 256) | O(k) |
| canonical codes | O(k log k) | O(k) |
| encode, decode | O(n) | O(n) output, decode table `2^L` |

## The code

**The heap** is the generic `MinHeap<T: Ord>` of
[`../dijkstra`](../dijkstra), here holding subtrees. A derived `Ord`
compares fields in order, weight first, then the node number, so trees
of equal weight always merge in the same order and the codes do not
depend on the heap's internals:

```tach
#[derive(Eq, Ord, Debug)]
struct Subtree { weight: i64, node: i64 }
```

**The tree** is a `Vec` of child pairs: nodes 0 to 255 are the leaves
(`(-1, -1)`), each merge pushes one more node. The depths come from a
walk with an explicit stack of `(node, depth)` tuples, destructured
right in the `while let`:

```tach
while heap.len() > 1 {
    let a = heap.pop().unwrap();
    let b = heap.pop().unwrap();
    kids.push((a.node, b.node));
    heap.push(Subtree { weight: a.weight + b.weight, node: kids.len() - 1 });
}
...
while let Some((node, depth)) = stack.pop() {
    let (left, right) = kids.get(node);
    if left < 0 { lengths[node] = depth; } else { ... }
}
```

**Canonical codes** sort `(length, byte)` pairs with `std::sort` and
another derived `Ord`, then count upward. Building the codebook returns
a `Result`: a code longer than the decoder's table allows is an error,
`HuffError::CodeTooLong`, which `?` passes up to `main`:

```tach
std::sort(order.as_slice());                   // by the derived Ord
let max_len = order.last().map(|e| e.len).unwrap_or(0);
if max_len > MAX_BITS { return Err(HuffError::CodeTooLong(max_len)); }
...
for e in order.iter() {
    code <<= e.len - prev;
    book.code[e.byte] = code;
    code += 1;
    prev = e.len;
}
```

**The encoder** keeps the bits not yet written in a `u64` accumulator
(fewer than 8 between bytes) and pushes whole bytes:

```tach
for b in text {
    let len = book.len[b];
    acc = (acc << len) | book.code[b];
    bits += len;
    while bits >= 8 {
        bits -= 8;
        out.push((acc >> bits) as u8);
    }
}
```

**The decoder** keeps 57 to 64 bits of the stream in its accumulator and
looks the next `max_len` of them up. A `u8` widens to `u64` in `(acc <<
8) | byte` and a `u32` table entry to `i64` in `have -= e >> 8`, without
casts:

```tach
for _ in 0..count {
    while have <= 56 {                             // refill a byte at a time
        let byte = if pos < bits.len { bits[pos] } else { 0 };
        acc = (acc << 8) | byte;
        pos += 1;
        have += 8;
    }
    let e = t[(acc >> (have - max)) & mask];
    out.push(e as u8);
    have -= e >> 8;
}
```

**Checking and reporting.** `round_trip(text, table: true)` uses a
named argument for its defaulted `table` parameter. The first byte that
differs after the round trip, if any, is found with
`(0..text.len).position(..)` and returned as `HuffError::Mismatch`;
`main` returns `Result<(), HuffError>`, so an error prints
`Error: Mismatch(...)` and exits with status 1. The total bit count is
a `zip` of the lengths and counts folded into a sum; the entropy calls
C's `log2` through `import "math.h"`.

## Output

```text
byte  count  bits  code
' '      7     3  000
 a       4     3  001
 e       4     3  010
 f       3     4  0110
 h       2     4  0111
 i       2     4  1000
 m       2     4  1001
 n       2     4  1010
 s       2     4  1011
 t       2     4  1100
 l       1     5  11010
 o       1     5  11011
 p       1     5  11100
 r       1     5  11101
 u       1     5  11110
 x       1     5  11111
36 bytes, 16 distinct, longest code 5 bits
encoded: 135 bits = 17 bytes, 47.2% of the input
bits per byte: 3.7500 (entropy 3.7142)
checksum of the encoding: cfd30a9398c66bee; decoded == input

"To is with is in for it and a on a. And it in of. The from t"...
4194304 bytes, 31 distinct, longest code 11 bits
encoded: 16010383 bits = 2001298 bytes, 47.7% of the input
bits per byte: 3.8172 (entropy 3.7992)
checksum of the encoding: f581e0f6347dd788; decoded == input
```

and on stderr the times of the big text (they vary):

```text
count + tree + codes:   2.35 ms
encode:   8.79 ms,   477 MB/s
decode:  14.03 ms,   299 MB/s
```

## Performance

[`reference.c`](reference.c) is the same coder in C (the same text,
tree with the same tie-breaking, codes, encoder and decoder; it prints
the same size and checksum). On 4 MiB, Apple M-series:

| | count + tree | encode | decode |
|---|---|---|---|
| tachyon 0.15, `-O2` (the default) | 2.4 ms | 8.7 ms | 14.0 ms |
| tachyon 0.15, `-O1` | 2.1 ms | 10.3 ms | 20.3 ms |
| tachyon 0.15, `-O0` | 9.6 ms | 37.8 ms | 56.7 ms |
| C, `clang -O2` | 2.3 ms | 7.4 ms | 13.1 ms |

The tachyon version checks its indexes and grows its output `Vec` with
`push`; the C one writes into preallocated arrays unchecked.

The encoder was first written with a `BitWriter { out, acc, bits }`
struct and a `put(self: *BitWriter, code, len)` method: 11.0 ms, because
the accumulator then lives in the struct, in memory, instead of in a
register. Keeping the hot state in locals of the loop's function is the
fix (in C too, where the compiler has more freedom to promote it).

## Language features

| feature | where | guide |
|---|---|---|
| `#[derive(Eq, Ord, Debug)]` to order heap entries and sort | `Subtree`, `ByLength`, `HuffError` | `tachyonc guide formatting` |
| generic `MinHeap<T: Ord>`, `?` on an `Option` | `MinHeap` | `tachyonc guide generics`, `guide conversions` |
| `Result`, `?`, `main -> Result<(), E>` | `Codebook::new`, `round_trip`, `main` | `tachyonc guide conversions` |
| default and named arguments: `table: bool = false` | `round_trip` | `tachyonc guide core` |
| tuples in a `Vec`, destructured in `while let` and `let` | `code_lengths` | `tachyonc guide syntax` |
| widening: `u8` into `u64`, `u32` into `i64` | `decode`, `encode` | `tachyonc guide conversions` |
| iterators: `zip`, `fold`, `filter`, `count`, `position`, `Option::map` | `round_trip`, `entropy` | `tachyonc guide iterators` |
| arrays as values: `[i64; 256]` returned and stored in a struct | `code_lengths`, `Codebook` | `tachyonc guide types` |
| f-strings: `{x:.4}`, `{h:x}`, `{b:c}`, `{s:?}` | output | `tachyonc guide formatting` |
| C's `log2` and clock | `entropy`, `now_ns` | `tachyonc guide c-interop` |

## Try

- Feed it a text with one byte value (`round_trip("aaaa")`): the
  one-symbol case gets a 1-bit code.
- Make the skew stronger in `generate_text` (the minimum of three
  draws) and watch the ratio and the longest code.
- Store the 256 lengths in front of the encoded bytes and write a
  decoder that rebuilds the codebook from them alone.
