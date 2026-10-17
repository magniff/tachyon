# tachyon 0.19 design: CPU intrinsics and target features (`std::arch`)

I read the language and the compiler from the worktree of branch
design-019 (from night-final: 0.16.0 plus the 0.17 work merged so far)
through `tachyonc guide types|effects|generics`, `query items/show/refs/grep`
on `middle::ir`, `middle::lower`, `middle::vectorize`, `back::mc_arm64`,
`back::mc_x86_64`, `back::enc_arm64`, `back::enc_x86`, `back::emit`,
`gen0::gen::vector`, `front::check::vectors`, `front::effects::infer` and
`front::modules::stdsections`, and docs/optimizer.md ("The back end",
"Calling conventions", "0.10: vectors"), docs/grammar.md ("Additions of
0.10"), docs/roadmap.md ("0.19") and tests/objcheck.sh, tests/run.sh and
tests/fuzz/run.sh. The 0.17 design (branch design-017b,
docs/design/value-semantics.md) is the model for this document's form and
the source of the reference rules it depends on. I modified nothing but
this file.

The user is away and asked for autonomous work through 0.23: every choice
below is taken as recommended and listed in the last section.

## 1. The current state

**Vector types (0.10).** Six 16-byte types, `v2f64 v4f32 v2i64 v4i32
v8i16 v16i8`, all lanes signed; there are no unsigned, 64-bit or 256-bit
vectors. Operators lane by lane (`+ - *`, `/` on floats, `& | ^`),
comparisons giving signed masks, `select`, `lane`, `with_lane`, `sum`,
`splat`, and checked `load(s, i)` / `store(s, i)` on slices and arrays.
They are not FFI-safe. Nothing about them is undefined behaviour.

**In the front end** a vector is a compound value, like a struct: an
expression's value is the address of its 16 bytes. The methods are a
built-in node (`front::check::vectors`, `make_vecop`, `synth_vecop`), not
std functions.

**In the IR** (`middle::ir::Op`) the vector instructions are `VBin VCmp
VSplat VExt VIns VSum VNeg VSel`, plus 0.16's `VMacW` (umlal, made only
by the vectorizer). They are pure: GVN numbers them and LICM moves them.
Nothing folds them, and the e-graph never matches them. Scalar
replacement keeps a vector slot whole, so vectors become SSA values.
0.16's `Op::Bits` turns std's `count_ones`, `leading_zeros` and
`trailing_zeros` into cnt/clz/rbit on AArch64 (`middle::lower::calls::bits_kind`).
On x86-64 those stay calls, because POPCNT and LZCNT are not in the
x86-64 baseline. This is the only place where the compiler recognizes a
std function as an instruction.

**In the back end** a vector lives in a float register: q/v on AArch64,
never d8-d15; xmm on x86-64. Spills take 16 bytes. Every IR vector
instruction is one NEON instruction, except a 64-bit multiply. SSE2 lacks
8/32/64-bit multiplies, 64-bit compares and cheap lane moves, so those go
lane by lane through the red zone. The machine layer (`mc_arm64/vector`,
`mc_x86_64/vector`) writes assembly text. The compiler's own assembler
(`objfile/assemble`) parses that text and encodes it (`enc_arm64`, 93
mnemonics in a chain of `if`s; `enc_x86`, with an `sse(name, class,
prefix, opcode)` table). So **adding an instruction means teaching both
the text emitter and the encoder**. `tests/objcheck.sh` checks the encoder
against `cc -c` on the same text for every program of the corpus. It runs
no program, so it works for a target the host cannot execute.

**At -O0** (`gen0`) vectors are computed lane by lane through frame
slots. No vector instruction is shared with -O1/-O2, which makes -O0 the
oracle for vector code.

**The vectorizer** (`middle/vectorize/`) vectorizes innermost counted
loops of one element type and outer loops (matmul), with run-time overlap
and bounds tests. It uses SSE2 and NEON only: AVX2 was never used,
because Rosetta, where x86-64 used to be tested, lacked it. Loops with
calls are left alone.

**Calling convention.** In tachyon's own convention, an aggregate of at
most four leaves goes as its leaves, and a larger one as 8-byte integer
chunks. A vector is "a struct of its lanes": a `v4f32` is four float
registers, a `v16i8` two integer registers. Helper functions that take
and return vectors therefore pay lane moves at every call that is not
inlined.

**Targets.** `base::target` knows four targets (aarch64-macos,
aarch64-linux, x86_64-linux, x86_64-macos) and one `X86` flag. There is
no notion of CPU features: the baseline is fixed per target, and there is
no `-C` option and no conditional compilation (no `cfg`). std is lexed in
sections: a lazy section loads only when the program names one of its
words (`front::modules::stdsections`).

**Effects (0.16)** are inferred per function over the call graph's SCCs
(`front::effects::infer`: `components`, `COMPONENT`, `ADDRESS_TAKEN`),
shown by `query effects`, and pinned by declarations. That pass walks
bodies *after* checking, not through checker hooks, because the checker
checks speculatively (`attempt`). The feature analysis of §2.4 follows
the same rule.

**Run targets now.** aarch64-macos (the host) and the aarch64-linux
container. **x86-64 is not executed** (user instruction): no
x86_64-linux container rows, no Rosetta. objcheck for an x86 target and
compile-only tests still run on the arm host: `cc -arch x86_64 -c` and
the link need no x86 CPU.

**What is missing for 0.19:** unsigned/64-bit/256-bit vector types;
bitcasts between vectors; constant vectors (tables for `tbl`/`pshufb`);
any NEON or SSE instruction beyond the eight IR ops; crc, aes, sha,
dotprod, SSSE3–SSE4.2, AVX/AVX2, BMI, FMA; feature sets per target, per
function and per program point; run-time CPU detection; a way to write
code for two architectures in one program; and an optimizer story for
instructions that may not exist on the running CPU.

## 2. The model (decided)

### 2.1 Intrinsics are table entries, seen as std functions

**One source of truth.** Every intrinsic is one line of a table:
`compiler/arch/aarch64.def`, `x86_64.def` and `portable.def`. The
instructions they use are lines of `compiler/arch/insn_a64.def` and
`insn_x86.def`. `compiler/arch/embed.sh`, like `compiler/std/embed.sh`,
writes them into `compiler/src/arch/tables.tach` as compact strings. A
test fails when the generated file is stale. An intrinsic line holds:

| field | example (`vqsubq_u8`) | used by |
|---|---|---|
| name | `vqsubq_u8` | name resolution, query |
| features | `neon` | §2.4 |
| signature | `(a: uint8x16_t, b: uint8x16_t) -> uint8x16_t` | the checker |
| const parameters and ranges | — (`vshrq_n_u8`: `n: 1..=8`) | the checker (`arch.const_arg`) |
| IR form | `intr` (or `vbin.add`, `vcmp.eq`, `cast`, `load`, `store`, `bits.ones`, ...) | lowering |
| instruction | `uqsub {d}.16b, {a}.16b, {b}.16b` | both back ends, gen0 |
| flags | `pure commutative=no tied=-` | GVN, LICM, regalloc |
| memory | `none` / `load(a, 16)` / `store(a, 16)` / `raw` | lowering, effects, alias analysis |
| fold | `lanes.qsub_u` | constant folding (§5.3) |
| semantics | `r[i] = max(a[i] - b[i], 0)` (u8 lanes) | `query show`, the test generator |
| equivalent | `x86_64: _mm_subs_epu8` | `query arch --equiv` |
| doc | `lanewise a - b, saturating at 0` | `query`, `guide arch` |

**Virtual std modules.** The table is not compiled into std source.
`std::arch`, `std::arch::aarch64`, `std::arch::x86_64` and their `raw`
submodules are *virtual*: when a path resolves into one, the compiler
synthesizes that one declaration from its table line, and std's lazy
sections never see it. A program that names three intrinsics pays for
three declarations, and the table (about 1,800 lines) is parsed on the
first use. A program that uses no intrinsics pays nothing. `query show`
prints the synthesized declaration together with the table's facts
(§2.9). The vendor type names are virtual items of the same modules.

**Names are the vendors'** (ACLE for AArch64, Intel's for x86-64), as
Rust's `core::arch` uses them. An agent that knows `vaddq_u8` or
`_mm_movemask_epi8` uses it as is. Rust-specific spellings (const
generics such as `vshrq_n_u8::<3>`, `is_x86_feature_detected!`) do not
exist here. Each one has a diagnostic with the exact rewrite (§2.9).

**Const parameters.** Immediates (shift counts, lane numbers, `ext`
positions, shuffle masks, comparison predicates) are ordinary arguments
that must be constant expressions (0.15's `consteval`) within the range
the table gives: `vshrq_n_u8(a, 3)`. Without const generics this is the
only spelling. It is how C writes them, and it is what agents write when
they forget Rust's turbofish.

### 2.2 Types

**New portable vector types**, with every 0.10 operation and the same
"nothing is undefined" rules:

| width | signed (0.10 + new) | unsigned (new) | float |
|---|---|---|---|
| 64-bit (new) | `v8i8 v4i16 v2i32 v1i64` | `v8u8 v4u16 v2u32 v1u64` | `v2f32 v1f64` |
| 128-bit | `v16i8 v8i16 v4i32 v2i64` | `v16u8 v8u16 v4u32 v2u64` | `v4f32 v2f64` |
| 256-bit (new) | `v32i8 v16i16 v8i32 v4i64` | `v32u8 v16u16 v8u32 v4u64` | `v8f32 v4f64` |

- An unsigned vector compares unsigned. Its mask type is itself (a lane
  is `MAX` or `0`), as NEON's `vceqq_u8` returns `uint8x16_t`. A signed
  vector's mask type is itself too (0.10's rule), and a float vector's is
  the signed vector of its width.
- **`T::from_bits(v)`** reinterprets any vector of the same size as `T`.
  It costs no instruction. `vreinterpretq_*` and `_mm_cast*` are table
  entries of IR form `cast`, which lowers to it.
- **256-bit vectors on a target or function without 256-bit registers**
  (every AArch64 function; x86-64 functions without AVX) are *legalized
  in lowering* into two 128-bit halves. So portable code with `v8i32`
  runs everywhere and is tested by execution on aarch64.
- **64-bit vectors** live in d registers on AArch64 (the `.8b`/`.4h`/
  `.2s` arrangements) and in the low half of an xmm register on x86-64
  (`movq` loads and stores).

**Vendor types are virtual items of the arch modules.**
- **AArch64:** the ACLE types are *aliases*: `uint8x16_t = v16u8`,
  `int16x8_t = v8i16`, `float32x4_t = v4f32`, `uint8x8_t = v8u8`, and so
  on for every one; `poly8x16_t = v16u8` and `poly64x2_t = v2u64`, with
  `p64 = u64` and `p128 = v2u64`. Tachyon has no `u128`, so `vmull_p64`
  returns `v2u64` (low lane first). The tuple types are tuples:
  `uint8x16x2_t = (v16u8, v16u8)`, also x3 and x4.
- **x86-64:** `__m128i`, `__m128`, `__m128d`, `__m256i`, `__m256` and
  `__m256d` are *distinct opaque vector types* of 16 and 32 bytes. They
  have no operators and no lanes, and convert only by `from_bits` both
  ways. This is Rust's rule, and it is deliberate: `a + b` on an
  `__m128i` alias of `v2i64` would add 64-bit lanes where the author
  meant bytes, silently.

All vector types are plain (0.17): they are bit-copied, never moved and
never dropped.

**Calling convention change** (tachyon's own convention only; C's is
untouched, and vectors stay non-FFI-safe):
- A vector is one leaf in a vector register: v0-v7 and v16-v23 on
  AArch64, xmm0-xmm13 on x86-64, never split into lanes.
- A 256-bit vector is two such leaves, whatever the features of the
  caller and the callee. The convention never depends on features, so a
  call between an AVX function and a non-AVX one needs nothing special.
- Tuples of vectors are their leaves (at most four).

A SIMD helper that is not inlined then costs a branch and nothing else.

### 2.3 What ships in 0.19.0

The aim, in order:
1. the instructions that **SIMD hash probing, byte search, UTF-8
   validation and checksums** need, on both architectures (table in
   §2.3.4);
2. then breadth, by whole families, so that an agent never meets a
   "this type is missing" hole inside a family.

Every name below is a line of the `.def` files. The `.def` files are the
exact list, and `query arch --list FEATURE` prints it.

#### 2.3.1 `std::arch::aarch64`

Notation:
- **I** = `s8 u8 s16 u16 s32 u32 s64 u64`; **I6** = I without the 64-bit
  types; **F** = `f32 f64`; **A** = I + F.
- "q+d" means both the 128-bit `...q_` form and the 64-bit form.

| feature | family | names |
|---|---|---|
| neon | loads/stores (safe: slice + index, §2.6) | `vld1q_T`, `vld1_T`, `vst1q_T`, `vst1_T`, `vld1q_dup_T` (T in A); `vld2q_T`, `vst2q_T` (T in `u8 u16 u32 f32`) |
| neon | build, lanes, halves | `vdupq_n_T`, `vdup_n_T`, `vmovq_n_T`, `vgetq_lane_T`, `vget_lane_T`, `vsetq_lane_T`, `vdupq_laneq_T`, `vcombine_T`, `vget_low_T`, `vget_high_T` (A) |
| neon | casts (no instruction) | `vreinterpretq_X_Y` and `vreinterpret_X_Y` for every pair of A ∪ {p8, p64} |
| neon | arithmetic | `vaddq vsubq` (A, q+d); `vmulq` (I6 + F, q+d); `vqaddq vqsubq` (I, q+d); `vhaddq vrhaddq vabdq` (I6, q+d; `vabdq_f32/f64`); `vminq vmaxq vpminq vpmaxq vpaddq` (I6 + F); `vabsq vnegq` (signed + F, q+d); `vqabsq vqnegq` (signed); `vmlaq vmlsq` (I6 + F); `vfmaq vfmsq` (F) |
| neon | widening, narrowing | `vaddl vaddl_high vaddw vsubl vmull vmull_high vmlal vmlal_high vpaddlq vpadalq vmovl vmovl_high vshll_n` (I6); `vmovn vmovn_high vqmovn vrshrn_n vshrn_n vqshrn_n` (16-, 32-, 64-bit sources); `vqmovun vqshrun_n` (s16 s32 s64); `vmull_p8` |
| neon | horizontal | `vaddvq` (A), `vaddv` (64-bit A), `vaddlvq` (I6), `vmaxvq vminvq` (I6 + F), `vmaxv vminv` (64-bit I6) |
| neon | compare | `vceqq vcgtq vcgeq vcltq vcleq vceqzq` (A, q+d); `vtstq` (I, q+d) |
| neon | logic | `vandq vorrq veorq vbicq vornq` (I, q+d); `vmvnq` (I6, q+d); `vbslq` (A, q+d) |
| neon | shifts | `vshlq_n vshrq_n vsraq_n vrshrq_n vsliq_n vsriq_n vqshlq_n` (I, q+d); `vshlq` by vector (I, q+d) |
| neon | permutes | `vextq` (A, q+d); `vzip1q vzip2q vuzp1q vuzp2q vtrn1q vtrn2q` (A, q+d); `vrev16q` (8-bit), `vrev32q` (8/16-bit), `vrev64q` (8/16/32-bit, f32); `vqtbl1q vqtbx1q vqtbl2q vqtbx2q` and their 64-bit-index forms `vqtbl1 vqtbx1` (`u8 s8 p8`) |
| neon | bits | `vcntq vrbitq` (`u8 s8 p8`, q+d); `vclzq` (I6, q+d); `vclsq` (signed I6) |
| neon | float | `vdivq vsqrtq vrndnq vrndmq vrndpq vrndq vrndaq vmaxnmq vminnmq vrecpeq vrecpsq vrsqrteq vrsqrtsq` (F); `vcvtq_s32_f32 vcvtq_u32_f32 vcvtq_f32_s32 vcvtq_f32_u32 vcvtq_s64_f64 vcvtq_u64_f64 vcvtq_f64_s64 vcvtq_f64_u64 vcvt_f64_f32 vcvt_f32_f64`; `vmulq_n vmulq_laneq` (F) |
| dotprod | dot products | `vdotq_u32 vdotq_s32 vdot_u32 vdot_s32 vdotq_laneq_u32 vdotq_laneq_s32` |
| crc | CRC-32 and CRC-32C | `__crc32b __crc32h __crc32w __crc32d __crc32cb __crc32ch __crc32cw __crc32cd` |
| aes | AES rounds, carry-less multiply | `vaeseq_u8 vaesdq_u8 vaesmcq_u8 vaesimcq_u8 vmull_p64 vmull_high_p64` |
| sha2 | SHA-1, SHA-256 | `vsha1cq_u32 vsha1pq_u32 vsha1mq_u32 vsha1h_u32 vsha1su0q_u32 vsha1su1q_u32 vsha256hq_u32 vsha256h2q_u32 vsha256su0q_u32 vsha256su1q_u32` |
| sha3 | three-way logic | `veor3q vbcaxq` (I), `vrax1q_u64 vxarq_u64` |

