## query arch (0.19): the intrinsic tables by words, feature, architecture;
## no program is read. The best matches first; a plain word finds the
## table's spelling (subtract: sub).
$ arch 'saturating subtract' u8
aarch64::vqsubq_u8	neon	uqsub <d>.16b, <a>.16b, <b>.16b	lanewise a - b, saturating at 0 and 255
aarch64::vqsub_u8	neon	uqsub <d>.8b, <a>.8b, <b>.8b	lanewise a - b, saturating at 0 and 255
x86_64::_mm_subs_epu8	sse2	psubusb <b>, <d>	lanewise a - b, saturating
x86_64::_mm256_subs_epu8	avx2	vpsubusb <b:y>, <a:y>, <d:y>	lanewise a - b, saturating
$ arch --feature crc
aarch64::__crc32b	crc	crc32b <d:w>, <crc:w>, <data:w>	one step of CRC-32 over 1 byte
aarch64::__crc32h	crc	crc32h <d:w>, <crc:w>, <data:w>	one step of CRC-32 over 2 bytes
aarch64::__crc32w	crc	crc32w <d:w>, <crc:w>, <data:w>	one step of CRC-32 over 4 bytes
aarch64::__crc32d	crc	crc32x <d:w>, <crc:w>, <data:x>	one step of CRC-32 over 8 bytes
aarch64::__crc32cb	crc	crc32cb <d:w>, <crc:w>, <data:w>	one step of CRC-32C over 1 byte
aarch64::__crc32ch	crc	crc32ch <d:w>, <crc:w>, <data:w>	one step of CRC-32C over 2 bytes
aarch64::__crc32cw	crc	crc32cw <d:w>, <crc:w>, <data:w>	one step of CRC-32C over 4 bytes
aarch64::__crc32cd	crc	crc32cx <d:w>, <crc:w>, <data:x>	one step of CRC-32C over 8 bytes
$ intrinsics --feature crc --arch x86_64
error query.no-match: no intrinsic matches with feature crc
try: tachyonc guide arch#recipes
[exit 1]
$ arch byte search --budget 60
aarch64::vceqq_u8	neon	cmeq <d>.16b, <a>.16b, <b>.16b	lanewise a == b: a mask, each lane all ones or 0
aarch64::vceq_u8	neon	cmeq <d>.8b, <a>.8b, <b>.8b	lanewise a == b: a mask, each lane all ones or 0
note query.budget: cut at about 60 tokens: 2 of 3 lines (about 73 tokens in all)
try: tachyonc query arch byte search --budget 100
$ arch sha256 --arch aarch64
aarch64::vsha256hq_u32	sha2	sha256h <d:q>, <hash_efgh:q>, <wk>.4s	four SHA-256 rounds of the state with wk (the message plus constants): the new abcd
aarch64::vsha256h2q_u32	sha2	sha256h2 <d:q>, <hash_abcd:q>, <wk>.4s	four SHA-256 rounds of the state with wk: the new efgh (pass the old abcd, before vsha256hq_u32)
aarch64::vsha256su0q_u32	sha2	sha256su0 <d>.4s, <w4_7>.4s	SHA-256 schedule update, part 1
aarch64::vsha256su1q_u32	sha2	sha256su1 <d>.4s, <w8_11>.4s, <w12_15>.4s	SHA-256 schedule update, part 2
$ arch --equiv _mm_movemask_epi8
x86_64::_mm_movemask_epi8	sse2	pmovmskb <a>, <d:w>	the 16 bytes' top bits as a 16-bit mask
equivalent: aarch64: (recipe) vshrn_n_u16(vreinterpretq_u16_u8(m), 4)
aarch64::vshrn_n_u16	neon	shrn <d>.8b, <a>.8h, #<n>	each lane shifted right by n, narrowed to its low half (the NEON movemask: n = 4 gives 4 bits per byte)
aarch64::vreinterpretq_u16_u8	neon	-	the same bits as 8 u16 lanes
x86_64::_mm256_movemask_epi8	avx2	vpmovmskb <a:y>, <d:w>	the 32 bytes' top bits as a 32-bit mask
$ arch --equiv vqsubq_u8
aarch64::vqsubq_u8	neon	uqsub <d>.16b, <a>.16b, <b>.16b	lanewise a - b, saturating at 0 and 255
equivalent: x86_64: _mm_subs_epu8
x86_64::_mm_subs_epu8	sse2	psubusb <b>, <d>	lanewise a - b, saturating
$ arch no-such-word
error query.no-match: no intrinsic matches no-such-word
try: tachyonc guide arch#recipes
[exit 1]
$ arch --equiv vnothing
error query.no-match: no intrinsic 'vnothing'
try: tachyonc query arch vnothing
[exit 1]
$ arch --arch sparc
error query.usage: unknown architecture 'sparc' (query arch WORDS... [--feature F] [--arch aarch64|x86_64|portable] [--equiv NAME] [--budget N])
try: tachyonc query arch 'saturating subtract'
[exit 2]
$ arch
error query.usage: no words to search for (query arch WORDS... [--feature F] [--arch aarch64|x86_64|portable] [--equiv NAME] [--budget N])
try: tachyonc query arch 'saturating subtract'
[exit 2]
## show, def and context of an intrinsic (with or without its path): the
## table's features and instruction on the first line; show adds its doc,
## what it computes, its equivalent and its `use` line.
$ show vqtbl1q_u8
// std::arch::aarch64::vqtbl1q_u8	<std::arch::aarch64>:109-110	effects: none	features: neon	instruction: tbl <d>.16b, {<t>.16b}, <idx>.16b
// a table lookup: lane k is t[idx[k]], 0 when idx[k] >= 16
// computes: r[k] = if idx[k] < 16 { t[idx[k]] } else { 0 }
// equivalent: x86_64: _mm_shuffle_epi8 (zeroes when bit 7 is set instead)
// use std::arch::aarch64::vqtbl1q_u8;
// use std::vqtbl1q_u8;
#[intrinsic(1404)]
pub fn vqtbl1q_u8(t: uint8x16_t, idx: uint8x16_t) -> uint8x16_t;
$ def std::arch::aarch64::__crc32cd _mm_movemask_epi8
std::arch::aarch64::__crc32cd	<std::arch::aarch64>:110:8	fn	pub fn __crc32cd(crc: u32, data: u64) -> u32	effects: none	features: crc	instruction: crc32cx <d:w>, <crc:w>, <data:x>
std::arch::x86_64::_mm_movemask_epi8	<std::arch::x86_64>:8:8	fn	pub fn _mm_movemask_epi8(a: __m128i) -> i32	effects: none	features: sse2	instruction: pmovmskb <a>, <d:w>
$ show std::arch::detect
// std::arch::detect	<std::arch>:3-4	effects: none	features: none	instruction: none
// true when the running CPU has the feature: a constant when known or foreign, else one cached bit test
// computes: r = whether the CPU running the program has `feature`
// use std::arch::detect;
// use std::detect;
#[intrinsic(2)]
pub fn detect(feature: [u8]) -> bool;
$ context vdotq_u32 --budget 120
// std::arch::aarch64::vdotq_u32	<std::arch::aarch64>:109-110	effects: none	features: dotprod	instruction: udot <d>.4s, <a>.16b, <b>.16b
// each 32-bit lane of acc plus the dot product of its four bytes of a and b
// computes: r[k] = acc[k] + a[4 * k] * b[4 * k] + a[4 * k + 1] * b[4 * k + 1] + a[4 * k + 2] * b[4 * k + 2] + a[4 * k + 3] * b[4 * k + 3]
// use std::arch::aarch64::vdotq_u32;
// use std::vdotq_u32;
#[intrinsic(1493)]
// (1 more lines)
note query.budget: over the budget of 120 tokens, left out: source lines (or bodies) 1, types or uses 2
try: tachyonc query show vdotq_u32
try: tachyonc query context vdotq_u32 --budget 360
