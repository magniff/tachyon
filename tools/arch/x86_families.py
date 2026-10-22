#!/usr/bin/env python3
"""The intrinsics of std::arch::x86_64 (0.19, docs/design/arch.md section
2.3.2) and the instructions they use, written as lines of
compiler/arch/x86_64.def and compiler/arch/insn_x86.def, and the encoding
corpus tests/arch/enc_x86.s (every instruction of insn_x86.def with low and
high registers, both vector widths and memory operands, which
tests/arch/enc.sh assembles with the compiler and with cc and compares
byte for byte).

The .def files stay the source of truth for the compiler: this script
makes their families (the same operation over lane types, widths and
features) in one place. compiler/arch/README.md gives the columns.

usage: tools/arch/x86_families.py [--insn | --enc] [--write]

  (no option)  print x86_64.def's generated section on stdout
  --insn       print insn_x86.def's instead
  --enc        print the encoding corpus instead
  --write      rewrite the three files (the .def files between the
               `# ==== generated` markers; the rest is kept), then run
               compiler/arch/embed.sh yourself

x86-64 is not executed in 0.19 (compile-tested only): the semantics are
the references tests/arch/gen.sh compiles; they run once x86 testing
returns (docs/design/arch.md, "T5 as built": what is encoded but never
run). A semantics column that is prose names `fn ref_NAME` in
tests/arch/ref/x86_*.vl.
"""
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# ---- Instructions (insn_x86.def) ----
#
# (mnemonic, class, prefix, map, opcode, flags, shapes): shapes are the
# operand lists the encoding corpus tries, AT&T order, one kind per
# operand: x xmm, X xmm or memory, y ymm, Y ymm or memory, v xmm or ymm
# (both widths, one per line), V v or memory, g r32, G r32 or memory, q
# r64, Q r64 or memory, h r16 or memory, b r8 or memory, i imm8, 0 %xmm0.

INSNS = []


def insn(mn, cls, pfx, mp, op, flags="-", shapes=()):
    INSNS.append((mn, cls, pfx, mp, op, flags, list(shapes)))


def sse_ops(pfx, mp, table, shape="X x", cls="sse"):
    for mn, op in table:
        insn(mn, cls, pfx, mp, op, "-", [shape])


# SSE2, 66 0F (the encoder's own table has paddb..pxor, pcmpeq/gt, the low
# unpacks, movdqa: the rest is here)
sse_ops("66", "0f", [
    ("paddsb", "ec"), ("paddsw", "ed"), ("paddusb", "dc"), ("paddusw", "dd"),
    ("psubsb", "e8"), ("psubsw", "e9"), ("psubusb", "d8"), ("psubusw", "d9"),
    ("pmulhw", "e5"), ("pmulhuw", "e4"), ("pmuludq", "f4"), ("pmaddwd", "f5"),
    ("psadbw", "f6"), ("pavgb", "e0"), ("pavgw", "e3"),
    ("pminub", "da"), ("pmaxub", "de"), ("pminsw", "ea"), ("pmaxsw", "ee"),
    ("punpckhbw", "68"), ("punpckhwd", "69"), ("punpckhdq", "6a"), ("punpckhqdq", "6d"),
    ("packsswb", "63"), ("packssdw", "6b"), ("packuswb", "67"),
    ("andpd", "54"), ("andnpd", "55"), ("orpd", "56"),
    ("minpd", "5d"), ("maxpd", "5f"), ("sqrtpd", "51"), ("unpckhpd", "15"),
    ("cvtps2dq", "5b"), ("cvttpd2dq", "e6"), ("cvtpd2ps", "5a"),
])
sse_ops("", "0f", [
    ("andps", "54"), ("andnps", "55"), ("orps", "56"), ("minps", "5d"), ("maxps", "5f"),
    ("sqrtps", "51"), ("unpcklps", "14"), ("unpckhps", "15"),
    ("cvtdq2ps", "5b"), ("cvtps2pd", "5a"),
])
sse_ops("f3", "0f", [("cvttps2dq", "5b"), ("cvtdq2pd", "e6")])
sse_ops("f2", "0f", [("cvtpd2dq", "e6")])
insn("pmovmskb", "sse", "66", "0f", "d7", "-", ["x g"])
insn("movmskps", "sse", "", "0f", "50", "-", ["x g"])
insn("movmskpd", "sse", "66", "0f", "50", "-", ["x g"])
insn("pshuflw", "ssei", "f2", "0f", "70", "-", ["i X x"])
insn("pshufhw", "ssei", "f3", "0f", "70", "-", ["i X x"])
insn("shufpd", "ssei", "66", "0f", "c6", "-", ["i X x"])
insn("pextrw", "ssei", "66", "0f", "c5", "-", ["i x g"])
insn("pinsrw", "ssei", "66", "0f", "c4", "-", ["i G x"])
# shifts: by an xmm count (the opcode) or an immediate (i=, the digit)
for mn, op, imm, digit in [("psllw", "f1", "71", "6"), ("psrlw", "d1", "71", "2"),
                           ("psrld", "d2", "72", "2"), ("psrlq", "d3", "73", "2"),
                           ("psraw", "e1", "71", "4"), ("psrad", "e2", "72", "4")]:
    insn(mn, "shift", "66", "0f", op, "i=" + imm + " /" + digit, ["i x", "X x"])
insn("pslldq", "shift", "66", "0f", "73", "i=73 /7", ["i x"])
insn("psrldq", "shift", "66", "0f", "73", "i=73 /3", ["i x"])
# SSE3
sse_ops("f2", "0f", [("haddps", "7c"), ("hsubps", "7d"), ("addsubps", "d0"),
                     ("movddup", "12")])
sse_ops("66", "0f", [("haddpd", "7c"), ("hsubpd", "7d"), ("addsubpd", "d0")])
sse_ops("f3", "0f", [("movshdup", "16"), ("movsldup", "12")])
# SSSE3, 66 0F38 (pshufb is the seed)
sse_ops("66", "0f38", [
    ("pshufb", "00"), ("phaddw", "01"), ("phaddd", "02"), ("phaddsw", "03"),
    ("pmaddubsw", "04"), ("phsubw", "05"), ("phsubd", "06"), ("phsubsw", "07"),
    ("psignb", "08"), ("psignw", "09"), ("psignd", "0a"), ("pmulhrsw", "0b"),
    ("pabsb", "1c"), ("pabsw", "1d"), ("pabsd", "1e"),
])
insn("palignr", "ssei", "66", "0f3a", "0f", "-", ["i X x"])
# SSE4.1
sse_ops("66", "0f38", [
    ("ptest", "17"), ("pmuldq", "28"), ("pcmpeqq", "29"), ("packusdw", "2b"),
    ("pminsb", "38"), ("pminsd", "39"), ("pminuw", "3a"), ("pminud", "3b"),
    ("pmaxsb", "3c"), ("pmaxsd", "3d"), ("pmaxuw", "3e"), ("pmaxud", "3f"),
    ("pmulld", "40"), ("phminposuw", "41"),
    ("pmovsxbw", "20"), ("pmovsxbd", "21"), ("pmovsxbq", "22"), ("pmovsxwd", "23"),
    ("pmovsxwq", "24"), ("pmovsxdq", "25"),
    ("pmovzxbw", "30"), ("pmovzxbd", "31"), ("pmovzxbq", "32"), ("pmovzxwd", "33"),
    ("pmovzxwq", "34"), ("pmovzxdq", "35"),
])
for mn, op in [("pblendvb", "10"), ("blendvps", "14"), ("blendvpd", "15")]:
    insn(mn, "sse0", "66", "0f38", op, "-", ["0 X x"])
for mn, op in [("roundps", "08"), ("roundpd", "09"), ("blendps", "0c"), ("blendpd", "0d"),
               ("pblendw", "0e")]:
    insn(mn, "ssei", "66", "0f3a", op, "-", ["i X x"])
insn("pextrb", "sseir", "66", "0f3a", "14", "-", ["i x g"])
insn("pextrd", "sseir", "66", "0f3a", "16", "-", ["i x G"])
insn("pextrq", "sseir", "66", "0f3a", "16", "w", ["i x Q"])
insn("extractps", "sseir", "66", "0f3a", "17", "-", ["i x G"])
insn("pinsrb", "ssei", "66", "0f3a", "20", "-", ["i g x"])
insn("pinsrd", "ssei", "66", "0f3a", "22", "-", ["i G x"])
insn("pinsrq", "ssei", "66", "0f3a", "22", "w", ["i Q x"])
# SSE4.2, CRC-32 (crc32q is the seed's), POPCNT, LZCNT, BMI1's TZCNT
insn("pcmpgtq", "sse", "66", "0f38", "37", "-", ["X x"])
insn("crc32b", "sse", "f2", "0f38", "f0", "-", ["b g"])
insn("crc32w", "sse", "f2", "0f38", "f1", "o16", ["h g"])
insn("crc32l", "sse", "f2", "0f38", "f1", "-", ["G g"])
insn("crc32q", "sse", "f2", "0f38", "f1", "w", ["Q q"])
for mn, op in [("popcnt", "b8"), ("lzcnt", "bd"), ("tzcnt", "bc")]:
    insn(mn + "l", "sse", "f3", "0f", op, "-", ["G g"])
    insn(mn + "q", "sse", "f3", "0f", op, "w", ["Q q"])
# PCLMULQDQ, AES-NI, SHA
insn("pclmulqdq", "ssei", "66", "0f3a", "44", "-", ["i X x"])
sse_ops("66", "0f38", [("aesimc", "db"), ("aesenc", "dc"), ("aesenclast", "dd"),
                       ("aesdec", "de"), ("aesdeclast", "df")])
insn("aeskeygenassist", "ssei", "66", "0f3a", "df", "-", ["i X x"])
sse_ops("", "0f38", [("sha1nexte", "c8"), ("sha1msg1", "c9"), ("sha1msg2", "ca"),
                     ("sha256msg1", "cc"), ("sha256msg2", "cd")])
insn("sha256rnds2", "sse0", "", "0f38", "cb", "-", ["0 X x"])
insn("sha1rnds4", "ssei", "", "0f3a", "cc", "-", ["i X x"])

# ---- AVX, AVX2, FMA, BMI (VEX) ----

def vex3(pfx, mp, table, flags="-", shape="V v v"):
    for mn, op in table:
        insn(mn, "vex", pfx, mp, op, flags, [shape])


# commutative (LLVM swaps their sources for the short prefix: flag c)
vex3("66", "0f", [
    ("vpaddb", "fc"), ("vpaddw", "fd"), ("vpaddd", "fe"), ("vpaddq", "d4"),
    ("vpaddsb", "ec"), ("vpaddsw", "ed"), ("vpaddusb", "dc"), ("vpaddusw", "dd"),
    ("vpmullw", "d5"), ("vpmulhw", "e5"), ("vpmulhuw", "e4"), ("vpmuludq", "f4"),
    ("vpmaddwd", "f5"), ("vpsadbw", "f6"), ("vpavgb", "e0"), ("vpavgw", "e3"),
    ("vpminub", "da"), ("vpmaxub", "de"), ("vpminsw", "ea"), ("vpmaxsw", "ee"),
    ("vpcmpeqb", "74"), ("vpcmpeqw", "75"), ("vpcmpeqd", "76"),
    ("vpand", "db"), ("vpor", "eb"), ("vpxor", "ef"),
    ("vaddpd", "58"), ("vmulpd", "59"), ("vandpd", "54"), ("vorpd", "56"), ("vxorpd", "57"),
], "c")
vex3("", "0f", [("vaddps", "58"), ("vmulps", "59"), ("vandps", "54"), ("vorps", "56"),
                ("vxorps", "57")], "c")
vex3("66", "0f", [
    ("vpsubb", "f8"), ("vpsubw", "f9"), ("vpsubd", "fa"), ("vpsubq", "fb"),
    ("vpsubsb", "e8"), ("vpsubsw", "e9"), ("vpsubusb", "d8"), ("vpsubusw", "d9"),
    ("vpcmpgtb", "64"), ("vpcmpgtw", "65"), ("vpcmpgtd", "66"), ("vpandn", "df"),
    ("vpunpcklbw", "60"), ("vpunpcklwd", "61"), ("vpunpckldq", "62"), ("vpunpcklqdq", "6c"),
    ("vpunpckhbw", "68"), ("vpunpckhwd", "69"), ("vpunpckhdq", "6a"), ("vpunpckhqdq", "6d"),
    ("vpacksswb", "63"), ("vpackssdw", "6b"), ("vpackuswb", "67"),
    ("vsubpd", "5c"), ("vdivpd", "5e"), ("vminpd", "5d"), ("vmaxpd", "5f"), ("vandnpd", "55"),
])
vex3("", "0f", [("vsubps", "5c"), ("vdivps", "5e"), ("vminps", "5d"), ("vmaxps", "5f"),
                ("vandnps", "55")])