That is about 1,250 names, most of them type instances and casts. Later
(0.19.x and after): the x3/x4 tuple forms (`vqtbl3q`, `vqtbl4q`,
`vld3q`, `vld4q`, `vst3q`, `vst4q`, which need consecutive registers,
§5.4), `vld1q_T_x2..x4`, fp16, i8mm, bf16, sha512, sm3/sm4, rdm, and
SVE.

#### 2.3.2 `std::arch::x86_64` (implemented and encoded; executed once x86 testing returns)

| feature | names |
|---|---|
| sse2 (baseline) | loads/stores `_mm_loadu_si128 _mm_load_si128 _mm_storeu_si128 _mm_store_si128 _mm_loadl_epi64 _mm_storel_epi64 _mm_loadu_ps/pd _mm_storeu_ps/pd`; build `_mm_set1_epi8/16/32/64x _mm_set_epi8/16/32/64x _mm_setr_epi8/16/32 _mm_setzero_si128 _mm_set1_ps/pd _mm_setzero_ps/pd _mm_cvtsi32_si128 _mm_cvtsi64_si128 _mm_cvtsi128_si32 _mm_cvtsi128_si64`; integer `_mm_add/sub_epi8/16/32/64 _mm_adds/subs_epi8/16 _mm_adds/subs_epu8/16 _mm_mullo_epi16 _mm_mulhi_epi16/epu16 _mm_mul_epu32 _mm_madd_epi16 _mm_sad_epu8 _mm_avg_epu8/16 _mm_min/max_epu8 _mm_min/max_epi16`; compare `_mm_cmpeq_epi8/16/32 _mm_cmpgt/cmplt_epi8/16/32`; logic `_mm_and/or/xor/andnot_si128`; shifts `_mm_slli/srli_epi16/32/64 _mm_srai_epi16/32 _mm_sll/srl_epi16/32/64 _mm_sra_epi16/32 _mm_slli_si128 _mm_srli_si128`; permutes `_mm_shuffle_epi32 _mm_shufflelo/hi_epi16 _mm_unpacklo/hi_epi8/16/32/64 _mm_packs_epi16/32 _mm_packus_epi16`; masks `_mm_movemask_epi8 _mm_movemask_ps/pd _mm_extract_epi16 _mm_insert_epi16`; float `_mm_add/sub/mul/div/sqrt/min/max_ps/pd _mm_cmp{eq,lt,le,neq,nlt,nle,ord,unord}_ps/pd _mm_cvtepi32_ps _mm_cvttps_epi32 _mm_cvtps_epi32`; casts `_mm_castsi128_ps` and the rest; hints `_mm_pause _mm_prefetch` |
| sse3 | `_mm_lddqu_si128 _mm_hadd_ps/pd _mm_movehdup_ps _mm_moveldup_ps` |
| ssse3 | `_mm_shuffle_epi8 _mm_alignr_epi8 _mm_abs_epi8/16/32 _mm_hadd_epi16/32 _mm_maddubs_epi16 _mm_mulhrs_epi16 _mm_sign_epi8/16/32` |
| sse4.1 | `_mm_blendv_epi8 _mm_blend_epi16 _mm_testz_si128 _mm_testc_si128 _mm_min/max_epi8/epu16/epi32/epu32 _mm_mullo_epi32 _mm_cmpeq_epi64 _mm_packus_epi32 _mm_extract_epi8/32/64 _mm_insert_epi8/32/64 _mm_cvtepu8/epi8_epi16/32/64 _mm_cvtepu16/epi16_epi32/64 _mm_cvtepu32/epi32_epi64 _mm_minpos_epu16 _mm_round_ps/pd _mm_floor_ps/pd _mm_ceil_ps/pd` |
| sse4.2 | `_mm_cmpgt_epi64 _mm_crc32_u8/u16/u32/u64 _mm_cmpistri _mm_cmpistrm _mm_cmpestri _mm_cmpestrm` |
| popcnt, lzcnt | `_popcnt32 _popcnt64 _lzcnt_u32 _lzcnt_u64` |
| bmi1, bmi2 | `_tzcnt_u32/64 _andn_u32/64 _blsr_u32/64 _blsi_u32/64 _blsmsk_u32/64 _bextr_u32/64`; `_pdep_u32/64 _pext_u32/64 _bzhi_u32/64 _mulx_u64` |
| pclmulqdq, aes, sha | `_mm_clmulepi64_si128`; `_mm_aesenc_si128 _mm_aesenclast_si128 _mm_aesdec_si128 _mm_aesdeclast_si128 _mm_aesimc_si128 _mm_aeskeygenassist_si128`; `_mm_sha1rnds4_epu32 _mm_sha1nexte_epu32 _mm_sha1msg1/2_epu32 _mm_sha256rnds2_epu32 _mm_sha256msg1/2_epu32` |
| avx | 256-bit float `_mm256_add/sub/mul/div/sqrt/min/max/and/or/xor_ps/pd _mm256_cmp_ps/pd _mm256_blendv_ps/pd _mm256_movemask_ps/pd _mm256_broadcast_ss/sd`; `_mm256_loadu/storeu_si256/ps/pd _mm256_set1_* _mm256_setzero_* _mm256_castsi256_si128 _mm256_castsi128_si256 _mm256_extractf128_* _mm256_insertf128_* _mm256_permute2f128_* _mm256_testz_si256 _mm256_zeroupper` and the casts |
| avx2 | the 256-bit forms of every sse2/ssse3/sse4.1 integer name above (`_mm256_add_epi8` ... `_mm256_shuffle_epi8 _mm256_alignr_epi8 _mm256_movemask_epi8 _mm256_cvtepu8_epi16` ...), and `_mm256_permute4x64_epi64 _mm256_permutevar8x32_epi32 _mm256_permute2x128_si256 _mm256_inserti128_si256 _mm256_extracti128_si256 _mm256_broadcastb/w/d/q_epi* _mm256_sllv/srlv_epi32/64 _mm256_srav_epi32 _mm256_i32gather_epi32 _mm256_i64gather_epi64 _mm256_maskload_epi32/64 _mm256_maskstore_epi32/64` |
| fma | `_mm_fmadd/fmsub/fnmadd/fnmsub_ps/pd`, the same with `_mm256_` |

That is about 650 names. AVX-512, F16C, VAES/VPCLMULQDQ and AMX come
later.

#### 2.3.3 `std::arch` (portable, every target)

| function | AArch64 | x86-64 | folds |
|---|---|---|---|
| `count_ones(x)`, `leading_zeros(x)`, `trailing_zeros(x)` (all integer widths) | cnt+addv, clz, rbit+clz | popcnt/lzcnt/tzcnt when known; else bsr/bsf+cmov, and popcount by halves inline | yes |
| `rotate_left(x, n)`, `rotate_right(x, n)` | ror | rol/ror | yes |
| `bswap(x)`, `bit_reverse(x)` | rev, rbit | bswap; bit_reverse a short sequence (pshufb when ssse3 is known) | yes |
| `wide_mul(a: u64, b: u64) -> (u64, u64)`, `wide_mul_signed` | mul + umulh/smulh | mul (rdx:rax) | yes |
| `prefetch(s, i)`, `prefetch_write(s, i)` | prfm pldl1keep/pstl1keep | prefetcht0 / prefetchw | — (a hint) |
| `spin_loop()` | yield | pause | — |
| `has("FEATURE") -> bool` | a constant (§2.4) | | always |
| `detect("FEATURE") -> bool` | cached run-time test (§2.5) | | when known or foreign |

std's existing `count_ones`, `leading_zeros` and `trailing_zeros` become
re-exports of these, so 0.16's AArch64-only `bits_kind` special case
disappears. `prefetch` takes a slice and an index and is never checked:
prfm and prefetcht0 never fault, so no check is needed for safety.

#### 2.3.4 The four workloads, mapped

This table is also `guide arch#recipes`, and `query arch --equiv` uses it:

| task | AArch64 | x86-64 (SSE2 / SSSE3 / AVX2) |
|---|---|---|
| SIMD hash probe (16-byte control group) | `vld1q_u8`, `vdupq_n_u8`, `vceqq_u8`, movemask = `vshrn_n_u16(vreinterpretq_u16_u8(m), 4)` → `vget_lane_u64` → `trailing_zeros / 4` | `_mm_loadu_si128`, `_mm_set1_epi8`, `_mm_cmpeq_epi8`, `_mm_movemask_epi8` → `trailing_zeros` |
| byte search (memchr, memchr2, Mula's first/last byte) | `vceqq_u8`, `vorrq_u8`, `vmaxvq_u8` (any), the shrn mask (where) | `_mm_cmpeq_epi8`, `_mm_or_si128`, `_mm_movemask_epi8`; `_mm256_*` with avx2 |
| UTF-8 validation (Keiser–Lemire) | `vextq_u8` (prev 1..3), `vshrq_n_u8`, `vqtbl1q_u8` ×3, `vandq_u8`, `vqsubq_u8`, `veorq_u8`, `vmaxvq_u8` (ASCII fast path and the error test) | `_mm_alignr_epi8`, `_mm_srli_epi16` + and, `_mm_shuffle_epi8` ×3, `_mm_subs_epu8`, `_mm_testz_si128`; avx2: `_mm256_permute2x128_si256` + `_mm256_alignr_epi8` |
| CRC-32C / CRC-32 | `__crc32cd`/`__crc32cb` (crc), `__crc32d` (gzip's polynomial); folding with `vmull_p64` (aes) | `_mm_crc32_u64/u8` (sse4.2, C only); gzip's through `_mm_clmulepi64_si128` folding |
| Adler-32, Fletcher | `vpadalq_u8`, `vpaddlq_u16`, `vmlal_u8` or `vdotq_u32` (dotprod) for the weighted sum | `_mm_sad_epu8`, `_mm_maddubs_epi16`, `_mm_madd_epi16` |
| hashing (wyhash, xxh3) | `wide_mul`, `rotate_left`; xxh3's NEON: `vmull_u32`, `vpadalq_u32`, `veorq` | `wide_mul`; `_mm_mul_epu32`, `_mm_shuffle_epi32` |

### 2.4 Target features: known sets, inferred requirements

**Features.**
- Each architecture has a fixed list. AArch64: `neon` (alias `asimd`),
  `fp`, `crc`, `aes` (includes pmull), `sha2`, `sha3`, `dotprod`, `rdm`,
  `lse` (for 0.21), `fp16`, `i8mm`, `bf16` (the last three recognized
  but with no intrinsics in 0.19.0). x86-64: `sse`, `sse2`, `sse3`,
  `ssse3`, `sse4.1`, `sse4.2`, `popcnt`, `lzcnt`, `bmi1`, `bmi2`,
  `pclmulqdq`, `aes`, `sha`, `avx`, `avx2`, `fma`.
- Implications are closed, so enabling one enables what it needs: `avx2
  ⇒ avx ⇒ sse4.2 ⇒ sse4.1 ⇒ ssse3 ⇒ sse3 ⇒ sse2`, `fma ⇒ avx`, `sha3 ⇒
  sha2 ⇒ neon`.
- The architecture is a feature too: `aarch64`, `x86_64`. Every
  intrinsic of `std::arch::x86_64` requires `x86_64`.
- **Naming.** A name that exists on one architecture only names that
  one, so `avx2` implies `x86_64`. A qualified name `x86_64.aes` /
  `aarch64.aes` is always accepted. An unqualified name that exists on
  both (only `aes` in 0.19) means the *target's*. If that reading
  guards or enables code that uses the other architecture's intrinsics,
  the checker says so: `arch.feature_ambiguous`, with `try:` the
  qualified name.

**The build's baseline** (it is in the query cache key):

| target | baseline (default `-C target-cpu`) |
|---|---|
| aarch64-macos | `apple-m1`: neon, fp, crc, aes, sha2, sha3, dotprod, rdm, lse, fp16 |
| aarch64-linux | `generic`: neon, fp |
| x86_64-linux | `x86-64`: sse, sse2 |
| x86_64-macos | `core2`: up to ssse3 |

The baselines follow the platforms. Every Apple-silicon Mac is at least
an M1, as Rust's aarch64-apple-darwin assumes. Linux on arm64 promises
only Armv8.0 with SIMD, so the container exercises the detection paths
for crc, aes, sha2 and dotprod.

**Options.**
- `-C target-cpu=NAME|native`. Names: `generic`, `apple-m1`...`apple-m4`,
  `neoverse-n1`, `neoverse-v1`, `neoverse-n2`, `cortex-a72`, `cortex-a76`;
  `x86-64`, `x86-64-v2`, `x86-64-v3`, `x86-64-v4`, `core2`, `haswell`,
  `skylake`, `znver2`, `znver3`, `znver4`.
- `native` reads the compiling machine. It is an error (`arch.cpu`) when
  the target is another architecture.
- `-C target-feature=+x,-y` adds or removes features after the CPU's.
  Removing a feature the target's ABI needs (`-neon`, `-fp`, `-sse2`) is
  an error (`arch.baseline`).
- Both options are accepted by every command that checks (`check`,
  `query`, `edit`, `fix`, `test`), because they change which calls are
  legal.

**The known set at a program point** is:
- the baseline,
- plus the enclosing function's **declared** features: from
  `#[target_feature(enable = "avx2,fma")]`, or the clone's features
  under `#[multiversion]` (§2.7),
- plus the features of every **guard** the point is under.

A guard is a condition made of `std::arch::detect("f")` or
`std::arch::has("f")` atoms, possibly joined by `&&`:
- the `then` branch of `if G { ... }` knows G's atoms;
- the rest of a block after `if !G { DIVERGES }` knows them, where
  DIVERGES is a block of type `!` (`return`, `break`, `continue`, a panic,
  `exit`);
- the rest of a block after `assert(G)` knows them;
- the `else` branch of `if !G { ... } else { ... }` knows them.

`||` and negations elsewhere give nothing, and a `bool` stored in a local
gives nothing (`try:` inline the call into the condition). This is the
narrowing the roadmap asks for. It is computed on the checked AST by a
walk after checking, like 0.16's effects, never through checker hooks.

**Requirements are inferred, as effects are.** For each function F:

```
needs(F) = ∪ over calls c in F of ( needs(callee(c)) \ known(c) )
needs(intrinsic) = its table features
```

The sets are computed over 0.16's call-graph SCCs, callees first. Generic
instances and closures each get their own set, as they get their own
effects. So a closure calling an AVX2 helper, passed to `map` inside a
detect branch, makes the `map<closure>` instance need avx2, and the call
to `map` is legal because it is under the guard.

**Where requirements are checked.**
- A function that declares `#[target_feature]` must have `needs(F) ⊆
  declared(F)`. Otherwise it is `arch.declared`, reported at the call
  that adds the feature. A declaration pins the set, as `#[effects]`
  does, so a callee's body can no longer change what its callers must
  know.
- An entry point has nothing above it to know features for it, so
  `needs(F) \ baseline` must be empty for: `main`, an `extern "C"`
  function, `#[test]`/`#[property]`/`#[fuzz]` entries (0.18), and
  functions whose address is taken. Otherwise it is `arch.feature`,
  reported at the call in that function which brings the feature in, with
  the chain down to the intrinsic.
- Taking the address of a function that needs non-baseline features is
  `arch.fn_pointer`, unless the address is taken where those features
  are known *and* the pointer's type is a closure bound or a generic
  instance (both tracked). A plain `fn` value escapes the analysis, so
  it is refused (`try:` `#[multiversion]` or a closure with a detect
  branch).
- `has` is never inferred: it is true only for what is known at that
  point (baseline, declared, guards). Making it depend on inference
  would make it circular.

**Foreign architectures make cfg unnecessary.**
- A feature of another architecture is never known. `has("avx2")` and
  `detect("avx2")` on an AArch64 target are the constant `false`, so a
  branch under them is dead.
- The checker still type-checks it, and the requirement analysis still
  runs on it: x86 code in a portable program is checked on an arm host.
  objcheck and the compile-only tests depend on this, and so does an
  agent working on one machine.
- Branches whose condition is a constant `has`/`detect` are marked
  statically dead. Neither gen0 nor lowering generates code for them.
- A function that needs a foreign architecture's features is checked but
  never generated: every call to it is either under a constant-false
  guard (dead) or an error.

**Code generation is per instruction, not per function.**
- An intrinsic's instruction carries its own feature. The back end needs
  no "enabled features" mode to emit it.
- A function's known set still selects how *generic* operations are
  emitted: `Op::Bits` becomes popcnt when popcnt is known, and an AVX
  function's 128-bit operations use VEX encodings.
- So inlining across feature boundaries is always allowed. A legal call
  site already knows the callee's features, and inlining keeps the
  callee's intrinsics under the caller's guard (§5.2). This is a
  deliberate difference from LLVM, which refuses to inline a function
  with more features than its caller and so turns every small
  `#[target_feature]` helper into a real call.

### 2.5 Run-time detection

- **`std::arch::detect("f")`.**
  - When f is known at that point, or foreign, it folds to a constant.
  - Otherwise it reads one 64-bit static, `ARCH_FEATURES`, and tests one
    bit.
  - The IR op is `CpuFeat` (imm = the bit). It is pure: its value never
    changes during a run. So GVN merges repeated tests, LICM hoists a
    test out of a loop, and unswitching (`lsr.tach`) duplicates a loop
    that branches on it.
- **Late expansion.** Just before instruction selection, `CpuFeat`
  becomes:
  - a load and a bit test;
  - a `cbz`/`jz` on the word being 0 to a cold block that calls
    `std::arch::init_features()` and retries.

  The call lives only on the cold path, so the hot path clobbers no
  registers.
- **Initialization.**
  - A program whose `main` can reach `detect` calls `init_features()`
    once at start-up, before `main`. The cold path is then never taken.
  - A library entered from C, which has no tachyon start-up, takes the
    cold path once.
  - Bit 63 means "initialized", so a CPU with no optional features still
    caches.
- **Sources of the word** (std code, `compiler/std/arch.tach`):
  - **aarch64-linux:** `getauxval(AT_HWCAP)` and `AT_HWCAP2`, through C
    import.
  - **aarch64-macos:** `sysctlbyname("hw.optional.arm.FEAT_*")`, only for
    features beyond the baseline, so a default build reads nothing.
  - **x86-64:** `__cpuid_count(1/7, 0)`, plus `_xgetbv(0)` to check that
    the OS saves ymm state before it reports avx/avx2/fma, which avoids
    the classic SIGILL-free but state-corrupting bug. Both are table
    intrinsics (`cpuid`, `xgetbv`), safe because every x86-64 CPU has
    cpuid.
- **Testing the fallback branches.** `init_features()` clears the bits
  named in `TACHYON_ARCH_DISABLE=aes,crc,...`. It can only *clear* bits,
  so no setting of it can make a missing instruction run. The aarch64-linux
  container runs every detect test twice, with and without it.
- **Threads (0.21).** The word is written once, with the same value by
  every writer. In 0.21 the load and the store become relaxed atomics;
  until then std has no threads.

### 2.6 Memory operands: slices, bounds, raw forms

- **The vendor name is the safe form.** It takes a slice and an index,
  as 0.10's `v16u8::load(s, i)` does:
  - `vld1q_u8(s: [u8], i: i64) -> uint8x16_t`, checked `0 <= i && i +
    16 <= s.len`;
  - `vst1q_u8(s: [u8], i: i64, v: uint8x16_t)`;
  - `_mm_loadu_si128(s: [u8], i: i64) -> __m128i`. The x86 forms take
    the slice of their element type: `[u8]` for `si128`, `[f32]` for
    `ps`.
- **Aligned forms check alignment as well**: `_mm_load_si128`,
  `_mm_store_si128`, `_mm256_load_*`. A misaligned address stops the
  program with `misaligned access: address % 16 = 8` (exit 101). It
  never faults.
- **Gathers and masked accesses:**
  - `_mm256_i32gather_epi32(s: [i32], idx: __m256i, const scale)` checks
    every lane: max(idx) < s.len and min(idx) >= 0, three instructions
    plus a branch before the gather;
  - masked loads and stores check the whole range, masked-off lanes
    included. That is stricter than the hardware, which is safe, and the
    guide says so.
- **The checks are ordinary bounds checks.** Range analysis removes them
  in counted loops, exactly as for `v.load(s, i)`: one hoisted check per
  loop, or none.
- **Raw forms keep the vendor signatures, `unsafe`.** They live in
  `std::arch::aarch64::raw::vld1q_u8(p: *u8)` and
  `std::arch::x86_64::raw::_mm_loadu_si128(p: *__m128i)`, for porting C
  and Rust code. They have effect `unsafe`, and `--check-unsafe` checks
  them against the program's heap blocks, as it checks any raw access.
- **0.17 references.**
  - Until 0.17's split slices (U2) land, stores take today's writable
    `[T]`.
  - With them, stores take `&mut [T]` and loads `[T]`, and `fix --values`
    migrates the calls. It is one commit in the std declarations, made by
    the table generator.
  - The place forms `&[T; N]` / `&mut [T; N]` (no check: the type proves
    the length) are in 0.19.0 if 0.17's references have landed by then,
    else in 0.19.1.

**Effects** (0.16), from the table:

| intrinsic | effect |
|---|---|
| register-only intrinsic | none |
| a safe memory form | `panic` (its check) |
| a raw form | `unsafe` |
| `detect`, `has` | none |
| `prefetch`, `spin_loop` | none |

So `#[pure]` code may use SIMD freely.

### 2.7 Multiversioning: sugar

```tach
#[multiversion("avx2", "sse4.2", "dotprod")]
fn count_byte(s: [u8], b: u8) -> i64 { ... if std::arch::has("avx2") { ... } ... }
```

- **The clones.** The compiler makes one clone per listed feature set
  that belongs to the target's architecture, plus the baseline version.
  Each clone has those features *declared*, so `has` folds differently in
  each. The vectorizer, isel and VEX selection see each clone's set.
- **The dispatcher.** The function's name becomes a dispatcher:
  `if detect("avx2") { avx2 clone } else if detect("sse4.2") { ... }
  else { baseline }`. It is ordinary inlinable code: no ifunc, no
  indirect call, and LICM hoists the tests out of the caller's loop.
- **Checking the clones.** Every clone must check. An intrinsic call that
  only one clone can make must be under `has`, else it is
  `arch.multiversion`, naming the clone.
- **Address-taking.** A multiversioned function's address can be taken
  (`arch.fn_pointer` does not apply): its dispatcher needs only the
  baseline.

### 2.8 Alternatives considered

- **Rust's model: `#[target_feature]` on every function that uses an
  intrinsic, and the call is `unsafe` unless the caller has the
  feature.**
  - Rejected for two reasons. Every helper needs the attribute, a
    boilerplate agents get wrong. And "unsafe" is the wrong tool here:
    the property can be checked, so no-UB demands that it be checked,
    not trusted.
  - The *declaration* is kept as a pin, and inference fills the rest,
    the decision 0.16 made for effects and 0.17 for view summaries.
- **No inference, but a feature error at every intrinsic call outside a
  declared or guarded region** (closer to Rust 1.86's safe
  target-feature calls).
  - Simpler and more local. But it forces the attribute onto every
    helper, multiversion bodies can no longer call shared helpers, and
    closures passed to iterator adapters cannot use SIMD at all.
  - Rejected for inference, with entry points and declarations as the
    places errors appear.
- **Intrinsics as std source** (thousands of bodyless `#[intrinsic] fn`
  declarations). It would make std's text about 400 KB larger and give
  the lazy-section index thousands of words. The table would still be
  needed by the back end, so there would be two sources of truth.
  Rejected for virtual modules.
- **Lowering every intrinsic to an opaque `Op::Intr`.** Simplest, but the
  optimizer would lose `vaddq_u8 ≡ a + b`, the loads' alias facts and
  every fold. Rejected: intrinsics with an exact generic equivalent lower
  to it (§5.1).
- **LLVM-style `shufflevector` as the one permute op**, with the back end
  pattern-matching it back to ext/zip/tbl/pshufb. Rejected: it breaks the
  "one intrinsic, one instruction" promise whenever the matcher misses.
  Permutes are `Op::Intr` with their exact instruction, and a later
  release may canonicalize.
- **ifunc-style dispatch for `#[multiversion]`** (a function pointer
  resolved once). Rejected: an indirect call per invocation, opaque to
  inlining. A chain of cached tests costs a load and a predictable branch,
  and LICM removes even that from loops.
- **Lazy-only detection** (no start-up init). Rejected for programs with
  `main`: the cold path would be taken once anyway, and the start-up init
  costs one sysctl, auxval read or cpuid. Kept for C-entered libraries.
- **`cfg(target_arch)`.** Tachyon has no conditional compilation, and
  0.19 does not add it. Foreign-feature guards (§2.4) give the same
  result and keep both architectures' code type-checked everywhere. A
  general `cfg` stays possible later, for OS differences (0.20's I/O).
- **`has::<"neon">()`** (the roadmap's spelling). Tachyon has no const
  generics. `has("neon")` with a required string literal
  (`arch.feature_literal`) gives the same constant, and agents write it
  naturally.
- **x86 vendor types as aliases of `v2i64`.** Rejected (§2.2): silent
  lane-width bugs.

### 2.9 What agents see

The aim:
- an agent finds the right intrinsic without reading a vendor manual;
- it never needs to know the feature analysis to write correct code;
- every rejection says what to run.

All diagnostics follow the 0.11 contract: one line `error[CODE]`, then
`help:`, then `try:` lines that run as they are. A test (tests/arch-try,
T8) runs every `try:` of the arch error tests and checks that the program
then checks clean or reports a different, named next step.

**Discovery.**
- `tachyonc guide arch` gives the model in about 2,500 tokens: types,
  `has`/`detect`, the known set, slices, the recipes table of §2.3.4,
  and the NEON movemask idiom.
- `query arch --find WORDS` searches the table's doc and semantics lines
  and prints one intrinsic per line with feature and instruction:
  ```text
  $ tachyonc query arch --find 'saturating subtract u8'
  vqsubq_u8        neon     uqsub v.16b     lanewise a - b, saturating at 0 (u8)
  vqsub_u8         neon     uqsub v.8b      the same, 64-bit
  x86_64::_mm_subs_epu8   sse2  psubusb     lanewise a - b, saturating at 0 (u8)
  ```
- `query arch --equiv NAME` gives the other architecture's equivalent, or
  the recipe when there is no single instruction:
  ```text
  $ tachyonc query arch --equiv _mm_movemask_epi8
  _mm_movemask_epi8 (x86_64, sse2): no single AArch64 instruction
  aarch64 recipe (guide arch#movemask): vshrn_n_u16(vreinterpretq_u16_u8(m), 4) -> vget_lane_u64(_, 0): 4 bits per byte; trailing_zeros(x) / 4 is the first set lane
  ```
- `query show`/`def` on an intrinsic print the synthesized declaration
  with the table's facts:
  ```text
  $ tachyonc query show vqtbl1q_u8
  // std::arch::aarch64::vqtbl1q_u8  intrinsic  feature: neon  instruction: tbl Vd.16b, {Vn.16b}, Vm.16b  effects: none
  // r[i] = if idx[i] < 16 { t[idx[i]] } else { 0 }   (x86_64: _mm_shuffle_epi8 zeroes when bit 7 is set instead)
  pub fn vqtbl1q_u8(t: uint8x16_t, idx: uint8x16_t) -> uint8x16_t
  ```
- `query items std::arch::aarch64 --feature crc` lists one feature's
  intrinsics.
- `query arch --features [-C ...]` prints the build's baseline, the
  features of a CPU, and which detect calls fold.
- `query features NAME` prints a function's requirement, `inferred` or
  `declared`, and `--why FEATURE` gives the chain of calls down to the
  intrinsic.
- `query def`, `show` and `context` print `features: avx2 (inferred)`
  after `effects:` on the first line of any function that needs
  something beyond the baseline.

**The diagnostics.** `check` prints them on one line, joined by ` | `.
Below, the parts are split for reading.

1. **A call that needs a feature the point does not know** (the
   commonest).
```text
sum.tach:14:13: error[arch.feature] 'sum_avx2' needs avx2 (from '_mm256_add_epi32' at sum.tach:5:17), which 'main' does not know here: x86_64-linux's baseline is sse2
  help: test the CPU and keep a fallback, compile one function per feature set with #[multiversion], or build only for CPUs that have it
  try: tachyonc edit patch sum.tach:14 --old 'sum_avx2(s)' --new 'if std::arch::detect("avx2") { sum_avx2(s) } else { sum_scalar(s) }'
  try: tachyonc sum.tach -C target-feature=+avx2 -o sum
  try: tachyonc query features sum_avx2 --why avx2
```
The first `try:` names a fallback only when one exists: a function in
scope with the same parameter and result types, needing nothing beyond
the point's known set, whose name shares the stem (`sum_avx2` →
`sum_scalar`, `sum_portable`, `sum`). Otherwise that line is left out and
`help:` says to write one.

2. **A declaration that is too small.**
```text
crc.tach:9:9: error[arch.declared] 'fold' is #[target_feature(enable = "neon")], but '__crc32cd' at crc.tach:9:9 needs crc
  try: tachyonc edit patch crc.tach:7 --old 'enable = "neon"' --new 'enable = "neon,crc"'
```

3. **A Rust spelling.** The diagnostic takes the place of the "unknown
   function" or type error.
```text
scan.tach:8:17: error[arch.rust_form] 'vshrq_n_u8::<3>(v)': tachyon passes an intrinsic's immediates as arguments
  try: tachyonc edit patch scan.tach:8 --old 'vshrq_n_u8::<3>(v)' --new 'vshrq_n_u8(v, 3)'
scan.tach:3:13: error[arch.raw_form] 'vld1q_u8(p)' passes a pointer: the safe form takes a slice and an index ('vld1q_u8(s, i)'); the pointer form is 'std::arch::aarch64::raw::vld1q_u8' (unsafe)
  try: tachyonc edit patch scan.tach:3 --old 'vld1q_u8(p)' --new 'vld1q_u8(s, i)'
scan.tach:2:8: error[arch.rust_form] 'is_x86_feature_detected!("avx2")' is std::arch::detect("avx2") here
  try: tachyonc edit patch scan.tach:2 --old 'is_x86_feature_detected!("avx2")' --new 'std::arch::detect("avx2")'
```
`raw_form` writes `s, i` only when the pointer is `s.ptr + i` or
`&s[i]` and the slice is in scope. Otherwise it leaves out the `try:`,
and `help:` explains the slice form.

4. **An immediate out of range.**
```text
utf8.tach:21:20: error[arch.const_arg] 'vextq_u8' takes n in 0..=15; got 16
```

5. **An unknown or ambiguous feature name** (with did-you-mean).
```text
fast.tach:4:24: error[arch.feature_name] unknown feature 'avx-2' for x86_64
  try: tachyonc edit patch fast.tach:4 --old '"avx-2"' --new '"avx2"'
```

6. **An entry point or function pointer.**
```text
lib.tach:30:1: error[arch.feature] 'hash_block' is extern "C", so its callers cannot know aes, which it needs (vaeseq_u8 at 33:13): guard the call or build with -C target-feature=+aes
```

7. **`unsafe` around safe intrinsic calls**, written from Rust habit:
   the existing unused-`unsafe` warning, fixed by `fix --only unsafe`.

**`explain`.** Every `arch.*` code has an entry: `arch.feature`,
`arch.declared`, `arch.feature_name`, `arch.feature_ambiguous`,
`arch.feature_literal`, `arch.const_arg`, `arch.fn_pointer`,
`arch.multiversion`, `arch.cpu`, `arch.baseline`, `arch.raw_form`,
`arch.rust_form`, `arch.misaligned` (the run-time message). `explain arch`
lists them.

## 3. Examples

**A byte search, portable, with SIMD on both architectures.**

```tach
use std::arch::aarch64::{uint8x16_t, vceqq_u8, vdupq_n_u8, vget_lane_u64, vld1q_u8,
    vreinterpret_u64_u8, vreinterpretq_u16_u8, vshrn_n_u16};
use std::arch::x86_64::{_mm_cmpeq_epi8, _mm_loadu_si128, _mm_movemask_epi8, _mm_set1_epi8};
use std::arch::{detect, trailing_zeros};

// The first i with s[i] == b, or -1.
fn find(s: [u8], b: u8) -> i64 {
    let mut i = 0;
    if detect("neon") {                       // aarch64: always true, folds; x86: false, dead
        let needle = vdupq_n_u8(b);
        while i + 16 <= s.len {
            let eq = vceqq_u8(vld1q_u8(s, i), needle);
            let mask = vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0);
            if mask != 0 { return i + trailing_zeros(mask) / 4; }
            i += 16;
        }
    } else if detect("sse2") {                // x86: baseline, folds; aarch64: dead
        let needle = _mm_set1_epi8(b as i8);
        while i + 16 <= s.len {
            let m = _mm_movemask_epi8(_mm_cmpeq_epi8(_mm_loadu_si128(s, i), needle));
            if m != 0 { return i + trailing_zeros(m as u32); }
            i += 16;
        }
    }
    while i < s.len { if s[i] == b { return i; } i += 1; }
    -1
}
```

On aarch64 at -O2:
- the loop is ld1/cmeq/shrn/fmov/cbnz/add/cmp/b.le;
- `vld1q_u8`'s check is gone: the loop condition implies it;
- the x86 branch was type-checked and never generated.

objcheck on x86_64-macos encodes the other branch.

**CRC-32C on aarch64-linux, where crc is not baseline.**

```tach
use std::arch::aarch64::{__crc32cb, __crc32cd};
use std::arch::detect;

fn crc32c(s: [u8], crc: u32) -> u32 {
    if !detect("crc") { return crc32c_table(s, crc); }    // narrowing: crc known below
    let mut c = ~crc;
    let mut i = 0;
    while i + 8 <= s.len {
        c = __crc32cd(c, le64(s, i));        // le64: the 8 bytes at i, little-endian (a load at -O2)
        i += 8;
    }
    while i < s.len { c = __crc32cb(c, s[i]); i += 1; }
    ~c
}
```

On aarch64-macos `detect("crc")` folds to `true` and the table fallback
is dead. In the linux container one bit is tested per call, and LICM
hoists the test when `crc32c` is inlined into a loop.

**A Swiss-table group probe** (what 0.20's HashMap uses).

```tach
fn match_byte(group: uint8x16_t, h2: u8) -> u64 {           // a mask, 4 bits per lane
    let eq = vceqq_u8(group, vdupq_n_u8(h2));
    vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(eq), 4)), 0)
}
```

`match_byte` takes and returns vectors in v registers (§2.2). Inlined, it
is dup, cmeq, shrn and fmov: four instructions.

**Multiversioning, one body.**

```tach
#[multiversion("avx2", "dotprod")]
fn dot_u8(a: [u8], b: [u8]) -> u32 {
    if std::arch::has("dotprod") {            // true only in the dotprod clone (aarch64-linux)
        // vdotq_u32 loop
    } else if std::arch::has("avx2") {        // true only in the avx2 clone (x86_64)
        // _mm256_maddubs_epi16 / _mm256_madd_epi16 loop
    } else {
        // portable loop; the vectorizer handles it per clone
    }
}
```

On aarch64-macos dotprod is baseline, so there is one version and no
dispatcher. On aarch64-linux there are two versions and a one-bit
dispatch. On x86_64 there are two versions.

**The examples directory.** `examples/arch/` holds four programs, each
with its portable version, a timing and a README session that
tests/walkthrough runs:
- `bytesearch`: memchr and memchr2;
- `crc32c`;
- `utf8` (Keiser–Lemire);
- `swissprobe`.

## 4. Front end

- **Parsing.**
  - `#[target_feature(enable = "a,b")]` and `#[multiversion("f", ...)]`
    on functions, stored on the Def.
  - `-C target-cpu`/`-C target-feature` in `main.tach`'s option parser
    and in the tools' option pass-through (`tools::edit::cli`,
    `tools::fix::command`, `tools::edit::apply` forward them like
    `--target`).
- **Types** (`front/types.tach`, `front/check/vectors.tach`):
  - the 18 new vector type names are reserved like 0.10's;
  - the opaque x86 types;
  - `from_bits`;
  - unsigned compares and masks;
  - lane types for `lane`, `sum` and `with_lane`.
- **Resolution** (`arch/virtual.tach`): a path into `std::arch*` resolves
  through the table. The item made is a Def with `intrinsic = id`, a
  signature and no body, cached per id.
- **Calls** (`front/check/arch.tach`): ordinary call checking, then the
  table's const-parameter ranges, then the Rust-form diagnostics.
- **Features** (`front/features/`, a pass after `infer_effects`):
  - `regions.tach`: the guard walk that computes `known(c)` per call
    node, and the static deadness of `has`/`detect` branches (a node
    flag gen0 and lowering read);
  - `infer.tach`: `needs` over the SCCs, reusing `components`, with the
    set stored next to the effects;
  - `check.tach`: declarations, entries, address-taking, multiversion
    clones;
  - `why.tach`: the chains for `query features --why` and for the
    diagnostics.
  - **Cost.** One walk over bodies plus one bit-set per function: under
    1% of check time. A program that names no `std::arch` item skips
    the pass entirely, because every requirement is then empty.
- **Multiversion** (`front/features/multiversion.tach`): after
  collection, before bodies are checked, each listed set gets a clone of
  the function's AST (the generics instantiation machinery's copier),
  with declared features. The original Def becomes the dispatcher body
  of §2.7.
- **Effects.** Intrinsic Defs take their effects from the table, so 0.16's
  inference sees them as it sees C functions with declared effects.

## 5. Lowering, the optimizer and the back ends

### 5.1 Lowering (`middle/lower/arch.tach`)

Each intrinsic lowers by its table's IR form:

| IR form | lowers to | examples |
|---|---|---|
| `vbin.OP`, `vcmp.COND`, `vsel`, `vsplat`, `vext`, `vins`, `vneg`, `vsum` | the existing vector op, on the unsigned type where needed | `vaddq_u8`, `vceqq_u8`, `vbslq_u8`, `vdupq_n_u8`, `vgetq_lane_u8`, `vaddvq_u8`, `_mm_add_epi8`, `_mm_cmpeq_epi8` |
| `bits.K`, `rot`, `bswap`, `wmul` | `Op::Bits`; new `Op::Rot`, `Op::BSwap`; `MulH` + `Mul` | portable intrinsics, `_popcnt64`, `_lzcnt_u64`, `__clz` |
| `cast` | nothing: the value with the new type (a register-preserving `Conv` the allocator coalesces) | `vreinterpretq_*`, `_mm_castsi128_ps` |
| `load(N)`, `store(N)` | 0.10's vector bounds check, then an ordinary `Load`/`Store` of the vector type | `vld1q_u8`, `vst1q_u8`, `_mm_loadu_si128` |
| `load.dup` | check, scalar `Load`, `VSplat` (isel fuses the two into `ld1r`) | `vld1q_dup_u8` |
| `intr` | **`Op::Intr`** (imm = the table id; up to three operands in a, b, c; the const arguments in imm2 and the args list) | `vqsubq_u8`, `vqtbl1q_u8`, `vextq_u8`, `vshrn_n_u16`, `__crc32cd`, `vaeseq_u8`, `_mm_shuffle_epi8`, `_mm_movemask_epi8` |
| `intr.mem` | **`Op::IntrMem`**, with its address operand and the byte range it touches recorded (`aux`) | `vld2q_u8`, `_mm256_i32gather_epi32`, `_mm256_maskload_epi32`, the raw forms of multi-register loads |
| `feat` | **`Op::CpuFeat`** (pure; expanded late, §2.5) | `detect` |
| `hint` | **`Op::Hint`** (kept by DCE, not a write for alias analysis) | `prefetch`, `spin_loop` |

**Further lowering rules.**
- **Two-result intrinsics** (`vzipq_u8` → `uint8x16x2_t`) are two `Intr`
  ops (zip1 and zip2): the same instruction count as the hardware.
- **256-bit legalization.** On a function without 256-bit registers, a
  256-bit vector lowers as two 128-bit SSA values: every op twice, loads
  and stores at offsets 0 and 16.
- **Constant vectors.** A vector whose lanes are all constant becomes
  **`Op::VConst`** (imm = an index into a per-program pool of 16/32-byte
  blobs). Statics holding vector constants, and `vNtT(...)` of constants,
  produce it. This is what makes `tbl`/`pshufb` lookup tables cheap
  (§5.3).
- **gen0** (`gen0/gen/arch.tach`): -O0 evaluates the arguments to slots,
  loads the vector operands into fixed registers (v0-v2 / xmm0-xmm2,
  ymm with AVX), emits the table's instruction template with those
  registers and the immediates, and stores the result. A generic-form
  intrinsic at -O0 goes through 0.10's lane-by-lane code, so -O0 stays
  an independent oracle for every intrinsic that has a generic
  equivalent.

### 5.2 The optimizer

| pass | what changes |
|---|---|
| `ir` | new ops `Intr IntrMem VConst CpuFeat Hint Rot BSwap`. `is_pure` covers `Intr` with the table's `pure` flag, plus `CpuFeat`, `Rot`, `BSwap`, `VConst`. `is_vector` covers the vector ones. `has_side_effect` covers `IntrMem` stores and `Hint`. |
| `gvn` | `Intr` numbered by (id, operands, const args), with operands sorted when the table says commutative. `IntrMem` loads take part in memory forwarding through their recorded range. `CpuFeat` numbered by its bit, so repeated detects merge. |
| `licm` | a pure `Intr` whose features are in the function's known set (baseline or declared) is hoisted like any pure op. **One whose features are known only under a guard is never speculated**: it is hoisted only when `runs_first` holds (LICM's rule for ops that may trap). The same for `ifconv` (no arm containing one is if-converted), `sroa`/`copies` (they never move ops), and the inliner (§2.4). This is the no-UB line in the optimizer: an instruction the CPU may lack never runs earlier than its guard. |
| `adce`, `opt` (dead code) | pure `Intr`, `CpuFeat`, `VConst` removed when unused; `Hint` kept |
| `fold` | **new: vector folding.** `VBin`, `VCmp`, `VSel`, `VSplat`, `VExt`, `VIns`, `VSum`, `VNeg` on `VConst`/splat operands fold, and `Intr` folds through the table's `fold` class: lanewise saturating/halving/abs-diff/min/max/shift/narrow/widen/pairwise/horizontal, `ext`/`zip`/`uzp`/`trn`/`rev`, `tbl`/`tbx`/`pshufb` with a constant index, `movemask`, `cnt`/`clz`/`rbit`, crc32 (a byte at a time), and the portable ops. Crypto rounds are not folded (no workload needs it). `fold_value` dispatches to `fold/arch.tach`. |
| `vectorize` | (1) loops containing an `Intr` are left alone: they are explicit SIMD already. (2) The portable scalar ops `Bits(ones)`, `BSwap` and `Rot` in a loop body become vector lanes (`cnt`+`uaddlp` chain, `rev`, shifts and orr) instead of blocking the loop. (3) The memory intrinsics' checks are the bounds checks the legality pass already proves for the whole loop. |
| `lsr` (unswitching) | already unswitches on loop-invariant conditions. `CpuFeat` is one, so a detect inside a hot loop costs nothing. Tested. |
| `range` | the loads' and stores' checks are ordinary `idx <u len` checks: removed in counted loops, hoisted elsewhere |
| `inline` | an `Intr` costs 1. A function whose body is one intrinsic call is always inlined at -O1 and -O2. |
| `effects_verify` | the table's effects are trusted, as declared C effects are |

**The vectorizer and target features.** In 0.19.0 the vectorizer keeps
SSE2 and NEON widths. AVX2 vectorization of scalar loops in `avx2`
functions and clones, and `sdot`/`udot` for i8 dot-product loops on
dotprod, are 0.19.x. The first needs x86 execution testing. The second
waits for the property tests (0.18) to cover it.

### 5.3 Back end: AArch64

- **`isel`.** `Intr` passes through unchanged; its const arguments are
  already immediates. `Load`+`VSplat` becomes `ld1r` when the load has no
  other use. `VConst` becomes:
  - `movi`/`mvni` when the constant is a modified-immediate pattern
    (splats of 8-bit patterns, zero, all ones);
  - `fmov` for float splats that fit;
  - otherwise `adrp` + `ldr q` from a 16-byte-aligned literal pool in
    `__TEXT,__literal16` / `.rodata.cst16`.

  LICM hoists it as a rematerializable constant.
- **`regalloc`.**
  - Operand classes come from the table: a vector register, a general
    register (crc's `w`/`x` operands, `fmov`/`umov` results), or an
    immediate.
  - A **tied** destination is the accumulator of `sdot`, `bsl`, `tbx`,
    `aese`, `sha256h`, `sra`, `sli` and `mla`. The allocator hints the
    result into the tied operand's register. The emitter adds a `mov`
    when the hint fails, which is what `ma_vmacw` does today.
  - `uint8x16x2_t` table operands (`tbl2`/`tbx2`, `ld2`/`st2`) need two
    consecutive registers. 0.19.0 moves them into the instruction
    temporaries v30/v31 (two `mov`s; documented). Tuples of three or
    four need consecutive allocation in the allocator, which is 0.19.x
    (§2.3.1).
- **`mc_arm64/arch.tach`.** One function, `ma_intr(id, d, ops, imms)`,
  formats the table's template into the text. When the program uses a
  non-baseline feature for the target, the text gets `.arch_extension
  crc|aes|sha2|sha3|dotprod` directives at the top. `cc -c` (GNU as on
  Linux) needs them to accept the instructions; the compiler's assembler
  ignores them.
- **`enc_arm64/simd.tach`.**
  - A table-driven encoder for the Advanced SIMD and crypto encoding
    classes: three same, three different, two-register misc, across
    lanes, copy, modified immediate, shift by immediate, permute,
    extract, table lookup, vector × element, the crypto AES, SHA-2 (two
    and three registers) and SHA-3 classes, and CRC32 in the
    data-processing class.
  - `insn_a64.def` gives each mnemonic's class and fixed bits per
    arrangement. Today's 93-mnemonic `if` chain stays for the scalar
    instructions; the vector ones move into the table.
  - This replaces about 90 lines of `a64_simd` with about 400 lines of
    class encoders plus data.

### 5.4 Back end: x86-64 (compile-tested only in 0.19.0)

- **Encodings.** Legacy SSE is `66/F2/F3` + `0F`/`0F38`/`0F3A` + opcode +
  ModRM (+ imm8), which extends `enc_x86`'s `sse()` table. AVX is VEX:
  the two- and three-byte prefixes with L, W and vvvv, the same
  `insn_x86.def` line with a `vex` flag. BMI uses VEX on general
  registers.
- **Two-operand SSE forms** go through `mx_v2op`: commutative ones swap,
  and the others get a `movdqa` first when the result is not the first
  operand.
- **Functions that know avx.**
  - Every vector op, generic ones included, is emitted in its VEX
    three-operand form: no copies, and no SSE/AVX transition penalty.
  - 256-bit values are `ymm` intervals: the same register numbers,
    32-byte spill slots, and the spill area aligned to 32.
  - `vzeroupper` goes before every call and every return of a function
    that wrote a ymm register. The calling convention keeps 256-bit
    values as two xmm leaves (§2.2), so no ymm crosses a call.
- **Detection** uses `cpuid` (clobbers eax/ebx/ecx/edx: fixed intervals,
  like a division's rax/rdx) and `xgetbv`.
- **What is checked without running.**
  - objcheck at `-t x86_64-macos` over the corpus. Every new
    `tests/run/arch_x86_*` case is part of it: it is compiled and
    assembled both ways and the disassembly compared. `cc -arch x86_64`
    and the link run on the arm host.
  - A new runner directive, **`// CROSS: x86_64-linux`**: the case is
    also compiled with `-S` for that target, its `ASM(x86_64-linux)` lines
    are checked, and nothing runs.
  - `--verify-regalloc` on those compilations.
  - **What waits:** running the x86 property tests, the fuzzer's
    intrinsic mode on x86, and the x86 benchmarks. They are written in
    0.19 and kept out of the runs by the gate's x86 switch only (no
    XFAIL), so they run as soon as x86 testing is re-enabled, with no
    code change.

## 6. Testing

1. **Every intrinsic against a scalar reference, at every level.**
   - `tests/arch/gen.sh` writes, from the tables, one program per family
     and type. Each calls the intrinsic on edge vectors (0, 1, MAX, MIN,
     -1, 0x80..., NaN, ±0.0, ±inf, denormals) and on 2,000 random
     vectors (xorshift, seeded), and compares lane by lane with the
     reference.
   - For lanewise families the reference is generated from the table's
     `semantics` line, so one line is the spec, the doc and the test.
   - Non-lanewise ones (tbl/tbx, ext, zip family, movemask, narrowing
     pairs, crc, aes, sha, pmull, dot products, string compares) have
     hand-written references in `tests/arch/ref/*.tach`.
   - 8-bit unary ops are checked exhaustively (256 inputs), and 8-bit
     binary ops on all 65,536 pairs for one lane position.
2. **Constant folding against the instruction.**
   - Each generated program runs every case twice: once with operands
     from a run-time source (`std::black_box`-like: an opaque load), once
     with literals, which -O2 folds.
   - Both must equal the reference. This catches a fold that disagrees
     with the hardware.
3. **Crypto and checksums by known answers.**
   - AES: FIPS-197 appendix C, built from `vaeseq`/`vaesmcq` rounds.
   - SHA-1 and SHA-256: FIPS 180-4 examples.
   - CRC-32 and CRC-32C: the check values `0xCBF43926` and `0xE3069283`,
     plus random buffers against table implementations.
   - pmull against a scalar carry-less multiply.
4. **The optimizer** (`tests/run/opt_arch_*.tach`, IR and `ASM(T)`
   checks):
   - GVN merges identical intrinsics;
   - LICM hoists a pure baseline intrinsic and **does not hoist a guarded
     one above its detect**: an aarch64-linux IR test with `crc`;
   - the bounds checks of `vld1q_u8` in a counted loop disappear;
   - a `tbl` table is a hoisted `VConst`;
   - `detect` in a loop is hoisted or unswitched;
   - one intrinsic is one instruction: the `ASM` lines count them for
     each family's representative;
   - `has` branches are absent from the output;
   - foreign-architecture functions are not generated.
5. **Features and diagnostics** (`tests/run/arch_err_*.tach`):
   - every `arch.*` code, with ERROR lines;
   - `-C` combinations;
   - narrowing forms: `&&`, early return, `assert`, else of `!`;
   - closures through `map`;
   - multiversion clones;
   - the entries of §2.4.

   **tests/arch-try** runs every `try:` they print.
6. **Detection.**
   - In the aarch64-linux container, every test that uses detect runs
     twice: plain, and with `TACHYON_ARCH_DISABLE` naming every optional
     feature. Both runs must print the same thing, since the fallbacks
     compute the same result.
   - On aarch64-macos, `-C target-cpu=generic` builds of the same tests
     take the detect paths through sysctl.
7. **The fuzzer gains `-A`** (`tests/fuzz/genarch.awk`): random
   expression trees over 128-bit intrinsics and portable vector ops on
   random slices. It compares -O0 (gen0's fixed-register templates and
   lane-by-lane generic ops), -O1 and -O2, at random slice offsets near
   the bounds. It runs in the gate's fuzz row.
8. **Encodings.**
   - objcheck on aarch64-macos and aarch64-linux, with the generated
     programs part of the corpus, so every intrinsic is assembled both
     ways at least once with its immediate's extreme values.
   - For x86, `objcheck -t x86_64-macos arch_` and the `CROSS` cases
     (§5.4). One `tests/arch/all_x86_64.tach` calls every x86 intrinsic
     once.
9. **Examples and benchmarks.**
   - `examples/arch/*` with walkthrough sessions.
   - bench/ pairs against C with `arm_neon.h`/`arm_acle.h` (clang -O2,
     the same algorithm): `bytesearch`, `utf8`, `crc32c`, `swissprobe`.
   - **The bench gate:** within 5% of clang on aarch64-macos. Today's
     benches must not get slower, since the calling-convention change
     touches every vector call.

**0.18's property tests.** When 0.18 ships, the generated programs of
items 1 and 2 become `#[property]` tests with generators derived from the
vector types, run by `tachyonc test` with its built-in -O0/-O2
comparison. Until then they are plain programs with an explicit xorshift
loop, so nothing in 0.19 waits for 0.18. The conversion is mechanical, in
the generator (T7).

## 7. Phase 0, then parallel tasks

### 7.1 Dependencies

| needs | from | parts of 0.19 that wait |
|---|---|---|
| `&mut [T]` (split slices, 0.17 U2) | 0.17.0 | only the *spelling* of store intrinsics' slice parameter; developed with today's `[T]`, migrated by one generator commit plus `fix --values` |
| `&[T; N]` / `&mut [T; N]` place forms | 0.17.0 | the place forms of loads and stores (§2.6); 0.19.1 if 0.17 is late |
| plain kind (0.17 §2.1) | 0.17.0 | nothing: vectors are plain by structure |
| `#[property]`, `tachyonc test` | 0.18 | the conversion of the reference tests (§6); the harness exists before |
| `#[test]/#[fuzz]` entries as feature entry points | 0.18 | one line in `front/features/check.tach` |
| per-function pipeline, parallel codegen | 0.17 speed track / 0.18 | the table is parsed in the front end (single-threaded) and read-only after; the back end keeps no new mutable globals |
| compiler/src using std::arch (e.g. crc32 for interning hashes) | 0.20 | the release rule: 0.19's features in compiler/src from 0.20; `-C target-cpu=native` detection in the compiler therefore uses sysctl/getauxval/`/proc/cpuinfo` and `sysctl machdep.cpu`, not `std::arch` |

**What can start now, before 0.17 and 0.18 ship.** Everything except
the two spelling changes and the property-test conversion:
- the tables;
- the types;
- the feature model;
- detection;
- both back ends;
- the optimizer work;
- the tools and guide.

The conflict risk is in shared files. 0.17's T5 owns
`middle/{copies,gvn,licm,vectorize,inline}` and 0.18 moves the IR to
per-function arenas. So 0.19's optimizer task (T6) rebases after 0.17's
T5 merges. Its first commits are self-contained new files
(`fold/arch.tach`, `lower/arch.tach`).

### 7.2 Phase 0: the interface commit (serial, the lead)

After it, each task builds against fixed signatures and stubs. It
contains:

- **`compiler/arch/`:**
  - the `.def` formats, documented in `compiler/arch/README.md`;
  - `embed.sh`;
  - **20 seed intrinsics**: `vld1q_u8 vst1q_u8 vdupq_n_u8 vceqq_u8
    vaddq_u8 vqsubq_u8 vqtbl1q_u8 vextq_u8 vshrn_n_u16
    vreinterpretq_u16_u8 vget_lane_u64 vmaxvq_u8 __crc32cd`; `_mm_loadu_si128
    _mm_storeu_si128 _mm_set1_epi8 _mm_cmpeq_epi8 _mm_movemask_epi8
    _mm_shuffle_epi8 _mm_crc32_u64`; the portable `count_ones`, `has`
    and `detect`.
- **`compiler/src/arch/`** (a new top-level module, made with `refactor
  new-module crate::arch`):

  | file | contents | in Phase 0 |
  |---|---|---|
  | `mod.tach` | `pub struct IntrInfo { id, name, arch, features: u64, form, nparams, consts, flags, mem, fold, ... }`, `intrinsic(id) -> IntrInfo`, `intrinsic_named(arch, name) -> i64` | done |
  | `tables.tach` | generated | the seeds |
  | `table.tach` | the lazy parser of the table strings into `IntrInfo` and the instruction lines | done |
  | `features.tach` | names, bits, implications, `parse_feature`, CPUs, baselines, `-C` parsing, `native` | done for the listed names; `native` a stub |
  | `virtual.tach` | Defs synthesized for `std::arch*` paths; vendor types | done for the seeds |
- **IR:** `Op::Intr`, `IntrMem`, `VConst`, `CpuFeat`, `Hint` declared,
  with printing, verification and the `is_pure`/`is_vector`/side-effect
  classifications. `Rot`/`BSwap` are added by T6.
- **Types:** the 18 vector type names and the six x86 types reserved and
  sized. `from_bits` checked. The operators on new types are T1's.
- **Front:**
  - `front/features/mod.tach` with `pub fn check_features()`, hooked after
    `infer_effects()`; the known-set walk and the inference are stubs
    (every requirement empty);
  - `has`/`detect` constant for baseline and foreign;
  - the attribute parsing;
  - the `arch.*` codes, with stub `explain` entries.
- **Lowering and emission, end to end for the seeds:**
  - `lower/arch.tach` with the form dispatch;
  - `mc_arm64/arch.tach` and `mc_x86_64/arch.tach` template formatting;
  - the encoders' class dispatch with the classes the seeds need;
  - gen0's template path.
- **Tests:**
  - `tests/run/arch_seed_*.tach` (aarch64, run);
  - `arch_seed_x86.tach` (`CROSS`);
  - the `CROSS` directive in tests/run.sh;
  - the `arch_` objcheck filter for x86_64-macos in gate.sh;
  - `tests/arch/gen.sh` skeleton.

### 7.3 Then, in parallel

| task | owns | provides |
|---|---|---|
| **T1 Types and checking** | `front/types.tach` (vector parts), `front/check/vectors.tach`, `front/check/arch.tach`, `compiler/src/arch/virtual.tach`, `middle/lower/vector.tach`, `gen0/gen/vector.tach` | unsigned, 64-bit and 256-bit vectors with every 0.10 operation at every level; 256-bit legalization in lowering; `from_bits`; const-argument checking; the Rust-form diagnostics (`arch.rust_form`, `arch.raw_form`); `raw::` submodules; the grammar.md section |
| **T2 Features** | `front/features/*`, `compiler/src/arch/features.tach`, `main.tach` options, the tools' option forwarding | the known-set walk (guards, `&&`, early exit, `assert`); inference over SCCs; declarations; entries; `arch.fn_pointer`; ambiguity; `#[multiversion]` clones and dispatcher; static dead branches; `-C`; `native` (sysctl, `getauxval`, `/proc/cpuinfo`); `query features`; the `arch.*` explain entries for its codes |
| **T3 Detection** | `compiler/std/arch.tach`, `middle/` late expansion of `CpuFeat` (`back/isel/arch.tach`), start-up init hook | `init_features` on the three OS paths; `cpuid`/`xgetbv`; `TACHYON_ARCH_DISABLE`; the cold path; the container double runs |
| **T4 AArch64** | `compiler/arch/aarch64.def`, `insn_a64.def`, `back/enc_arm64/simd.tach`, `back/mc_arm64/arch.tach`, the AArch64 half of `gen0/gen/arch.tach`, `tests/arch/ref/a64_*.tach` | every name of §2.3.1, core families first (§2.3.4's column), then breadth; tied operands; v30/v31 pairs; `.arch_extension`; objcheck clean on both aarch64 targets |
| **T5 x86-64** | `compiler/arch/x86_64.def`, `insn_x86.def`, `back/enc_x86.tach` (VEX), `back/mc_x86_64/arch.tach`, the x86 half of `gen0/gen/arch.tach`, `back/regalloc` (the ymm class and 32-byte spills), `back/emit/function.tach` (vzeroupper, VEX selection in avx functions) | every name of §2.3.2; compile-only and `CROSS` tests; `objcheck -t x86_64-macos` clean; `--verify-regalloc` clean; the x86 run tests written and gated off |
| **T6 Optimizer** | `middle/fold/arch.tach` (new), `middle/fold/mod.tach` (dispatch), `middle/gvn.tach`, `middle/licm.tach`, `middle/ifconv.tach`, `middle/vectorize/legality.tach`, `middle/vectorize/build.tach`, `middle/ir/*` (Rot, BSwap), `back/isel/tiling.tach` (ld1r, VConst), the VConst literal pools in `back/emit` + `objfile` | vector folding; intrinsic folds; GVN/LICM/ifconv rules incl. no speculation above guards; `VConst`; portable ops lowered on x86 too (`bits_kind` removed); vectorizing `Bits`/`BSwap`/`Rot`; **the calling-convention change** (vectors as one leaf in a vector register; `back/abi.tach`, `back/emit/calls.tach`); the bench gate |
| **T7 Tests** | `tests/arch/*`, `tests/fuzz/genarch.awk`, `tests/fuzz/run.sh` (`-A`), `tests/run/opt_arch_*`, `tests/run/arch_err_*` | the generator from the tables; references; KATs; constant-vs-run-time; the fuzzer mode; detection double runs; after 0.18, the `#[property]` conversion |
| **T8 Tools, guide, examples** | `tools/query` (`query arch`, the intrinsic lines in show/def/context, `query items --feature`), `tools/explain` entries, `compiler/guide/arch.md`, `compiler/guide/types.md` (vector table), `examples/arch/*`, `bench/*` pairs, docs/optimizer.md "0.19", tests/arch-try | discovery (§2.9) and its tests in tests/query; `guide arch` with its examples run by tests/guide; the four examples with walkthroughs; benches; docs |

**Where the tasks meet.**
- **T4/T5 and T7** meet at the table: T7's generator reads whatever the
  `.def` files hold, so each family T4 or T5 adds is tested by the next
  generator run without T7's help. Hand references come with the family.
- **T1 and T6** share lowering of vector types. T1 owns
  `lower/vector.tach` (new types, legalization), and T6 owns
  `lower/arch.tach` after Phase 0 (forms, `VConst`).
- **T2 and T3** meet at `CpuFeat`. T2 folds it, T3 expands what remains.
- **T6 and T4/T5** meet at `VConst` emission. T6 writes it with one
  `ma_vconst`/`mx_vconst` function in each machine layer, the only
  shared lines.
- **T8** documents against Phase 0's interfaces and follows each merge.

**Merge order:**
1. Phase 0.
2. T1 and T2 (they change what programs mean).
3. T4 (tested by running).
4. T7's generator, run against T4.
5. T6, after 0.17's T5 is in.
6. T3.
7. T5 (compile-only).
8. T8 throughout, with its last commit last.

**Gate:**
- `gate.sh --quick` plus `objcheck -t x86_64-macos arch_`;
- the aarch64-linux container row, with its `TACHYON_ARCH_DISABLE` runs;
- `tests/fuzz/run.sh -A`;
- the bench gate.

x86 execution rows stay off, per the standing instruction.

**Time.** About 2-3 weeks of agent work in parallel. T4 is the largest
task (~1,250 names, but generated families), T5 the riskiest (VEX, ymm
and vzeroupper with no execution), and T2 the subtlest (narrowing and
inference).

### 7.4 Phase 0 contract (as built, branch a19-phase0, on 0.18.1)

Phase 0 is in. What it made, what each task fills, and what each must
leave alone. The briefs of T1–T8 are these paragraphs.

**What exists.**
- `compiler/arch/`: the tables (`portable.def`, `aarch64.def`,
  `x86_64.def`; `insn_a64.def`, `insn_x86.def`), `embed.sh` (writes
  `compiler/src/arch/tables.tach`; `tests/run.sh` fails while it is
  stale) and `README.md`, the formats. 23 seeds: the 13 AArch64 and 7
  x86-64 ones of §7.2 and `count_ones`, `has`, `detect`.
- `compiler/src/arch/` (`crate::arch`): `mod.tach` (`IntrInfo`; the
  `FORM_*`, `IF_*`, `MEM_*`, `F_*` constants; `intrinsic(id) ->
  *IntrInfo`, `intrinsic_named(sym) -> i64`, `intr_text(id, F_*)`,
  `intr_param_*`, `intr_tied`, `intr_tied_operand`, `intr_imm`,
  `intr_with_imm`, `intrinsic_of_fn(f)`, `intrinsic_of_node(n)`,
  `intrinsic_is_foreign(id)`, `intrinsic_effect_bits(id)`, `ARCH_USED`);
  `table.tach` (the lazy parser; `insn_named`, `insn_text`, `insn_hex`);
  `features.tach` (bits `FT_*`, `feature_name`, `feature_bit_in`,
  `parse_feature`, `feature_ambiguous`, `implied`, `cpu_features`,
  `target_baseline`, `abi_features`, `arch_option` for `-C`,
  `build_features`, `feature_is_foreign`, `feature_value`);
  `template.tach` (the instruction templates: `<d>`, `<t>`, `<NAME>`,
  `<NAME:w>`); `virtual.tach` (`load_arch_modules`: the three modules,
  the vendor types, a `#[intrinsic(ID)]` declaration per intrinsic the
  program's tokens name).
- Types: the 24 new vector names of §2.2 (§7.2 said 18) and Intel's six
  opaque types (vectors of i64 lanes with a marker element,
  `is_opaque_vector`, `opaque_vector_name`; spelled `__tachyon__m128i`
  inside, `__m128i` by the x86_64 module's aliases), sized 8/16/32 bytes
  and aligned to their size; `T::from_bits(v)` (`VK_FROM_BITS`, a
  `Conv` between vector types at -O1/-O2, the same bytes at -O0); 64-bit
  vectors load, store, splat and extract on AArch64 (`ma_f`, `ma_arr`,
  `ma_elem_letter` go by element and vector size).
- IR: `Op::Intr` (56; imm the id; a, b, c the register parameters in order;
  imm2 the immediates, 16 bits each), `IntrMem`, `VConst`, `CpuFeat`,
  `Hint` (56–60), printed (`intr.vqsubq_u8 v3, v4 #4`) and classified: `Intr`,
  `VConst`, `CpuFeat` are in `Op::is_vector` (GVN, LICM, the vectorizer's
  rejection of explicit-SIMD loops, emission), not `is_pure` (the scalar
  passes that evaluate or speculate pure operations do not know them);
  `IntrMem` and `Hint` have side effects. An `Intr` is pure by
  definition: an intrinsic with effects is an `IntrMem` or a `Hint`.
- Front: `FN_INTRINSIC` (bodyless declarations: not checked, not
  emitted, effects from the table), `FN_FEATURES`;
  `front/check/arch.tach` (`check_intrinsic_call`, from
  `check_direct_call`); `front/features/mod.tach` (`check_features`,
  after the effects; `known_at(n)`, `fn_needs(f)`,
  `fn_declared_features(node)`, `feature_call_bit(n)`,
  `feature_call_value(n)`; the attributes `#[target_feature(enable =
  "...")]` and `#[multiversion("...", ...)]` in `FEATURE_ATTRS`; the
  codes `AE_*` with `arch_error_begin(pos, AE_*)` / `arch_error_end()`);
  `-C target-cpu=` / `-C target-feature=` on the build's command line.
- Lowering and emission: `middle/lower/arch.tach` (`lower_intrinsic`,
  from `lower_call`), `gen0/gen/arch.tach` (`gen_intrinsic`, from
  `gen_call`: the operands in v0-v2/x0-x2, the machine layer's own
  emission), `back/emit/arch.tach` (`emit_intr`),
  `back/mc_arm64/arch.tach` (`ma_intr`, `.arch_extension`),
  `back/mc_x86_64/arch.tach` (`mx_intr`), `back/isel/arch.tach`
  (`expand_cpu_features`: a stub, `CpuFeat` is false),
  `back/enc_arm64/simd.tach` (classes same3, across, umov, tbl, ext,
  shrn, crc; register lists `{v.16b}`), `enc_x86`'s
  `x86_table_instruction` (classes sse, ssei: maps 0f/0f38/0f3a, REX.W).
  The allocator hints a tied result into its operand.
- Tests: `tests/run/arch_seed_neon.tach` (run; one instruction each,
  ASM lines), `arch_seed_x86.tach` (`// CROSS: x86_64-linux`),
  `arch_err_seed.tach`, `opt_arch_seed.tach` (GVN, LICM);
  `tests/arch/gen.sh` (every intrinsic of each table, -O0 against -O2;
  category `arch-gen`); the `CROSS` directive (tests/run.sh); the gate's
  `objcheck-x86-arch` step (`tests/objcheck.sh -t x86_64-macos arch_`, in
  `--quick` too); `tachyonc explain arch.*` (13 entries,
  `tools/explain/arch_table.tach`).
- Cost: a program that names no `arch` token pays one scan of its tokens
  (not measurable: the compiler's own source checks and builds in the
  same CPU time as before, 167 against 171 ms for `check`, 428 against
  426 ms at -O0, within the noise); a program that names four
  intrinsics pays the table's parse and four declarations (5.9 ms
  against 5.9 ms for a small program at -O2).

- Threads and the code cache (0.18.1). Every function of lowering,
  -O0 and emission takes `cx: *FnCtx`; nothing of std::arch keeps state
  in a task. The tables (`INTRS`, `INTR_COUNT`, `TABLE_BUF`, `FIELDS`,
  `PARAMS`) and the instruction tables (`load_insns`, a `NameMap` by
  mnemonic text) are loaded by the front end (`load_arch_modules`) and
  read-only after: the accessors (`intrinsic_count`, `intrinsic_name`,
  `intr_*`, `insn_named`) never load. The `.arch_extension` lines are
  written once, in `emit_file_header` (`ma_arch_extensions`, from
  `ARCH_EXT_FEATURES`), not per function. tests/threads_writes.sh lists
  the tables and `ARCH_USED` in READ (the code cache's key covers them:
  the tables are the compiler's identity, `ARCH_USED` changes the IR,
  and `options_hash` mixes in `build_features()`); `-C` and its value
  are hashed options (`arg_kind`). An `Intr`'s id and immediates are in
  its IR hash (imm, imm2). A task adding a static that emission or a
  pass reads must add it there with its reason, or keep it in `FnCtx`.

**What each task owns, fills, and leaves alone.** Every task may add
lines to the `.def` tables of its families and tests under
`tests/run/arch_*`; `compiler/src/arch/tables.tach` is only ever
written by `embed.sh`.

- **T1 Types and checking.** Owns `front/types.tach` (vector parts:
  `init_arch_vector_types`, `is_opaque_vector`, `vec_mask_type`),
  `front/check/vectors.tach`, `front/check/arch.tach`,
  `compiler/src/arch/virtual.tach`, `middle/lower/vector.tach`,
  `gen0/gen/vector.tach`, `back/mc_*/vector.tach` (the generic
  operations on the new types). Fills: every 0.10 operation on the
  unsigned, 64- and 256-bit types (unsigned compares and masks, `umov`
  lanes; `vector_type` stays the six for the vectorizer), 256-bit
  legalization, `from_bits` on the vendor aliases (`synth_path_call`
  sees only primitives), `raw::` submodules, `arch.rust_form` and
  `arch.raw_form` in `check_intrinsic_call`, the tuple types, the
  grammar.md section; may route -O0's generic forms through lane-by-lane
  code. Leaves: the table formats, `IntrInfo`, the IR ops, the features.
- **T2 Features.** Owns `front/features/*` (adds `regions.tach`,
  `infer.tach`, `check.tach`, `why.tach`, `multiversion.tach`),
  `compiler/src/arch/features.tach`, `main.tach`'s `-C` and the tools'
  forwarding of it. Fills: `known_at(n)` (declared features, guards),
  `fn_needs(f)` over the SCCs, the static deadness of has/detect
  branches (read by lowering and gen0 where they lower `If`), the
  checks reporting `AE_FEATURE`, `AE_DECLARED`, `AE_FN_POINTER`,
  `AE_MULTIVERSION`, `AE_FEATURE_AMBIGUOUS` through
  `arch_error_begin`, an unguarded call of a foreign intrinsic an error
  (today it lowers to unreachable), `native`, `query features`. Leaves:
  the bit numbers (`FT_*`: the run-time word's too), `feature_value`'s
  meaning, lowering's use of `feature_call_value`.
- **T3 Detection.** Owns `compiler/std/arch.tach` (new; std's
  `init_features`), `back/isel/arch.tach`, the start-up hook. Fills:
  `expand_cpu_features` (the load of `ARCH_FEATURES`, the bit test, the
  cold `init_features` call), gen0's detect (today constant false in
  `gen_intrinsic`), the three OS sources, `TACHYON_ARCH_DISABLE`, the
  container's double runs. Leaves: `Op::CpuFeat`'s meaning (pure, imm =
  `FT_*` bit), the folding (T2's `feature_call_value`).
- **T4 AArch64.** Owns `compiler/arch/aarch64.def`, `insn_a64.def`,
  `back/enc_arm64/simd.tach` (and moves the chain's vector mnemonics
  into it), `back/mc_arm64/arch.tach`, the AArch64 half of
  `gen0/gen/arch.tach`. Fills: the names of §2.3.1, the encoding
  classes they need, tied operands beyond the hint, the v30/v31 pairs,
  objcheck on both aarch64 targets. Leaves: the template syntax (adds
  modifiers if needed, documented in the README), `IntrInfo`.
- **T5 x86-64.** Owns `compiler/arch/x86_64.def`, `insn_x86.def`,
  `back/enc_x86.tach` (VEX in `x86_table_instruction`),
  `back/mc_x86_64/arch.tach`, the x86 half of `gen0/gen/arch.tach`,
  `back/regalloc` (the ymm class, 32-byte spills),
  `back/emit/function.tach` (vzeroupper). Fills: §2.3.2's names, the
  CROSS and objcheck tests, `--verify-regalloc`. Leaves: what x86 runs:
  nothing (the gate's x86 switch).
- **T6 Optimizer.** Owns `middle/lower/arch.tach` (after Phase 0; adds
  `VConst`, the forms `vsel vins vneg vsum load.dup rot bswap wmul`),
  `middle/fold/arch.tach`, the GVN/LICM/ifconv rules (the no-speculation
  line for guarded intrinsics), `Rot`/`BSwap`, the vectorizer's portable
  bit ops, `back/emit/arch.tach`'s `VConst` and the literal pools, the
  calling-convention change, `bits_kind`'s removal. Leaves: `Op::Intr`'s
  operand layout and imm2 packing, `is_vector`'s classification unless
  it moves all three ops at once.
- **T7 Tests.** Owns `tests/arch/*` (grows `gen.sh`: references from
  the `semantics` column, edges, random vectors, constants against
  run-time values), `tests/fuzz/genarch.awk`, `-A`, `tests/run/opt_arch_*`,
  `tests/run/arch_err_*`. Leaves: the tables.
- **T8 Tools, guide, examples.** Owns `tools/query` (`query arch`, the
  intrinsic lines in show/def/context), `tools/explain/arch_table.tach`
  (the 13 entries are there: T8 makes them follow T1/T2's messages),
  `compiler/guide/arch.md`, `examples/arch/*`, `bench/*`, the docs,
  `tests/arch-try`. Phase 0 adds no guide text. Leaves: the codes'
  names.

**Not to touch without the lead:** `IntrInfo`'s fields (add, never
renumber), the `FORM_*`/`IF_*`/`MEM_*`/`FT_*` values, the `.def`
column order, `Op`'s numbering (56–60; 0.18.1's `RtId` is 55), `FN_INTRINSIC`/`FN_FEATURES`,
the `AE_*` codes.

**Design points that changed in Phase 0.**
- The virtual declarations are synthesized as source text and parsed
  (`#[intrinsic(ID)] pub fn ...;`, a body only for `bits.*`), not built
  as Defs: the parser, collector and tools need nothing new.
- `Intr`/`VConst`/`CpuFeat` are classified through `is_vector`, not
  `is_pure`.
- -O0 emits intrinsics through the machine layers with fixed registers
  (the same text as -O1/-O2), the generic forms included; the oracle for
  T7 is the scalar reference, not -O0 alone.
- Immediates are `i64` parameters, packed in imm2.
- Templates write `<d>`, `<NAME:w>` (not `{d}`); tied operands are
  handled now (an emitter move, the allocator's hint).
- `.arch_extension` is written once per output, at the top, from the
  features of the intrinsics the program names (not at the first use:
  emission keeps no state across functions on 0.18.1).
- `CpuFeat` is false until T3; a foreign intrinsic's call is
  unreachable until T2 makes it an error.

**T2 as built (branch a19-t2).**
- `front/features/regions.tach` walks every checked body once (after the
  effects): the known set at each point (the build's features, the
  declaration, the guards of §2.4: `then` of `if G`, `&&` atoms, `else` of
  `if !G`, the rest of a block after `if !G { DIVERGES }` or
  `assert(G)`, which 0.18 checks as `std::contract_check`), recorded per
  direct call (`CALLS`: caller, callee, known, the ambiguous readings,
  node) and per has()/detect() call (`known_at`).
- `infer.tach`: `NEEDS[f]` (beyond the build's features; a declaration
  pins it to what it declares) by a worklist over the calls, from the
  intrinsics and declarations up. No SCCs are needed: a set only grows.
- `check.tach`: `arch.feature` in entry points (main, `extern "C" fn`s,
  tests), `arch.declared`, `arch.feature_ambiguous` (where the
  unqualified name is, not carried up), `arch.fn_pointer` for a plain
  `fn` value or a closure coerced to a `fn` type. **Change:** a closure
  passed as itself is not checked where it is made: it is called directly
  (in its own function, or in the generic instance it is passed to), so
  the calls carry its set. Unguarded calls of another architecture's
  intrinsics are `arch.feature` errors.
- **Static deadness** is a function, not a node flag:
  `front::features::static_condition(cond)` (1, 0, or -1 when not a
  constant has/detect condition: `!`, `&&`, `||` of them), read by
  `lower_if` and `gen_if`, which generate only the live branch.
- `-C`: `-x` also removes what needs x; `native` reads /proc/cpuinfo or
  `sysctl` (`front::cpp::cc::run_command`, now `pub`); `check`, `query`
  and the editing commands take `-C` (their cache is skipped then), and
  the edits' checks forward it (`push_arch_args`).
- `query features NAME [--why F] [-C ...]` (tools/query/features.tach).
- Not done: `#[multiversion]` (clones, dispatcher, `arch.multiversion`);
  `features:` on `def`/`show`/`context` lines (T8's); `--target` on
  `query`. `arch.feature_ambiguous` has no run test until an AArch64 aes
  intrinsic exists (T4).

**T7 as built (branch a19-t7).** What T4 and T5 need to know:
- `tests/arch/gen.sh` (`gen.awk`) writes one program per `# ---- Family
  ----` section of each table (40 intrinsics at most): edges (every pair
  of the first two inputs), mixed edges, `-r` random cases (2,000), every
  8-bit value or pair, at run time; then constant edges and random lanes
  (the folds); every value of a constant range below 16, else its ends,
  middle and three more. Run at the suite's level (`tests/run.sh
  arch-gen`; -O0 and -O2 without one); about 0.6 s for the 23 seeds, so
  `--quick` and `--release` run the same.
- **The semantics column is the reference** when it is `r[k] = E`, `r =
  E`, `r = max|min|sum over k of E`, `S[I] = E` or uses `X[A..B]`
  (compiler/arch/README.md, "Semantics"): integers below 64 bits in i64,
  64-bit lanes in their own type, floats in f64; the result is `as` the
  lane type. Saturating 64-bit semantics need an explicit form (`if a[k] >
  b[k] { a[k] - b[k] } else { 0 }`). Opaque x86 types are bytes unless a
  trailing note says `(i16 lanes)` or `(a, b: i16 lanes; r: i8 lanes)`.
  Tuples are their lanes one after the other (`t[idx[k]]` over 32 lanes
  for tbl2).
- **Prose needs `fn ref_NAME`** in `tests/arch/ref/*.tach` (T4's:
  `a64_*.tach`; shared ones: `crc.tach`, `movemask.tach`, `bits.tach`):
  the intrinsic's parameters with vectors and slices as `[D]`, scalars
  as `D`, constants and indexes as `i64`, a store's slice as `&mut [D]`,
  then `k: i64` for a vector result; it returns lane k (or the value). An
  intrinsic with neither, or of a type the generator does not know, fails
  `arch-gen` with `error NAME: ...`. `cast` forms are compared by bytes;
  `feat.*`, `hint` and `raw` memory forms are skipped.
- `tests/fuzz/run.sh -A` (`genarch.awk`, the gate's `fuzz-arch`) draws
  every register and `[u8]` memory intrinsic of the target's table whose
  types are integer vectors of 8 or 16 bytes, `__m128i` or integer
  scalars; floats, tuples and 256-bit types are not drawn yet.
- `tests/objcheck.sh` checks the generated programs of the target's
  architecture (with the portable one) as part of its corpus, so the
  gate's `objcheck-x86-arch` covers every x86 intrinsic.
- Fixed on the way: a memory intrinsic's bounds check now names the
  index's position at -O1/-O2 as at -O0 (`middle/lower/arch.tach`,
  `checked_address`'s `site`).
- Not done: the KATs (AES, SHA: no such intrinsic yet; the CRC reference
  is bitwise), `tests/run/opt_arch_*` beyond the seed, the container's
  `TACHYON_ARCH_DISABLE` double runs (T3), the `#[property]` conversion.

**T5 as built (branch a19-t5).** x86-64, compile-tested only.
- `x86_64.def` holds 484 intrinsics, written with every line of
  `insn_x86.def` (368 instructions) by `tools/arch/x86_families.py
  --write` between the `# ==== generated` markers: sse 20, sse2 127, sse3
  8, ssse3 16, sse4.1 47, sse4.2 5, popcnt 2, lzcnt 2, bmi1 12, bmi2 6,
  pclmulqdq 1, aes 6, sha 7, avx 71, avx2 138, fma 16. Each has its
  semantics or a `fn ref_NAME` (`tests/arch/ref/x86_bits.tach`,
  `x86_float.tach`, `x86_crypto.tach`); `arch-gen` compiles all 33
  programs at -O0 and -O2 for x86_64-linux and x86_64-macos, and
  `objcheck -t x86_64-macos arch_` agrees with cc on all 184 compilations.
- **Encoder.** VEX (two- and three-byte prefixes, L, W, vvvv) in
  `enc_x86`'s table classes (compiler/arch/README.md: `sse ssei sser sseir
  shift sse0 vex vexv vex2 vex2r vexi vex2i vex2ir vexshift vex4 vexd`);
  ymm registers; `vmovdqu`, `vmovdqa`, `vzeroupper` in its own table; the
  operand swaps LLVM's assembler makes for the short VEX prefix
  (commutative operations, symmetric `vcmpps` predicates, register moves).
  **`tachyonc assemble [--target T] FILE.s -o FILE.o`** (a developer's
  tool, `tools/assemble.tach`) runs the compiler's assembler on a file;
  **`tests/arch/enc.sh`** (category `arch-enc` of tests/run.sh) assembles
  `tests/arch/enc_x86.s` (7,777 instructions: every line of `insn_x86.def`
  and the back end's AVX moves, low and high registers, both widths, eight
  addressing forms) with it and with cc for x86_64-macos and x86_64-linux:
  byte for byte the same.
- **256-bit values** live in ymm registers (the same numbers as xmm):
  `mx_load`/`mx_store` write `vmovdqu`, `mx_mov` `vmovdqa`, spill slots
  are 32 bytes (four 8-byte slots, `assign_spill_slots`). Only AVX
  instructions make one: an intrinsic's result, its operands' loads, and
  the `load`/`store` forms; a 256-bit `cast` copies its bytes as two
  halves (`lower_intrinsic`), since a cast needs no feature. T1's
  legalization of the portable 256-bit types is unchanged.
- **vzeroupper** is an AVX instruction, so it goes only where AVX is
  proven: before a call or return that every path reaches through an
  instruction writing a ymm register (a must analysis over the blocks,
  `holds_ymm`, FnCtx `ymm_in`/`ymm_ret`); no ymm value is live across a
  call (they are spilled), so it destroys nothing. At -O0 one follows each
  256-bit intrinsic.
- **Templates.** `<NAME:y>` is the ymm view; `<NAME:0>` an operand read in
  xmm0 (SSE4.1's `pblendvb`/`blendvps`/`blendvpd`, `sha256rnds2`): the
  machine layer saves xmm0 in xmm14 around it (`mx_intr_xmm0`, five moves).
  A tied 256-bit result (FMA) is moved whole.
- Tests: `tests/run/arch_x86_core.tach` (byte search with SSE2 and AVX2,
  pshufb/palignr/psubusb/ptest, CRC-32C, POPCNT, pblendvb),
  `arch_x86_kat.tach` (FIPS-197 C.1 through aeskeygenassist, aesenc,
  aesdec with aesimc's keys; carry-less squares; sha1msg1),
  `arch_x86_avx.tach` (sixteen live ymm values: spills; FMA; vpblendvb,
  shifts, permutes): `CROSS: x86_64-linux` with ASM lines, run on AArch64
  (the fallbacks print the answers).
- Not done (of §2.3.2): gathers and masked loads/stores (`intr.mem` is not
  lowered), the string compares (`pcmpistri`/`pcmpestri`: implicit ecx,
  eax, edx), `_mulx_u64`, `_mm256_zeroupper` (the `hint` form is T6's),
  intrinsics with float scalars (`_mm_set1_ps`, `_mm_cvtss_f32`: -O0's
  float operands are T4's change to `gen0/gen/arch.tach`), `_mm_set_epi*`
  (more than three operands), `_mm_loadl_epi64`/`storel` (8 of a 16-byte
  vector), `lddqu`, `_mm_dp_ps`, `mpsadbw`, `pause`/`prefetch` (T6's
  hints), VEX forms of the generic 128-bit operations in AVX functions,
  the AVX2 vectorizer (O3). The aligned forms (`_mm_load_si128`, ...) load
  unaligned: no alignment check yet, and never a fault.
- **Encoded but never run** (to run when x86 testing returns; nothing
  needs changing to run them, only the gate's x86 switch):
  - every intrinsic of `x86_64.def` (the `arch_x86_*` programs of
    `tests/arch/gen.sh`, built for x86 and not run);
  - the x86 paths of `arch_seed_x86`, `arch_x86_core`, `arch_x86_kat`
    (AES, PCLMULQDQ, SHA known answers), `arch_x86_avx`;
  - the ymm back end: 32-byte spills and reloads, `vmovdqa` moves of
    256-bit values (tied FMA results, parallel moves), the vzeroupper
    placement, -O0's vzeroupper, the 256-bit casts through halves;
  - the xmm0 save/restore of `pblendvb`/`blendvps`/`blendvpd`/
    `sha256rnds2`; the AVX `set1` sequences (`movd`, `punpcklbw`,
    `pshuflw`, `pshufd`, `vinsertf128`); `ptest`/`vptest` with `setcc`.
  - Known risks to check then: the f64 square-root reference (Newton's
    method) may be an ulp off; the FMA references are unfused (computed in
    f64): exact references are needed before the f64 (and rare f32) FMA
    cases can pass; LICM hoists loop-invariant loads and `Intr`s without
    `runs_first` (T6's no-speculation rule must cover a 256-bit load,
    `vmovdqu`, as it covers a guarded `Intr`, or a load hoisted above its
    `detect` runs on a CPU without AVX).
- **Changes for others.** FnCtx gains `ymm_used`, `ymm_in`, `ymm_ret`
  (per function, emission only). `emit_call_inst` (T6's file) writes the
  vzeroupper after the arguments' moves (one line). The store intrinsics
  keep Phase 0's `[u8]` slice (a read-only view under 0.17's rules: the
  migration to `&mut [T]` is D13's generator commit, for both tables).

**T3 as built (branch a19-t3).**
- **std's word** is `compiler/std/arch.tach`, four lazy sections: the
  portable part (`ARCH_FEATURES`, `TACHYON_ARCH_DISABLE`, the
  implications' consistency: sha3 without sha2 is cleared), then one per
  source: macOS (sysctl `hw.optional.arm.FEAT_*`), Linux (`getauxval`),
  x86-64 (`cpuid`, `xgetbv`). No `cfg`: the compiler names the target's
  section (`arch_init_macos|linux|x86`, `arch_word_*`; the loader's
  `know_program`, so `set_target` now runs before the modules load), and
  only that one is lexed. std's code names no `std::arch` item (a query
  loading all of std would otherwise load the virtual modules). Each init
  takes the build's features (`known`), which it does not ask the system
  about, so a default macOS build reads two sysctls (i8mm, bf16).
- **Who fills it.** A program with `main`: main's first call
  (`arch_after_lowering`, after lowering, `back/isel/arch.tach`; gen0's
  `gen_function` at -O0), only when a CPUFEAT survived lowering (-O0: a
  detect not folded). Then each CPUFEAT becomes, just before isel, a load
  and a bit test: no cold path is needed, nothing is clobbered, the
  optimizer saw a pure op. With no `main` (a library), each CPUFEAT
  becomes after lowering a call of `arch_word_*` (filled at the first
  call) and the bit test. **Change:** no `cbz` to a cold block; the
  library form is an ordinary call, not hoisted (left for later: making
  it pure needs keeping `arch_word_*` alive past dead-function removal).
  -O0 calls `arch_word_*` at every detect.
- **Soundness without atomics** (the comment at the top of std's
  section): one write before main, while single-threaded; in a library,
  an idempotent race on one aligned word that every writer fills with
  the same value, which the hardware never tears and the back end never
  splits; relaxed atomics in 0.21's terms.
- **x86-64** (compile-only): `tachyon_arch_cpuid` and
  `tachyon_arch_xgetbv`, global helpers the compiler writes after the
  run-time helpers (`emit_arch_runtime`), `cpuid`/`xgetbv` as `.byte`s:
  no table intrinsic, no register-class change (T5's regalloc stays as
  it is).
- **`#[multiversion]`** (`front/features/multiversion.tach`): before
  the contracts, each listed set of the target's architecture that the
  build lacks makes a version `f$mvK` (a copy of the AST, `FN_DERIVED`,
  declaring the set through a `FA_TARGET_FEATURE` entry); the first set
  the build has ends the list; the function's body becomes `if
  detect(..) { f$mv0(..) } else if .. else { <its body> }` (its body is
  the baseline version). The dispatcher is pinned (`DECLARED_MARK`, no
  needs), so callers and `arch.fn_pointer` see the baseline; calls a
  version cannot make are `arch.multiversion` (once per position).
  Methods and generic functions use the contracts' call form
  (`Self::f$mvK`, the type parameters written).
- **The double runs**: `tests/run.sh` runs every run case whose source
  names `detect(` or `#[multiversion` a second time with
  `TACHYON_ARCH_DISABLE=all` and expects the same output and exit code,
  on every host (the container's suite included).
- Tests: `arch_detect_run` (CRC-32C by detect and by a multiversioned
  function, through a `fn` value and a closure; the word's implications;
  a detect in a loop), `arch_detect_lib` (a C main, no tachyon main),
  `arch_err_multiversion`.

**T4 as built (branch a19-t4).**
- `aarch64.def` holds 1,743 intrinsics. The regular families are
  written by `tools/arch/a64_families.py --write` between the `# ====
  generated` markers of `aarch64.def` and `insn_a64.def` (one Python
  function per family; lines outside the markers are kept). Every one
  has its semantics or a `fn ref_NAME` (`tests/arch/ref/a64_lanes.tach`,
  `a64_crypto.tach`, `a64_float.tach`, and `crc.tach`'s other seven) and
  passes `arch-gen`; `tests/objcheck.sh arch_` agrees with `cc -c` on
  aarch64-macos and aarch64-linux.
- **Encoder.** For vector and SIMD scalar operands the table is read
  before the chain, and a mnemonic may have several (consecutive) lines:
  the first whose class fits the operands encodes them; none fits, the
  chain does (`arch/table.tach`'s name map keeps a mnemonic's first
  line). Classes added: `same3f diff3 misc2 misc2f acrossf shl elem
  fpair rr rrr rrrr xar` and the scalar `same3s misc2s misc2fs shrns
  shls` (compiler/arch/README.md); operands `.1q`, `.4b[i]`, `#0.0`.
- **One 64-bit lane.** A 64-bit vector of one 64-bit lane has no `.1d`
  arrangement in most instructions: its intrinsics use the SIMD scalar
  forms (`sqadd d0, d1, d2`); the generator rewrites `<a>.1d` to `<a:d>`.
- **Templates.** `<n:2>` scales an immediate (ext of 16-bit lanes);
  `<u>` is a second temporary, v30 (the allocator gives out neither v30
  nor v31): a scalar that sha1c, pmull's p64 or the like wants in the
  vector file is moved there (`fmov`), the only intrinsics of more than
  one instruction besides the horizontal ones (`umaxv` then `umov`).
- **`.arch armv8.2-a`** precedes the `.arch_extension` lines when the
  program uses sha3, dotprod, rdm, fp16, i8mm or bf16: GNU as accepts
  those extensions only on an Armv8.2 base.
- -O0 keeps float scalar operands and results in vector registers (v0-v2).
- A function that needs another architecture's features is lowered as
  `unreachable` (`middle/lower/mod.tach`, `lower_function`, as §2.4
  says): its calls are dead or errors, and lowering such a body, never
  called, could overflow the stack in SSA construction
  (tests/run/arch_foreign_body).
- Fixed: a 64-bit vector of constant lanes (a folded load of a constant
  8-byte array) was materialized into a general register numbered 48
  and up (`back/emit/operands.tach`, `materialize`).
- Not done (left of §2.3.1): `vld1q_dup` (the `load.dup` form, T6's),
  `vld2q`/`vst2q` (`intr.mem` is not lowered yet), `vqtbl2q`/`vqtbx2q`
  (tuple operands: the v30/v31 pair), the float forms whose references
  are not exact yet (`vsqrtq`, `vfmaq_f64`/`vfmsq_f64`, `vmaxnmq`/
  `vminnmq`: signaling NaNs in the random inputs, `vrecpe`/`vrecps`/
  `vrsqrte`/`vrsqrts`), `vbslq_f32`/`f64`, `vmlaq`/`vmlsq` on floats (two
  instructions: unfused), and the `f64` 64-bit forms of the float
  family (scalar FP encodings).

**T6 as built (branch a19-t6).**
- **Guards in the optimizer.** An `Intr` needing a feature outside its
  function's whole-body set (the build's, `made_build_features()`, and
  `fn_needs(f)`) is under a guard: LICM hoists it only when `runs_first`
  holds (`middle/licm.tach`, `intr_guarded`). Inlined intrinsics are
  judged in the caller. `ifconv` and isel's selects never speculate an
  `Intr` (it is not `is_pure`); GVN only replaces by dominating copies.
  `NEEDS` and `BUILD_FEATURES` are on threads_writes.sh's READ list.
- **Exact equivalents.** New forms `vneg`, `vins`, `vsel`, `vsum`,
  `vbin.div` and `load.dup` (`FORM_VNEG`..`FORM_LOAD_DUP`, 13-17):
  vnegq/vnegq_f, vsetq_lane, vbslq, vaddvq, vdivq lower to VNEG, VINS,
  VSEL (bitwise), VSUM, VBIN div; one 64-bit lane keeps `intr`. -O0 writes
  the table's instruction for them (an independent check of -O2).
- **Folding** (`middle/fold/arch.tach`, from instcombine): constant
  vectors are VSPLATs of constants; the generic ops and the fold classes
  listed in that file fold to a VSPLAT or a constant; integer lanes,
  AArch64 and portable intrinsics. `VConst` (non-splat constants, the
  literal pools) is not made yet.
- **Calling convention** (`back/abi.tach` `tabi_leaves`,
  `back/emit/machine.tach` `t_arg_location`): a vector is one leaf in a
  float/vector register (256-bit: two), past them a stack slot of its
  size at a multiple of it. C's convention is untouched. bench/ compiles
  to the same code.
- **T4's leftovers.** `vld1q_dup`/`vld1_dup` (28, `load.dup`: checked
  scalar load, VSPLAT; -O0 `ld1r`, encoder class `ldst`); `vld2q`/`vst2q`
  (22, `intr.mem`): two vector loads and uzp1/uzp2 (stores: zip1/zip2,
  two stores), the permutes' ids in `IntrInfo.part1/part2` (`link_parts`,
  when the table is parsed); -O0 writes `ld2`/`st2` on v30/v31. `Op::IntrMem`
  is still unused.
- Not done: isel's `ld1r` fusion of `Load`+`VSplat` at -O1/-O2 (two
  instructions), `VConst` and the literal pools, `Rot`/`BSwap` and the
  vectorizer's portable bit ops, float folds, x86's folds.

**T8 as built (branch a19-t8).**
- `query arch WORDS... [--feature F] [--arch A] [--equiv NAME]` (also
  `query intrinsics`; tools/query/intrinsics.tach): the tables without a
  program; words are positional (the design's `--find`), `--feature`
  stands for `query items --feature`; `query arch --features` (the
  baseline listing) is not done.
- def/show/context of an intrinsic: the query's names are declared for
  it through `arch::virtual::QUERY_WANTED` (C strings, interned in
  `load_arch_modules`: interning before the program's keywords broke the
  lexer); `features:`/`instruction:` on the first line, doc, semantics,
  equivalent and `use` line under it. `features: X (inferred|declared)`
  on functions; query cache version 7.
- `guide arch` (examples run by tests/guide, guide-find-arch); `guide
  --find` weighs a topic's summary words. The x86 rows of the recipes
  table name Intel's intrinsics; a note there says the table has the
  seeds until T5 merges (T5: update it, and refresh tests/query/arch019.q,
  whose `#[intrinsic(N)]` lines and x86 positions move with the tables).
- explain: the 13 entries from the compiler's own lines; `query.partial`.
- examples/arch/bytesearch and crc32 with walkthroughs and timings (M1:
  0.12 s = libc memchr vs 1.87 s; 0.09 s = clang vs 2.21 s). Not done:
  utf8, swissprobe, bench/ pairs, tests/arch-try.
- Found: range analysis keeps the checks of `vld1q_u8(s, i + 16/32/48)`
  under `while i + 64 <= s.len`; arch.feature's try at `main` wraps the
  call (skipping it) when the guard was removed lower down; indexing a
  `&[u32; 256]` says "indexing a raw pointer is unsafe".

## 8. Open questions

- **O1. Latency and throughput in `query show`.** Useful for choosing
  between equivalent sequences, but it needs per-CPU data (Apple M1–M4,
  Neoverse; uops.info for x86). *Proposed:* 0.19.x, from public tables,
  for the core families only.
- **O2. Consecutive-register tuples in the allocator** (tbl3/tbl4,
  ld3/ld4/st3/st4). Base64, RGB deinterleave and transposes need them.
  *Proposed:* 0.19.1, after measuring how much the v30/v31 moves cost
  the tbl2 users.
- **O3. AVX2 in the vectorizer** for `avx2` functions and clones, and
  SVE as a whole. Both need execution on hardware we do not test now.
  *Proposed:* AVX2 vectorization as soon as x86 testing is re-enabled;
  SVE after 0.23.
- **O4. A general `cfg`.** The foreign-feature guard covers
  architectures. 0.20's I/O may want OS differences (`has("linux")`
  could cover those with the same mechanism). *Proposed:* extend
  features with OS names rather than add `cfg`, decided in 0.20's
  design.
- **O5. Folding crypto and string-compare intrinsics.** Nobody needs it
  yet. *Proposed:* not in 0.19.
- **O6. Memory-operand folding on x86** (`paddb xmm, [mem]`). It saves a
  register and a µop. *Proposed:* 0.19.x with x86 execution, through
  isel's tiling.
- **O7. Should `has` see *inferred* requirements?** That would let a
  helper called only from an avx2 function pick its avx2 path without a
  declaration. It is circular, so it would need a fixpoint, and it makes
  `has` depend on callers. *Proposed:* no (§2.4). Pin with
  `#[target_feature]` or use `#[multiversion]`.

### Critical files for implementation

- compiler/src/middle/ir/mod.tach (`Op`, `is_pure`, `is_vector`,
  `has_side_effect`): the new ops
- compiler/src/middle/lower/calls.tach (`bits_kind`, `lower_call`): the
  existing std-call-to-instruction path, generalized by lower/arch.tach
- compiler/src/back/emit/insts.tach (`emit_vector`) with
  back/mc_arm64/vector.tach and back/mc_x86_64/vector.tach (`ma_vbin`,
  `mx_v2op`, `ma_vmacw`): where `Intr` is emitted and the tied-operand
  pattern comes from
- compiler/src/back/enc_arm64/mod.tach (`a64_simd`, `init_a64`) and
  back/enc_x86.tach (`sse`, `enc`): the encoders made table-driven
- compiler/src/front/effects/infer.tach (`infer_effects`, `components`,
  `ADDRESS_TAKEN`): the SCCs and address-taken set that feature inference
  reuses
- compiler/src/front/check/vectors.tach and gen0/gen/vector.tach: the
  vector types' checking and -O0 code
- compiler/src/front/modules/stdsections.tach and front/modules/lookup.tach:
  where virtual `std::arch*` paths resolve
- compiler/src/middle/licm.tach (`runs_first`), middle/ifconv.tach: the
  no-speculation rule
- compiler/src/back/abi.tach and back/emit/calls.tach: the vector
  calling-convention change
- tests/objcheck.sh, tests/run.sh (the `CROSS` directive), tests/fuzz/run.sh

## Decisions taken (for the user's review)

All taken as recommended on 2026-10-16, under the standing instruction to
work autonomously through 0.23. Each can be revisited.

**The model**
- D1. **Intrinsics are table lines** (`compiler/arch/*.def`), the one
  source for signatures, features, instructions, encodings, folds,
  semantics, docs and tests. std's `std::arch*` modules are virtual:
  declarations are synthesized on use, and std's text does not grow.
- D2. **Vendor names**, as Rust and C use them. Immediates are plain
  constant arguments (no const generics), with ranges checked.
- D3. **New portable vector types:** unsigned, 64-bit and 256-bit, 30 in
  all, with every 0.10 operation and `T::from_bits`. 256-bit vectors are
  legalized to pairs where the registers are missing, so they run and
  are tested on aarch64.
- D4. **The vendor types:** NEON types are aliases of the portable types;
  `p128` is `v2u64` (tachyon has no `u128`). x86 `__m*` types are
  opaque distinct types with no operators.
- D5. **The calling convention:** tachyon's own convention passes a
  vector as one leaf in a vector register, and a 256-bit vector as two.
  It does not depend on features. C's convention is unchanged, and
  vectors stay non-FFI-safe.

**Features and safety**
- D6. **Feature requirements are inferred over the call graph**, as
  effects are. `#[target_feature(enable = ...)]` is a pin and an upper
  bound. Errors appear at entry points (main, `extern "C"`, tests,
  address-taken functions), at declarations, and at address-taking. A
  call is legal where its callee's needs are known: baseline, declared,
  or under a `detect`/`has` guard (then-branch, `&&`, the rest after an
  `if !G { diverge }`, `assert(G)`).
- D7. **Code generation is per instruction**, so inlining across feature
  boundaries is allowed. The optimizer never speculates an instruction
  known only under a guard above that guard (LICM `runs_first`, no
  if-conversion).
- D8. **Foreign architectures replace `cfg`:** another architecture's
  features are constant-false, its branches are type-checked but never
  generated, and its functions are never emitted.
- D9. **Spellings:** `has("neon")` with a required literal, instead of
  `has::<"neon">()`. `detect("avx2")` as the roadmap writes it. The
  qualified `x86_64.aes`/`aarch64.aes` exist, and an unqualified
  ambiguous name means the target's.
- D10. **Baselines:** apple-m1 on aarch64-macos (crc, aes, sha2, sha3
  and dotprod are constant-true there), generic Armv8.0 on aarch64-linux,
  x86-64 v1 on x86_64-linux, core2 on x86_64-macos. `-C target-cpu`
  takes names and `native`; `-C target-feature=+x,-y`; the ABI's
  features cannot be removed.
- D11. **Detection:** a pure `CpuFeat` op over one cached word, expanded
  late with a cold init path. The word is initialized at start-up in
  programs with `main`, and lazily for C-entered code. The sources are
  sysctl, getauxval and cpuid+xgetbv. `TACHYON_ARCH_DISABLE` may only
  clear bits, for testing the fallbacks.
- D12. **Multiversioning** is clones with declared features plus an
  inlinable chain of `detect` tests, not ifunc. `has` folds per clone.

**Memory and effects**
- D13. **The vendor names take slices** (`vld1q_u8(s, i)`), checked like
  0.10's `load`. Aligned forms also check alignment. Gathers check every
  lane; masked forms check the whole range. The raw pointer forms live
  in `raw::` and are `unsafe`. Stores move to `&mut [T]` when 0.17's
  split slices land.
- D14. **Effects come from the table:** none for register intrinsics,
  `panic` for checked memory forms, `unsafe` for raw forms. `detect`,
  `has`, `prefetch` and `spin_loop` have none.

**Scope of 0.19.0**
- D15. **The intrinsics listed in §2.3:**
  - AArch64 (~1,250): NEON, crc, aes, sha2, sha3, dotprod, without the
    x3/x4 tuple forms.
  - x86-64 (~650): SSE2 to SSE4.2, POPCNT, LZCNT, BMI1/2, PCLMULQDQ,
    AES-NI, SHA, AVX, AVX2, FMA.
  - Portable: bit counts, rotates, bswap, bit_reverse, wide_mul,
    prefetch, spin_loop, has, detect.
  - Later: AVX-512, SVE, fp16, i8mm, bf16, the tuple x3/x4 forms.
- D16. **Optimizer visibility:**
  - intrinsics with an exact generic equivalent lower to the generic
    vector op;
  - the rest become `Op::Intr`, pure per the table, numbered by GVN,
    moved by LICM and folded by family;
  - memory forms become ordinary loads and stores;
  - constant vectors become `VConst`;
  - the vectorizer leaves explicit-SIMD loops alone and vectorizes the
    portable bit ops.
- D17. **x86-64 is implemented, encoded and checked without running:**
  objcheck at x86_64-macos, `CROSS` compile-only cases,
  `--verify-regalloc`. The x86 run tests are written and gated off
  until x86 testing is re-enabled. The run targets are aarch64-macos
  and the aarch64-linux container.
- D18. **Testing:** every intrinsic against a scalar reference generated
  from the table's semantics, with constants (folded) and run-time
  values (executed), at every level. Crypto by known answers. A fuzzer
  mode `-A`. The references become `#[property]` tests when 0.18 ships;
  nothing in 0.19 waits for 0.18.
- D19. **Agents:**
  - `guide arch`, with the task recipes;
  - `query arch --find/--equiv/--features`;
  - `query features --why`;
  - intrinsic facts (feature, instruction, semantics, equivalent) in
    `query show`/`def`, and `features:` on function headers;
  - `arch.*` codes with `try:` lines, run by tests/arch-try;
  - diagnostics for Rust spellings.
- D20. **The order:** Phase 0 then T1–T8. Everything except store
  spellings, place forms and the property-test conversion starts before
  0.17 and 0.18 ship. T6 rebases after 0.17's optimizer task.
