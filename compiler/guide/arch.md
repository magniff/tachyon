# std::arch: SIMD and CPU intrinsics (0.19)

`std::arch` gives the CPU's own instructions as functions, the
intrinsics: SIMD on vectors (NEON on AArch64, SSE to AVX2 on x86-64),
CRC32 checksums, AES, SHA-256, dot products, popcount and bit scans.
They are in `std::arch::aarch64`, `std::arch::x86_64`, and, portable,
`std::arch` (`has`, `detect`, `count_ones`). The names are the vendors' (ACLE's `vaddq_u8`,
`__crc32cd`; Intel's `_mm_movemask_epi8`), as C and Rust's `core::arch`
spell them, so code and answers written for those carry over. Each
intrinsic is one instruction, seen by the optimizer (constant folding,
GVN, hoisting out of loops).

Three rules make it safe: an instruction the CPU lacks never runs (the
compiler checks every call against the features known at that point:
`arch.feature`), memory intrinsics take a checked slice and an index,
and nothing is undefined (a shift count or lane out of range is a
compile error, `arch.const_arg`). No `unsafe` is needed, and none is
written: an `unsafe` block around them is a warning.

## Recipes

What to reach for, by task. AArch64 is executed and tested on every
build; x86-64 is compiled and its encodings checked.

| task | AArch64 | x86-64 |
|---|---|---|
| byte search (memchr) | `vceqq_u8`, `vmaxvq_u8` (any match), the shrn movemask (where: below) | `_mm_cmpeq_epi8`, `_mm_movemask_epi8`, `trailing_zeros` (sse2); `_mm256_cmpeq_epi8`, `_mm256_movemask_epi8` (avx2) |
| hash-table probe (16 control bytes) | `vld1q_u8`, `vdupq_n_u8`, `vceqq_u8`, shrn movemask | `_mm_loadu_si128`, `_mm_set1_epi8`, `_mm_cmpeq_epi8`, `_mm_movemask_epi8` |
| checksums: CRC-32 (gzip), CRC-32C | `__crc32b`...`__crc32d`, `__crc32cb`...`__crc32cd` (crc) | `_mm_crc32_u8`...`_mm_crc32_u64` (sse4.2, CRC-32C only) |
| hashing, GHASH, CRC folding | `vmull_p64` (aes: carry-less multiply), `vaeseq_u8` + `vaesmcq_u8` | `_mm_clmulepi64_si128` (pclmulqdq), `_mm_aesenc_si128` (aes) |
| SHA-1, SHA-256 | `vsha256hq_u32`, `vsha256h2q_u32`, `vsha256su0q_u32`, `vsha256su1q_u32` (sha2) | `_mm_sha256rnds2_epu32`, `_mm_sha256msg1_epu32` (sha) |
| dot products (int8 ML, Adler-32) | `vdotq_u32`, `vdotq_s32` (dotprod) | `_mm_maddubs_epi16` (ssse3), `_mm_madd_epi16`, `_mm_sad_epu8` (sse2) |
| popcount, bit scans | `count_ones`, `leading_zeros`, `trailing_zeros` (std, one instruction); `vcntq_u8` per byte | the same std functions (popcnt, lzcnt, tzcnt when known); `_popcnt64` (popcnt), `_lzcnt_u64` (lzcnt), `_tzcnt_u64` (bmi1) |
| table lookup, shuffles | `vqtbl1q_u8`, `vextq_u8`, `vzip1q_u8` | `_mm_shuffle_epi8`, `_mm_alignr_epi8` (ssse3) |
| saturating arithmetic | `vqaddq_u8`, `vqsubq_u8` | `_mm_adds_epu8`, `_mm_subs_epu8` (sse2) |

The x86-64 column is Intel's names, SSE2 to AVX2 (`volec query arch
--arch x86_64` lists them, `--feature avx2` one feature's); the feature
in parentheses is what the call needs beyond x86-64's baseline (sse2).

Finding one without a manual, by words, feature or instruction (no
program needed; one intrinsic a line: name, features, instruction,
what it does):

```sh
volec query arch saturating subtract u8    # aarch64::vqsubq_u8  neon  uqsub ...
volec query arch --feature crc             # every CRC intrinsic
volec query arch --equiv _mm_movemask_epi8 # the other architecture's way
volec query show vqtbl1q_u8                # signature, features, instruction, what it computes, its use line
```

## Types

Vectors are values in a vector register, with lanes: `v16u8` (16 lanes
of `u8`), `v8i16`, `v4f32`, ...: 64-bit (`v8u8`, `v2f32`), 128-bit and
256-bit (`v32u8`, `v8f32`; two registers on AArch64), signed, unsigned
and float, with `+ - * & | ^`, compares (a mask), `splat`, `load`,
`lane`, `sum` (`guide types#simd-vectors`). ACLE's names are aliases:
`uint8x16_t` is `v16u8`, `int32x4_t` is `v4i32`, `uint8x16x2_t` is
`(v16u8, v16u8)`. Intel's `__m128i`, `__m128`, `__m256i` ... are opaque:
no lanes, no operators, made and read by their intrinsics, because
`a + b` on an `__m128i` would not say the lane width.
`T::from_bits(v)` reinterprets any vector of the same size, with no
instruction (`v16u8::from_bits(m)`, as `vreinterpretq_*` and
`_mm_cast*` do).

