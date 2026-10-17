#!/usr/bin/env python3
"""The regular families of std::arch::aarch64 (0.19, docs/design/arch.md
section 2.3.1), written as lines of compiler/arch/aarch64.def and
compiler/arch/insn_a64.def.

compiler/arch/aarch64.def stays the source of truth: this script makes the
lines of the families whose instances differ only by type and arrangement
(one entry per family below), so that a family is added, or a column of
it changed, in one place. compiler/arch/README.md gives the columns.

usage: tools/arch/a64_families.py [--insn] [--write]

  (no option)  print aarch64.def's generated sections on stdout
  --insn       print insn_a64.def instead
  --write      rewrite both files (the generated sections, between the
               `# ==== generated` markers; the rest is kept), then run
               compiler/arch/embed.sh yourself

Semantics are written in the expression language tests/arch/gen.sh
translates (a lane `k`, the parameters' lanes, max min abs clamp, `if`,
`as`); a family that needs more names a hand reference, `fn ref_NAME`
in tests/arch/ref/a64_*.tach, and its semantics column is prose.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))

# ---- Types ----

# ACLE's lane suffixes: (bits, kind): s signed, u unsigned, f float, p poly.
LANES = {
    "s8": (8, "s"), "u8": (8, "u"), "s16": (16, "s"), "u16": (16, "u"),
    "s32": (32, "s"), "u32": (32, "u"), "s64": (64, "s"), "u64": (64, "u"),
    "f32": (32, "f"), "f64": (64, "f"), "p8": (8, "p"), "p16": (16, "p"), "p64": (64, "p"),
}
I = ["s8", "u8", "s16", "u16", "s32", "u32", "s64", "u64"]
I6 = ["s8", "u8", "s16", "u16", "s32", "u32"]
S6 = ["s8", "s16", "s32"]
SI = ["s8", "s16", "s32", "s64"]
F = ["f32", "f64"]
A = I + F
B8 = ["u8", "s8", "p8"]


def bits(t):
    return LANES[t][0]


def kind(t):
    return LANES[t][1]


def vtype(t, q):
    """ACLE's vector type of lane t, 128-bit (q) or 64-bit."""
    prefix = {"s": "int", "u": "uint", "f": "float", "p": "poly"}[kind(t)]
    return "%s%dx%d_t" % (prefix, bits(t), (128 if q else 64) // bits(t))


def scalar(t):
    """The scalar type of lane t (poly lanes are unsigned: p8 is u8)."""
    return {"s": "i", "u": "u", "f": "f", "p": "u"}[kind(t)] + str(bits(t))


def prim(t, q):
    """The portable vector type (`v16u8`) of lane t."""
    k = {"s": "i", "u": "u", "f": "f", "p": "u"}[kind(t)]
    return "v%d%s%d" % ((128 if q else 64) // bits(t), k, bits(t))


def lanes(t, q):
    return (128 if q else 64) // bits(t)


def arr(t, q):
    """The arrangement (`16b`)."""
    return "%d%s" % (lanes(t, q), {8: "b", 16: "h", 32: "s", 64: "d"}[bits(t)])


def letter(t):
    return {8: "b", 16: "h", 32: "s", 64: "d"}[bits(t)]


def utype(t):
    """The unsigned lane of t's width (a compare's result)."""
    return "u%d" % bits(t)


def widen(t):
    return "%s%d" % (t[0], bits(t) * 2)


def narrow(t):
    return "%s%d" % (t[0], bits(t) // 2)


def name(pattern, t, q):
    return pattern.replace("{q}", "q" if q else "").replace("{t}", t)


# ---- The semantics' domain (tests/arch/gen.sh): i64 for integer lanes
# narrower than 64 bits, the lane's own type for 64-bit ones, f64 ----

def dom(t):
    if kind(t) == "f":
        return "f64"
    if bits(t) == 64:
        return "u64" if kind(t) in "up" else "i64"
    return "i64"


def ones(t):
    """All ones in the domain of the unsigned lane of t's width."""
    return "0xffffffffffffffffu64" if bits(t) == 64 else hex((1 << bits(t)) - 1)


def tmax(t):
    if kind(t) == "s":
        return str((1 << (bits(t) - 1)) - 1)
    return str((1 << bits(t)) - 1)


def tmin(t):
    if kind(t) == "s":
        return str(-(1 << (bits(t) - 1)))
    return "0"


def x86(n):
    return "x86_64: " + n if n else "-"


# ---- Lines ----

LINES = []      # (section, line)
SECTION = [""]


def section(title):
    SECTION[0] = title


def line(nm, feats, sig, form, insn, flags, mem, fold, sem, equiv, doc):
    # (a 64-bit vector of one 64-bit lane has no `.1d` arrangement in most
    # instructions: their scalar forms, `sqadd d0, d1, d2`)
    if all(x == "1d" for x in re.findall(r">\.(\w+)", insn)) and ">.1d" in insn:
        insn = re.sub(r"<(\w+)>\.1d", r"<\1:d>", insn)
    # (a trailing parenthesized group is a note to tests/arch/gen.sh: an
    # expression ending in one is parenthesized whole)
    for lhs in ["r[k] = ", "r = "]:
        if sem.startswith(lhs) and sem.endswith(")") and " over k of " not in sem:
            sem = lhs + "(" + sem[len(lhs):] + ")"
    cols = [nm, feats, sig, form, insn, flags or "-", mem or "none", fold or "-", sem, equiv or "-", doc]
    # (` | ` separates the columns: an or is written `a|b`)
    cols = [c.replace(" | ", "|") for c in cols]
    LINES.append((SECTION[0], " | ".join(cols)))


def qd(types, q_only=False, d_only=False, no64d=False):
    """(t, q) for every type, 128-bit then 64-bit forms."""
    out = []
    for t in types:
        if not d_only:
            out.append((t, True))
    for t in types:
        if not q_only and not (no64d and bits(t) == 64):
            out.append((t, False))
    return out


def vv(t, q):
    return vtype(t, q)


# ---- The families ----

def loads_stores():
    section("Loads and stores (safe: a slice and an index, checked)")
    for t, q in qd(A + ["p8", "p64"]):
        n = 16 if q else 8
        reg = "q" if q else "d"
        el = scalar(t).replace("p", "u")
        line(name("vld1{q}_{t}", t, q), "neon", "(s: [%s], i: i64) -> %s" % (el, vv(t, q)), "load",
             "ldr <d:%s>, [<s>]" % reg, "-", "load(s, %d)" % n, "-",
             "r[k] = s[i + k]", x86("_mm_loadu_si128" if q else "_mm_loadl_epi64"),
             "the %d lanes s[i..i + %d] as a vector (checked: 0 <= i, i + %d <= s.len)"
             % (lanes(t, q), lanes(t, q), lanes(t, q)))
    for t, q in qd(A + ["p8", "p64"]):
        n = 16 if q else 8
        reg = "q" if q else "d"
        el = scalar(t).replace("p", "u")
        line(name("vst1{q}_{t}", t, q), "neon", "(s: [%s], i: i64, v: %s)" % (el, vv(t, q)), "store",
             "str <v:%s>, [<s>]" % reg, "-", "store(s, %d)" % n, "-",
             "s[i + k] = v[k]", x86("_mm_storeu_si128" if q else "_mm_storel_epi64"),
             "v's %d lanes into s[i..i + %d] (checked)" % (lanes(t, q), lanes(t, q)))


def build_lanes():
    section("Build, lanes, halves")
    for base in ["vdup{q}_n_{t}", "vmov{q}_n_{t}"]:
        for t, q in qd(A + ["p8"]):
            if kind(t) == "f":
                insn = "dup <d>.%s, <x>.%s[0]" % (arr(t, q), letter(t))
            else:
                insn = "dup <d>.%s, <x:%s>" % (arr(t, q), "x" if bits(t) == 64 else "w")
            line(name(base, t, q), "neon", "(x: %s) -> %s" % (scalar(t), vv(t, q)), "vsplat", insn,
                 "pure", None, "splat", "r[k] = x",
                 x86({8: "_mm_set1_epi8", 16: "_mm_set1_epi16", 32: "_mm_set1_epi32",
                      64: "_mm_set1_epi64x"}[bits(t)] if kind(t) != "f"
                     else ("_mm_set1_ps" if bits(t) == 32 else "_mm_set1_pd")),
                 "every lane x")
    for t, q in qd(A + ["p8"]):
        n = lanes(t, q)
        if kind(t) == "f":
            insn = "mov <d:%s>, <v>.%s[<lane>]" % (letter(t), letter(t))
        elif bits(t) == 64:
            insn = "mov <d:x>, <v>.d[<lane>]"
        elif kind(t) == "s":
            insn = "smov <d:x>, <v>.%s[<lane>]" % letter(t)
        else:
            insn = "umov <d:w>, <v>.%s[<lane>]" % letter(t)
        line(name("vget{q}_lane_{t}", t, q), "neon",
             "(v: %s, lane: const 0..=%d) -> %s" % (vv(t, q), n - 1, scalar(t)), "vext", insn,
             "pure", None, "lane", "r = v[lane]", None, "lane `lane` of v")
    for t, q in qd(A + ["p8"]):
        n = lanes(t, q)
        if kind(t) == "f":
            insn = "mov <d>.%s[<lane>], <x>.%s[0]" % (letter(t), letter(t))
        else:
            insn = "mov <d>.%s[<lane>], <x:%s>" % (letter(t), "x" if bits(t) == 64 else "w")
        line(name("vset{q}_lane_{t}", t, q), "neon",
             "(x: %s, v: %s, lane: const 0..=%d) -> %s" % (scalar(t), vv(t, q), n - 1, vv(t, q)),
             "intr", insn, "pure tied=v", None, "lane.set",
             "r[k] = if k == lane { x } else { v[k] }", None, "v with lane `lane` replaced by x")
    for t in A + ["p8"]:
        n = lanes(t, False)
        line("vcombine_%s" % t, "neon", "(low: %s, high: %s) -> %s" % (vv(t, False), vv(t, False), vv(t, True)),
             "intr", "mov <d>.d[1], <high>.d[0]", "pure tied=low", None, "perm.combine",
             "r[k] = if k < %d { low[k] } else { high[k - %d] }" % (n, n), None,
             "the 128-bit vector of low's lanes then high's")
    for t in A + ["p8"]:
        line("vget_low_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(t, False)), "intr",
             "mov <d>.8b, <a>.8b", "pure", None, "perm.low", "r[k] = a[k]", None,
             "the low 64 bits of a")
    for t in A + ["p8"]:
        n = lanes(t, False)
        line("vget_high_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(t, False)), "intr",
             "mov <d:d>, <a>.d[1]", "pure", None, "perm.high", "r[k] = a[k + %d]" % n, None,
             "the high 64 bits of a")


def casts():
    section("Casts (no instruction)")
    ts = A + ["p8", "p64"]
    for q in [True, False]:
        for x in ts:
            for y in ts:
                if x == y:
                    continue
                nm = "vreinterpret%s_%s_%s" % ("q" if q else "", x, y)
                nb = 16 if q else 8
                line(nm, "neon", "(a: %s) -> %s" % (vv(y, q), vv(x, q)), "cast", "-", "pure", None, "cast",
                     "r = a's %d bytes as %s lanes" % (nb, scalar(x)), None,
                     "the same bits as %d %s lanes" % (lanes(x, q), scalar(x)))


# Three-same integer instructions: (U, opcode) -> bits.
def same3(u, opc):
    return 0x0e200400 | u << 29 | opc << 11


def same3f(u, a, opc):
    return 0x0e200400 | u << 29 | a << 23 | opc << 11


def misc2(u, opc):
    return 0x0e200800 | u << 29 | opc << 12


def misc2f(u, a, opc):
    return 0x0e200800 | u << 29 | a << 23 | opc << 12


def across(u, opc):
    return 0x0e300800 | u << 29 | opc << 12


def diff3(u, opc):
    return 0x0e200000 | u << 29 | opc << 12


def shimm(u, opc):
    return 0x0f000400 | u << 29 | opc << 11


def perm(opc):
    return 0x0e000800 | opc << 12


INSNS = []      # (mnemonic, class, bits, syntax)


def insn(mn, cls, b, syntax):
    INSNS.append((mn, cls, "0x%08x" % b, syntax))


def instructions():
    # (seed instructions first, in their order)
    insn("uqsub", "same3", same3(1, 0b00101), "uqsub Vd.T, Vn.T, Vm.T")
    insn("umaxv", "across", across(1, 0b01010), "umaxv <V>d, Vn.T")
    insn("umov", "umov", 0x0e003c00, "umov Wd, Vn.Ts[i]")
    insn("tbl", "tbl", 0x0e000000, "tbl Vd.T, {Vn.16b, ...}, Vm.T")
    insn("ext", "ext", 0x2e000000, "ext Vd.T, Vn.T, Vm.T, #index")
    insn("shrn", "shrn", shimm(0, 0b10000), "shrn Vd.Tb, Vn.Ta, #shift")
    insn("crc32cx", "crc", 0x9ac05c00, "crc32cx Wd, Wn, Xm")
    # three same, integer
    for mn, u, opc in [("shadd", 0, 0), ("uhadd", 1, 0), ("sqadd", 0, 1), ("uqadd", 1, 1),
                       ("srhadd", 0, 2), ("urhadd", 1, 2), ("shsub", 0, 4), ("uhsub", 1, 4),
                       ("sqsub", 0, 5), ("cmgt", 0, 6), ("cmhi", 1, 6), ("cmge", 0, 7), ("cmhs", 1, 7),
                       ("sshl", 0, 8), ("ushl", 1, 8), ("sqshl", 0, 9), ("uqshl", 1, 9),
                       ("srshl", 0, 10), ("urshl", 1, 10), ("smax", 0, 12), ("umax", 1, 12),
                       ("smin", 0, 13), ("umin", 1, 13), ("sabd", 0, 14), ("uabd", 1, 14),
                       ("saba", 0, 15), ("uaba", 1, 15), ("cmtst", 0, 17), ("mla", 0, 18),
                       ("mls", 1, 18), ("pmul", 1, 19), ("smaxp", 0, 20), ("umaxp", 1, 20),
                       ("sminp", 0, 21), ("uminp", 1, 21), ("sqdmulh", 0, 22), ("sqrdmulh", 1, 22),
                       ("addp", 0, 23)]:
        insn(mn, "same3", same3(u, opc), "%s Vd.T, Vn.T, Vm.T" % mn)
    # logic (the size field is the operation)
    insn("bic", "same3", 0x0e601c00, "bic Vd.16b, Vn.16b, Vm.16b")
    insn("orn", "same3", 0x0ee01c00, "orn Vd.16b, Vn.16b, Vm.16b")
    # permutes
    for mn, opc in [("uzp1", 1), ("trn1", 2), ("zip1", 3), ("uzp2", 5), ("trn2", 6), ("zip2", 7)]:
        insn(mn, "same3", perm(opc), "%s Vd.T, Vn.T, Vm.T" % mn)
    insn("tbx", "tbl", 0x0e001000, "tbx Vd.T, {Vn.16b, ...}, Vm.T")
    # two-register misc, integer (`cmeq` and the like: against #0)
    for mn, u, opc in [("rev64", 0, 0), ("rev32", 1, 0), ("rev16", 0, 1), ("saddlp", 0, 2),
                       ("uaddlp", 1, 2), ("cls", 0, 4), ("clz", 1, 4), ("sadalp", 0, 6),
                       ("uadalp", 1, 6), ("sqabs", 0, 7), ("sqneg", 1, 7), ("cmgt", 0, 8),
                       ("cmge", 1, 8), ("cmeq", 0, 9), ("cmle", 1, 9), ("cmlt", 0, 10),
                       ("abs", 0, 11), ("xtn", 0, 18), ("sqxtun", 1, 18), ("sqxtn", 0, 20),
                       ("uqxtn", 1, 20)]:
        insn(mn, "misc2", misc2(u, opc), "%s Vd.T, Vn.T%s" % (mn, ", #0" if mn.startswith("cm") else ""))
    insn("rbit", "misc2", 0x2e605800, "rbit Vd.T, Vn.T")
    # two-register misc, float (against #0.0)
    for mn, u, a, opc in [("fcmgt", 0, 1, 12), ("fcmeq", 0, 1, 13), ("fcmlt", 0, 1, 14),
                          ("fcmge", 1, 1, 12), ("fcmle", 1, 1, 13)]:
        insn(mn, "misc2f", misc2f(u, a, opc), "%s Vd.T, Vn.T, #0.0" % mn)
    insn("xtn2", "misc2", misc2(0, 18), "xtn2 Vd.Tb, Vn.Ta")
    insn("sqxtn2", "misc2", misc2(0, 20), "sqxtn2 Vd.Tb, Vn.Ta")
    insn("uqxtn2", "misc2", misc2(1, 20), "uqxtn2 Vd.Tb, Vn.Ta")
    insn("sqxtun2", "misc2", misc2(1, 18), "sqxtun2 Vd.Tb, Vn.Ta")
    # across lanes
    for mn, u, opc in [("saddlv", 0, 3), ("uaddlv", 1, 3), ("smaxv", 0, 10), ("sminv", 0, 26),
                       ("uminv", 1, 26)]:
        insn(mn, "across", across(u, opc), "%s <V>d, Vn.T" % mn)
    # shifts by immediate
    for mn, u, opc, cls in [("sshr", 0, 0, "shrn"), ("ushr", 1, 0, "shrn"), ("ssra", 0, 2, "shrn"),
                            ("usra", 1, 2, "shrn"), ("srshr", 0, 4, "shrn"), ("urshr", 1, 4, "shrn"),
                            ("srsra", 0, 6, "shrn"), ("ursra", 1, 6, "shrn"), ("sri", 1, 8, "shrn"),
                            ("shl", 0, 10, "shl"), ("sli", 1, 10, "shl"), ("sqshlu", 1, 12, "shl"),
                            ("sqshl", 0, 14, "shl"), ("uqshl", 1, 14, "shl"),
                            ("sqshrun", 1, 16, "shrn"), ("rshrn", 0, 17, "shrn"),
                            ("sqrshrun", 1, 17, "shrn"), ("sqshrn", 0, 18, "shrn"),
                            ("uqshrn", 1, 18, "shrn"), ("sqrshrn", 0, 19, "shrn"),
                            ("uqrshrn", 1, 19, "shrn"), ("sshll", 0, 20, "shl"),
                            ("ushll", 1, 20, "shl")]:
        insn(mn, cls, shimm(u, opc), "%s Vd.T, Vn.T, #shift" % mn)
    # dot products, widening, the high-half narrowing forms
    insn("sdot", "same3", 0x0e809400, "sdot Vd.4s, Vn.16b, Vm.16b")
    insn("sdot", "elem", 0x0f80e000, "sdot Vd.4s, Vn.16b, Vm.4b[i]")
    insn("udot", "same3", 0x2e809400, "udot Vd.4s, Vn.16b, Vm.16b")
    insn("udot", "elem", 0x2f80e000, "udot Vd.4s, Vn.16b, Vm.4b[i]")
    for mn, opc in [("addl", 0), ("addw", 1), ("subl", 2), ("subw", 3), ("mlal", 8), ("mlsl", 10), ("mull", 12)]:
        for u, pre in [(0, "s"), (1, "u")]:
            for two in ["", "2"]:
                if pre + mn + two == "umlal":
                    # (the chain's umlal by element stays the chain's: diff3
                    # wants a vector third operand)
                    pass
                insn(pre + mn + two, "diff3", diff3(u, opc), "%s Vd.Ta, Vn.Tb, Vm.Tb" % (pre + mn + two))
    for mn, u in [("sshll2", 0), ("ushll2", 1)]:
        insn(mn, "shl", shimm(u, 20), "%s Vd.Ta, Vn.Tb, #shift" % mn)
    for mn, u, opc in [("shrn2", 0, 16), ("rshrn2", 0, 17), ("sqshrn2", 0, 18), ("uqshrn2", 1, 18),
                       ("sqshrun2", 1, 16)]:
        insn(mn, "shrn", shimm(u, opc), "%s Vd.Tb, Vn.Ta, #shift" % mn)
    # crypto
    for mn, cls, b in [("aese", "rr", 0x4e284800), ("aesd", "rr", 0x4e285800), ("aesmc", "rr", 0x4e286800),
                       ("aesimc", "rr", 0x4e287800), ("sha1c", "rrr", 0x5e000000), ("sha1p", "rrr", 0x5e001000),
                       ("sha1m", "rrr", 0x5e002000), ("sha1su0", "rrr", 0x5e003000),
                       ("sha256h", "rrr", 0x5e004000), ("sha256h2", "rrr", 0x5e005000),
                       ("sha256su1", "rrr", 0x5e006000), ("sha1h", "rr", 0x5e280800),
                       ("sha1su1", "rr", 0x5e281800), ("sha256su0", "rr", 0x5e282800),
                       ("sha512h", "rrr", 0xce608000), ("sha512h2", "rrr", 0xce608400),
                       ("sha512su1", "rrr", 0xce608800), ("rax1", "rrr", 0xce608c00),
                       ("sha512su0", "rr", 0xcec08000), ("eor3", "rrrr", 0xce000000),
                       ("bcax", "rrrr", 0xce200000), ("xar", "xar", 0xce800000)]:
        insn(mn, cls, b, mn + " (crypto)")
    insn("pmull", "diff3", diff3(0, 14), "pmull Vd.Ta, Vn.Tb, Vm.Tb")
    insn("pmull2", "diff3", diff3(0, 14) | 1 << 30, "pmull2 Vd.Ta, Vn.Tb, Vm.Tb")
    # CRC-32
    for mn, b in [("crc32b", 0x1ac04000), ("crc32h", 0x1ac04400), ("crc32w", 0x1ac04800),
                  ("crc32x", 0x9ac04c00), ("crc32cb", 0x1ac05000), ("crc32ch", 0x1ac05400),
                  ("crc32cw", 0x1ac05800)]:
        insn(mn, "crc", b, "%s Wd, Wn, %sm" % (mn, "X" if mn.endswith("x") else "W"))


# ---- Integer arithmetic and the rest of the core families ----

def sem_bin(op, t):
    return "r[k] = a[k] %s b[k]" % op


def arithmetic():
    section("Arithmetic")
    for t, q in qd(A):
        line(name("vadd{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
             "vbin.add", "%s <d>.%s, <a>.%s, <b>.%s" % ("fadd" if kind(t) == "f" else "add", arr(t, q), arr(t, q), arr(t, q)),
             "pure commutative", None, "lanes.add", "r[k] = a[k] + b[k]",
             None, "lanewise a + b" + ("" if kind(t) == "f" else ", wrapping"))
    for t, q in qd(A):
        line(name("vsub{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
             "vbin.sub", "%s <d>.%s, <a>.%s, <b>.%s" % ("fsub" if kind(t) == "f" else "sub", arr(t, q), arr(t, q), arr(t, q)),
             "pure", None, "lanes.sub", "r[k] = a[k] - b[k]",
             None, "lanewise a - b" + ("" if kind(t) == "f" else ", wrapping"))
    for t, q in qd(I6 + F):
        line(name("vmul{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
             "vbin.mul", "%s <d>.%s, <a>.%s, <b>.%s" % ("fmul" if kind(t) == "f" else "mul", arr(t, q), arr(t, q), arr(t, q)),
             "pure commutative", None, "lanes.mul", "r[k] = a[k] * b[k]",
             None, "lanewise a * b" + ("" if kind(t) == "f" else ", wrapping"))
    for op, mn_s, mn_u, x86s, x86u, doc in [
            ("qadd", "sqadd", "uqadd", "_mm_adds_epi", "_mm_adds_epu", "lanewise a + b, saturating"),
            ("qsub", "sqsub", "uqsub", "_mm_subs_epi", "_mm_subs_epu", "lanewise a - b, saturating")]:
        for t, q in qd(I):
            mn = mn_s if kind(t) == "s" else mn_u
            sign = "+" if op == "qadd" else "-"
            if bits(t) < 64:
                if kind(t) == "s":
                    sem = "r[k] = clamp(a[k] %s b[k], %s, %s)" % (sign, tmin(t), tmax(t))
                elif op == "qadd":
                    sem = "r[k] = min(a[k] + b[k], %s)" % tmax(t)
                else:
                    sem = "r[k] = max(a[k] - b[k], 0)"
            elif kind(t) == "u":
                sem = ("r[k] = if a[k] + b[k] < a[k] { %s } else { a[k] + b[k] }" % ones(t) if op == "qadd"
                       else "r[k] = if a[k] > b[k] { a[k] - b[k] } else { 0 }")
            else:
                sem = "the saturated a[k] %s b[k]" % sign
            nm = name("v%s{q}_{t}" % op, t, q)
            if nm == "vqsubq_u8":
                sem = "r[k] = max(a[k] - b[k], 0)"
            eq = (x86s if kind(t) == "s" else x86u) + str(bits(t)) if bits(t) <= 16 and q else None
            line(nm, "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)), "intr",
                 "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)),
                 "pure commutative" if op == "qadd" else "pure", None,
                 "lanes.%s_%s" % (op, "s" if kind(t) == "s" else "u"), sem, x86(eq),
                 doc + (" at %s and %s" % (tmin(t), tmax(t)) if bits(t) < 64 else ""))
    for op, sem, doc in [("hadd", "r[k] = (a[k] + b[k]) >> 1", "lanewise (a + b) / 2, rounding down, without overflow"),
                         ("rhadd", "r[k] = (a[k] + b[k] + 1) >> 1", "lanewise (a + b + 1) / 2, without overflow"),
                         ("hsub", "r[k] = (a[k] - b[k]) >> 1", "lanewise (a - b) / 2, rounding down, without overflow"),
                         ("abd", "r[k] = abs(a[k] - b[k])", "lanewise |a - b|, without overflow")]:
        for t, q in qd(I6):
            mn = ("s" if kind(t) == "s" else "u") + op
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
                 "intr", "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)),
                 "pure" if op == "hsub" else "pure commutative", None, "lanes.%s" % op, sem,
                 x86("_mm_avg_epu%d" % bits(t) if op == "rhadd" and kind(t) == "u" and bits(t) <= 16 and q else None),
                 doc)
    for op, mnop, fn in [("max", "max", "max"), ("min", "min", "min")]:
        for t, q in qd(I6):
            mn = ("s" if kind(t) == "s" else "u") + mnop
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
                 "intr", "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)),
                 "pure commutative", None, "lanes.%s" % op, "r[k] = %s(a[k], b[k])" % fn, None,
                 "lanewise %s(a, b)" % fn)
    for op, fn in [("pmax", "max"), ("pmin", "min"), ("padd", None)]:
        for t, q in qd(I6 if op != "padd" else I6 + ["s64", "u64"]):
            if bits(t) == 64 and not q:
                continue
            n = lanes(t, q)
            mn = "addp" if op == "padd" else ("s" if kind(t) == "s" else "u") + op[1:] + "p"
            if fn:
                e = "%s(a[2 * k], a[2 * k + 1])" % fn
                e2 = "%s(b[2 * k - %d], b[2 * k - %d])" % (fn, n, n - 1)
            else:
                e = "a[2 * k] + a[2 * k + 1]"
                e2 = "b[2 * k - %d] + b[2 * k - %d]" % (n, n - 1)
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
                 "intr", "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)),
                 "pure", None, "pairwise.%s" % op[1:],
                 "r[k] = if k < %d { %s } else { %s }" % (n // 2, e, e2), None,
                 "pairwise %s of adjacent lanes: a's pairs, then b's" % (fn or "sum"))
    for t, q in qd(SI):
        line(name("vneg{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "neg <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.neg", "r[k] = -a[k]",
             None, "lanewise -a, wrapping")
    for t, q in qd(SI):
        line(name("vabs{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "abs <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.abs", "r[k] = abs(a[k])",
             x86("_mm_abs_epi%d" % bits(t) if q and bits(t) <= 32 else None), "lanewise |a|, wrapping (|MIN| is MIN)")
    for op, mn, doc in [("qabs", "sqabs", "lanewise |a|, saturating"), ("qneg", "sqneg", "lanewise -a, saturating")]:
        for t, q in qd(SI):
            if bits(t) < 64:
                e = "abs(a[k])" if op == "qabs" else "-a[k]"
                sem = "r[k] = clamp(%s, %s, %s)" % (e, tmin(t), tmax(t))
            else:
                sem = "the saturated %s" % ("|a[k]|" if op == "qabs" else "-a[k]")
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
                 "%s <d>.%s, <a>.%s" % (mn, arr(t, q), arr(t, q)), "pure", None, "lanes.%s" % op, sem, None, doc)
    for op, mn, s in [("mla", "mla", "+"), ("mls", "mls", "-")]:
        for t, q in qd(I6):
            line(name("v%s{q}_{t}" % op, t, q), "neon",
                 "(a: %s, b: %s, c: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q), vv(t, q)), "intr",
                 "%s <d>.%s, <b>.%s, <c>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)), "pure tied=a", None,
                 "lanes.%s" % op, "r[k] = a[k] %s b[k] * c[k]" % s, None, "lanewise a %s b * c, wrapping" % s)


def compare():
    section("Compare")
    for op, cond, mn_s, mn_u, mn_f, swap in [
            ("ceq", "eq", "cmeq", "cmeq", "fcmeq", False), ("cgt", "gt", "cmgt", "cmhi", "fcmgt", False),
            ("cge", "ge", "cmge", "cmhs", "fcmge", False), ("clt", "lt", "cmgt", "cmhi", "fcmgt", True),
            ("cle", "le", "cmge", "cmhs", "fcmge", True)]:
        for t, q in qd(A):
            mn = mn_f if kind(t) == "f" else (mn_s if kind(t) == "s" else mn_u)
            x, y = ("b", "a") if swap else ("a", "b")
            rel = {"eq": "==", "gt": ">", "ge": ">=", "lt": "<", "le": "<="}[cond]
            work = prim(t, q)
            line(name("v%s{q}_{t}" % op, t, q), "neon",
                 "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(utype(t), q)),
                 "vcmp.%s:%s" % (cond, work),
                 "%s <d>.%s, <%s>.%s, <%s>.%s" % (mn, arr(t, q), x, arr(t, q), y, arr(t, q)),
                 "pure commutative" if cond == "eq" else "pure", None, "lanes.%s" % cond,
                 "r[k] = if a[k] %s b[k] { %s } else { 0 }" % (rel, ones(t)),
                 x86(("_mm_cmpeq_epi%d" % bits(t)) if cond == "eq" and q and kind(t) != "f" and bits(t) <= 32 else None),
                 "lanewise a %s b: a mask, each lane all ones or 0" % rel)
    for op, mn_i, mn_f, rel, types in [("ceqz", "cmeq", "fcmeq", "==", A), ("cgtz", "cmgt", "fcmgt", ">", SI + F),
                                       ("cgez", "cmge", "fcmge", ">=", SI + F), ("cltz", "cmlt", "fcmlt", "<", SI + F),
                                       ("clez", "cmle", "fcmle", "<=", SI + F)]:
        for t, q in qd(types):
            f = kind(t) == "f"
            zero = "0.0" if f else "0"
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(utype(t), q)), "intr",
                 "%s <d>.%s, <a>.%s, #%s" % (mn_f if f else mn_i, arr(t, q), arr(t, q), zero), "pure", None,
                 "lanes.%sz" % op[1:3], "r[k] = if a[k] %s %s { %s } else { 0 }" % (rel, zero, ones(t)), None,
                 "lanewise a %s 0: a mask" % rel)
    for t, q in qd(I + ["p8"]):
        line(name("vtst{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(utype(t), q)), "intr",
             "cmtst <d>.%s, <a>.%s, <b>.%s" % (arr(t, q), arr(t, q), arr(t, q)), "pure commutative", None,
             "lanes.tst", "r[k] = if (a[k] & b[k]) != 0 { %s } else { 0 }" % ones(t), None,
             "lanewise (a & b) != 0: a mask")


def logic():
    section("Logic")
    for op, form, mn, sem, comm in [("and", "vbin.and", "and", "a[k] & b[k]", True),
                                    ("orr", "vbin.or", "orr", "a[k] | b[k]", True),
                                    ("eor", "vbin.xor", "eor", "a[k] ^ b[k]", True),
                                    ("bic", "intr", "bic", "a[k] & ~b[k]", False),
                                    ("orn", "intr", "orn", "a[k] | ~b[k]", False)]:
        for t, q in qd(I):
            a = "16b" if q else "8b"
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)),
                 form, "%s <d>.%s, <a>.%s, <b>.%s" % (mn, a, a, a), "pure commutative" if comm else "pure", None,
                 "lanes.%s" % op, "r[k] = " + sem,
                 x86({"and": "_mm_and_si128", "orr": "_mm_or_si128", "eor": "_mm_xor_si128",
                      "bic": "_mm_andnot_si128(b, a)"}.get(op) if q else None),
                 "lanewise " + sem.replace("[k]", ""))
    for t, q in qd(I6 + ["p8"]):
        a = "16b" if q else "8b"
        line(name("vmvn{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "mvn <d>.%s, <a>.%s" % (a, a), "pure", None, "lanes.not", "r[k] = ~a[k]", None, "lanewise ~a")
    for t, q in qd(I + ["p8"]):
        a = "16b" if q else "8b"
        line(name("vbsl{q}_{t}", t, q), "neon",
             "(a: %s, b: %s, c: %s) -> %s" % (vv(utype(t), q), vv(t, q), vv(t, q), vv(t, q)), "intr",
             "bsl <d>.%s, <b>.%s, <c>.%s" % (a, a, a), "pure tied=a", None, "lanes.bsl",
             "r[k] = (b[k] & (a[k] as i64)) | (c[k] & ~(a[k] as i64))" if t == "s64"
             else "r[k] = (b[k] & a[k]) | (c[k] & ~a[k])", None,
             "bitwise select: b's bits where a's are set, c's elsewhere")


def shifts():
    section("Shifts")
    for t, q in qd(I):
        b = bits(t)
        d = dom(t)
        n = "(n as u64)" if d == "u64" else "n"
        line(name("vshl{q}_n_{t}", t, q), "neon", "(a: %s, n: const 0..=%d) -> %s" % (vv(t, q), b - 1, vv(t, q)),
             "intr", "shl <d>.%s, <a>.%s, #<n>" % (arr(t, q), arr(t, q)), "pure", None, "lanes.shl",
             "r[k] = a[k] << %s" % n, x86("_mm_slli_epi%d" % b if q and b >= 16 else None),
             "lanewise a << n")
    for t, q in qd(I):
        b = bits(t)
        mn = "sshr" if kind(t) == "s" else "ushr"
        if b < 64:
            sem = "r[k] = a[k] >> n"
        elif kind(t) == "s":
            sem = "r[k] = a[k] >> min(n, 63)"
        else:
            sem = "r[k] = if n == 64 { 0 } else { a[k] >> (n as u64) }"
        line(name("vshr{q}_n_{t}", t, q), "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, q), b, vv(t, q)),
             "intr", "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(t, q), arr(t, q)), "pure", None, "lanes.shr",
             sem, x86(("_mm_srai_epi%d" if kind(t) == "s" else "_mm_srli_epi%d") % b if q and 16 <= b <= 32 else None),
             "lanewise a >> n (%s)" % ("arithmetic" if kind(t) == "s" else "logical"))
    for t, q in qd(I):
        b = bits(t)
        mn = "ssra" if kind(t) == "s" else "usra"
        if b < 64:
            sem = "r[k] = a[k] + (b[k] >> n)"
        elif kind(t) == "s":
            sem = "r[k] = a[k] + (b[k] >> min(n, 63))"
        else:
            sem = "r[k] = a[k] + (if n == 64 { 0 } else { b[k] >> (n as u64) })"
        line(name("vsra{q}_n_{t}", t, q), "neon",
             "(a: %s, b: %s, n: const 1..=%d) -> %s" % (vv(t, q), vv(t, q), b, vv(t, q)),
             "intr", "%s <d>.%s, <b>.%s, #<n>" % (mn, arr(t, q), arr(t, q)), "pure tied=a", None, "lanes.sra",
             sem, None, "lanewise a + (b >> n), wrapping")
    for t, q in qd(I):
        b = bits(t)
        mn = "srshr" if kind(t) == "s" else "urshr"
        sem = "r[k] = (a[k] + (1 << (n - 1))) >> n" if b < 64 else "a[k] >> n, rounded (the bit below added)"
        line(name("vrshr{q}_n_{t}", t, q), "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, q), b, vv(t, q)),
             "intr", "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(t, q), arr(t, q)), "pure", None, "lanes.rshr",
             sem, None, "lanewise a >> n, rounding to nearest")
    for t, q in qd(I + ["p8"]):
        b = bits(t)
        d = dom(t)
        if b < 64:
            sem = "r[k] = (b[k] << n) | (a[k] & ((1 << n) - 1))"
        else:
            sem = "r[k] = (b[k] << %s) | (a[k] & ((%s << %s) - %s))" % (
                "(n as u64)" if d == "u64" else "n", "1u64" if d == "u64" else "1",
                "(n as u64)" if d == "u64" else "n", "1u64" if d == "u64" else "1")
        line(name("vsli{q}_n_{t}", t, q), "neon",
             "(a: %s, b: %s, n: const 0..=%d) -> %s" % (vv(t, q), vv(t, q), b - 1, vv(t, q)),
             "intr", "sli <d>.%s, <b>.%s, #<n>" % (arr(t, q), arr(t, q)), "pure tied=a", None, "lanes.sli",
             sem, None, "lanewise (b << n) with a's low n bits kept")
    for t, q in qd(I + ["p8"]):
        b = bits(t)
        if b < 64:
            m = ones(t)
            sem = "r[k] = ((b[k] & %s) >> n) | (a[k] & (%s ^ (%s >> n)))" % (m, m, m)
        else:
            sem = "(b[k] >> n, logical) with a's high n bits kept"
        line(name("vsri{q}_n_{t}", t, q), "neon",
             "(a: %s, b: %s, n: const 1..=%d) -> %s" % (vv(t, q), vv(t, q), b, vv(t, q)),
             "intr", "sri <d>.%s, <b>.%s, #<n>" % (arr(t, q), arr(t, q)), "pure tied=a", None, "lanes.sri",
             sem, None, "lanewise (b >> n, logical) with a's high n bits kept")
    for t, q in qd(I):
        b = bits(t)
        mn = "sqshl" if kind(t) == "s" else "uqshl"
        if b < 64:
            sem = ("r[k] = clamp(a[k] << n, %s, %s)" % (tmin(t), tmax(t)) if kind(t) == "s"
                   else "r[k] = min(a[k] << n, %s)" % tmax(t))
        else:
            sem = "a[k] << n, saturated"
        line(name("vqshl{q}_n_{t}", t, q), "neon", "(a: %s, n: const 0..=%d) -> %s" % (vv(t, q), b - 1, vv(t, q)),
             "intr", "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(t, q), arr(t, q)), "pure", None, "lanes.qshl",
             sem, None, "lanewise a << n, saturating")


def horizontal():
    section("Horizontal")
    for t, q in qd(I6 + ["s64", "u64"]):
        if bits(t) == 64 and not q:
            continue
        mv = ("smov <d:x>, <t>.%s[0]" if kind(t) == "s" else "umov <d:w>, <t>.%s[0]") % letter(t)
        if bits(t) == 64:
            insn = "addp <t:d>, <a>.2d; umov <d:x>, <t>.d[0]"
        elif bits(t) == 32 and not q:
            insn = "addp <t>.2s, <a>.2s, <a>.2s; " + mv
        else:
            insn = "addv <t:%s>, <a>.%s; %s" % (letter(t), arr(t, q), mv)
        line(name("vaddv{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), scalar(t)), "intr", insn, "pure", None,
             "across.add", "r = sum over k of a[k]", None, "the sum of the lanes, wrapping")
    for op, fn in [("max", "max"), ("min", "min")]:
        for t, q in qd(I6):
            mv = ("smov <d:x>, <t>.%s[0]" if kind(t) == "s" else "umov <d:w>, <t>.%s[0]") % letter(t)
            mn = ("s" if kind(t) == "s" else "u") + op
            if bits(t) == 32 and not q:
                insn = "%sp <t>.2s, <a>.2s, <a>.2s; %s" % (mn, mv)
            else:
                insn = "%sv <t:%s>, <a>.%s; %s" % (mn, letter(t), arr(t, q), mv)
            line(name("v%sv{q}_{t}" % op, t, q), "neon", "(a: %s) -> %s" % (vv(t, q), scalar(t)), "intr", insn, "pure",
                 None, "across.%s" % op, "r = %s over k of a[k]" % fn, None,
                 "the %s lane%s" % ("largest" if op == "max" else "smallest",
                                   " (any byte set: vmaxvq_u8(m) != 0)" if name("v%sv{q}_{t}" % op, t, q) == "vmaxvq_u8" else ""))
    for t, q in qd(I6):
        w = widen(t)
        mn = ("s" if kind(t) == "s" else "u") + "addlv"
        if bits(t) == 32 and not q:
            insn = "%saddlp <t>.1d, <a>.2s; %s" % ("s" if kind(t) == "s" else "u", "umov <d:x>, <t>.d[0]")
        else:
            wl = letter(w)
            if bits(w) == 64:
                mv = "umov <d:x>, <t>.d[0]"
            elif kind(t) == "s":
                mv = "smov <d:x>, <t>.%s[0]" % wl
            else:
                mv = "umov <d:w>, <t>.%s[0]" % wl
            insn = "%s <t:%s>, <a>.%s; %s" % (mn, wl, arr(t, q), mv)
        line(name("vaddlv{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), scalar(w)), "intr", insn, "pure", None,
             "across.addl", "r = sum over k of a[k]", None, "the sum of the lanes, widened (no overflow)")


def narrowing():
    section("Narrowing")
    for t in ["s16", "u16", "s32", "u32", "s64", "u64"]:
        nt = narrow(t)
        b = bits(t)
        sem = "r[k] = a[k] >> (n as u64)" if dom(t) == "u64" else "r[k] = a[k] >> n"
        line("vshrn_n_%s" % t, "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, True), b // 2, vv(nt, False)), "intr",
             "shrn <d>.%s, <a>.%s, #<n>" % (arr(nt, False), arr(t, True)), "pure", None, "lanes.shrn", sem, None,
             "each lane shifted right by n, narrowed to its low half%s" %
             (" (the NEON movemask: n = 4 gives 4 bits per byte)" if t == "u16" else ""))
    for t in ["s16", "u16", "s32", "u32", "s64", "u64"]:
        nt = narrow(t)
        b = bits(t)
        sem = ("r[k] = (a[k] + (1 << (n - 1))) >> n" if dom(t) == "i64"
               else "(a[k] + (1 << (n - 1))) >> n, narrowed (computed without overflow)")
        line("vrshrn_n_%s" % t, "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, True), b // 2, vv(nt, False)), "intr",
             "rshrn <d>.%s, <a>.%s, #<n>" % (arr(nt, False), arr(t, True)), "pure", None, "lanes.rshrn", sem, None,
             "each lane shifted right by n, rounding, narrowed to its low half")
    for t in ["s16", "u16", "s32", "u32", "s64", "u64"]:
        nt = narrow(t)
        e = "a[k]" if dom(t) == "i64" else "(a[k] as i64)"
        line("vmovn_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(nt, False)), "intr",
             "xtn <d>.%s, <a>.%s" % (arr(nt, False), arr(t, True)), "pure", None, "lanes.movn", "r[k] = " + e, None,
             "each lane narrowed to its low half")
    for t in ["s16", "u16", "s32", "u32", "s64", "u64"]:
        nt = narrow(t)
        mn = "sqxtn" if kind(t) == "s" else "uqxtn"
        if kind(t) == "s":
            sem = "r[k] = clamp(a[k], %s, %s)" % (tmin(nt), tmax(nt))
        elif dom(t) == "i64":
            sem = "r[k] = min(a[k], %s)" % tmax(nt)
        else:
            sem = "r[k] = min(a[k], %su64) as i64" % tmax(nt)
        line("vqmovn_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(nt, False)), "intr",
             "%s <d>.%s, <a>.%s" % (mn, arr(nt, False), arr(t, True)), "pure", None, "lanes.qmovn", sem, None,
             "each lane narrowed, saturating")
    for t in ["s16", "s32", "s64"]:
        nt = "u%d" % (bits(t) // 2)
        line("vqmovun_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(nt, False)), "intr",
             "sqxtun <d>.%s, <a>.%s" % (arr(nt, False), arr(t, True)), "pure", None, "lanes.qmovun",
             "r[k] = clamp(a[k], 0, %s)" % tmax(nt), None, "each signed lane narrowed to unsigned, saturating")
    for t in ["s16", "u16", "s32", "u32", "s64", "u64"]:
        nt = narrow(t)
        b = bits(t)
        mn = "sqshrn" if kind(t) == "s" else "uqshrn"
        if kind(t) == "s":
            sem = "r[k] = clamp(a[k] >> n, %s, %s)" % (tmin(nt), tmax(nt))
        elif dom(t) == "i64":
            sem = "r[k] = min(a[k] >> n, %s)" % tmax(nt)
        else:
            sem = "r[k] = min(a[k] >> (n as u64), %su64) as i64" % tmax(nt)
        line("vqshrn_n_%s" % t, "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, True), b // 2, vv(nt, False)), "intr",
             "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(nt, False), arr(t, True)), "pure", None, "lanes.qshrn", sem, None,
             "each lane shifted right by n, narrowed, saturating")
    for t in ["s16", "s32", "s64"]:
        nt = "u%d" % (bits(t) // 2)
        b = bits(t)
        line("vqshrun_n_%s" % t, "neon", "(a: %s, n: const 1..=%d) -> %s" % (vv(t, True), b // 2, vv(nt, False)), "intr",
             "sqshrun <d>.%s, <a>.%s, #<n>" % (arr(nt, False), arr(t, True)), "pure", None, "lanes.qshrun",
             "r[k] = clamp(a[k] >> n, 0, %s)" % tmax(nt), None,
             "each signed lane shifted right by n, narrowed to unsigned, saturating")


def permutes():
    section("Permutes")
    for t, q in qd(A + ["p8"]):
        n = lanes(t, q)
        scale = bits(t) // 8
        imm = "<n>" if scale == 1 else "<n:%d>" % scale
        a = "16b" if q else "8b"
        line(name("vext{q}_{t}", t, q), "neon",
             "(a: %s, b: %s, n: const 0..=%d) -> %s" % (vv(t, q), vv(t, q), n - 1, vv(t, q)), "intr",
             "ext <d>.%s, <a>.%s, <b>.%s, #%s" % (a, a, a, imm), "pure", None, "perm.ext",
             "r[k] = if k + n < %d { a[k + n] } else { b[k + n - %d] }" % (n, n),
             x86("_mm_alignr_epi8(b, a, n)" if q and scale == 1 else None),
             "lanes n..n + %d of a then b" % n)
    for op, sem in [("zip1", "r[k] = if k %% 2 == 0 { a[k / 2] } else { b[k / 2] }"),
                    ("zip2", "r[k] = if k %% 2 == 0 { a[%(h)d + k / 2] } else { b[%(h)d + k / 2] }"),
                    ("uzp1", "r[k] = if k < %(h)d { a[2 * k] } else { b[2 * k - %(n)d] }"),
                    ("uzp2", "r[k] = if k < %(h)d { a[2 * k + 1] } else { b[2 * k + 1 - %(n)d] }"),
                    ("trn1", "r[k] = if k %% 2 == 0 { a[k] } else { b[k - 1] }"),
                    ("trn2", "r[k] = if k %% 2 == 0 { a[k + 1] } else { b[k] }")]:
        for t, q in qd(A + ["p8"], no64d=True):
            n = lanes(t, q)
            nm = "v%s%s_%s" % (op[:-1], op[-1] + ("q" if q else ""), t)
            line(nm, "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), vv(t, q), vv(t, q)), "intr",
                 "%s <d>.%s, <a>.%s, <b>.%s" % (op, arr(t, q), arr(t, q), arr(t, q)), "pure", None, "perm." + op,
                 sem % {"h": n // 2, "n": n}, None,
                 {"zip1": "the low halves of a and b, interleaved", "zip2": "the high halves of a and b, interleaved",
                  "uzp1": "the even lanes of a then of b", "uzp2": "the odd lanes of a then of b",
                  "trn1": "a's even lanes interleaved with b's even lanes",
                  "trn2": "a's odd lanes interleaved with b's odd lanes"}[op])
    for op, mn, types, x in [("rev16", "rev16", ["s8", "u8", "p8"], 1),
                             ("rev32", "rev32", ["s8", "u8", "p8", "s16", "u16"], None),
                             ("rev64", "rev64", ["s8", "u8", "p8", "s16", "u16", "s32", "u32", "f32"], None)]:
        for t, q in qd(types):
            group = int(op[3:]) // bits(t)
            line(name("v%s{q}_{t}" % op, t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
                 "%s <d>.%s, <a>.%s" % (mn, arr(t, q), arr(t, q)), "pure", None, "perm.rev",
                 "r[k] = a[k ^ %d]" % (group - 1), None,
                 "the lanes of each %d-bit group reversed" % int(op[3:]))
    for t, q in [(t, q) for q in [True, False] for t in B8]:
        idx = "uint8x16_t" if q else "uint8x8_t"
        a = "16b" if q else "8b"
        nm = "vqtbl1%s_%s" % ("q" if q else "", t)
        line(nm, "neon", "(t: %s, idx: %s) -> %s" % (vv(t, True), idx, vv(t, q)), "intr",
             "tbl <d>.%s, {<t>.16b}, <idx>.%s" % (a, a), "pure", None, "perm.tbl",
             "r[k] = if idx[k] < 16 { t[idx[k]] } else { 0 }",
             x86("_mm_shuffle_epi8 (zeroes when bit 7 is set instead)" if q else None),
             "a table lookup: lane k is t[idx[k]], 0 when idx[k] >= 16")
    for t, q in [(t, q) for q in [True, False] for t in B8]:
        idx = "uint8x16_t" if q else "uint8x8_t"
        a = "16b" if q else "8b"
        nm = "vqtbx1%s_%s" % ("q" if q else "", t)
        line(nm, "neon", "(a: %s, t: %s, idx: %s) -> %s" % (vv(t, q), vv(t, True), idx, vv(t, q)), "intr",
             "tbx <d>.%s, {<t>.16b}, <idx>.%s" % (a, a), "pure tied=a", None, "perm.tbx",
             "r[k] = if idx[k] < 16 { t[idx[k]] } else { a[k] }", None,
             "a table lookup: lane k is t[idx[k]], a[k] when idx[k] >= 16")


def bit_ops():
    section("Bits")
    for t, q in qd(B8):
        line(name("vcnt{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "cnt <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.cnt",
             "the number of 1 bits of a[k]", None, "the number of 1 bits of each byte")
    for t, q in qd(B8):
        line(name("vrbit{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "rbit <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.rbit",
             "a[k]'s bits reversed", None, "the bits of each byte reversed")
    for t, q in qd(I6):
        line(name("vclz{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "clz <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.clz",
             "the number of leading 0 bits of a[k]", None, "the leading zero bits of each lane")
    for t, q in qd(S6):
        line(name("vcls{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(t, q)), "intr",
             "cls <d>.%s, <a>.%s" % (arr(t, q), arr(t, q)), "pure", None, "lanes.cls",
             "the number of bits after the top one equal to it, of a[k]", None,
             "the leading sign bits of each lane (not counting the top one)")


def crc():
    section("CRC-32")
    for nm, mn, ty, reg in [("__crc32b", "crc32b", "u8", "w"), ("__crc32h", "crc32h", "u16", "w"),
                            ("__crc32w", "crc32w", "u32", "w"), ("__crc32d", "crc32x", "u64", "x"),
                            ("__crc32cb", "crc32cb", "u8", "w"), ("__crc32ch", "crc32ch", "u16", "w"),
                            ("__crc32cw", "crc32cw", "u32", "w"), ("__crc32cd", "crc32cx", "u64", "x")]:
        c = "c" in nm[7:]
        nb = {"u8": 1, "u16": 2, "u32": 4, "u64": 8}[ty]
        poly = "CRC-32C (Castagnoli" if c else "CRC-32 (ISO-HDLC, gzip's"
        x = {"u8": "_mm_crc32_u8", "u16": "_mm_crc32_u16", "u32": "_mm_crc32_u32", "u64": "_mm_crc32_u64"}[ty] if c else None
        line(nm, "crc", "(crc: u32, data: %s) -> u32" % ty, "intr",
             "%s <d:w>, <crc:w>, <data:%s>" % (mn, reg), "pure", None, "crc.%s%d" % ("c" if c else "", nb * 8),
             "r = %s, reflected, no inversion) of crc and data's %d byte%s" % (poly, nb, "s" if nb > 1 else ""),
             x86(x), "one step of %s over %d byte%s" % ("CRC-32C" if c else "CRC-32", nb, "s" if nb > 1 else ""))


def crypto():
    section("SHA-1, SHA-256")
    u4 = "uint32x4_t"
    for nm, mn, doc in [("vsha1cq_u32", "sha1c", "choose"), ("vsha1pq_u32", "sha1p", "parity"),
                        ("vsha1mq_u32", "sha1m", "majority")]:
        line(nm, "sha2", "(hash_abcd: %s, hash_e: u32, wk: %s) -> %s" % (u4, u4, u4), "intr",
             "fmov <u:s>, <hash_e:w>; %s <d:q>, <u:s>, <wk>.4s" % mn, "pure tied=hash_abcd", None, "-",
             "four SHA-1 rounds (%s) of hash_abcd and hash_e with wk (FIPS 180-4)" % doc, x86("_mm_sha1rnds4_epu32"),
             "four SHA-1 rounds with the %s function: the new abcd" % doc)
    line("vsha1h_u32", "sha2", "(hash_e: u32) -> u32", "intr",
         "fmov <t:s>, <hash_e:w>; sha1h <t:s>, <t:s>; fmov <d:w>, <t:s>", "pure", None, "-",
         "r = ROL(hash_e, 30)", x86("_mm_sha1nexte_epu32"), "SHA-1's fixed rotate: hash_e rotated left by 30")
    line("vsha1su0q_u32", "sha2", "(w0_3: %s, w4_7: %s, w8_11: %s) -> %s" % (u4, u4, u4, u4), "intr",
         "sha1su0 <d>.4s, <w4_7>.4s, <w8_11>.4s", "pure tied=w0_3", None, "-",
         "the first half of SHA-1's message schedule update", x86("_mm_sha1msg1_epu32"),
         "SHA-1 schedule update, part 1")
    line("vsha1su1q_u32", "sha2", "(tw0_3: %s, w12_15: %s) -> %s" % (u4, u4, u4), "intr",
         "sha1su1 <d>.4s, <w12_15>.4s", "pure tied=tw0_3", None, "-",
         "the second half of SHA-1's message schedule update", x86("_mm_sha1msg2_epu32"),
         "SHA-1 schedule update, part 2")
    line("vsha256hq_u32", "sha2", "(hash_abcd: %s, hash_efgh: %s, wk: %s) -> %s" % (u4, u4, u4, u4), "intr",
         "sha256h <d:q>, <hash_efgh:q>, <wk>.4s", "pure tied=hash_abcd", None, "-",
         "four SHA-256 rounds: the new abcd (FIPS 180-4)", x86("_mm_sha256rnds2_epu32 (two rounds)"),
         "four SHA-256 rounds of the state with wk (the message plus constants): the new abcd")
    line("vsha256h2q_u32", "sha2", "(hash_efgh: %s, hash_abcd: %s, wk: %s) -> %s" % (u4, u4, u4, u4), "intr",
         "sha256h2 <d:q>, <hash_abcd:q>, <wk>.4s", "pure tied=hash_efgh", None, "-",
         "four SHA-256 rounds: the new efgh (FIPS 180-4)", x86("_mm_sha256rnds2_epu32 (two rounds)"),
         "four SHA-256 rounds of the state with wk: the new efgh (pass the old abcd, before vsha256hq_u32)")
    line("vsha256su0q_u32", "sha2", "(w0_3: %s, w4_7: %s) -> %s" % (u4, u4, u4), "intr",
         "sha256su0 <d>.4s, <w4_7>.4s", "pure tied=w0_3", None, "-",
         "the first half of SHA-256's message schedule update (sigma0)", x86("_mm_sha256msg1_epu32"),
         "SHA-256 schedule update, part 1")
    line("vsha256su1q_u32", "sha2", "(tw0_3: %s, w8_11: %s, w12_15: %s) -> %s" % (u4, u4, u4, u4), "intr",
         "sha256su1 <d>.4s, <w8_11>.4s, <w12_15>.4s", "pure tied=tw0_3", None, "-",
         "the second half of SHA-256's message schedule update (sigma1)", x86("_mm_sha256msg2_epu32"),
         "SHA-256 schedule update, part 2")
    section("SHA-512, SHA-3")
    u2 = "uint64x2_t"
    line("vsha512hq_u64", "sha3", "(sum_ab: %s, hash_c_: %s, hash_ab: %s) -> %s" % (u2, u2, u2, u2), "intr",
         "sha512h <d:q>, <hash_c_:q>, <hash_ab>.2d", "pure tied=sum_ab", None, "-",
         "two SHA-512 rounds, part 1 (Arm's SHA512H)", None, "SHA-512 hash update, part 1")
    line("vsha512h2q_u64", "sha3", "(sum_ab: %s, hash_c_: %s, hash_ab: %s) -> %s" % (u2, u2, u2, u2), "intr",
         "sha512h2 <d:q>, <hash_c_:q>, <hash_ab>.2d", "pure tied=sum_ab", None, "-",
         "two SHA-512 rounds, part 2 (Arm's SHA512H2)", None, "SHA-512 hash update, part 2")
    line("vsha512su0q_u64", "sha3", "(w0_1: %s, w2_: %s) -> %s" % (u2, u2, u2), "intr",
         "sha512su0 <d>.2d, <w2_>.2d", "pure tied=w0_1", None, "-",
         "the first half of SHA-512's message schedule update (sigma0)", None, "SHA-512 schedule update, part 1")
    line("vsha512su1q_u64", "sha3", "(s01_s02: %s, w14_15: %s, w9_10: %s) -> %s" % (u2, u2, u2, u2), "intr",
         "sha512su1 <d>.2d, <w14_15>.2d, <w9_10>.2d", "pure tied=s01_s02", None, "-",
         "the second half of SHA-512's message schedule update (sigma1)", None, "SHA-512 schedule update, part 2")
    for t in I:
        q = vv(t, True)
        line("veor3q_%s" % t, "sha3", "(a: %s, b: %s, c: %s) -> %s" % (q, q, q, q), "intr",
             "eor3 <d>.16b, <a>.16b, <b>.16b, <c>.16b", "pure commutative", None, "lanes.eor3",
             "r[k] = a[k] ^ b[k] ^ c[k]", None, "three-way exclusive or")
    for t in I:
        q = vv(t, True)
        line("vbcaxq_%s" % t, "sha3", "(a: %s, b: %s, c: %s) -> %s" % (q, q, q, q), "intr",
             "bcax <d>.16b, <a>.16b, <b>.16b, <c>.16b", "pure", None, "lanes.bcax",
             "r[k] = a[k] ^ (b[k] & ~c[k])", None, "a ^ (b & ~c), Keccak's chi step")
    line("vrax1q_u64", "sha3", "(a: %s, b: %s) -> %s" % (u2, u2, u2), "intr", "rax1 <d>.2d, <a>.2d, <b>.2d",
         "pure", None, "lanes.rax1", "r[k] = a[k] ^ ((b[k] << 1) | (b[k] >> 63))", None,
         "a ^ (b rotated left by 1), Keccak's theta step")
    line("vxarq_u64", "sha3", "(a: %s, b: %s, imm6: const 0..=63) -> %s" % (u2, u2, u2), "intr",
         "xar <d>.2d, <a>.2d, <b>.2d, #<imm6>", "pure", None, "lanes.xar",
         "(a[k] ^ b[k]) rotated right by imm6", None, "(a ^ b) rotated right by imm6, Keccak's rho step")
    section("AES, carry-less multiply")
    b16 = "uint8x16_t"
    for nm, mn, doc in [("vaeseq_u8", "aese", "AddRoundKey, SubBytes, ShiftRows"),
                        ("vaesdq_u8", "aesd", "AddRoundKey, InvSubBytes, InvShiftRows")]:
        line(nm, "aes", "(data: %s, key: %s) -> %s" % (b16, b16, b16), "intr", "%s <d>.16b, <key>.16b" % mn,
             "pure tied=data", None, "-", "one AES %s round: %s (FIPS-197)" % ("encryption" if mn == "aese" else "decryption", doc),
             x86("_mm_aesenclast_si128 (key added after)" if mn == "aese" else "_mm_aesdeclast_si128 (key added after)"),
             "one AES round: %s" % doc)
    for nm, mn, doc in [("vaesmcq_u8", "aesmc", "MixColumns"), ("vaesimcq_u8", "aesimc", "InvMixColumns")]:
        line(nm, "aes", "(data: %s) -> %s" % (b16, b16), "intr", "%s <d>.16b, <data>.16b" % mn, "pure", None, "-",
             "AES %s of data (FIPS-197)" % doc, x86("_mm_aesimc_si128" if mn == "aesimc" else None), "AES %s" % doc)
    line("vmull_p64", "aes", "(a: u64, b: u64) -> v2u64", "intr",
         "fmov <t:d>, <a:x>; fmov <u:d>, <b:x>; pmull <d>.1q, <t>.1d, <u>.1d", "pure commutative", None, "clmul",
         "the carry-less product of a and b, 128 bits, low lane first", x86("_mm_clmulepi64_si128(a, b, 0x00)"),
         "carry-less multiply: 64 x 64 -> 128 bits (CRC folding, GHASH)")
    line("vmull_high_p64", "aes", "(a: poly64x2_t, b: poly64x2_t) -> v2u64", "intr",
         "pmull2 <d>.1q, <a>.2d, <b>.2d", "pure commutative", None, "clmul",
         "the carry-less product of a[1] and b[1], 128 bits, low lane first", x86("_mm_clmulepi64_si128(a, b, 0x11)"),
         "carry-less multiply of the high lanes")
    line("vmull_p8", "neon", "(a: poly8x8_t, b: poly8x8_t) -> poly16x8_t", "intr",
         "pmull <d>.8h, <a>.8b, <b>.8b", "pure commutative", None, "clmul",
         "the carry-less product of a[k] and b[k], 16 bits", None, "lanewise carry-less multiply, 8 x 8 -> 16 bits")


def dotprod():
    section("Dot products")
    for t in ["u32", "s32"]:
        src = "u8" if t == "u32" else "s8"
        mn = "udot" if t == "u32" else "sdot"
        for q in [True, False]:
            acc, v = vv(t, q), vv(src, q)
            line(name("vdot{q}_{t}", t, q), "dotprod", "(acc: %s, a: %s, b: %s) -> %s" % (acc, v, v, acc), "intr",
                 "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(src, q), arr(src, q)), "pure tied=acc", None,
                 "dot", "r[k] = acc[k] + a[4 * k] * b[4 * k] + a[4 * k + 1] * b[4 * k + 1] + a[4 * k + 2] * b[4 * k + 2]"
                 " + a[4 * k + 3] * b[4 * k + 3]", None,
                 "each 32-bit lane of acc plus the dot product of its four bytes of a and b")
        for q in [True, False]:
            for bq in [True, False]:
                acc, v = vv(t, q), vv(src, q)
                bt = vv(src, bq)
                n = 4 if bq else 2
                nm = "vdot%s_lane%s_%s" % ("q" if q else "", "q" if bq else "", t)
                line(nm, "dotprod", "(acc: %s, a: %s, b: %s, lane: const 0..=%d) -> %s" % (acc, v, bt, n - 1, acc),
                     "intr", "%s <d>.%s, <a>.%s, <b>.4b[<lane>]" % (mn, arr(t, q), arr(src, q)), "pure tied=acc",
                     None, "dot", "r[k] = acc[k] + a[4 * k] * b[4 * lane] + a[4 * k + 1] * b[4 * lane + 1]"
                     " + a[4 * k + 2] * b[4 * lane + 2] + a[4 * k + 3] * b[4 * lane + 3]", None,
                     "each 32-bit lane of acc plus the dot product of its four bytes of a and b's group `lane`")


def widening():
    section("Widening")

    def wcast(e, t):
        # (a 64-bit unsigned result from narrower lanes: in u64)
        return "((%s) as u64)" % e if dom(widen(t)) == "u64" else e

    for op, sign, mnb in [("addl", "+", "addl"), ("subl", "-", "subl")]:
        for t in I6:
            w = widen(t)
            mn = ("s" if kind(t) == "s" else "u") + mnb
            line("v%s_%s" % (op, t), "neon", "(a: %s, b: %s) -> %s" % (vv(t, False), vv(t, False), vv(w, True)), "intr",
                 "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(w, True), arr(t, False), arr(t, False)), "pure", None,
                 "lanes.%s" % op, "r[k] = a[k] %s b[k]" % sign, None, "lanewise a %s b, widened" % sign)
            n = lanes(w, True)
            line("v%s_high_%s" % (op, t), "neon", "(a: %s, b: %s) -> %s" % (vv(t, True), vv(t, True), vv(w, True)), "intr",
                 "%s2 <d>.%s, <a>.%s, <b>.%s" % (mn, arr(w, True), arr(t, True), arr(t, True)), "pure", None,
                 "lanes.%s" % op, "r[k] = a[k + %d] %s b[k + %d]" % (n, sign, n), None,
                 "lanewise a %s b of the high halves, widened" % sign)
    for op, sign, mnb in [("addw", "+", "addw"), ("subw", "-", "subw")]:
        for t in I6:
            w = widen(t)
            mn = ("s" if kind(t) == "s" else "u") + mnb
            line("v%s_%s" % (op, t), "neon", "(a: %s, b: %s) -> %s" % (vv(w, True), vv(t, False), vv(w, True)), "intr",
                 "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(w, True), arr(w, True), arr(t, False)), "pure", None,
                 "lanes.%s" % op, "r[k] = a[k] %s %s" % (sign, wcast("b[k]", t)), None,
                 "lanewise a %s b, b widened" % sign)
    for t in I6:
        w = widen(t)
        mn = ("s" if kind(t) == "s" else "u") + "mull"
        line("vmull_%s" % t, "neon", "(a: %s, b: %s) -> %s" % (vv(t, False), vv(t, False), vv(w, True)), "intr",
             "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(w, True), arr(t, False), arr(t, False)), "pure commutative", None,
             "lanes.mull", "r[k] = a[k] * b[k]", None, "lanewise a * b, widened (exact)")
        n = lanes(w, True)
        line("vmull_high_%s" % t, "neon", "(a: %s, b: %s) -> %s" % (vv(t, True), vv(t, True), vv(w, True)), "intr",
             "%s2 <d>.%s, <a>.%s, <b>.%s" % (mn, arr(w, True), arr(t, True), arr(t, True)), "pure commutative", None,
             "lanes.mull", "r[k] = a[k + %d] * b[k + %d]" % (n, n), None, "lanewise a * b of the high halves, widened")
    for op, sign in [("mlal", "+"), ("mlsl", "-")]:
        for t in I6:
            w = widen(t)
            mn = ("s" if kind(t) == "s" else "u") + op
            line("v%s_%s" % (op, t), "neon",
                 "(a: %s, b: %s, c: %s) -> %s" % (vv(w, True), vv(t, False), vv(t, False), vv(w, True)), "intr",
                 "%s <d>.%s, <b>.%s, <c>.%s" % (mn, arr(w, True), arr(t, False), arr(t, False)), "pure tied=a", None,
                 "lanes.%s" % op, "r[k] = a[k] %s %s" % (sign, wcast("b[k] * c[k]", t)), None,
                 "lanewise a %s b * c, the product widened" % sign)
            n = lanes(w, True)
            line("v%s_high_%s" % (op, t), "neon",
                 "(a: %s, b: %s, c: %s) -> %s" % (vv(w, True), vv(t, True), vv(t, True), vv(w, True)), "intr",
                 "%s2 <d>.%s, <b>.%s, <c>.%s" % (mn, arr(w, True), arr(t, True), arr(t, True)), "pure tied=a", None,
                 "lanes.%s" % op, "r[k] = a[k] %s %s" % (sign, wcast("b[k + %d] * c[k + %d]" % (n, n), t)), None,
                 "lanewise a %s b * c of the high halves, widened" % sign)
    for t, q in qd(I6):
        w = widen(t)
        mn = ("s" if kind(t) == "s" else "u") + "addlp"
        line(name("vpaddl{q}_{t}", t, q), "neon", "(a: %s) -> %s" % (vv(t, q), vv(w, q)), "intr",
             "%s <d>.%s, <a>.%s" % (mn, arr(w, q), arr(t, q)), "pure", None, "pairwise.addl",
             "r[k] = a[2 * k] + a[2 * k + 1]", None, "the sums of adjacent pairs of lanes, widened")
    for t, q in qd(I6):
        w = widen(t)
        mn = ("s" if kind(t) == "s" else "u") + "adalp"
        line(name("vpadal{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(w, q), vv(t, q), vv(w, q)), "intr",
             "%s <d>.%s, <b>.%s" % (mn, arr(w, q), arr(t, q)), "pure tied=a", None, "pairwise.adal",
             "r[k] = a[k] + %s" % wcast("(b[2 * k] + b[2 * k + 1])", t), None,
             "a plus the sums of adjacent pairs of b's lanes, widened")
    for t in I6:
        w = widen(t)
        mn = ("s" if kind(t) == "s" else "u") + "shll"
        line("vmovl_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, False), vv(w, True)), "intr",
             "%s <d>.%s, <a>.%s, #0" % (mn, arr(w, True), arr(t, False)), "pure", None, "lanes.movl", "r[k] = a[k]",
             None, "each lane widened")
        n = lanes(w, True)
        line("vmovl_high_%s" % t, "neon", "(a: %s) -> %s" % (vv(t, True), vv(w, True)), "intr",
             "%s2 <d>.%s, <a>.%s, #0" % (mn, arr(w, True), arr(t, True)), "pure", None, "lanes.movl",
             "r[k] = a[k + %d]" % n, None, "each lane of the high half widened")
        line("vshll_n_%s" % t, "neon", "(a: %s, n: const 0..=%d) -> %s" % (vv(t, False), bits(t) - 1, vv(w, True)), "intr",
             "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(w, True), arr(t, False)), "pure", None, "lanes.shll",
             "r[k] = %s" % ("(a[k] as u64) << (n as u64)" if dom(w) == "u64" else "a[k] << n"), None,
             "each lane widened, then shifted left by n (n < the lane's bits)")
    section("Narrowing, high halves")
    for op, mn_s, mn_u, types, sem_of in [
            ("movn", "xtn", "xtn", ["s16", "u16", "s32", "u32", "s64", "u64"], None),
            ("qmovn", "sqxtn", "uqxtn", ["s16", "u16", "s32", "u32", "s64", "u64"], None),
            ("qmovun", "sqxtun", "sqxtun", ["s16", "s32", "s64"], None)]:
        for t in types:
            nt = narrow(t) if op != "qmovun" else "u%d" % (bits(t) // 2)
            mn = (mn_s if kind(t) == "s" else mn_u) + "2"
            n = lanes(nt, False)
            line("v%s_high_%s" % (op, t), "neon", "(lo: %s, a: %s) -> %s" % (vv(nt, False), vv(t, True), vv(nt, True)),
                 "intr", "%s <d>.%s, <a>.%s" % (mn, arr(nt, True), arr(t, True)), "pure tied=lo", None,
                 "lanes.%s" % op, high_sem(op, t, nt), None,
                 "lo, then a narrowed as v%s_%s does, as the high half" % (op, t))
    for op, mn_s, mn_u, types in [("shrn", "shrn", "shrn", ["s16", "u16", "s32", "u32", "s64", "u64"]),
                                  ("rshrn", "rshrn", "rshrn", ["s16", "u16", "s32", "u32", "s64", "u64"]),
                                  ("qshrn", "sqshrn", "uqshrn", ["s16", "u16", "s32", "u32", "s64", "u64"]),
                                  ("qshrun", "sqshrun", "sqshrun", ["s16", "s32", "s64"])]:
        for t in types:
            nt = narrow(t) if op != "qshrun" else "u%d" % (bits(t) // 2)
            mn = (mn_s if kind(t) == "s" else mn_u) + "2"
            line("v%s_high_n_%s" % (op, t), "neon",
                 "(lo: %s, a: %s, n: const 1..=%d) -> %s" % (vv(nt, False), vv(t, True), bits(t) // 2, vv(nt, True)),
                 "intr", "%s <d>.%s, <a>.%s, #<n>" % (mn, arr(nt, True), arr(t, True)), "pure tied=lo", None,
                 "lanes.%s" % op, high_sem(op, t, nt), None,
                 "lo, then a shifted and narrowed as v%s_n_%s does, as the high half" % (op, t))


def high_sem(op, t, nt):
    """lo, then a's lanes narrowed by op (movn qmovn qmovun shrn rshrn
    qshrn qshrun): the semantics of a `_high` narrowing intrinsic."""
    n = lanes(nt, False)
    x = "a[k - %d]" % n
    u64 = dom(t) == "u64"
    sh = "(%s >> (n as u64))" % x if u64 else "(%s >> n)" % x
    if op == "movn":
        e = x
    elif op == "qmovn":
        e = "clamp(%s, %s, %s)" % (x, tmin(nt), tmax(nt)) if kind(t) == "s" else "min(%s, %s%s)" % (x, tmax(nt), "u64" if u64 else "")
    elif op == "qmovun":
        e = "clamp(%s, 0, %s)" % (x, tmax(nt))
    elif op == "shrn":
        e = sh
    elif op == "rshrn":
        e = ("(%s + ((%s >> ((n - 1) as u64)) & 1u64))" % (sh, x) if u64
             else "((%s + (1 << (n - 1))) >> n)" % x)
    elif op == "qshrn":
        e = "clamp(%s, %s, %s)" % (sh, tmin(nt), tmax(nt)) if kind(t) == "s" else "min(%s, %s%s)" % (sh, tmax(nt), "u64" if u64 else "")
    else:
        e = "clamp(%s, 0, %s)" % (sh, tmax(nt))
    if u64:
        e = "(%s as i64)" % e
    return "r[k] = if k < %d { lo[k] } else { %s }" % (n, e)


def lanes_dup_shift():
    section("Lane duplicates, shifts by vector")
    for t, q in qd(A + ["p8"]):
        for src_q in [False, True]:
            n = lanes(t, src_q)
            nm = "vdup%s_lane%s_%s" % ("q" if q else "", "q" if src_q else "", t)
            if bits(t) == 64 and not q:
                insn = "mov <d:d>, <a>.d[<lane>]"
            else:
                insn = "dup <d>.%s, <a>.%s[<lane>]" % (arr(t, q), letter(t))
            line(nm, "neon", "(a: %s, lane: const 0..=%d) -> %s" % (vv(t, src_q), n - 1, vv(t, q)), "intr", insn,
                 "pure", None, "splat.lane", "r[k] = a[lane]", None, "every lane a[lane]")
    for t, q in qd(I):
        mn = "sshl" if kind(t) == "s" else "ushl"
        st = vv("s" + t[1:], q)
        line(name("vshl{q}_{t}", t, q), "neon", "(a: %s, b: %s) -> %s" % (vv(t, q), st, vv(t, q)), "intr",
             "%s <d>.%s, <a>.%s, <b>.%s" % (mn, arr(t, q), arr(t, q), arr(t, q)), "pure", None, "lanes.shlv",
             "a[k] shifted left by b[k]'s low byte, signed (right when negative)", None,
             "lanewise a << b, by the signed low byte of b: right (%s) when negative" %
             ("arithmetic" if kind(t) == "s" else "logical"))


FAMILIES = [loads_stores, build_lanes, casts, arithmetic, compare, logic, shifts, horizontal, narrowing,
            permutes, bit_ops, crc, crypto, dotprod, widening, lanes_dup_shift]


def def_text():
    for f in FAMILIES:
        f()
    out = []
    last = None
    for sec, ln in LINES:
        if sec != last:
            out.append("")
            out.append("# ---- %s ----" % sec)
            last = sec
        out.append(ln)
    return "\n".join(out) + "\n"


# The mnemonics used with SIMD scalar operands (64-bit lanes of a 64-bit
# vector): a sibling line of the scalar class, the vector bits | 0x50000000.
SCALAR_MNS = set("""sqadd uqadd sqsub uqsub sshl ushl cmtst cmgt cmhi cmge cmhs cmeq cmle cmlt neg abs sqabs
    sqneg fcmeq fcmgt fcmge fcmlt fcmle sshr ushr ssra usra srshr urshr srsra ursra sri shl sli
    sqshlu sqshl uqshl""".split())
SCALAR_CLASS = {"same3": "same3s", "misc2": "misc2s", "misc2f": "misc2fs", "shrn": "shrns", "shl": "shls"}


def insn_text():
    instructions()
    for m, c, b, s in list(INSNS):
        if m in SCALAR_MNS and c in SCALAR_CLASS:
            INSNS.append((m, SCALAR_CLASS[c], "0x%08x" % (int(b, 16) | 0x50000000),
                          re.sub(r"V(\w)\.T\w*", r"<V>\1", s)))
    for m in ["neg"]:
        INSNS.append((m, "misc2s", "0x%08x" % (misc2(1, 11) | 0x50000000), "neg <V>d, <V>n"))
    w = max(len(m) for m, _, _, _ in INSNS)
    out = []
    seen = {}
    for m, c, b, s in INSNS:
        out.append("%s | %s | %s | %s" % (m, c, b, s))
    # (a mnemonic's lines must be consecutive)
    order = []
    for m, c, b, s in INSNS:
        if m not in seen:
            seen[m] = []
            order.append(m)
        seen[m].append("%s | %s | %s | %s" % (m, c, b, s))
    out = []
    for m in order:
        out.extend(seen[m])
    return "\n".join(out) + "\n"


MARK = "# ==== generated by tools/arch/a64_families.py (edit the script, then --write) ===="
END = "# ==== end of the generated lines ===="


def splice(path, text):
    with open(path) as f:
        old = f.read()
    if MARK in old:
        head = old[:old.index(MARK)]
        tail = old[old.index(END) + len(END):] if END in old else "\n"
    else:
        head = old.rstrip("\n") + "\n\n"
        tail = "\n"
    with open(path, "w") as f:
        f.write(head + MARK + "\n" + text.strip("\n") + "\n" + END + tail)


def main():
    args = sys.argv[1:]
    if "--write" in args:
        splice(os.path.join(ROOT, "compiler/arch/aarch64.def"), def_text())
        splice(os.path.join(ROOT, "compiler/arch/insn_a64.def"), insn_text())
        return
    sys.stdout.write(insn_text() if "--insn" in args else def_text())


if __name__ == "__main__":
    main()