vex3("66", "0f38", [
    ("vpshufb", "00"), ("vphaddw", "01"), ("vphaddd", "02"), ("vphaddsw", "03"),
    ("vpmaddubsw", "04"), ("vphsubw", "05"), ("vphsubd", "06"), ("vphsubsw", "07"),
    ("vpsignb", "08"), ("vpsignw", "09"), ("vpsignd", "0a"), ("vpmulhrsw", "0b"),
    ("vpmuldq", "28"), ("vpcmpeqq", "29"), ("vpackusdw", "2b"), ("vpcmpgtq", "37"),
    ("vpminsb", "38"), ("vpminsd", "39"), ("vpminuw", "3a"), ("vpminud", "3b"),
    ("vpmaxsb", "3c"), ("vpmaxsd", "3d"), ("vpmaxuw", "3e"), ("vpmaxud", "3f"),
    ("vpmulld", "40"), ("vpsrlvd", "45"), ("vpsravd", "46"), ("vpsllvd", "47"),
    ("vpermilps", "0c"), ("vpermilpd", "0d"),
])
vex3("66", "0f38", [("vpsrlvq", "45"), ("vpsllvq", "47")], "w")
vex3("66", "0f38", [("vpermd", "36"), ("vpermps", "16")], "-", "Y y y")
# one source
for mn, pfx, mp, op, shape in [
        ("vpmovmskb", "66", "0f", "d7", "v g"), ("vmovmskps", "", "0f", "50", "v g"),
        ("vmovmskpd", "66", "0f", "50", "v g"),
        ("vsqrtps", "", "0f", "51", "V v"), ("vsqrtpd", "66", "0f", "51", "V v"),
        ("vcvtdq2ps", "", "0f", "5b", "V v"), ("vcvttps2dq", "f3", "0f", "5b", "V v"),
        ("vcvtps2dq", "66", "0f", "5b", "V v"),
        ("vpabsb", "66", "0f38", "1c", "V v"), ("vpabsw", "66", "0f38", "1d", "V v"),
        ("vpabsd", "66", "0f38", "1e", "V v"), ("vptest", "66", "0f38", "17", "V v"),
        ("vtestps", "66", "0f38", "0e", "V v"), ("vtestpd", "66", "0f38", "0f", "V v"),
        ("vpbroadcastb", "66", "0f38", "78", "x v"), ("vpbroadcastw", "66", "0f38", "79", "x v"),
        ("vpbroadcastd", "66", "0f38", "58", "x v"), ("vpbroadcastq", "66", "0f38", "59", "x v"),
        ("vbroadcastss", "66", "0f38", "18", "x v"), ("vbroadcastsd", "66", "0f38", "19", "x y"),
        ("vmovshdup", "f3", "0f", "16", "V v"), ("vmovsldup", "f3", "0f", "12", "V v")]:
    insn(mn, "vex2", pfx, mp, op, "-", [shape])
for mn, op in [("vpmovsxbw", "20"), ("vpmovsxbd", "21"), ("vpmovsxbq", "22"),
               ("vpmovsxwd", "23"), ("vpmovsxwq", "24"), ("vpmovsxdq", "25"),
               ("vpmovzxbw", "30"), ("vpmovzxbd", "31"), ("vpmovzxbq", "32"),
               ("vpmovzxwd", "33"), ("vpmovzxwq", "34"), ("vpmovzxdq", "35")]:
    insn(mn, "vex2", "66", "0f38", op, "-", ["X y"])
# an immediate
for mn, pfx, mp, op, flags, cls, shape in [
        ("vpshufd", "66", "0f", "70", "-", "vex2i", "i V v"),
        ("vpshuflw", "f2", "0f", "70", "-", "vex2i", "i V v"),
        ("vpshufhw", "f3", "0f", "70", "-", "vex2i", "i V v"),
        ("vpermq", "66", "0f3a", "00", "w", "vex2i", "i Y y"),
        ("vpermpd", "66", "0f3a", "01", "w", "vex2i", "i Y y"),
        ("vroundps", "66", "0f3a", "08", "-", "vex2i", "i V v"),
        ("vroundpd", "66", "0f3a", "09", "-", "vex2i", "i V v"),
        ("vextracti128", "66", "0f3a", "39", "-", "vex2ir", "i y X"),
        ("vextractf128", "66", "0f3a", "19", "-", "vex2ir", "i y X"),
        ("vpalignr", "66", "0f3a", "0f", "-", "vexi", "i V v v"),
        ("vpblendw", "66", "0f3a", "0e", "-", "vexi", "i V v v"),
        ("vpblendd", "66", "0f3a", "02", "-", "vexi", "i V v v"),
        ("vblendps", "66", "0f3a", "0c", "-", "vexi", "i V v v"),
        ("vblendpd", "66", "0f3a", "0d", "-", "vexi", "i V v v"),
        ("vshufps", "", "0f", "c6", "-", "vexi", "i V v v"),
        ("vshufpd", "66", "0f", "c6", "-", "vexi", "i V v v"),
        ("vcmpps", "", "0f", "c2", "cmp", "vexi", "i V v v"),
        ("vcmppd", "66", "0f", "c2", "cmp", "vexi", "i V v v"),
        ("vperm2i128", "66", "0f3a", "46", "-", "vexi", "i Y y y"),
        ("vperm2f128", "66", "0f3a", "06", "-", "vexi", "i Y y y"),
        ("vinserti128", "66", "0f3a", "38", "-", "vexi", "i X y y"),
        ("vinsertf128", "66", "0f3a", "18", "-", "vexi", "i X y y")]:
    insn(mn, cls, pfx, mp, op, flags, [shape])
# the mask in the immediate's top nibble
for mn, op in [("vpblendvb", "4c"), ("vblendvps", "4a"), ("vblendvpd", "4b")]:
    insn(mn, "vex4", "66", "0f3a", op, "-", ["v V v v"])
# shifts: by an xmm count or an immediate (vvvv is then the destination)
for mn, op, imm, digit in [("vpsllw", "f1", "71", "6"), ("vpslld", "f2", "72", "6"),
                           ("vpsllq", "f3", "73", "6"), ("vpsrlw", "d1", "71", "2"),
                           ("vpsrld", "d2", "72", "2"), ("vpsrlq", "d3", "73", "2"),
                           ("vpsraw", "e1", "71", "4"), ("vpsrad", "e2", "72", "4")]:
    insn(mn, "vexshift", "66", "0f", op, "i=" + imm + " /" + digit, ["i v v", "X v v"])
insn("vpslldq", "vexshift", "66", "0f", "73", "i=73 /7", ["i v v"])
insn("vpsrldq", "vexshift", "66", "0f", "73", "i=73 /3", ["i v v"])
# FMA: 66 0F38, W0 ps, W1 pd
for kind, base in [("fmadd", 0x98), ("fmsub", 0x9a), ("fnmadd", 0x9c), ("fnmsub", 0x9e)]:
    for order, add in [("132", 0), ("213", 0x10), ("231", 0x20)]:
        for t, w in [("ps", "-"), ("pd", "w")]:
            insn("v" + kind + order + t, "vex", "66", "0f38", "%02x" % (base + add), w, ["V v v"])
# BMI1, BMI2 (VEX on general registers; q: W1)
for sfx, w, s, S in [("l", "-", "g", "G"), ("q", "w", "q", "Q")]:
    insn("andn" + sfx, "vex", "", "0f38", "f2", w, [S + " " + s + " " + s])
    insn("bextr" + sfx, "vexv", "", "0f38", "f7", w, [s + " " + S + " " + s])
    insn("bzhi" + sfx, "vexv", "", "0f38", "f5", w, [s + " " + S + " " + s])
    insn("pdep" + sfx, "vex", "f2", "0f38", "f5", w, [S + " " + s + " " + s])
    insn("pext" + sfx, "vex", "f3", "0f38", "f5", w, [S + " " + s + " " + s])
    insn("blsr" + sfx, "vexd", "", "0f38", "f3", w + " /1" if w != "-" else "/1", [S + " " + s])
    insn("blsmsk" + sfx, "vexd", "", "0f38", "f3", w + " /2" if w != "-" else "/2", [S + " " + s])
    insn("blsi" + sfx, "vexd", "", "0f38", "f3", w + " /3" if w != "-" else "/3", [S + " " + s])


# ---- Intrinsics (x86_64.def) ----

OUT = []


def family(title):
    OUT.append("")
    OUT.append("# ---- " + title + " ----")


def line(name, feat, sig, form, ins, flags, mem, fold, sem, equiv, doc):
    # (` | ` separates the columns: an `or` is written `a[k]|b[k]`)
    fields = [f.replace(" | ", "|") for f in [name, feat, sig, form, ins, flags, mem, fold, sem, equiv, doc]]
    OUT.append(" | ".join(fields))


def intr(name, feat, sig, ins, flags, sem, doc, fold="-", equiv="-", form="intr"):
    line(name, feat, sig, form, ins, flags, "none", fold, sem, equiv, doc)


M = "__m128i"
Y = "__m256i"
LANE = {8: "i8", 16: "i16", 32: "i32", 64: "i64"}
ULANE = {8: "u8", 16: "u16", 32: "u32", 64: "u64"}
SFX = {8: "b", 16: "w", 32: "d", 64: "q"}
EPI = {8: "epi8", 16: "epi16", 32: "epi32", 64: "epi64"}
EPU = {8: "epu8", 16: "epu16", 32: "epu32", 64: "epu64"}
NLANES = {8: 16, 16: 8, 32: 4, 64: 2}


PERM2 = ("r[k] = if (imm8 >> (4 * (k / 16))) & 8 != 0 { 0 } else if (imm8 >> (4 * (k / 16))) & 2 == 0 { a[16 * ((imm8 >> (4 * (k / 16))) & 1) + k % 16] } else { b[16 * ((imm8 >> (4 * (k / 16))) & 1) + k % 16] } (a, b, r: bytes)")
SAD = ("r[k] = " + " + ".join("abs(a[8 * k + %d] - b[8 * k + %d])" % (j, j) for j in range(8))
       + " (a, b: u8 lanes; r: u64 lanes)")
TESTZ = "r = min over k of (if a[k] & b[k] == 0 { 1 } else { 0 }) (bytes)"
TESTC = "r = min over k of (if (a[k] ^ 255) & b[k] == 0 { 1 } else { 0 }) (bytes)"
SHIFT_L = "r[k] = if count[0] > %d { 0 } else { a[k] << (count[0]%s) } (a, r: %s lanes; count: u64 lanes)"
SHIFT_R = "r[k] = if count[0] > %d { 0 } else { a[k] >> (count[0]%s) } (a, r: %s lanes; count: u64 lanes)"
SHIFT_A = "r[k] = a[k] >> (if count[0] > %d { %d } else { count[0] as i64 }) (a, r: %s lanes; count: u64 lanes)"


def lanes(bits, signed=True):
    return "(%s lanes)" % (LANE[bits] if signed else ULANE[bits])


def two(t):
    return "(a: %s, b: %s) -> %s" % (t, t, t)


def sse2op(name, feat, mn, sem, doc, comm=False, equiv="-", t=M):
    """An SSE operation of two sources, tied to the first; with its
    256-bit AVX2 twin when `avx2` names it."""
    intr(name, feat, two(t), "%s <b>, <d>" % mn, "pure%s tied=a" % (" commutative" if comm else ""),
         sem, doc, equiv=equiv)


def avx2op(name, feat, mn, sem, doc, comm=False, equiv="-", t=Y):
    intr(name, feat, two(t), "v%s <b:y>, <a:y>, <d:y>" % mn, "pure" + (" commutative" if comm else ""),
         sem, doc, equiv=equiv)


def per_lane(sem):
    """A 128-bit semantics over k made per 128-bit lane of a 256-bit
    vector: `k` within the lane, the lane's base added to each index."""
    return sem


# -- loads and stores --
family("Loads and stores (safe: a slice and an index, checked)")
for nm, el, t, bytes_ in [("_mm_loadu_si128", "u8", M, 16), ("_mm_load_si128", "u8", M, 16),
                          ("_mm_loadu_ps", "f32", "__m128", 16),
                          ("_mm_loadu_pd", "f64", "__m128d", 16),
                          ("_mm256_loadu_si256", "u8", Y, 32), ("_mm256_load_si256", "u8", Y, 32),
                          ("_mm256_loadu_ps", "f32", "__m256", 32),
                          ("_mm256_loadu_pd", "f64", "__m256d", 32)]:
    n = bytes_ * 8 // {"u8": 8, "f32": 32, "f64": 64}[el]
    feat = "avx" if bytes_ == 32 else "sse2"
    mnem = "vmovdqu (<s>), <d:y>" if bytes_ == 32 else "movdqu (<s>), <d>"
    aligned = "_load_" in nm
    line(nm, feat, "(s: [%s], i: i64) -> %s" % (el, t), "load", mnem, "-",
         "load(s, %d)" % bytes_, "-", "r = s[i..i + %d]" % n,
         "aarch64: vld1q_u8" if bytes_ == 16 and el == "u8" else "-",
         "the %d bytes s[i..i + %d] (checked: 0 <= i, i + %d <= s.len)%s" % (
             bytes_, n, n, "; alignment is not required (an unaligned load: it never faults)" if aligned else ""))
for nm, el, t, bytes_ in [("_mm_storeu_si128", "u8", M, 16), ("_mm_store_si128", "u8", M, 16),
                          ("_mm_storeu_ps", "f32", "__m128", 16),
                          ("_mm_storeu_pd", "f64", "__m128d", 16),
                          ("_mm256_storeu_si256", "u8", Y, 32), ("_mm256_store_si256", "u8", Y, 32),
                          ("_mm256_storeu_ps", "f32", "__m256", 32),
                          ("_mm256_storeu_pd", "f64", "__m256d", 32)]:
    n = bytes_ * 8 // {"u8": 8, "f32": 32, "f64": 64}[el]
    feat = "avx" if bytes_ == 32 else "sse2"
    mnem = "vmovdqu <v:y>, (<s>)" if bytes_ == 32 else "movdqu <v>, (<s>)"
    line(nm, feat, "(s: [%s], i: i64, v: %s)" % (el, t), "store", mnem, "-",
         "store(s, %d)" % bytes_, "-", "s[i..i + %d] = v" % n,
         "aarch64: vst1q_u8" if bytes_ == 16 and el == "u8" else "-",
         "v's %d bytes into s[i..i + %d] (checked)%s" % (
             bytes_, n, "; alignment is not required" if "_store_" in nm else ""))