Immediates (shift counts, lanes, `ext` positions) are the last
arguments and must be constants in the instruction's range:
`vshrq_n_u8(v, 3)`, never Rust's `vshrq_n_u8::<3>(v)` (`arch.rust_form`
says so, with the edit).

```tach
use std::arch::aarch64::{vaddq_u8, vdupq_n_u8, vextq_u8, vgetq_lane_u8, vqsubq_u8};

fn main() {
    let a = vdupq_n_u8(200);
    let b = vdupq_n_u8(100);
    let wrapped = vaddq_u8(a, b);      // 300 wraps to 44
    let floor = vqsubq_u8(b, a);       // saturates at 0
    let both = vextq_u8(wrapped, floor, 15);
    println(f"{vgetq_lane_u8(wrapped, 0)} {vgetq_lane_u8(floor, 0)} {vgetq_lane_u8(both, 1)}");
}
```
```out
44 0 0
```

## Guards

An intrinsic needs its features (`query show NAME` prints them). A call
is accepted where they are known:

- the build's features: the target's baseline, or `-C target-cpu=` /
  `-C target-feature=+f` (below, Features);
- the enclosing function's `#[target_feature(enable = "crc")]`;
- a guard: the then branch of `if std::arch::detect("crc")` or
  `if std::arch::has("crc")` (`&&` of them too), the else branch of
  `if !detect("crc")`, the rest of a block after `if !detect("crc") {
  return ...; }`, and after `assert(detect("crc"))`. A `bool` kept in a
  local or an `||` is no guard.

`detect("f")` asks the running CPU: one cached bit (filled once before
`main`), a constant when the build already knows f, and `false` for
another architecture's feature. `has("f")` is the build's answer, a
constant. What a function needs is inferred from its calls, as effects
are, so helpers need no attribute: the error appears in the entry point
(`main`, an `extern "C"` function, a test) at the call that is not
guarded, with the intrinsic it comes from and an edit that adds the
guard. `volec query features NAME` prints a function's requirement,
`--why crc` the calls down to the intrinsic; `def`, `show` and `context`
print it as `features: crc (inferred)` after its effects.

```tach
use std::arch::aarch64::__crc32cb;
use std::arch::detect;

// CRC-32C of s, bit by bit: the fallback.
fn crc32c_portable(s: [u8]) -> u32 {
    var c: u32 = 0xffffffff;
    for b in s {
        c ^= b as u32;
        for _ in 0..8 {
            c = if (c & 1) != 0 { (c >> 1) ^ 0x82f63b78 } else { c >> 1 };
        }
    }
    ~c
}

// The same by the crc instructions: needs crc (inferred).
fn crc32c_hw(s: [u8]) -> u32 {
    var c: u32 = 0xffffffff;
    for b in s {
        c = __crc32cb(c, b);
    }
    ~c
}

fn crc32c(s: [u8]) -> u32 {
    if detect("crc") { crc32c_hw(s) } else { crc32c_portable(s) }
}

fn main() {
    println(f"{crc32c("123456789"):x} {crc32c_portable("123456789"):x}");
}
```
```out
e3069283 e3069283
```

Code for the other architecture stays in the program: under
`has("avx2")` it is type-checked on an arm machine and never generated
there, so one source serves both (no `cfg`).

## Features

| target | the build's baseline (default `-C target-cpu`) |
|---|---|
| aarch64-macos | `apple-m1`: neon, fp, crc, aes, sha2, sha3, dotprod, rdm, lse, fp16 |
| aarch64-linux | `generic`: neon, fp (crc, aes, sha2, dotprod are detected) |
| x86_64-linux | `x86-64`: sse, sse2 |
| x86_64-macos | `core2`: up to ssse3 |

