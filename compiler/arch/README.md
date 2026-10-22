# The intrinsic tables (0.19)

Every intrinsic of `std::arch` is one line of a table here; the
instructions they use are lines of the instruction tables. The design is
docs/design/arch.md (§2.1, and §7.2 for who adds what).

| file | holds |
|---|---|
| `portable.def` | `std::arch`: `count_ones`, `has`, `detect`, ... (every target) |
| `aarch64.def` | `std::arch::aarch64`: ACLE's names |
| `x86_64.def` | `std::arch::x86_64`: Intel's names |
| `insn_a64.def` | the AArch64 instructions the compiler's assembler reads from here |
| `insn_x86.def` | the x86-64 instructions the same |
| `embed.sh` | writes them into `compiler/src/arch/tables.vl` |

Run `compiler/arch/embed.sh` after changing a `.def` file;
`tests/run.sh` fails while the generated file is stale. Lines starting
with `#` and blank lines are comments. Columns are separated by ` | `
(space, bar, space), which no column may contain. A malformed line is an
internal error of the compiler on the first program that names
`std::arch` (`tests/run.sh arch` finds it).

## Intrinsic lines

    name | features | signature | form | instruction | flags | memory | fold | semantics | equivalent | doc

| column | what | examples |
|---|---|---|
| name | the vendor's name, unique over the three tables | `vqsubq_u8`, `_mm_movemask_epi8` |
| features | the target features it needs, comma-separated (the table's architecture's names); `-` none | `neon`, `crc`, `sse4.2` |
| signature | `(PARAM: TYPE, ...) -> TYPE`, without `->` for none. Types are vole's, the vendor aliases of the same module (`uint8x16_t`, `__m128i`), or a slice `[u8]` with an `i64` index for a memory form. An immediate is `NAME: const LO..=HI`: an argument that must be a constant in that range (`arch.const_arg`), passed as an `i64` | `(a: uint8x16_t, n: const 0..=15) -> uint8x16_t` |
| form | how lowering makes it (`middle/lower/arch.vl`): `intr` (`Op::Intr`, the instruction), `intr.mem` (0.19: vld2q/vst2q, two vector loads and the uzp1/uzp2 permutes, or zip1/zip2 and two stores; the instruction at -O0; `<u>`, `<t>` are the pair v30, v31), `load`, `store` (a checked `Load`/`Store` of the vector), `cast` (no instruction), `vbin.OP` (add sub mul div and or xor), `vcmp.C` (eq gt ge lt le), `vsplat`, `vext`, `vneg`, `vins` (x, v, lane), `vsel` (the bitwise select of mask a, b, c), `vsum` (the wrapping sum of the lanes): 0.10's vector operations, where the intrinsic is exactly one (-O0 writes its instruction); `load.dup` (one checked element, splat: `ld1r`); `bits.K` (ones leading trailing), `feat.has`, `feat.detect`, `hint`. `:TYPE` after a generic form: the type it computes in when the signature's are others | `intr`, `vcmp.eq:v16i8` |
| instruction | its assembly template (below); `-` none | `uqsub <d>.16b, <a>.16b, <b>.16b` |
| flags | `pure`, `commutative`, `tied=PARAM` (the instruction overwrites that parameter's register: the result starts as a copy of it); `-` none | `pure tied=a` |
| memory | `none`, `load(SLICE, BYTES)`, `store(SLICE, BYTES)` (SLICE's parameter is followed by the index; checked `0 <= i`, `i + BYTES / elem <= len`), `raw` (a pointer form: unsafe) | `load(s, 16)` |
| fold | the constant folder's family (T6, `middle/fold/arch.vl`); `-` none | `lanes.qsub_u`, `perm.tbl` |
| semantics | one line of what it computes, lane `k` of result `r`: the reference `tests/arch/gen.sh` tests against (below, "Semantics") | `r[k] = max(a[k] - b[k], 0)` |
| equivalent | the other architecture's equivalent or recipe (`query arch --equiv`) | `x86_64: _mm_subs_epu8` |
| doc | one line for `query show` and the guide | `lanewise a - b, saturating at 0` |

The effects come from the memory column: none for a register intrinsic,
`panic` for a checked memory form, `unsafe` for a raw one.

### Instruction templates

The assembly the machine layers write (`back/mc_arm64/arch.vl`,
`back/mc_x86_64/arch.vl`, and -O0's `gen0/gen/arch.vl` with fixed
registers), AT&T syntax on x86-64. Placeholders in angle brackets:

| placeholder | is |
|---|---|
| `<d>` | the result's register |
| `<t>` | the instruction temporary: v31 / xmm15 (x17 / r11 for a general register) |
| `<NAME>` | parameter NAME's register, or an immediate's value |
| `<NAME:M>` | a view of the register: `w` (32-bit), `x` (64-bit) general register; on AArch64 `b h s d q`, a vector register's scalar view; for an immediate, a digit scales it (`#<n:2>`: ext's lane count in bytes) |
| `<_d>`, `<_t>` | the result and the temporary, when a parameter is named d or t |

Instructions are separated by `; ` (a result moved between register
files, as `umaxv` then `umov`). Under `tied=P` the template writes the
tied register as `<d>`.

### Semantics

`tests/arch/gen.sh` turns the column into the scalar reference each
intrinsic is tested against, when it is one of:

| form | means | example |
|---|---|---|
| `r[k] = E` | lane k of the result (a vector) | `r[k] = if idx[k] < 16 { t[idx[k]] } else { 0 }` |
| `r = E` | the result (a scalar) | `r = v[lane]` |
| `r = max\|min\|sum over k of E` | a reduction over the lanes of the first vector parameter | `r = max over k of a[k]` |
| `S[I] = E` | a store into slice parameter S, for each lane k | `s[i + k] = v[k]` |
| `X[A..B]` | the elements from A: `r = s[i..i + 16]` is `r[k] = s[i + k]`, `s[i..i + 16] = v` is `s[i + k] = v[k]` | |

E is a vole expression naming only the parameters, `k`, `if`/`else`,
`as`, integer and float literals, the lane types and `max`, `min`,
`abs`, `clamp`. A vector parameter is its lanes, indexed by `k` (`a[k]`,
or any lane: `t[idx[k]]`); a tuple's lanes follow each other. Integers
narrower than 64 bits are computed in `i64` (so `a[k] - b[k]` of u8
lanes may be negative, and `max(a[k] - b[k], 0)` saturates); 64-bit
lanes in their own type (`u64` compares unsigned; arithmetic wraps);
floats in `f64`. The result is converted to the result's lane type with
`as`: it truncates, so wrapping needs nothing more. A trailing
parenthesized note is a comment (`(wrapping)`), except the lanes an
opaque x86 type is read as: `(bytes)`, `(i16 lanes)`, or by name, `(a,
b: i16 lanes; r: i8 lanes)`; `__m128i` is bytes unless it says. Any
other text is prose: the intrinsic then needs `fn ref_NAME` in
`tests/arch/ref/*.vl` (gen.sh's header gives its parameters), and
gen.sh reports one that has neither. A `cast` form is compared byte for
byte with its operand.

## Instruction lines

AArch64 (`insn_a64.def`), for the mnemonics the scalar encoder
(`back/enc_arm64/mod.vl`) does not know:

    mnemonic | class | bits | syntax

`bits` is the encoding with the class's fields zero; `syntax` is
documentation. With vector operands (and SIMD scalar ones, `d0`), the
encoder reads this table before its own chain: a mnemonic may have
several lines, consecutive, and the first whose class fits the operands
encodes them (`cmeq` against `#0` is a line here, against a register the
chain's). The classes (`back/enc_arm64/simd.vl`):

| class | operands | fields added |
|---|---|---|
| `same3` | `Vd.T, Vn.T, Vm.T` | Q, size (from Vd), Rm, Rn, Rd |
| `same3f` | the same, float | Q, sz (bit 22), Rm, Rn, Rd |
| `diff3` | `Vd.Ta, Vn.Tb, Vm.Tb` (long, wide, narrow) | Q and size of the narrowest arrangement, Rm, Rn, Rd |
| `misc2` | `Vd.T, Vn.T[, #0]` | Q and size of the narrowest arrangement, Rn, Rd |
| `misc2f` | the same, float (`#0.0`) | Q of the narrowest, sz of the widest, Rn, Rd |
| `across` | `<V>d, Vn.T` | Q, size, Rn, Rd |
| `acrossf` | the same, float | Q, Rn, Rd |
| `umov` | `Wd\|Xd, Vn.Ts[i]` | Q (for .d), imm5, Rn, Rd |
| `tbl` | `Vd.T, {Vn.16b, ...}, Vm.T` | Q, Rm, len - 1, Rn, Rd |
| `ext` | `Vd.T, Vn.T, Vm.T, #index` | Q, Rm, imm4, Rn, Rd |
| `shrn` | `Vd.T, Vn.T, #shift`: right shifts, narrowing ones too | Q, immh:immb = 2 * esize - shift (esize of the narrowest) |
| `shl` | `Vd.T, Vn.T, #shift`: left shifts, widening ones too | Q, immh:immb = esize + shift (esize of the narrowest) |
| `elem` | `Vd.T, Vn.T, Vm.Ts[i]` (also `Vm.4b[i]`) | Q, size, H:L:M, Rm, Rn, Rd |
| `same3s`, `misc2s`, `misc2fs`, `shrns`, `shls` | the scalar forms, `<V>d, <V>n, ...` (`sqadd d0, d1, d2`: a 64-bit vector of one 64-bit lane) | as the vector class, size from the register's letter; bits are the vector bits \| 0x50000000 |
| `fpair` | `<V>d, Vn.T` (float pairwise to a scalar: `fmaxp s0, v1.2s`) | sz (from Vn), Rn, Rd |
| `rr` | `Rd, Rn` (any registers: crypto) | Rn, Rd |
| `rrr`, `crc` | `Rd, Rn, Rm` | Rm, Rn, Rd |
| `rrrr` | `Vd, Vn, Vm, Va` (`eor3`, `bcax`) | Rm, Ra, Rn, Rd |
| `ldst` | `{Vt.T, ...}, [Xn]` (`ld1r`; the multiple-structure loads and stores) | Q, size (from the list), Rn, Rt |
| `xar` | `Vd, Vn, Vm, #imm6` | Rm, imm6, Rn, Rd |

The regular AArch64 families (every type and arrangement of an
operation) are written by `tools/arch/a64_families.py --write`, between
the `# ==== generated` markers of `aarch64.def` and `insn_a64.def`: change
a family there, not its lines; lines outside the markers are kept.

x86-64 (`insn_x86.def`), for the mnemonics `back/enc_x86.vl`'s own
table lacks:

    mnemonic | class | prefix | map | opcode | flags

`prefix` is the mandatory prefix (`66`, `f2`, `f3`, `-`), `map` the
opcode map (`0f`, `0f38`, `0f3a`), `opcode` the byte, in hexadecimal;
`flags`, space-separated (`-`: none): `w` REX.W (VEX.W1 in a VEX class),
`o16` the 0x66 operand-size prefix, `/N` the ModRM.reg digit, `i=XX` a
shift's immediate form (opcode XX with the digit), `c` commutative and
`cmp` commutative for the symmetric predicates (the sources are swapped,
as LLVM's assembler does, when only the second is r8-r15: the two-byte
VEX prefix then holds). The classes (operands in AT&T order):

| class | operands | ModRM reg, r/m, VEX.vvvv |
|---|---|---|
| `sse` | `src, dst` | dst, src, - |
| `ssei` | `$imm8, src, dst` | dst, src, - |
| `sser` | `src, dst` | src, dst, - (a register written to r/m) |
| `sseir` | `$imm8, src, dst` | src, dst, - (`pextrb`) |
| `shift` | `$imm8\|%xmm, dst` | dst, count; the immediate: the digit, dst |
| `sse0` | `%xmm0, src, dst` | dst, src (xmm0 implicit: `pblendvb`, `sha256rnds2`) |
| `vex` | `src2, src1, dst` | dst, src2, src1 |
| `vexv` | `src1, src2, dst` | dst, src2, src1 (`bextr`, `bzhi`) |
| `vex2`, `vex2r` | `src, dst` | dst, src (`vex2r`: src, dst); no vvvv |
| `vexi`, `vex2i`, `vex2ir` | `$imm8, ...` | as `vex`, `vex2`, `vex2r` |
| `vexshift` | `$imm8\|%xmm, src, dst` | count form as `vex`; the immediate: the digit, src, dst |
| `vex4` | `mask, src2, src1, dst` | as `vex`; the mask in the immediate's top nibble |
| `vexd` | `src, dst` | the digit, src, dst (`blsr`) |

VEX.L is 1 when an operand is a ymm register. The encoder's own table
also has `vmovdqu`, `vmovdqa` and `vzeroupper` (the back end writes them
for 256-bit values). On x86-64 a template writes `<NAME:y>` for a vector
register's 256-bit view (`%ymm3`), and `<NAME:0>` for an operand the
instruction reads in xmm0 (printed `%xmm0`; the machine layer saves xmm0
around it). The families of `x86_64.def` and every line of
`insn_x86.def` are written by `tools/arch/x86_families.py --write`
(between the `# ==== generated` markers), with `tests/arch/enc_x86.s`,
the corpus `tests/arch/enc.sh` assembles with the compiler and with cc
and compares byte for byte.

## Adding an intrinsic

1. Its line in the architecture's table, its instruction's line when the
   encoder lacks it; `compiler/arch/embed.sh`.
2. Its semantics as above, or a reference in `tests/arch/ref/`;
   `tests/arch/gen.sh --check` (`tests/run.sh arch-gen`) tests it
   against the reference at -O0 and -O2, at run time and folded (the
   host's architecture runs; the other is compiled); `tests/objcheck.sh
   arch_` (and `-t x86_64-macos arch_`) checks the encoder against `cc
   -c` on the generated programs; `tests/fuzz/run.sh -A` draws it into
   random programs.
3. A new form, class or placeholder is a change to the compiler: its
   owner is in docs/design/arch.md, "Phase 0 contract".