# -- build --
family("Build")
for bits in (8, 16, 32, 64):
    lt = LANE[bits]
    nm = "_mm_set1_epi64x" if bits == 64 else "_mm_set1_" + EPI[bits]
    seq = {8: "movd <x:w>, <d>; punpcklbw <d>, <d>; pshuflw $0, <d>, <d>; pshufd $0, <d>, <d>",
           16: "movd <x:w>, <d>; pshuflw $0, <d>, <d>; pshufd $0, <d>, <d>",
           32: "movd <x:w>, <d>; pshufd $0, <d>, <d>",
           64: "movq <x>, <d>; punpcklqdq <d>, <d>"}[bits]
    line(nm, "sse2", "(x: %s) -> %s" % (lt, M), "vsplat:v%d%s" % (NLANES[bits], lt), seq,
         "pure", "none", "splat", "r[k] = x %s" % lanes(bits),
         "aarch64: vdupq_n_%s" % lt.replace("i", "s"), "every %d-bit lane x" % bits)
intr("_mm_setzero_si128", "sse2", "() -> " + M, "pxor <d>, <d>", "pure", "r[k] = 0 (bytes)",
     "zero", equiv="aarch64: vdupq_n_u8(0)")
intr("_mm_setzero_ps", "sse2", "() -> __m128", "xorps <d>, <d>", "pure",
     "r[k] = 0.0", "zero")
intr("_mm_setzero_pd", "sse2", "() -> __m128d", "xorpd <d>, <d>", "pure",
     "r[k] = 0.0", "zero")
intr("_mm_cvtsi32_si128", "sse2", "(a: i32) -> " + M, "movd <a:w>, <d>", "pure",
     "r[k] = if k == 0 { a } else { 0 } (i32 lanes)", "a in lane 0, the rest zero")
intr("_mm_cvtsi64_si128", "sse2", "(a: i64) -> " + M, "movq <a>, <d>", "pure",
     "r[k] = if k == 0 { a } else { 0 } (i64 lanes)", "a in lane 0, the rest zero")
intr("_mm_cvtsi128_si32", "sse2", "(a: %s) -> i32" % M, "movd <a>, <d:w>", "pure",
     "r = a[0] (i32 lanes)", "lane 0")
intr("_mm_cvtsi128_si64", "sse2", "(a: %s) -> i64" % M, "movq <a>, <d>", "pure",
     "r = a[0] (i64 lanes)", "lane 0")
for bits in (8, 16, 32, 64):
    lt = LANE[bits]
    nm = "_mm256_set1_epi64x" if bits == 64 else "_mm256_set1_" + EPI[bits]
    seq = {8: "movd <x:w>, <t>; punpcklbw <t>, <t>; pshuflw $0, <t>, <t>; pshufd $0, <t>, <t>",
           16: "movd <x:w>, <t>; pshuflw $0, <t>, <t>; pshufd $0, <t>, <t>",
           32: "movd <x:w>, <t>; pshufd $0, <t>, <t>",
           64: "movq <x>, <t>; punpcklqdq <t>, <t>"}[bits]
    intr(nm, "avx", "(x: %s) -> %s" % (lt, Y), seq + "; vinsertf128 $1, <t>, <t:y>, <d:y>",
         "pure", "r[k] = x %s" % lanes(bits), "every %d-bit lane x" % bits)
intr("_mm256_setzero_si256", "avx", "() -> " + Y, "vxorps <d:y>, <d:y>, <d:y>", "pure",
     "r[k] = 0 (bytes)", "zero")
intr("_mm256_setzero_ps", "avx", "() -> __m256", "vxorps <d:y>, <d:y>, <d:y>", "pure",
     "r[k] = 0.0", "zero")
intr("_mm256_setzero_pd", "avx", "() -> __m256d", "vxorps <d:y>, <d:y>, <d:y>", "pure",
     "r[k] = 0.0", "zero")

# -- casts --
family("Casts")
CASTS = [("si128", M), ("ps", "__m128"), ("pd", "__m128d")]
for a, ta in CASTS:
    for b, tb in CASTS:
        if a != b:
            line("_mm_cast%s_%s" % (a, b), "sse2", "(a: %s) -> %s" % (ta, tb), "cast", "-", "pure",
                 "none", "cast", "r = a's 16 bytes as %s" % tb, "-", "the same bits as %s" % tb)
CASTS = [("si256", Y), ("ps", "__m256"), ("pd", "__m256d")]
for a, ta in CASTS:
    for b, tb in CASTS:
        if a != b:
            line("_mm256_cast%s_%s" % (a, b), "avx", "(a: %s) -> %s" % (ta, tb), "cast", "-", "pure",
                 "none", "cast", "r = a's 32 bytes as %s" % tb, "-", "the same bits as %s" % tb)
for nm, ta, tb in [("_mm256_castsi256_si128", Y, M), ("_mm256_castps256_ps128", "__m256", "__m128"),
                   ("_mm256_castpd256_pd128", "__m256d", "__m128d")]:
    intr(nm, "avx", "(a: %s) -> %s" % (ta, tb), "vmovdqa <a>, <d>", "pure",
         "r[k] = a[k] (a, r: bytes)", "the low 128 bits")
for nm, ta, tb in [("_mm256_castsi128_si256", M, Y), ("_mm256_castps128_ps256", "__m128", "__m256"),
                   ("_mm256_castpd128_pd256", "__m128d", "__m256d"),
                   ("_mm256_zextsi128_si256", M, Y), ("_mm256_zextps128_ps256", "__m128", "__m256"),
                   ("_mm256_zextpd128_pd256", "__m128d", "__m256d")]:
    intr(nm, "avx", "(a: %s) -> %s" % (ta, tb), "vmovdqa <a>, <d>", "pure",
         "r[k] = if k < 16 { a[k] } else { 0 } (a, r: bytes)",
         "a in the low 128 bits, the high ones zero (defined: Intel leaves them undefined in the cast)")

# -- integer arithmetic, SSE2 --
family("Integer arithmetic (SSE2)")
for bits in (8, 16, 32, 64):
    for op, sym, mn in [("add", "+", "padd"), ("sub", "-", "psub")]:
        line("_mm_%s_%s" % (op, EPI[bits]), "sse2", two(M), "vbin.%s:v%d%s" % (op, NLANES[bits], LANE[bits]),
             "%s%s <b>, <d>" % (mn, SFX[bits]), "pure" + (" commutative" if op == "add" else ""),
             "none", "lanes." + op, "r[k] = a[k] %s b[k] %s" % (sym, lanes(bits)),
             "aarch64: v%sq_s%d" % (op, bits), "lanewise a %s b, wrapping" % sym)
line("_mm_mullo_epi16", "sse2", two(M), "vbin.mul:v8i16", "pmullw <b>, <d>", "pure commutative",
     "none", "lanes.mul", "r[k] = a[k] * b[k] (i16 lanes)", "aarch64: vmulq_s16",
     "lanewise a * b, the low 16 bits")
for bits, s in [(8, True), (16, True), (8, False), (16, False)]:
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if s else (0, (1 << bits) - 1)
    lt = lanes(bits, s)
    suffix = (EPI if s else EPU)[bits]
    mnsuf = ("s" if s else "us") + SFX[bits]
    sse2op("_mm_adds_" + suffix, "sse2", "padd" + mnsuf,
           "r[k] = clamp(a[k] + b[k], %d, %d) %s" % (lo, hi, lt),
           "lanewise a + b, saturating", comm=True,
           equiv="aarch64: vqaddq_%s%d" % ("s" if s else "u", bits))
    sse2op("_mm_subs_" + suffix, "sse2", "psub" + mnsuf,
           "r[k] = clamp(a[k] - b[k], %d, %d) %s" % (lo, hi, lt),
           "lanewise a - b, saturating", equiv="aarch64: vqsubq_%s%d" % ("s" if s else "u", bits))
sse2op("_mm_mulhi_epi16", "sse2", "pmulhw", "r[k] = (a[k] * b[k]) >> 16 (i16 lanes)",
       "the high 16 bits of the lanes' signed products", comm=True)
sse2op("_mm_mulhi_epu16", "sse2", "pmulhuw", "r[k] = (a[k] * b[k]) >> 16 (u16 lanes)",
       "the high 16 bits of the lanes' unsigned products", comm=True)
sse2op("_mm_mul_epu32", "sse2", "pmuludq",
       "r[k] = (a[2 * k] as u64) * (b[2 * k] as u64) (a, b: u32 lanes; r: u64 lanes)",
       "the 64-bit products of the even unsigned 32-bit lanes", comm=True,
       equiv="aarch64: vmull_u32 of the even lanes")
sse2op("_mm_madd_epi16", "sse2", "pmaddwd",
       "r[k] = a[2 * k] * b[2 * k] + a[2 * k + 1] * b[2 * k + 1] (a, b: i16 lanes; r: i32 lanes)",
       "adjacent signed 16-bit products, summed in pairs into 32-bit lanes (wrapping)", comm=True)
sse2op("_mm_sad_epu8", "sse2", "psadbw", SAD,
       "sums of absolute byte differences, one per 8 bytes (Adler-32, Fletcher)", comm=True)
sse2op("_mm_avg_epu8", "sse2", "pavgb", "r[k] = (a[k] + b[k] + 1) >> 1 (bytes)",
       "lanewise rounded average", comm=True, equiv="aarch64: vrhaddq_u8")
sse2op("_mm_avg_epu16", "sse2", "pavgw", "r[k] = (a[k] + b[k] + 1) >> 1 (u16 lanes)",
       "lanewise rounded average", comm=True, equiv="aarch64: vrhaddq_u16")
for nm, mn, f, lt in [("_mm_min_epu8", "pminub", "min", "(bytes)"),
                      ("_mm_max_epu8", "pmaxub", "max", "(bytes)"),
                      ("_mm_min_epi16", "pminsw", "min", "(i16 lanes)"),
                      ("_mm_max_epi16", "pmaxsw", "max", "(i16 lanes)")]:
    sse2op(nm, "sse2", mn, "r[k] = %s(a[k], b[k]) %s" % (f, lt), "lanewise %simum" % f, comm=True)

# -- compare and logic, SSE2 --
family("Compare and logic (SSE2)")
for bits in (8, 16, 32):
    lt = "v%d%s" % (NLANES[bits], LANE[bits])
    for op, sym, mn in [("cmpeq", "==", "pcmpeq"), ("cmpgt", ">", "pcmpgt"), ("cmplt", "<", "pcmpgt")]:
        nm = "_mm_%s_%s" % (op, EPI[bits])
        if nm == "_mm_cmpeq_epi8":
            line(nm, "sse2", two(M), "vcmp.eq:v16i8", "pcmpeqb <b>, <d>", "pure commutative tied=a",
                 "none", "lanes.eq", "r[k] = if a[k] == b[k] { 0xff } else { 0 } (bytes)",
                 "aarch64: vceqq_u8", "bytewise a == b: a mask, each byte 0xff or 0")
            continue
        ins = "%s%s <b>, <d>" % (mn, SFX[bits]) if op != "cmplt" else "%s%s <a>, <d> (b > a)" % (mn, SFX[bits])
        line(nm, "sse2", two(M), "vcmp.%s:%s" % (op[3:], lt), ins.replace(" (b > a)", ""),
             "pure" + (" commutative" if op == "cmpeq" else ""), "none", "lanes." + op[3:],
             "r[k] = if a[k] %s b[k] { -1 } else { 0 } %s" % (sym, lanes(bits)),
             "aarch64: vc%sq_s%d" % ({"cmpeq": "eq", "cmpgt": "gt", "cmplt": "lt"}[op], bits),
             "lanewise a %s b (signed): a mask, each lane all ones or 0" % sym)
for op, sym in [("and", "&"), ("or", "|"), ("xor", "^")]:
    line("_mm_%s_si128" % op, "sse2", two(M), "vbin.%s:v16i8" % op, "p%s <b>, <d>" % op,
         "pure commutative", "none", "lanes." + op, "r[k] = a[k] %s b[k] (bytes)" % sym,
         "aarch64: v%sq_u8" % {"and": "and", "or": "orr", "xor": "eor"}[op], "bitwise a %s b" % sym)
sse2op("_mm_andnot_si128", "sse2", "pandn", "r[k] = (a[k] ^ 255) & b[k] (bytes)",
       "bitwise !a & b", equiv="aarch64: vbicq_u8(b, a)")

# -- shifts, SSE2 --
family("Shifts (SSE2)")
for bits in (16, 32, 64):
    ul = lanes(bits, False)
    il = lanes(bits)
    sx = SFX[bits]
    one = "(%s as u64)" % "imm8" if bits == 64 else "imm8"
    intr("_mm_slli_" + EPI[bits], "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
         "psll%s $<imm8>, <d>" % sx, "pure tied=a",
         "r[k] = if imm8 > %d { 0 } else { a[k] << %s } %s" % (bits - 1, one, ul),
         "each lane shifted left by imm8 (0 from %d)" % bits)
    intr("_mm_srli_" + EPI[bits], "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
         "psrl%s $<imm8>, <d>" % sx, "pure tied=a",
         "r[k] = if imm8 > %d { 0 } else { a[k] >> %s } %s" % (bits - 1, one, ul),
         "each lane shifted right by imm8, zeros in (0 from %d)" % bits)
    intr("_mm_sll_" + EPI[bits], "sse2", "(a: %s, count: %s) -> %s" % (M, M, M),
         "psll%s <count>, <d>" % sx, "pure tied=a",
         SHIFT_L % (bits - 1, "" if bits == 64 else " as i64", ULANE[bits]),
         "each lane shifted left by the count in count's low 64 bits")
    intr("_mm_srl_" + EPI[bits], "sse2", "(a: %s, count: %s) -> %s" % (M, M, M),
         "psrl%s <count>, <d>" % sx, "pure tied=a",
         SHIFT_R % (bits - 1, "" if bits == 64 else " as i64", ULANE[bits]),
         "each lane shifted right by the count in count's low 64 bits, zeros in")
    if bits != 64:
        intr("_mm_srai_" + EPI[bits], "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
             "psra%s $<imm8>, <d>" % sx, "pure tied=a",
             "r[k] = a[k] >> min(imm8, %d) %s" % (bits - 1, il),
             "each lane shifted right by imm8, copies of the sign in")
        intr("_mm_sra_" + EPI[bits], "sse2", "(a: %s, count: %s) -> %s" % (M, M, M),
             "psra%s <count>, <d>" % sx, "pure tied=a",
             SHIFT_A % (bits - 1, bits - 1, LANE[bits]),
             "each lane shifted right by the count in count's low 64 bits, the sign in")