`-C target-cpu=NAME|native` and `-C target-feature=+crc,-aes` change
it, on every command that checks (`check`, `query`, the edits). A
feature implies those below it (`avx2` => `avx` => `sse4.2` ... => `sse2`;
`sha3` => `sha2` => `neon`); `aes` exists on both architectures, so
`aarch64.aes` and `x86_64.aes` name one. `VOLE_ARCH_DISABLE=crc,aes`
(or `all`) in the environment makes `detect` answer false for those at
run time: the way to test a fallback on a machine that has the feature.
It can only clear features, never add one.

`#[target_feature(enable = "crc,aes")]` on a function declares what it
needs: callers must know it, and its body is checked against it
(`arch.declared`). It is a pin, as `#[effects]` is, rarely needed.

`#[multiversion("dotprod", "avx2")]` compiles one body once per listed
set the build lacks, plus the baseline version, and makes the function
a dispatcher (`if detect(..) { version } else ...`: no indirect call,
hoisted out of loops). Inside, `has("dotprod")` is a constant per
version, so it picks the code; a call only some versions can make must
be under it (`arch.multiversion`). Its address can be taken.

```tach
use std::arch::aarch64::{vaddvq_u32, vdotq_u32, vdupq_n_u32, vld1q_u8};
use std::arch::has;

// The dot product of a and b (equal lengths, a multiple of 16).
#[multiversion("dotprod")]
fn dot(a: [u8], b: [u8]) -> u32 {
    if has("dotprod") {
        var acc = vdupq_n_u32(0);
        var i = 0;
        while i + 16 <= a.len {
            acc = vdotq_u32(acc, vld1q_u8(a, i), vld1q_u8(b, i));
            i += 16;
        }
        vaddvq_u32(acc)
    } else {
        var n: u32 = 0;
        for i in 0..a.len {
            n += a[i] as u32 * b[i] as u32;
        }
        n
    }
}

fn main() {
    let a: [u8; 32] = [3; 32];
    let b: [u8; 32] = [2; 32];
    println(f"{dot(a[..], b[..])}");
}
```
```out
192
```

## Memory

The vendor's name is the safe form: it takes a slice and an index,
`vld1q_u8(s, i)` (16 bytes from `s[i]`), `vst1q_u8(s, i, v)`,
`_mm_loadu_si128(s, i)`, and checks `0 <= i` and `i + 16 <= s.len` as
`s[i]` does (`panic` in its effects). A store writes, so its slice is
`inout [T]`: `vst1q_u8(&out[..], i, v)`, `v.as_mut_slice()`, or an
`inout [T]` parameter passed on; a read-only `[T]` there is
`own.readonly`, whose `try:` line makes the view exclusive. Range analysis removes the check
in counted loops (`while i + 16 <= s.len`), so the loop body is the bare
load. Aligned forms (`_mm_load_si128`) check the alignment too and stop
with `misaligned access` instead of faulting (`arch.misaligned`).

The pointer forms keep the vendor signatures and are `unsafe`, in the
`raw` submodules, for porting C: `std::arch::aarch64::raw::vld1q_u8(p:
*u8)`. Passing a pointer to the safe form is `arch.raw_form`, with the
edit to `s, i` when the pointer is `&s[i]`. `--check-unsafe` checks raw
loads against the program's blocks as it checks any raw access.

## Byte search

AArch64 has no movemask: to know *which* byte matched, narrow the
compare mask to 4 bits a byte (`vshrn_n_u16(.., 4)`), read it as a u64
and count trailing zeros; `vmaxvq_u8(eq) != 0` is the cheaper "any
match" test for the loop. x86-64's `_mm_movemask_epi8` gives one bit a
byte. Both branches can sit in one function: the other architecture's
is checked and dropped.

```tach
use std::arch::aarch64::{
    vceqq_u8, vdupq_n_u8, vget_lane_u64, vld1q_u8, vmaxvq_u8, vreinterpret_u64_u8,
    vreinterpretq_u16_u8, vshrn_n_u16,
};
use std::arch::x86_64::{_mm_cmpeq_epi8, _mm_loadu_si128, _mm_movemask_epi8, _mm_set1_epi8};
use std::arch::has;
use std::trailing_zeros;

// The first i with s[i] == b, or -1.
fn find(s: [u8], b: u8) -> i64 {
    var i = 0;
    if has("neon") {
        let needle = vdupq_n_u8(b);
        while i + 16 <= s.len {
            let eq = vceqq_u8(vld1q_u8(s, i), needle);
            if vmaxvq_u8(eq) != 0 {
                let m = vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0);
                return i + trailing_zeros(m) / 4;
            }
            i += 16;
        }
    } else if has("sse2") {
        let needle = _mm_set1_epi8(b as i8);
        while i + 16 <= s.len {
            let m = _mm_movemask_epi8(_mm_cmpeq_epi8(_mm_loadu_si128(s, i), needle));
            if m != 0 {
                return i + trailing_zeros(m as u64);
            }
            i += 16;
        }
    }
    while i < s.len {
        if s[i] == b {
            return i;
        }
        i += 1;
    }
    -1
}

fn main() {
    let text = "the quick brown fox jumps over the lazy dog";
    println(f"{find(text, 'z')} {find(text, 'q')} {find(text, '!')}");
}
```
```out
37 4 -1
```

