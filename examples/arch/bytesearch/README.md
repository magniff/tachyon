# bytesearch: memchr with NEON

Where does a byte first occur in a buffer? The portable loop looks at
one byte an iteration. `find_byte_neon` looks at 64: four 16-byte loads,
four compares against the needle (`vceqq_u8`: a lane is `0xff` where
the bytes are equal), or-ed together and tested at once (`vmaxvq_u8`:
the largest lane, not 0 when any byte matched). When a block matches, a
16-byte loop finds the byte.

That last step needs x86's `_mm_movemask_epi8` (one bit a byte), which
AArch64 lacks. The idiom is to narrow the mask: `vshrn_n_u16(m, 4)`
shifts each 16-bit lane right by 4 and keeps its low byte, so each input
byte leaves 4 bits; read as one `u64`, its trailing zeros divided by 4
are the first match.

```tach
let eq = vceqq_u8(vld1q_u8(s, i), needle);
let m = vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0);
if m != 0 {
    return i + trailing_zeros(m) / 4;
}
```

`find_byte` picks the version: `detect("neon")` is a constant on AArch64
(neon is its baseline) and `detect("sse2")` on x86-64, so a build keeps
one branch. The SSE2 version is in the same file: on an arm machine it
is type-checked and its requirement inferred, but no code is made for
it.

## Run it

`./bytesearch` checks the SIMD search against the portable one on every
length and offset up to 300 bytes, for four needles, and a `z` at every
position:

```console
$ volec main.vl -o bytesearch && ./bytesearch
19500 searches, 0 wrong
first 'q' at 10, first 'z' at -1
ok: built bytesearch
```

## Finding the intrinsics

`query arch` searches the tables by words, a feature or an
instruction, with no program; `--equiv` gives the other architecture's
way:

```console
$ volec query arch --equiv _mm_movemask_epi8
x86_64::_mm_movemask_epi8	sse2	pmovmskb <a>, <d:w>	the 16 bytes' top bits as a 16-bit mask
equivalent: aarch64: (recipe) vshrn_n_u16(vreinterpretq_u16_u8(m), 4)
aarch64::vshrn_n_u16	neon	shrn <d>.8b, <a>.8h, #<n>	each lane shifted right by n, narrowed to its low half (the NEON movemask: n = 4 gives 4 bits per byte)
aarch64::vreinterpretq_u16_u8	neon	-	the same bits as 8 u16 lanes
x86_64::_mm256_movemask_epi8	avx2	vpmovmskb <a:y>, <d:w>	the 32 bytes' top bits as a 32-bit mask
```

`def` says what each version needs beyond the build's features: the
SSE2 one needs sse2, which an AArch64 build never has, so it may only
be called under `detect("sse2")` (or `has`), where it is dead code:

```console
$ volec query def find_byte_neon find_byte_sse2 find_byte
crate::find_byte_neon	main.vl:33:4	fn	fn find_byte_neon(s: [u8], b: u8, from: i64) -> i64	effects: panic diverge
crate::find_byte_sse2	main.vl:59:4	fn	fn find_byte_sse2(s: [u8], b: u8, from: i64) -> i64	effects: panic diverge	features: sse2 (inferred)
crate::find_byte	main.vl:75:4	fn	fn find_byte(s: [u8], b: u8) -> i64	effects: panic diverge
std::string::find_byte	<std>:41028:4	fn	fn find_byte(b: u8, s: [u8], from: i64) -> i64	effects: panic diverge
```

## Timings

`./bytesearch simd` and `./bytesearch portable` scan 1 MiB for its last
byte 8192 times (8 GiB). On an Apple M1 at -O2 (the default), the
fastest of three runs, with the C library's `memchr` (a C program doing the same scans,
`cc -O2`) for comparison:

```text
./bytesearch simd       0.12 s   (about 70 GB/s: the buffer stays in L2)
memchr (libc)           0.12 s
./bytesearch portable   1.87 s
```

The SIMD search is 15 times the portable loop and as fast as the C
library's hand-written `memchr`.