intr("_mm_slli_si128", "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "pslldq $<imm8>, <d>", "pure tied=a",
     "r[k] = if k >= imm8 { a[k - imm8] } else { 0 } (bytes)", "a shifted left by imm8 bytes")
intr("_mm_srli_si128", "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "psrldq $<imm8>, <d>", "pure tied=a",
     "r[k] = if k + imm8 < 16 { a[k + imm8] } else { 0 } (bytes)",
     "a shifted right by imm8 bytes", equiv="aarch64: vextq_u8(a, zero, imm8)")

# -- permutes, SSE2 --
family("Permutes (SSE2)")
intr("_mm_shuffle_epi32", "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "pshufd $<imm8>, <a>, <d>", "pure", "r[k] = a[(imm8 >> (2 * k)) & 3] (i32 lanes)",
     "lane k is a's lane (imm8 >> 2k) & 3")
intr("_mm_shufflelo_epi16", "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "pshuflw $<imm8>, <a>, <d>", "pure",
     "r[k] = if k < 4 { a[(imm8 >> (2 * k)) & 3] } else { a[k] } (i16 lanes)",
     "the low four lanes shuffled by imm8, the high four kept")
intr("_mm_shufflehi_epi16", "sse2", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "pshufhw $<imm8>, <a>, <d>", "pure",
     "r[k] = if k < 4 { a[k] } else { a[4 + ((imm8 >> (2 * (k - 4))) & 3)] } (i16 lanes)",
     "the high four lanes shuffled by imm8, the low four kept")