`examples/arch/bytesearch` is this, with timings against the portable
loop.

## SHA-256

The sha2 feature does SHA-256's compression four rounds an instruction.
A block is 16 big-endian words; `vrev32q_u8` turns little-endian loads
into them. Each group of four rounds adds the round constants to four
message words (`vaddq_u32`), then `vsha256hq_u32` makes the new
`abcd` and `vsha256h2q_u32` the new `efgh` from the old `abcd` (keep a
copy: both read it). `vsha256su0q_u32` and `vsha256su1q_u32` extend the
schedule four words at a time: the words of group g + 4 from those of
groups g..g + 3. After the 16 groups the state adds the block's input
state.

```tach
use std::arch::aarch64::{
    uint32x4_t, vaddq_u32, vld1q_u32, vld1q_u8, vreinterpretq_u32_u8, vrev32q_u8, vsha256h2q_u32,
    vsha256hq_u32, vsha256su0q_u32, vsha256su1q_u32, vst1q_u32,
};
use std::arch::detect;

// SHA-256's round constants (FIPS 180-4, 4.2.2).
static K: [u32; 64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

// The 4 big-endian words of block[i..i + 16].
fn words(block: [u8], i: i64) -> uint32x4_t {
    vreinterpretq_u32_u8(vrev32q_u8(vld1q_u8(block, i)))
}

// One 64-byte block into the state (a, b, c, d, e, f, g, h).
fn compress(state: inout [u32], block: [u8]) {
    var abcd = vld1q_u32(state, 0);
    var efgh = vld1q_u32(state, 4);
    let (abcd0, efgh0) = (abcd, efgh);
    var w0 = words(block, 0);
    var w1 = words(block, 16);
    var w2 = words(block, 32);
    var w3 = words(block, 48);
    for g in 0..16 {
        let wk = vaddq_u32(w0, vld1q_u32(K[..], 4 * g));
        let next = if g < 12 { vsha256su1q_u32(vsha256su0q_u32(w0, w1), w2, w3) } else { w0 };
        let old = abcd;
        abcd = vsha256hq_u32(abcd, efgh, wk);
        efgh = vsha256h2q_u32(efgh, old, wk);
        w0 = w1;
        w1 = w2;
        w2 = w3;
        w3 = next;
    }
    vst1q_u32(&state, 0, vaddq_u32(abcd, abcd0));
    vst1q_u32(&state, 4, vaddq_u32(efgh, efgh0));
}

fn main() {
    var state: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    ];
    // "abc" padded to one block: 0x80, zeros, its length in bits at the end.
    var block: [u8; 64] = [0; 64];
    block[0] = 'a';
    block[1] = 'b';
    block[2] = 'c';
    block[3] = 0x80;
    block[63] = 24;
    if !detect("sha2") {
        println("no sha2 on this CPU: use a portable SHA-256");
        return;
    }
    compress(&state[..], block[..]);
    for k in 0..8 {
        print(f"{state[k]:08x}");
    }
    println("");
}
```
```out
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
```

x86-64's `_mm_sha256rnds2_epu32` does two rounds and wants the state as
`abef`/`cdgh`: `query arch --equiv vsha256hq_u32`.

## Errors

| code | what | fix |
|---|---|---|
| `arch.feature` | a call needs a feature the point does not know | the `try:` guard with a fallback, `-C target-feature=+f`, or `#[multiversion]` |
| `arch.declared` | a `#[target_feature]` smaller than its body's needs | add the feature (the `try:` edit) |
| `arch.const_arg` | an immediate not constant, or out of range | a literal in range (`query show NAME`) |
| `arch.rust_form` | `f::<3>(v)`, `is_x86_feature_detected!` | `f(v, 3)`, `std::arch::detect("f")` |
| `arch.raw_form` | a pointer to a safe memory form | `vld1q_u8(s, i)`, or `raw::` in `unsafe` |
| `arch.fn_pointer` | a `fn` value of a function that needs features | call it under a guard, a closure, or `#[multiversion]` |
| `arch.multiversion` | a call one version cannot make | put it under `has("f")` |
| `arch.feature_name`, `arch.feature_ambiguous` | an unknown name; `aes` of the other architecture | the suggested name; `aarch64.aes` |

`volec explain arch` lists them; `explain arch.feature` gives one in
full.