for bits in (8, 16, 32, 64):
    n = NLANES[bits]
    sse2op("_mm_unpacklo_" + EPI[bits], "sse2", "punpckl" + {8: "bw", 16: "wd", 32: "dq", 64: "qdq"}[bits],
           "r[k] = if k %% 2 == 0 { a[k / 2] } else { b[k / 2] } %s" % lanes(bits),
           "the low halves' lanes interleaved, a's first", equiv="aarch64: vzip1q_s%d" % bits)
    sse2op("_mm_unpackhi_" + EPI[bits], "sse2", "punpckh" + {8: "bw", 16: "wd", 32: "dq", 64: "qdq"}[bits],
           "r[k] = if k %% 2 == 0 { a[%d + k / 2] } else { b[%d + k / 2] } %s" % (n // 2, n // 2, lanes(bits)),
           "the high halves' lanes interleaved, a's first", equiv="aarch64: vzip2q_s%d" % bits)
sse2op("_mm_packs_epi16", "sse2", "packsswb",
       "r[k] = if k < 8 { clamp(a[k], -128, 127) } else { clamp(b[k - 8], -128, 127) } (a, b: i16 lanes; r: i8 lanes)",
       "a's then b's lanes narrowed to 8 bits, saturating (signed)")
sse2op("_mm_packs_epi32", "sse2", "packssdw",
       "r[k] = if k < 4 { clamp(a[k], -32768, 32767) } else { clamp(b[k - 4], -32768, 32767) } (a, b: i32 lanes; r: i16 lanes)",
       "a's then b's lanes narrowed to 16 bits, saturating (signed)")
sse2op("_mm_packus_epi16", "sse2", "packuswb",
       "r[k] = if k < 8 { clamp(a[k], 0, 255) } else { clamp(b[k - 8], 0, 255) } (a, b: i16 lanes; r: u8 lanes)",
       "a's then b's lanes narrowed to 8 bits, saturating to 0..255")

# -- masks and lanes, SSE2 --
family("Masks and lanes (SSE2)")
intr("_mm_movemask_epi8", "sse2", "(a: %s) -> i32" % M, "pmovmskb <a>, <d:w>", "pure",
     "r = the top bit of each byte, byte k at bit k", "the 16 bytes' top bits as a 16-bit mask",
     fold="movemask.b", equiv="aarch64: (recipe) vshrn_n_u16(vreinterpretq_u16_u8(m), 4)")
intr("_mm_movemask_ps", "sse", "(a: __m128) -> i32", "movmskps <a>, <d:w>", "pure",
     "r = sum over k of (if a[k] < 0 { 1 << k } else { 0 }) (a: i32 lanes)", "the four lanes' sign bits")
intr("_mm_movemask_pd", "sse2", "(a: __m128d) -> i32", "movmskpd <a>, <d:w>", "pure",
     "r = sum over k of (if a[k] < 0 { 1 << k } else { 0 }) (a: i64 lanes)", "the two lanes' sign bits")
intr("_mm_extract_epi16", "sse2", "(a: %s, imm8: const 0..=7) -> i32" % M,
     "pextrw $<imm8>, <a>, <d:w>", "pure", "r = a[imm8] (u16 lanes)",
     "lane imm8, zero-extended")
intr("_mm_insert_epi16", "sse2", "(a: %s, i: i32, imm8: const 0..=7) -> %s" % (M, M),
     "pinsrw $<imm8>, <i:w>, <d>", "pure tied=a",
     "r[k] = if k == imm8 { i } else { a[k] } (u16 lanes)", "a with lane imm8 = i's low 16 bits")

# -- float, SSE and SSE2 --
family("Float arithmetic (SSE, SSE2)")
for t, lt, sfx, feat in [("__m128", "v4f32", "ps", "sse"), ("__m128d", "v2f64", "pd", "sse2")]:
    sse2op("_mm_div_" + sfx, feat, "div" + sfx, "r[k] = a[k] / b[k]", "lanewise a / b", t=t)
    for op, sym in [("add", "+"), ("sub", "-"), ("mul", "*")]:
        line("_mm_%s_%s" % (op, sfx), feat, two(t), "vbin.%s:%s" % (op, lt),
             "%s%s <b>, <d>" % (op, sfx), "pure" + (" commutative" if op in ("add", "mul") else ""),
             "none", "lanes." + op, "r[k] = a[k] %s b[k]" % sym, "-", "lanewise a %s b" % sym)
    intr("_mm_sqrt_" + sfx, feat, "(a: %s) -> %s" % (t, t), "sqrt%s <a>, <d>" % sfx, "pure",
         "r = each lane's square root (correctly rounded)", "lanewise square root")
    for op in ("min", "max"):
        cmp = "<" if op == "min" else ">"
        sse2op("_mm_%s_%s" % (op, sfx), feat, op + sfx,
               "r[k] = if a[k] %s b[k] { a[k] } else { b[k] }" % cmp,
               "lanewise %simum: b when either is NaN or both are zeros" % op, t=t)
    for op, sym in [("and", "&"), ("or", "|"), ("xor", "^")]:
        sse2op("_mm_%s_%s" % (op, sfx), feat, op + sfx, "r[k] = a[k] %s b[k] (a, b, r: bytes)" % sym,
               "bitwise a %s b" % sym, comm=True, t=t)
    sse2op("_mm_andnot_" + sfx, feat, "andn" + sfx, "r[k] = (a[k] ^ 255) & b[k] (a, b, r: bytes)",
           "bitwise !a & b", t=t)

family("Float compare (SSE, SSE2)")
for t, sfx, feat, il in [("__m128", "ps", "sse", "i32"), ("__m128d", "pd", "sse2", "i64")]:
    for op, pred, cond in [("cmpeq", 0, "a[k] == b[k]"), ("cmplt", 1, "a[k] < b[k]"),
                           ("cmple", 2, "a[k] <= b[k]"), ("cmpunord", 3, "a[k] != a[k] || b[k] != b[k]"),
                           ("cmpneq", 4, "a[k] != b[k]"), ("cmpnlt", 5, "!(a[k] < b[k])"),
                           ("cmpnle", 6, "!(a[k] <= b[k])"), ("cmpord", 7, "a[k] == a[k] && b[k] == b[k]")]:
        intr("_mm_%s_%s" % (op, sfx), feat, two(t), "cmp%s $%d, <b>, <d>" % (sfx, pred), "pure tied=a",
             "r[k] = if %s { -1 } else { 0 } (r: %s lanes)" % (cond, il),
             "lanewise compare (predicate %d): a mask, each lane all ones or 0" % pred)

family("Float conversions (SSE2)")
intr("_mm_cvtepi32_ps", "sse2", "(a: %s) -> __m128" % M, "cvtdq2ps <a>, <d>", "pure",
     "r[k] = a[k] (a: i32 lanes)", "each i32 lane as an f32 (rounded to nearest)")
intr("_mm_cvttps_epi32", "sse2", "(a: __m128) -> " + M, "cvttps2dq <a>, <d>", "pure",
     "r = each lane truncated to i32; NaN and out of range give 0x80000000 (r: i32 lanes)",
     "each lane truncated to an i32 (0x80000000 when out of range or NaN)")
intr("_mm_cvtps_epi32", "sse2", "(a: __m128) -> " + M, "cvtps2dq <a>, <d>", "pure",
     "r = each lane rounded to the nearest i32, ties to even; NaN and out of range give 0x80000000 (r: i32 lanes)",
     "each lane rounded to an i32 (to nearest even; 0x80000000 when out of range or NaN)")
intr("_mm_cvtepi32_pd", "sse2", "(a: %s) -> __m128d" % M, "cvtdq2pd <a>, <d>", "pure",
     "r[k] = a[k] (a: i32 lanes)", "the low two i32 lanes as f64s")
intr("_mm_cvtps_pd", "sse2", "(a: __m128) -> __m128d", "cvtps2pd <a>, <d>", "pure",
     "r[k] = a[k]", "the low two f32 lanes as f64s")
intr("_mm_cvtpd_ps", "sse2", "(a: __m128d) -> __m128", "cvtpd2ps <a>, <d>", "pure",
     "r[k] = if k < 2 { a[k] } else { 0.0 }", "the two f64 lanes rounded to f32s, the high two zero")

# -- SSE3 --
family("SSE3")
intr("_mm_hadd_ps", "sse3", two("__m128"), "haddps <b>, <d>", "pure tied=a",
     "r[k] = if k < 2 { a[2 * k] + a[2 * k + 1] } else { b[2 * k - 4] + b[2 * k - 3] }",
     "adjacent pairs summed: a's two sums, then b's")
intr("_mm_hadd_pd", "sse3", two("__m128d"), "haddpd <b>, <d>", "pure tied=a",
     "r[k] = if k == 0 { a[0] + a[1] } else { b[0] + b[1] }", "a's sum, then b's")
intr("_mm_hsub_ps", "sse3", two("__m128"), "hsubps <b>, <d>", "pure tied=a",
     "r[k] = if k < 2 { a[2 * k] - a[2 * k + 1] } else { b[2 * k - 4] - b[2 * k - 3] }",
     "adjacent pairs subtracted: a's two, then b's")
intr("_mm_hsub_pd", "sse3", two("__m128d"), "hsubpd <b>, <d>", "pure tied=a",
     "r[k] = if k == 0 { a[0] - a[1] } else { b[0] - b[1] }", "a's difference, then b's")
intr("_mm_addsub_ps", "sse3", two("__m128"), "addsubps <b>, <d>", "pure tied=a",
     "r[k] = if k % 2 == 0 { a[k] - b[k] } else { a[k] + b[k] }",
     "even lanes subtracted, odd lanes added")
intr("_mm_addsub_pd", "sse3", two("__m128d"), "addsubpd <b>, <d>", "pure tied=a",
     "r[k] = if k == 0 { a[0] - b[0] } else { a[1] + b[1] }", "lane 0 subtracted, lane 1 added")
intr("_mm_movehdup_ps", "sse3", "(a: __m128) -> __m128", "movshdup <a>, <d>", "pure",
     "r[k] = a[k - k % 2 + 1]", "the odd lanes, each twice")
intr("_mm_moveldup_ps", "sse3", "(a: __m128) -> __m128", "movsldup <a>, <d>", "pure",
     "r[k] = a[k - k % 2]", "the even lanes, each twice")

# -- SSSE3 --
family("SSSE3")
intr("_mm_shuffle_epi8", "ssse3", two(M), "pshufb <b>, <d>", "pure tied=a",
     "r[k] = if b[k] & 0x80 != 0 { 0 } else { a[b[k] & 15] } (bytes)",
     "a table lookup: byte k is a[b[k] & 15], 0 when b[k]'s bit 7 is set", fold="perm.pshufb",
     equiv="aarch64: vqtbl1q_u8 (zeroes when idx >= 16 instead)")
intr("_mm_alignr_epi8", "ssse3", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (M, M, M),
     "palignr $<imm8>, <b>, <d>", "pure tied=a",
     "r[k] = if k + imm8 < 16 { b[k + imm8] } else if k + imm8 < 32 { a[k + imm8 - 16] } else { 0 } (bytes)",
     "bytes imm8.. of b then a (b the low half), zeros past them", equiv="aarch64: vextq_u8(b, a, imm8)")
for bits in (8, 16, 32):
    intr("_mm_abs_" + EPI[bits], "ssse3", "(a: %s) -> %s" % (M, M), "pabs%s <a>, <d>" % SFX[bits], "pure",
         "r[k] = abs(a[k]) %s" % lanes(bits), "lanewise absolute value (MIN stays MIN)",
         equiv="aarch64: vabsq_s%d" % bits)
    intr("_mm_sign_" + EPI[bits], "ssse3", two(M), "psign%s <b>, <d>" % SFX[bits], "pure tied=a",
         "r[k] = if b[k] < 0 { -a[k] } else if b[k] == 0 { 0 } else { a[k] } %s" % lanes(bits),
         "a negated where b < 0, zeroed where b == 0")
for bits in (16, 32):
    n = NLANES[bits]
    h = n // 2
    for op, sym, mn in [("hadd", "+", "phadd"), ("hsub", "-", "phsub")]:
        intr("_mm_%s_%s" % (op, EPI[bits]), "ssse3", two(M), "%s%s <b>, <d>" % (mn, SFX[bits]), "pure tied=a",
             "r[k] = if k < %d { a[2 * k] %s a[2 * k + 1] } else { b[2 * k - %d] %s b[2 * k - %d] } %s"
             % (h, sym, n, sym, n - 1, lanes(bits)),
             "adjacent pairs %s (wrapping): a's, then b's" % ("summed" if op == "hadd" else "subtracted"))
for op, sym, mn in [("hadds", "+", "phaddsw"), ("hsubs", "-", "phsubsw")]:
    intr("_mm_%s_epi16" % op, "ssse3", two(M), "%s <b>, <d>" % mn, "pure tied=a",
         "r[k] = if k < 4 { clamp(a[2 * k] %s a[2 * k + 1], -32768, 32767) } else { clamp(b[2 * k - 8] %s b[2 * k - 7], -32768, 32767) } (i16 lanes)"
         % (sym, sym), "adjacent pairs, saturating: a's, then b's")
intr("_mm_maddubs_epi16", "ssse3", two(M), "pmaddubsw <b>, <d>", "pure tied=a",
     "r[k] = clamp(a[2 * k] * b[2 * k] + a[2 * k + 1] * b[2 * k + 1], -32768, 32767) (a: u8 lanes; b: i8 lanes; r: i16 lanes)",
     "unsigned bytes of a times signed bytes of b, adjacent pairs summed, saturating")
intr("_mm_mulhrs_epi16", "ssse3", two(M), "pmulhrsw <b>, <d>", "pure commutative tied=a",
     "r[k] = (((a[k] * b[k]) >> 14) + 1) >> 1 (i16 lanes)",
     "lanewise (a * b + 0x4000) >> 15: a rounded fixed-point product")

# -- SSE4.1 --
family("SSE4.1 blends and tests")
intr("_mm_blendv_epi8", "sse4.1", "(a: %s, b: %s, mask: %s) -> %s" % (M, M, M, M),
     "pblendvb <mask:0>, <b>, <d>", "pure tied=a",
     "r[k] = if mask[k] >= 128 { b[k] } else { a[k] } (bytes)",
     "byte k is b's where mask's byte k has its top bit set, else a's", equiv="aarch64: vbslq_u8")
intr("_mm_blendv_ps", "sse4.1", "(a: __m128, b: __m128, mask: __m128) -> __m128",
     "blendvps <mask:0>, <b>, <d>", "pure tied=a",
     "r[k] = if mask[k] < 0 { b[k] } else { a[k] } (a, b, r: u32 lanes; mask: i32 lanes)",
     "lane k is b's where mask's lane k has its sign bit set, else a's")
intr("_mm_blendv_pd", "sse4.1", "(a: __m128d, b: __m128d, mask: __m128d) -> __m128d",
     "blendvpd <mask:0>, <b>, <d>", "pure tied=a",
     "r[k] = if mask[k] < 0 { b[k] } else { a[k] } (a, b, r: u64 lanes; mask: i64 lanes)",
     "lane k is b's where mask's lane k has its sign bit set, else a's")
intr("_mm_blend_epi16", "sse4.1", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (M, M, M),
     "pblendw $<imm8>, <b>, <d>", "pure tied=a",
     "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (i16 lanes)", "lane k is b's where imm8's bit k is set")
intr("_mm_blend_ps", "sse4.1", "(a: __m128, b: __m128, imm8: const 0..=15) -> __m128",
     "blendps $<imm8>, <b>, <d>", "pure tied=a",
     "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (a, b, r: u32 lanes)", "lane k is b's where imm8's bit k is set")
intr("_mm_blend_pd", "sse4.1", "(a: __m128d, b: __m128d, imm8: const 0..=3) -> __m128d",
     "blendpd $<imm8>, <b>, <d>", "pure tied=a",
     "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (a, b, r: u64 lanes)", "lane k is b's where imm8's bit k is set")
for nm, cc, sem, doc in [("_mm_testz_si128", "sete", TESTZ, "1 when a & b is all zeros"),
                         ("_mm_testc_si128", "setb", TESTC, "1 when !a & b is all zeros"),
                         ("_mm_testnzc_si128", "seta", "r = 1 when neither a & b nor !a & b is all zeros (bytes)",
                          "1 when neither a & b nor !a & b is all zeros")]:
    intr(nm, "sse4.1", "(a: %s, b: %s) -> i32" % (M, M),
         "ptest <b>, <a>; %s <d:b>; movzbl <d:b>, <d:w>" % cc, "pure", sem, doc)

family("SSE4.1 integer")
for nm, mn, f, lt in [("_mm_min_epi8", "pminsb", "min", "(i8 lanes)"), ("_mm_max_epi8", "pmaxsb", "max", "(i8 lanes)"),
                      ("_mm_min_epu16", "pminuw", "min", "(u16 lanes)"), ("_mm_max_epu16", "pmaxuw", "max", "(u16 lanes)"),
                      ("_mm_min_epi32", "pminsd", "min", "(i32 lanes)"), ("_mm_max_epi32", "pmaxsd", "max", "(i32 lanes)"),
                      ("_mm_min_epu32", "pminud", "min", "(u32 lanes)"), ("_mm_max_epu32", "pmaxud", "max", "(u32 lanes)")]:
    sse2op(nm, "sse4.1", mn, "r[k] = %s(a[k], b[k]) %s" % (f, lt), "lanewise %simum" % f, comm=True)
sse2op("_mm_mullo_epi32", "sse4.1", "pmulld", "r[k] = a[k] * b[k] (i32 lanes)",
       "lanewise a * b, the low 32 bits", comm=True, equiv="aarch64: vmulq_s32")
sse2op("_mm_mul_epi32", "sse4.1", "pmuldq", "r[k] = a[2 * k] * b[2 * k] (a, b: i32 lanes; r: i64 lanes)",
       "the 64-bit products of the even signed 32-bit lanes", comm=True)
sse2op("_mm_cmpeq_epi64", "sse4.1", "pcmpeqq", "r[k] = if a[k] == b[k] { -1 } else { 0 } (i64 lanes)",
       "lanewise a == b: a mask", comm=True, equiv="aarch64: vceqq_u64")
sse2op("_mm_packus_epi32", "sse4.1", "packusdw",
       "r[k] = if k < 4 { clamp(a[k], 0, 65535) } else { clamp(b[k - 4], 0, 65535) } (a, b: i32 lanes; r: u16 lanes)",
       "a's then b's lanes narrowed to 16 bits, saturating to 0..65535")
intr("_mm_minpos_epu16", "sse4.1", "(a: %s) -> %s" % (M, M), "phminposuw <a>, <d>", "pure",
     "r = the least lane in lane 0, its index in lane 1, zeros above (a, r: u16 lanes)",
     "the least lane and its (first) index")

family("SSE4.1 lanes")
for bits, mn, rt in [(8, "pextrb", "i32"), (32, "pextrd", "i32"), (64, "pextrq", "i64")]:
    n = NLANES[bits]
    dst = "<d:w>" if bits != 64 else "<d>"
    intr("_mm_extract_" + EPI[bits], "sse4.1", "(a: %s, imm8: const 0..=%d) -> %s" % (M, n - 1, rt),
         "%s $<imm8>, <a>, %s" % (mn, dst), "pure", "r = a[imm8] %s" % lanes(bits, bits == 32 or bits == 64),
         "lane imm8" + (", zero-extended" if bits == 8 else ""))
for bits, mn, it in [(8, "pinsrb", "i32"), (32, "pinsrd", "i32"), (64, "pinsrq", "i64")]:
    n = NLANES[bits]
    src = "<i:w>" if bits != 64 else "<i>"
    intr("_mm_insert_" + EPI[bits], "sse4.1", "(a: %s, i: %s, imm8: const 0..=%d) -> %s" % (M, it, n - 1, M),
         "%s $<imm8>, %s, <d>" % (mn, src), "pure tied=a",
         "r[k] = if k == imm8 { i } else { a[k] } %s" % lanes(bits), "a with lane imm8 = i")
intr("_mm_extract_ps", "sse4.1", "(a: __m128, imm8: const 0..=3) -> i32", "extractps $<imm8>, <a>, <d:w>",
     "pure", "r = a[imm8] (a: i32 lanes)", "lane imm8's bits")

family("SSE4.1 widening")
for sbits, dbits in [(8, 16), (8, 32), (8, 64), (16, 32), (16, 64), (32, 64)]:
    for signed in (True, False):
        mn = "pmov%sx%s%s" % ("s" if signed else "z", SFX[sbits], SFX[dbits])
        src = (EPI if signed else EPU)[sbits]
        intr("_mm_cvt%s_%s" % (src, EPI[dbits]), "sse4.1", "(a: %s) -> %s" % (M, M), "%s <a>, <d>" % mn, "pure",
             "r[k] = a[k] (a: %s lanes; r: %s lanes)" % ((LANE if signed else ULANE)[sbits], LANE[dbits]),
             "the low lanes %s-extended to %d bits" % ("sign" if signed else "zero", dbits))

family("SSE4.1 rounding")
for t, sfx in [("__m128", "ps"), ("__m128d", "pd")]:
    intr("_mm_round_" + sfx, "sse4.1", "(a: %s, rounding: const 0..=15) -> %s" % (t, t),
         "round%s $<rounding>, <a>, <d>" % sfx, "pure",
         "r = each lane rounded to an integer by `rounding` (0 nearest even, 1 down, 2 up, 3 toward zero; 4 and up: the current mode, nearest)",
         "each lane rounded to an integral value by the mode in rounding")
    intr("_mm_floor_" + sfx, "sse4.1", "(a: %s) -> %s" % (t, t), "round%s $9, <a>, <d>" % sfx, "pure",
         "r = each lane rounded down to an integer", "each lane rounded down")
    intr("_mm_ceil_" + sfx, "sse4.1", "(a: %s) -> %s" % (t, t), "round%s $10, <a>, <d>" % sfx, "pure",
         "r = each lane rounded up to an integer", "each lane rounded up")

# -- SSE4.2 and the bit counts --
family("SSE4.2")
sse2op("_mm_cmpgt_epi64", "sse4.2", "pcmpgtq", "r[k] = if a[k] > b[k] { -1 } else { 0 } (i64 lanes)",
       "lanewise a > b (signed): a mask", equiv="aarch64: vcgtq_s64")

family("CRC-32C")
for nm, it, mn, vm, dm in [("_mm_crc32_u8", "u8", "crc32b", "<v:b>", "<d:w>"),
                           ("_mm_crc32_u16", "u16", "crc32w", "<v:h>", "<d:w>"),
                           ("_mm_crc32_u32", "u32", "crc32l", "<v:w>", "<d:w>")]:
    nb = {"u8": 1, "u16": 2, "u32": 4}[it]
    intr(nm, "sse4.2", "(crc: u32, v: %s) -> u32" % it, "%s %s, %s" % (mn, vm, dm), "pure tied=crc",
         "r = CRC-32C of crc and v's %d byte%s" % (nb, "s" if nb > 1 else ""),
         "one step of CRC-32C over %d byte%s" % (nb, "s" if nb > 1 else ""), fold="crc.c%d" % (8 * nb),
         equiv="aarch64: __crc32c%s" % {"u8": "b", "u16": "h", "u32": "w"}[it])
intr("_mm_crc32_u64", "sse4.2", "(crc: u64, v: u64) -> u64", "crc32q <v>, <d>", "pure tied=crc",
     "r = CRC-32C of crc's low 32 bits and v's 8 bytes", "one step of CRC-32C over 8 bytes",
     fold="crc.c64", equiv="aarch64: __crc32cd")

family("Bit counts (POPCNT, LZCNT, BMI1, BMI2)")
intr("_popcnt32", "popcnt", "(a: i32) -> i32", "popcntl <a:w>, <d:w>", "pure",
     "r = the number of 1 bits of a", "the number of 1 bits", fold="bits.ones", equiv="std::arch::count_ones")
intr("_popcnt64", "popcnt", "(a: i64) -> i32", "popcntq <a>, <d>", "pure",
     "r = the number of 1 bits of a", "the number of 1 bits", fold="bits.ones", equiv="std::arch::count_ones")
intr("_lzcnt_u32", "lzcnt", "(a: u32) -> u32", "lzcntl <a:w>, <d:w>", "pure",
     "r = the number of leading 0 bits of a (32 for 0)", "leading zero bits (32 for 0)", fold="bits.leading")
intr("_lzcnt_u64", "lzcnt", "(a: u64) -> u64", "lzcntq <a>, <d>", "pure",
     "r = the number of leading 0 bits of a (64 for 0)", "leading zero bits (64 for 0)", fold="bits.leading")
intr("_tzcnt_u32", "bmi1", "(a: u32) -> u32", "tzcntl <a:w>, <d:w>", "pure",
     "r = the number of trailing 0 bits of a (32 for 0)", "trailing zero bits (32 for 0)", fold="bits.trailing")
intr("_tzcnt_u64", "bmi1", "(a: u64) -> u64", "tzcntq <a>, <d>", "pure",
     "r = the number of trailing 0 bits of a (64 for 0)", "trailing zero bits (64 for 0)", fold="bits.trailing")
for bits, sfx, m, ones in [(32, "l", ":w", "0xffffffff"), (64, "q", "", "0xffffffffffffffffu64")]:
    u = "u%d" % bits
    intr("_andn_" + u, "bmi1", "(a: %s, b: %s) -> %s" % (u, u, u), "andn%s <b%s>, <a%s>, <d%s>" % (sfx, m, m, m),
         "pure", "r = (a ^ %s) & b" % ones, "!a & b")
    intr("_blsr_" + u, "bmi1", "(a: %s) -> %s" % (u, u), "blsr%s <a%s>, <d%s>" % (sfx, m, m), "pure",
         "r = a & (a - 1)", "a without its lowest set bit")
    intr("_blsi_" + u, "bmi1", "(a: %s) -> %s" % (u, u), "blsi%s <a%s>, <d%s>" % (sfx, m, m), "pure",
         "r = a & (0 - a)", "a's lowest set bit alone")
    intr("_blsmsk_" + u, "bmi1", "(a: %s) -> %s" % (u, u), "blsmsk%s <a%s>, <d%s>" % (sfx, m, m), "pure",
         "r = a ^ (a - 1)", "the bits up to a's lowest set bit")
    intr("_bextr2_" + u, "bmi1", "(a: %s, control: %s) -> %s" % (u, u, u),
         "bextr%s <control%s>, <a%s>, <d%s>" % (sfx, m, m, m), "pure",
         "r = the control >> 8 & 255 bits of a from bit control & 255, zero-extended",
         "a bit field of a: start in control's bits 0-7, length in 8-15")
    intr("_bzhi_" + u, "bmi2", "(a: %s, index: %s) -> %s" % (u, u, u),
         "bzhi%s <index%s>, <a%s>, <d%s>" % (sfx, m, m, m), "pure",
         "r = a with the bits from index & 255 up cleared", "a with the bits from index up cleared")
    intr("_pdep_" + u, "bmi2", "(a: %s, mask: %s) -> %s" % (u, u, u),
         "pdep%s <mask%s>, <a%s>, <d%s>" % (sfx, m, m, m), "pure",
         "r = a's low bits deposited at mask's set bits, in order", "parallel bit deposit")
    intr("_pext_" + u, "bmi2", "(a: %s, mask: %s) -> %s" % (u, u, u),
         "pext%s <mask%s>, <a%s>, <d%s>" % (sfx, m, m, m), "pure",
         "r = a's bits at mask's set bits, gathered into the low bits in order", "parallel bit extract")

# -- carry-less multiply, AES, SHA --
family("Carry-less multiply (PCLMULQDQ)")
intr("_mm_clmulepi64_si128", "pclmulqdq", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (M, M, M),
     "pclmulqdq $<imm8>, <b>, <d>", "pure tied=a",
     "r = the carry-less product of a's lane imm8 & 1 and b's lane (imm8 >> 4) & 1 (a, b, r: u64 lanes)",
     "the 128-bit carry-less product of a 64-bit lane of each", equiv="aarch64: vmull_p64")

family("AES")
for nm, mn, doc in [("_mm_aesenc_si128", "aesenc", "one AES encryption round: ShiftRows, SubBytes, MixColumns, then ^ round_key"),
                    ("_mm_aesenclast_si128", "aesenclast", "the last AES encryption round: ShiftRows, SubBytes, then ^ round_key"),
                    ("_mm_aesdec_si128", "aesdec", "one AES decryption round: InvShiftRows, InvSubBytes, InvMixColumns, then ^ round_key"),
                    ("_mm_aesdeclast_si128", "aesdeclast", "the last AES decryption round: InvShiftRows, InvSubBytes, then ^ round_key")]:
    intr(nm, "aes", "(a: %s, round_key: %s) -> %s" % (M, M, M), "%s <round_key>, <d>" % mn, "pure tied=a",
         "r = " + doc, doc, equiv="aarch64: vaeseq_u8 + vaesmcq_u8 (the key added first)")
intr("_mm_aesimc_si128", "aes", "(a: %s) -> %s" % (M, M), "aesimc <a>, <d>", "pure",
     "r = InvMixColumns of a", "InvMixColumns (decryption keys from encryption ones)", equiv="aarch64: vaesimcq_u8")
intr("_mm_aeskeygenassist_si128", "aes", "(a: %s, imm8: const 0..=255) -> %s" % (M, M),
     "aeskeygenassist $<imm8>, <a>, <d>", "pure",
     "r = SubWord of a's words 1 and 3, each also rotated and ^ imm8 (the key expansion's step)",
     "the AES key expansion's SubWord/RotWord step with round constant imm8")

family("SHA")
intr("_mm_sha1rnds4_epu32", "sha", "(a: %s, b: %s, func: const 0..=3) -> %s" % (M, M, M),
     "sha1rnds4 $<func>, <b>, <d>", "pure tied=a",
     "r = four SHA-1 rounds on state a (A..D) with b's message words plus E, function func (a, b, r: u32 lanes)",
     "four SHA-1 rounds", equiv="aarch64: vsha1cq_u32 / vsha1pq_u32 / vsha1mq_u32")
intr("_mm_sha1nexte_epu32", "sha", two(M), "sha1nexte <b>, <d>", "pure tied=a",
     "r = b with rol(a's lane 3, 30) added to its lane 3 (a, b, r: u32 lanes)", "the next E for SHA-1's rounds")
intr("_mm_sha1msg1_epu32", "sha", two(M), "sha1msg1 <b>, <d>", "pure tied=a",
     "r = SHA-1's first message schedule step on a and b (a, b, r: u32 lanes)", "SHA-1 message schedule, step 1",
     equiv="aarch64: vsha1su0q_u32")
intr("_mm_sha1msg2_epu32", "sha", two(M), "sha1msg2 <b>, <d>", "pure tied=a",
     "r = SHA-1's second message schedule step on a and b (a, b, r: u32 lanes)", "SHA-1 message schedule, step 2",
     equiv="aarch64: vsha1su1q_u32")
intr("_mm_sha256rnds2_epu32", "sha", "(a: %s, b: %s, wk: %s) -> %s" % (M, M, M, M),
     "sha256rnds2 <wk:0>, <b>, <d>", "pure tied=a",
     "r = two SHA-256 rounds: a the state's C D G H, b its A B E F, wk's lanes 0 and 1 the message words plus constants; the new A B E F (a, b, wk, r: u32 lanes)",
     "two SHA-256 rounds", equiv="aarch64: vsha256hq_u32 + vsha256h2q_u32")
intr("_mm_sha256msg1_epu32", "sha", two(M), "sha256msg1 <b>, <d>", "pure tied=a",
     "r = SHA-256's first message schedule step on a and b (a, b, r: u32 lanes)", "SHA-256 message schedule, step 1",
     equiv="aarch64: vsha256su0q_u32")
intr("_mm_sha256msg2_epu32", "sha", two(M), "sha256msg2 <b>, <d>", "pure tied=a",
     "r = SHA-256's second message schedule step on a and b (a, b, r: u32 lanes)", "SHA-256 message schedule, step 2",
     equiv="aarch64: vsha256su1q_u32")

# -- AVX: 256-bit float --
family("AVX float")
for t, sfx, il, ul in [("__m256", "ps", "i32", "u32"), ("__m256d", "pd", "i64", "u64")]:
    for op, sym, comm in [("add", "+", True), ("sub", "-", False), ("mul", "*", True), ("div", "/", False)]:
        avx2op("_mm256_%s_%s" % (op, sfx), "avx", op + sfx, "r[k] = a[k] %s b[k]" % sym,
               "lanewise a %s b" % sym, comm=comm, t=t)
    for op in ("min", "max"):
        cmp = "<" if op == "min" else ">"
        avx2op("_mm256_%s_%s" % (op, sfx), "avx", op + sfx, "r[k] = if a[k] %s b[k] { a[k] } else { b[k] }" % cmp,
               "lanewise %simum: b when either is NaN or both are zeros" % op, t=t)
    for op, sym in [("and", "&"), ("or", "|"), ("xor", "^")]:
        avx2op("_mm256_%s_%s" % (op, sfx), "avx", op + sfx, "r[k] = a[k] %s b[k] (a, b, r: bytes)" % sym,
               "bitwise a %s b" % sym, comm=True, t=t)
    avx2op("_mm256_andnot_" + sfx, "avx", "andn" + sfx, "r[k] = (a[k] ^ 255) & b[k] (a, b, r: bytes)",
           "bitwise !a & b", t=t)
    intr("_mm256_sqrt_" + sfx, "avx", "(a: %s) -> %s" % (t, t), "vsqrt%s <a:y>, <d:y>" % sfx, "pure",
         "r = each lane's square root (correctly rounded)", "lanewise square root")
    intr("_mm256_cmp_" + sfx, "avx", "(a: %s, b: %s, imm8: const 0..=31) -> %s" % (t, t, t),
         "vcmp%s $<imm8>, <b:y>, <a:y>, <d:y>" % sfx, "pure",
         "r = each lane compared by predicate imm8 (Intel's _CMP_*): a mask, each lane all ones or 0 (r: %s lanes)" % il,
         "lanewise compare by predicate imm8 (_CMP_EQ_OQ = 0 ... _CMP_TRUE_US = 31)")
    intr("_mm256_blendv_" + sfx, "avx", "(a: %s, b: %s, mask: %s) -> %s" % (t, t, t, t),
         "vblendv%s <mask:y>, <b:y>, <a:y>, <d:y>" % sfx, "pure",
         "r[k] = if mask[k] < 0 { b[k] } else { a[k] } (a, b, r: %s lanes; mask: %s lanes)" % (ul, il),
         "lane k is b's where mask's lane k has its sign bit set, else a's")
    intr("_mm256_movemask_" + sfx, "avx", "(a: %s) -> i32" % t, "vmovmsk%s <a:y>, <d:w>" % sfx, "pure",
         "r = sum over k of (if a[k] < 0 { 1 << k } else { 0 }) (a: %s lanes)" % il, "the lanes' sign bits")
    intr("_mm256_blend_" + sfx, "avx", "(a: %s, b: %s, imm8: const 0..=%d) -> %s" % (t, t, 255 if sfx == "ps" else 15, t),
         "vblend%s $<imm8>, <b:y>, <a:y>, <d:y>" % sfx, "pure",
         "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (a, b, r: %s lanes)" % ul,
         "lane k is b's where imm8's bit k is set")

family("AVX lanes and tests")
for t, sfx, mn in [(Y, "si256", "vextractf128"), ("__m256", "ps", "vextractf128"), ("__m256d", "pd", "vextractf128")]:
    half = {"si256": M, "ps": "__m128", "pd": "__m128d"}[sfx]
    intr("_mm256_extractf128_" + sfx, "avx", "(a: %s, imm8: const 0..=1) -> %s" % (t, half),
         "vextractf128 $<imm8>, <a:y>, <d>", "pure",
         "r[k] = a[16 * imm8 + k] (a, r: bytes)", "the 128-bit half imm8 (0 low, 1 high)")
    intr("_mm256_insertf128_" + sfx, "avx", "(a: %s, b: %s, imm8: const 0..=1) -> %s" % (t, half, t),
         "vinsertf128 $<imm8>, <b>, <a:y>, <d:y>", "pure",
         "r[k] = if k / 16 == imm8 { b[k % 16] } else { a[k] } (a, b, r: bytes)",
         "a with its 128-bit half imm8 replaced by b")
    intr("_mm256_permute2f128_" + sfx, "avx", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (t, t, t),
         "vperm2f128 $<imm8>, <b:y>, <a:y>, <d:y>", "pure",
         PERM2, 
         "each half from a or b by imm8 (bits 0-1 low, 4-5 high; bits 3, 7: zero)")
intr("_mm256_testz_si256", "avx", "(a: %s, b: %s) -> i32" % (Y, Y),
     "vptest <b:y>, <a:y>; sete <d:b>; movzbl <d:b>, <d:w>", "pure",
     TESTZ, "1 when a & b is all zeros")
intr("_mm256_testc_si256", "avx", "(a: %s, b: %s) -> i32" % (Y, Y),
     "vptest <b:y>, <a:y>; setb <d:b>; movzbl <d:b>, <d:w>", "pure",
     TESTC, "1 when !a & b is all zeros")

# -- AVX2: 256-bit integer --
def lane16(expr):
    """`k` as the index inside its 128-bit lane: a 256-bit semantics made of a
    128-bit one, per lane (the AVX2 shuffles, unpacks, packs and alignr work
    on each 128-bit lane alone)."""
    return expr


family("AVX2 integer arithmetic")
for bits in (8, 16, 32, 64):
    for op, sym, mn, comm in [("add", "+", "padd", True), ("sub", "-", "psub", False)]:
        avx2op("_mm256_%s_%s" % (op, EPI[bits]), "avx2", mn + SFX[bits],
               "r[k] = a[k] %s b[k] %s" % (sym, lanes(bits)), "lanewise a %s b, wrapping" % sym, comm=comm)
for bits, s in [(8, True), (16, True), (8, False), (16, False)]:
    lo, hi = (-(1 << (bits - 1)), (1 << (bits - 1)) - 1) if s else (0, (1 << bits) - 1)
    suffix = (EPI if s else EPU)[bits]
    mnsuf = ("s" if s else "us") + SFX[bits]
    avx2op("_mm256_adds_" + suffix, "avx2", "padd" + mnsuf,
           "r[k] = clamp(a[k] + b[k], %d, %d) %s" % (lo, hi, lanes(bits, s)), "lanewise a + b, saturating", comm=True)
    avx2op("_mm256_subs_" + suffix, "avx2", "psub" + mnsuf,
           "r[k] = clamp(a[k] - b[k], %d, %d) %s" % (lo, hi, lanes(bits, s)), "lanewise a - b, saturating")
avx2op("_mm256_mullo_epi16", "avx2", "pmullw", "r[k] = a[k] * b[k] (i16 lanes)", "lanewise a * b, the low 16 bits", comm=True)
avx2op("_mm256_mullo_epi32", "avx2", "pmulld", "r[k] = a[k] * b[k] (i32 lanes)", "lanewise a * b, the low 32 bits", comm=True)
avx2op("_mm256_mulhi_epi16", "avx2", "pmulhw", "r[k] = (a[k] * b[k]) >> 16 (i16 lanes)",
       "the high 16 bits of the signed products", comm=True)
avx2op("_mm256_mulhi_epu16", "avx2", "pmulhuw", "r[k] = (a[k] * b[k]) >> 16 (u16 lanes)",
       "the high 16 bits of the unsigned products", comm=True)
avx2op("_mm256_mul_epu32", "avx2", "pmuludq",
       "r[k] = (a[2 * k] as u64) * (b[2 * k] as u64) (a, b: u32 lanes; r: u64 lanes)",
       "the 64-bit products of the even unsigned 32-bit lanes", comm=True)
avx2op("_mm256_mul_epi32", "avx2", "pmuldq", "r[k] = a[2 * k] * b[2 * k] (a, b: i32 lanes; r: i64 lanes)",
       "the 64-bit products of the even signed 32-bit lanes", comm=True)
avx2op("_mm256_madd_epi16", "avx2", "pmaddwd",
       "r[k] = a[2 * k] * b[2 * k] + a[2 * k + 1] * b[2 * k + 1] (a, b: i16 lanes; r: i32 lanes)",
       "adjacent signed 16-bit products, summed in pairs (wrapping)", comm=True)
avx2op("_mm256_maddubs_epi16", "avx2", "pmaddubsw",
       "r[k] = clamp(a[2 * k] * b[2 * k] + a[2 * k + 1] * b[2 * k + 1], -32768, 32767) (a: u8 lanes; b: i8 lanes; r: i16 lanes)",
       "unsigned bytes of a times signed bytes of b, adjacent pairs summed, saturating")
avx2op("_mm256_mulhrs_epi16", "avx2", "pmulhrsw", "r[k] = (((a[k] * b[k]) >> 14) + 1) >> 1 (i16 lanes)",
       "lanewise rounded fixed-point product", comm=True)
avx2op("_mm256_sad_epu8", "avx2", "psadbw", SAD,
       "sums of absolute byte differences, one per 8 bytes", comm=True)
avx2op("_mm256_avg_epu8", "avx2", "pavgb", "r[k] = (a[k] + b[k] + 1) >> 1 (bytes)", "lanewise rounded average", comm=True)
avx2op("_mm256_avg_epu16", "avx2", "pavgw", "r[k] = (a[k] + b[k] + 1) >> 1 (u16 lanes)", "lanewise rounded average", comm=True)

family("AVX2 min, max, abs, sign")
for nm, mn, f, lt in [("epu8", "pminub", "min", "(bytes)"), ("epu8", "pmaxub", "max", "(bytes)"),
                      ("epi8", "pminsb", "min", "(i8 lanes)"), ("epi8", "pmaxsb", "max", "(i8 lanes)"),
                      ("epi16", "pminsw", "min", "(i16 lanes)"), ("epi16", "pmaxsw", "max", "(i16 lanes)"),
                      ("epu16", "pminuw", "min", "(u16 lanes)"), ("epu16", "pmaxuw", "max", "(u16 lanes)"),
                      ("epi32", "pminsd", "min", "(i32 lanes)"), ("epi32", "pmaxsd", "max", "(i32 lanes)"),
                      ("epu32", "pminud", "min", "(u32 lanes)"), ("epu32", "pmaxud", "max", "(u32 lanes)")]:
    avx2op("_mm256_%s_%s" % (f, nm), "avx2", mn, "r[k] = %s(a[k], b[k]) %s" % (f, lt), "lanewise %simum" % f, comm=True)
for bits in (8, 16, 32):
    intr("_mm256_abs_" + EPI[bits], "avx2", "(a: %s) -> %s" % (Y, Y), "vpabs%s <a:y>, <d:y>" % SFX[bits], "pure",
         "r[k] = abs(a[k]) %s" % lanes(bits), "lanewise absolute value (MIN stays MIN)")
    avx2op("_mm256_sign_" + EPI[bits], "avx2", "psign" + SFX[bits],
           "r[k] = if b[k] < 0 { -a[k] } else if b[k] == 0 { 0 } else { a[k] } %s" % lanes(bits),
           "a negated where b < 0, zeroed where b == 0")

family("AVX2 compare and logic")
for bits in (8, 16, 32, 64):
    avx2op("_mm256_cmpeq_" + EPI[bits], "avx2", "pcmpeq" + SFX[bits],
           "r[k] = if a[k] == b[k] { -1 } else { 0 } %s" % lanes(bits), "lanewise a == b: a mask", comm=True,
           equiv="x86_64: _mm_cmpeq_%s, twice" % EPI[bits])
    avx2op("_mm256_cmpgt_" + EPI[bits], "avx2", "pcmpgt" + SFX[bits],
           "r[k] = if a[k] > b[k] { -1 } else { 0 } %s" % lanes(bits), "lanewise a > b (signed): a mask")
for op, sym in [("and", "&"), ("or", "|"), ("xor", "^")]:
    avx2op("_mm256_%s_si256" % op, "avx2", "p" + op, "r[k] = a[k] %s b[k] (bytes)" % sym, "bitwise a %s b" % sym, comm=True)
avx2op("_mm256_andnot_si256", "avx2", "pandn", "r[k] = (a[k] ^ 255) & b[k] (bytes)", "bitwise !a & b")
intr("_mm256_movemask_epi8", "avx2", "(a: %s) -> i32" % Y, "vpmovmskb <a:y>, <d:w>", "pure",
     "r = sum over k of (if a[k] >= 128 { 1 << k } else { 0 }) (bytes)", "the 32 bytes' top bits as a 32-bit mask",
     fold="movemask.b", equiv="x86_64: _mm_movemask_epi8, twice")
intr("_mm256_blendv_epi8", "avx2", "(a: %s, b: %s, mask: %s) -> %s" % (Y, Y, Y, Y),
     "vpblendvb <mask:y>, <b:y>, <a:y>, <d:y>", "pure",
     "r[k] = if mask[k] >= 128 { b[k] } else { a[k] } (bytes)", "byte k is b's where mask's byte k has its top bit set")
intr("_mm256_blend_epi16", "avx2", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (Y, Y, Y),
     "vpblendw $<imm8>, <b:y>, <a:y>, <d:y>", "pure",
     "r[k] = if (imm8 >> (k % 8)) & 1 != 0 { b[k] } else { a[k] } (i16 lanes)",
     "lane k is b's where imm8's bit k % 8 is set (the same 8 bits for each 128-bit half)")
intr("_mm256_blend_epi32", "avx2", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (Y, Y, Y),
     "vpblendd $<imm8>, <b:y>, <a:y>, <d:y>", "pure",
     "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (i32 lanes)", "lane k is b's where imm8's bit k is set")
intr("_mm_blend_epi32", "avx2", "(a: %s, b: %s, imm8: const 0..=15) -> %s" % (M, M, M),
     "vpblendd $<imm8>, <b>, <a>, <d>", "pure",
     "r[k] = if (imm8 >> k) & 1 != 0 { b[k] } else { a[k] } (i32 lanes)", "lane k is b's where imm8's bit k is set")

family("AVX2 shifts")
for bits in (16, 32, 64):
    sx = SFX[bits]
    one = "(imm8 as u64)" if bits == 64 else "imm8"
    intr("_mm256_slli_" + EPI[bits], "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
         "vpsll%s $<imm8>, <a:y>, <d:y>" % sx, "pure",
         "r[k] = if imm8 > %d { 0 } else { a[k] << %s } %s" % (bits - 1, one, lanes(bits, False)),
         "each lane shifted left by imm8")
    intr("_mm256_srli_" + EPI[bits], "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
         "vpsrl%s $<imm8>, <a:y>, <d:y>" % sx, "pure",
         "r[k] = if imm8 > %d { 0 } else { a[k] >> %s } %s" % (bits - 1, one, lanes(bits, False)),
         "each lane shifted right by imm8, zeros in")
    intr("_mm256_sll_" + EPI[bits], "avx2", "(a: %s, count: %s) -> %s" % (Y, M, Y),
         "vpsll%s <count>, <a:y>, <d:y>" % sx, "pure",
         SHIFT_L % (bits - 1, "" if bits == 64 else " as i64", ULANE[bits]),
         "each lane shifted left by count's low 64 bits")
    intr("_mm256_srl_" + EPI[bits], "avx2", "(a: %s, count: %s) -> %s" % (Y, M, Y),
         "vpsrl%s <count>, <a:y>, <d:y>" % sx, "pure",
         SHIFT_R % (bits - 1, "" if bits == 64 else " as i64", ULANE[bits]),
         "each lane shifted right by count's low 64 bits, zeros in")
    if bits != 64:
        intr("_mm256_srai_" + EPI[bits], "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
             "vpsra%s $<imm8>, <a:y>, <d:y>" % sx, "pure",
             "r[k] = a[k] >> min(imm8, %d) %s" % (bits - 1, lanes(bits)), "each lane shifted right by imm8, the sign in")
        intr("_mm256_sra_" + EPI[bits], "avx2", "(a: %s, count: %s) -> %s" % (Y, M, Y),
             "vpsra%s <count>, <a:y>, <d:y>" % sx, "pure",
             SHIFT_A % (bits - 1, bits - 1, LANE[bits]),
             "each lane shifted right by count's low 64 bits, the sign in")
for bits in (32, 64):
    for t, n, ym in [(M, NLANES[bits], ""), (Y, 2 * NLANES[bits], ":y")]:
        p = "_mm_" if t == M else "_mm256_"
        cnt = "(b[k] as u64)" if bits == 64 else "b[k]"
        intr(p + "sllv_" + EPI[bits], "avx2", two(t), "vpsllv%s <b%s>, <a%s>, <d%s>" % (SFX[bits], ym, ym, ym), "pure",
             "r[k] = if b[k] > %d { 0 } else { a[k] << %s } %s" % (bits - 1, cnt, lanes(bits, False)),
             "each lane shifted left by b's lane (0 from %d)" % bits)
        intr(p + "srlv_" + EPI[bits], "avx2", two(t), "vpsrlv%s <b%s>, <a%s>, <d%s>" % (SFX[bits], ym, ym, ym), "pure",
             "r[k] = if b[k] > %d { 0 } else { a[k] >> %s } %s" % (bits - 1, cnt, lanes(bits, False)),
             "each lane shifted right by b's lane, zeros in (0 from %d)" % bits)
    if bits == 32:
        for t, ym in [(M, ""), (Y, ":y")]:
            p = "_mm_" if t == M else "_mm256_"
            intr(p + "srav_epi32", "avx2", two(t), "vpsravd <b%s>, <a%s>, <d%s>" % (ym, ym, ym), "pure",
                 "r[k] = a[k] >> min(b[k], 31) (a, r: i32 lanes; b: u32 lanes)",
                 "each lane shifted right by b's lane, the sign in")
intr("_mm256_slli_si256", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpslldq $<imm8>, <a:y>, <d:y>", "pure",
     "r[k] = if k % 16 >= imm8 { a[k - imm8] } else { 0 } (bytes)",
     "each 128-bit half shifted left by imm8 bytes")
intr("_mm256_srli_si256", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpsrldq $<imm8>, <a:y>, <d:y>", "pure",
     "r[k] = if k % 16 + imm8 < 16 { a[k + imm8] } else { 0 } (bytes)",
     "each 128-bit half shifted right by imm8 bytes")

family("AVX2 shuffles within 128-bit halves")
intr("_mm256_shuffle_epi8", "avx2", two(Y), "vpshufb <b:y>, <a:y>, <d:y>", "pure",
     "r[k] = if b[k] & 0x80 != 0 { 0 } else { a[k - k % 16 + (b[k] & 15)] } (bytes)",
     "a table lookup in each 128-bit half: byte k is its half's a[b[k] & 15], 0 when b[k]'s bit 7 is set",
     fold="perm.pshufb")
intr("_mm256_alignr_epi8", "avx2", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (Y, Y, Y),
     "vpalignr $<imm8>, <b:y>, <a:y>, <d:y>", "pure",
     "r[k] = if k % 16 + imm8 < 16 { b[k + imm8] } else if k % 16 + imm8 < 32 { a[k + imm8 - 16] } else { 0 } (bytes)",
     "in each 128-bit half, bytes imm8.. of b's half then a's")
intr("_mm256_shuffle_epi32", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpshufd $<imm8>, <a:y>, <d:y>", "pure",
     "r[k] = a[k - k % 4 + ((imm8 >> (2 * (k % 4))) & 3)] (i32 lanes)", "each 128-bit half's lanes shuffled by imm8")
intr("_mm256_shufflelo_epi16", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpshuflw $<imm8>, <a:y>, <d:y>", "pure",
     "r[k] = if k % 8 < 4 { a[k - k % 8 + ((imm8 >> (2 * (k % 8))) & 3)] } else { a[k] } (i16 lanes)",
     "each half's low four lanes shuffled by imm8")
intr("_mm256_shufflehi_epi16", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpshufhw $<imm8>, <a:y>, <d:y>", "pure",
     "r[k] = if k % 8 < 4 { a[k] } else { a[k - k % 8 + 4 + ((imm8 >> (2 * (k % 8 - 4))) & 3)] } (i16 lanes)",
     "each half's high four lanes shuffled by imm8")
for bits in (8, 16, 32, 64):
    n = NLANES[bits]
    sfx = {8: "bw", 16: "wd", 32: "dq", 64: "qdq"}[bits]
    avx2op("_mm256_unpacklo_" + EPI[bits], "avx2", "punpckl" + sfx,
           "r[k] = if k %% 2 == 0 { a[k - k %% %d + (k %% %d) / 2] } else { b[k - k %% %d + (k %% %d) / 2] } %s"
           % (n, n, n, n, lanes(bits)), "each half's low lanes interleaved, a's first")
    avx2op("_mm256_unpackhi_" + EPI[bits], "avx2", "punpckh" + sfx,
           "r[k] = if k %% 2 == 0 { a[k - k %% %d + %d + (k %% %d) / 2] } else { b[k - k %% %d + %d + (k %% %d) / 2] } %s"
           % (n, n // 2, n, n, n // 2, n, lanes(bits)), "each half's high lanes interleaved, a's first")
avx2op("_mm256_packs_epi16", "avx2", "packsswb",
       "r[k] = if k % 16 < 8 { clamp(a[k / 16 * 8 + k % 16], -128, 127) } else { clamp(b[k / 16 * 8 + k % 16 - 8], -128, 127) } (a, b: i16 lanes; r: i8 lanes)",
       "per 128-bit half: a's then b's lanes narrowed to 8 bits, saturating")
avx2op("_mm256_packs_epi32", "avx2", "packssdw",
       "r[k] = if k % 8 < 4 { clamp(a[k / 8 * 4 + k % 8], -32768, 32767) } else { clamp(b[k / 8 * 4 + k % 8 - 4], -32768, 32767) } (a, b: i32 lanes; r: i16 lanes)",
       "per 128-bit half: a's then b's lanes narrowed to 16 bits, saturating")
avx2op("_mm256_packus_epi16", "avx2", "packuswb",
       "r[k] = if k % 16 < 8 { clamp(a[k / 16 * 8 + k % 16], 0, 255) } else { clamp(b[k / 16 * 8 + k % 16 - 8], 0, 255) } (a, b: i16 lanes; r: u8 lanes)",
       "per 128-bit half: a's then b's lanes narrowed to 8 bits, saturating to 0..255")
avx2op("_mm256_packus_epi32", "avx2", "packusdw",
       "r[k] = if k % 8 < 4 { clamp(a[k / 8 * 4 + k % 8], 0, 65535) } else { clamp(b[k / 8 * 4 + k % 8 - 4], 0, 65535) } (a, b: i32 lanes; r: u16 lanes)",
       "per 128-bit half: a's then b's lanes narrowed to 16 bits, saturating to 0..65535")
for bits in (16, 32):
    n = NLANES[bits]
    h = n // 2
    for op, sym, mn in [("hadd", "+", "phadd"), ("hsub", "-", "phsub")]:
        avx2op("_mm256_%s_%s" % (op, EPI[bits]), "avx2", mn + SFX[bits],
               "r[k] = if k %% %d < %d { a[k - k %% %d + 2 * (k %% %d)] %s a[k - k %% %d + 2 * (k %% %d) + 1] } else { b[k - k %% %d + 2 * (k %% %d) - %d] %s b[k - k %% %d + 2 * (k %% %d) - %d] } %s"
               % (n, h, n, n, sym, n, n, n, n, n, sym, n, n, n - 1, lanes(bits)),
               "per 128-bit half: adjacent pairs, a's then b's (wrapping)")

family("AVX2 across halves")
intr("_mm256_permute4x64_epi64", "avx2", "(a: %s, imm8: const 0..=255) -> %s" % (Y, Y),
     "vpermq $<imm8>, <a:y>, <d:y>", "pure", "r[k] = a[(imm8 >> (2 * k)) & 3] (i64 lanes)",
     "lane k is a's lane (imm8 >> 2k) & 3")
intr("_mm256_permutevar8x32_epi32", "avx2", "(a: %s, idx: %s) -> %s" % (Y, Y, Y),
     "vpermd <a:y>, <idx:y>, <d:y>", "pure", "r[k] = a[idx[k] & 7] (i32 lanes)",
     "lane k is a's lane idx[k] & 7")
intr("_mm256_permute2x128_si256", "avx2", "(a: %s, b: %s, imm8: const 0..=255) -> %s" % (Y, Y, Y),
     "vperm2i128 $<imm8>, <b:y>, <a:y>, <d:y>", "pure",
     PERM2,
     "each half from a or b by imm8 (bits 0-1 low, 4-5 high; bits 3, 7: zero)")
intr("_mm256_extracti128_si256", "avx2", "(a: %s, imm8: const 0..=1) -> %s" % (Y, M),
     "vextracti128 $<imm8>, <a:y>, <d>", "pure", "r[k] = a[16 * imm8 + k] (bytes)",
     "the 128-bit half imm8 (0 low, 1 high)")
intr("_mm256_inserti128_si256", "avx2", "(a: %s, b: %s, imm8: const 0..=1) -> %s" % (Y, M, Y),
     "vinserti128 $<imm8>, <b>, <a:y>, <d:y>", "pure",
     "r[k] = if k / 16 == imm8 { b[k % 16] } else { a[k] } (bytes)", "a with its 128-bit half imm8 replaced by b")
for bits, mn in [(8, "vpbroadcastb"), (16, "vpbroadcastw"), (32, "vpbroadcastd"), (64, "vpbroadcastq")]:
    for t, ym, p in [(M, "", "_mm_"), (Y, ":y", "_mm256_")]:
        intr("%sbroadcast%s_%s" % (p, SFX[bits], EPI[bits]), "avx2", "(a: %s) -> %s" % (M, t),
             "%s <a>, <d%s>" % (mn, ym), "pure", "r[k] = a[0] %s" % lanes(bits), "a's lane 0 in every lane")
intr("_mm256_broadcastsi128_si256", "avx2", "(a: %s) -> %s" % (M, Y),
     "vinserti128 $1, <a>, <a:y>, <d:y>", "pure", "r[k] = a[k % 16] (bytes)", "a in both halves")
for sbits, dbits in [(8, 16), (8, 32), (8, 64), (16, 32), (16, 64), (32, 64)]:
    for signed in (True, False):
        mn = "vpmov%sx%s%s" % ("s" if signed else "z", SFX[sbits], SFX[dbits])
        src = (EPI if signed else EPU)[sbits]
        intr("_mm256_cvt%s_%s" % (src, EPI[dbits]), "avx2", "(a: %s) -> %s" % (M, Y), "%s <a>, <d:y>" % mn, "pure",
             "r[k] = a[k] (a: %s lanes; r: %s lanes)" % ((LANE if signed else ULANE)[sbits], LANE[dbits]),
             "a's low lanes %s-extended to %d bits" % ("sign" if signed else "zero", dbits))

family("FMA")
for t, sfx, ym, p in [("__m128", "ps", "", "_mm_"), ("__m128d", "pd", "", "_mm_"),
                      ("__m256", "ps", ":y", "_mm256_"), ("__m256d", "pd", ":y", "_mm256_")]:
    for op, sem in [("fmadd", "a[k] * b[k] + c[k]"), ("fmsub", "a[k] * b[k] - c[k]"),
                    ("fnmadd", "c[k] - a[k] * b[k]"), ("fnmsub", "0.0 - a[k] * b[k] - c[k]")]:
        intr("%s%s_%s" % (p, op, sfx), "fma", "(a: %s, b: %s, c: %s) -> %s" % (t, t, t, t),
             "v%s213%s <c%s>, <b%s>, <d%s>" % (op, sfx, ym, ym, ym), "pure tied=a",
             "r[k] = %s" % sem, "lanewise %s, rounded once (fused)" % sem.replace("[k]", ""))


def enc_corpus():
    """Every instruction of INSNS with low and high registers, both widths
    and memory operands, AT&T syntax."""
    mems = ["(%rax)", "8(%rsp)", "-200(%rbp)", "(%r12)", "0x40(%r13)", "(%rax,%r9,8)",
            "16(%r15,%rcx,2)", "-4(%rdx,%r14,4)"]
    lo = [1, 6, 3, 0, 7, 2]
    hi = [9, 14, 12, 8, 15, 11]
    g32 = ["eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi", "r8d", "r9d", "r10d", "r11d",
           "r12d", "r13d", "r14d", "r15d"]
    g64 = ["rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi", "r8", "r9", "r10", "r11",
           "r12", "r13", "r14", "r15"]
    g16 = ["ax", "cx", "dx", "bx", "sp", "bp", "si", "di", "r8w", "r9w", "r10w", "r11w",
           "r12w", "r13w", "r14w", "r15w"]
    g8 = ["al", "cl", "dl", "bl", "spl", "bpl", "sil", "dil", "r8b", "r9b", "r10b", "r11b",
          "r12b", "r13b", "r14b", "r15b"]
    imms = ["$0", "$1", "$0x7f", "$0x80", "$0xff", "$3"]
    # (no comments: the compiler's assembler reads instructions only; the
    # file is generated by this script, tests/arch/enc.sh says so)
    out = ["    .text"]

    def reg(kind, n, width):
        if kind in "xX":
            return "%%xmm%d" % n
        if kind in "yY":
            return "%%ymm%d" % n
        if kind in "vV":
            return "%%%smm%d" % ("y" if width == 256 else "x", n)
        if kind in "gG":
            return "%" + g32[n]
        if kind in "qQ":
            return "%" + g64[n]
        if kind == "h":
            return "%" + g16[n]
        if kind == "b":
            return "%" + g8[n]
        raise ValueError(kind)

    count = 0
    for mn, cls, pfx, mp, op, flags, shapes in INSNS + [
            ("vmovdqu", "", "", "", "", "", ["Y y", "y Y", "V v", "v V"]),
            ("vmovdqa", "", "", "", "", "", ["Y y", "y Y", "V v", "v V"]),
            ("pslld", "", "", "", "", "", ["i x", "X x"]),
            ("psllq", "", "", "", "", "", ["i x", "X x"])]:
        for shape in shapes:
            kinds = shape.split()
            widths = [128, 256] if any(k in "vV" for k in kinds) else [0]
            for width in widths:
                regpos = [i for i, k in enumerate(kinds) if k not in "i0"]
                # every low/high assignment of the register operands
                for mask in range(1 << len(regpos)):
                    ops = []
                    for i, k in enumerate(kinds):
                        if k == "i":
                            ops.append(imms[(mask + count) % len(imms)])
                        elif k == "0":
                            ops.append("%xmm0")
                        else:
                            j = regpos.index(i)
                            high = (mask >> j) & 1
                            n = (hi if high else lo)[(mask + j + count) % 6]
                            if k in "gGqQhb" and n == 4 and False:
                                n = 5
                            ops.append(reg(k, n, width))
                    out.append("    %s %s" % (mn, ", ".join(ops)))
                    count += 1
                # each memory form for the operand that may be memory
                for i, k in enumerate(kinds):
                    if k in "XYVGQhb":
                        for mi, m in enumerate(mems):
                            ops = []
                            for i2, k2 in enumerate(kinds):
                                if i2 == i:
                                    ops.append(m)
                                elif k2 == "i":
                                    ops.append(imms[(mi + count) % len(imms)])
                                elif k2 == "0":
                                    ops.append("%xmm0")
                                else:
                                    n = (hi if (mi + i2) % 2 else lo)[(mi + i2) % 6]
                                    ops.append(reg(k2, n, width))
                            out.append("    %s %s" % (mn, ", ".join(ops)))
                            count += 1
                        break
    out.append("    vzeroupper")
    return "\n".join(out) + "\n"


def insn_lines():
    out = []
    for mn, cls, pfx, mp, op, flags, shapes in INSNS:
        out.append(" | ".join([mn, cls, pfx or "-", mp, op, flags]))
    return "\n".join(out) + "\n"


MARK = "# ==== generated by tools/arch/x86_families.py (edit the script, then --write) ===="
END = "# ==== end of the generated lines ===="


def splice(path, text):
    with open(path) as f:
        old = f.read()
    if MARK in old:
        head = old[:old.index(MARK)]
        tail = old[old.index(END) + len(END):]
    else:
        head = old.rstrip("\n") + "\n\n"
        tail = "\n"
    with open(path, "w") as f:
        f.write(head + MARK + "\n" + text.strip("\n") + "\n" + END + tail)


def main():
    args = sys.argv[1:]
    defs = "\n".join(OUT).strip("\n") + "\n"
    if "--write" in args:
        splice(os.path.join(ROOT, "compiler/arch/x86_64.def"), defs)
        splice(os.path.join(ROOT, "compiler/arch/insn_x86.def"), insn_lines())
        with open(os.path.join(ROOT, "tests/arch/enc_x86.s"), "w") as f:
            f.write(enc_corpus())
        names = [l.split(" | ")[0] for l in OUT if l and not l.startswith("#")]
        dup = sorted(set(n for n in names if names.count(n) > 1))
        if dup:
            sys.exit("duplicate intrinsics: " + " ".join(dup))
        print("x86_64.def: %d intrinsics; insn_x86.def: %d instructions" % (len(names), len(INSNS)))
        return
    if "--insn" in args:
        sys.stdout.write(insn_lines())
    elif "--enc" in args:
        sys.stdout.write(enc_corpus())
    else:
        sys.stdout.write(defs)


main()
