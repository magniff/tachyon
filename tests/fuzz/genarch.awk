# Writes a random tachyon program of intrinsics (0.19, docs/design/arch.md
# §6.7): expression trees over the intrinsics of the target's table
# (compiler/arch/aarch64.def or x86_64.def, and portable.def) and the
# portable vector operations (lanewise + - & | ^, splat, from_bits between
# vectors of a size), on loads from a slice at random offsets, near its
# end, and now and then one past it (the bounds check stops the program
# with 101, alike at every level); stores through the store intrinsics and
# `store`. Every value is folded into a hash that the program prints, so
# every optimization level must print the same. The tables are read as
# they are: each intrinsic T4 or T5 adds is drawn from the next run.
#
# usage: awk -v seed=N -f genarch.awk compiler/arch/portable.def compiler/arch/ARCH.def

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function rnd(n) { return int(rand() * n) }
function lbits(lt) { return substr(lt, 2) + 0 }
function is_lane(lt) { return lt ~ /^[ui](8|16|32|64)$/ }

# The key of type t: a portable vector (v16u8, v8u16, ...; the ACLE
# aliases are these), an opaque one (__m128i), an integer
# scalar; "" for any other (floats, tuples, slices: not drawn). SZ: its
# size in bytes (0 for a scalar).
function tkey(t,    v, parts, n, base, bits, lanes, lt) {
    SZ = 0
    if (is_lane(t)) return t
    if (t ~ /^v[0-9]+[ui][0-9]+$/) {
        match(t, /[ui][0-9]+$/)
        lt = substr(t, RSTART)
        if (!is_lane(lt)) return ""
        SZ = substr(t, 2, RSTART - 2) * lbits(lt) / 8
        return SZ == 8 || SZ == 16 ? t : ""
    }
    if (t ~ /^(u?int|poly)[0-9]+x[0-9]+_t$/) {
        v = substr(t, 1, length(t) - 2)
        base = substr(v, 1, 1) == "i" ? "i" : "u"
        sub(/^(u?int|poly)/, "", v)
        n = split(v, parts, "x")
        bits = parts[1] + 0; lanes = parts[2] + 0
        if (!is_lane(base bits)) return ""
        SZ = lanes * bits / 8
        return SZ == 8 || SZ == 16 ? "v" lanes base bits : ""
    }
    if (t == "__m128i") { SZ = 16; return t }
    return ""
}
function ksize(k) { SZ = 0; tkey(k); return SZ }
function is_portable_vec(k) { return k ~ /^v/ }

# k converted from expression e of key f.
function conv(e, f, k) {
    if (f == k) return e
    if (ksize(k) == 0) return "(" e " as " k ")"
    return k "::from_bits(" e ")"
}

# An index for a load or store of n elements of a slice of length len:
# in bounds, at its end, moving with j, or (now and then) one past it.
function index_expr(n, len,    r, c) {
    r = rnd(40)
    if (r == 0) { OOB = 1; return (len - n + 1) "" }
    if (r < 10) return (len - n) ""
    if (r < 20 && len - n >= 2) { c = rnd(len - n - 1); return "(j % 3 + " c ")" }
    return rnd(len - n + 1) ""
}

# A literal of scalar key k.
function literal(k,    r) {
    r = rnd(6)
    if (r == 0) return "(0 as " k ")"
    if (r == 1) return "(" k "::MAX)"
    if (r == 2 && substr(k, 1, 1) == "i") return "(" k "::MIN)"
    return "(" rnd(256) " as " k ")"
}

# A leaf of key k: a load, a parameter, a splat, an earlier value.
function leaf(k,    r, s, i, cand, nc) {
    s = ksize(k)
    if (s == 0) {
        r = rnd(4)
        if (r == 0) return "(s0 as " k ")"
        if (r == 1) return "(j as " k ")"
        return literal(k)
    }
    r = rnd(5)
    if (r == 0) {
        nc = 0
        for (i = 0; i < NT; i++) if (TSZ[i] == s) cand[nc++] = i
        if (nc > 0) { i = cand[rnd(nc)]; return conv("t" i, TK[i], k) }
    }
    if (r <= 1) return conv(s == 16 ? "x0" : "x2", s == 16 ? "v16u8" : "v8u8", k)
    if (r == 2 && is_portable_vec(k)) return k "::splat(" literal(lane_of(k)) ")"
    if (r == 2) return conv("v16u8::splat(" literal("u8") ")", "v16u8", k)
    return conv((s == 16 ? "v16u8" : "v8u8") "::load(src, " index_expr(s, SRCLEN) ")", s == 16 ? "v16u8" : "v8u8", k)
}

# The lane type of a portable vector key.
function lane_of(k) { match(k, /[ui][0-9]+$/); return substr(k, RSTART) }

# An expression of key k, depth at most d.
function expr(k, d,    r, s, i, cand, nc, op, ops, c) {
    if (d <= 0 || rnd(5) == 0) return leaf(k)
    s = ksize(k)
    r = rnd(10)
    if (r < 7) {
        nc = 0
        for (i = 0; i < NI; i++) if (I_rs[i] == s && I_mem[i] != "store") cand[nc++] = i
        if (nc > 0) { c = call(cand[rnd(nc)], d); return conv(c, I_rk[CALLED], k) }
    }
    if (s > 0 && is_portable_vec(k) && r < 9) {
        split("+ - & | ^", ops, " ")
        return "(" expr(k, d - 1) " " ops[1 + rnd(5)] " " expr(k, d - 1) ")"
    }
    if (s == 0 && r < 9) {
        split("^ & |", ops, " ")
        return "(" expr(k, d - 1) " " ops[1 + rnd(3)] " " expr(k, d - 1) ")"
    }
    return leaf(k)
}

# A call of intrinsic i (sets CALLED; its features are needed).
function call(i, d,    p, a, s, lo, hi, r) {
    NEED[I_feat[i]] = 1
    a = ""
    for (p = 1; p <= I_np[i]; p++) {
        a = a (p > 1 ? ", " : "")
        if (I_pk[i, p] == "const") {
            lo = I_lo[i, p]; hi = I_hi[i, p]
            r = rnd(4)
            a = a (r == 0 ? lo : r == 1 ? hi : lo + rnd(hi - lo + 1))
        } else if (I_pk[i, p] == "slice") {
            a = a (I_mem[i] == "store" ? "dst" : "src")
        } else if (I_pk[i, p] == "index") {
            a = a index_expr(I_mn[i], I_mem[i] == "store" ? DSTLEN : SRCLEN)
        } else {
            a = a expr(I_pk[i, p], d - 1)
        }
    }
    CALLED = i
    return MOD[i] I_name[i] "(" a ")"
}

BEGIN { srand(seed); NI = 0 }

/^[ \t]*#/ || /^[ \t]*$/ { next }
{
    split($0, col, / \| /)
    name = trim(col[1]); feats = trim(col[2]); sig = trim(col[3]); form = trim(col[4]); mem = trim(col[7])
    if (form ~ /^feat/ || form == "hint" || mem == "raw") next
    table = FILENAME; sub(/.*\//, "", table); sub(/\.def$/, "", table)
    lp = index(sig, "("); rp = index(sig, ")")
    params = substr(sig, lp + 1, rp - lp - 1)
    rest = trim(substr(sig, rp + 1))
    rt = rest ~ /^->/ ? trim(substr(rest, 3)) : ""
    np = params == "" ? 0 : split(params, ps, /, /)
    ok = 1
    memk = ""; ms = ""; mn = 0
    if (mem ~ /^(load|store)\(/) {
        memk = substr(mem, 1, index(mem, "(") - 1)
        split(substr(mem, index(mem, "(") + 1), ml, /[,)] */)
        ms = trim(ml[1]); mn = trim(ml[2]) + 0
    }
    for (p = 1; p <= np; p++) {
        pn = trim(substr(ps[p], 1, index(ps[p], ":") - 1))
        pt = trim(substr(ps[p], index(ps[p], ":") + 1))
        if (pt ~ /^const /) {
            I_pk[NI, p] = "const"
            split(substr(pt, 7), lohi, /\.\.=/)
            I_lo[NI, p] = lohi[1] + 0; I_hi[NI, p] = lohi[2] + 0
        } else if (pn == ms) {
            if (pt != "[u8]") ok = 0
            I_pk[NI, p] = "slice"
        } else if (p > 1 && I_pk[NI, p - 1] == "slice") {
            I_pk[NI, p] = "index"
        } else {
            I_pk[NI, p] = tkey(pt)
            if (I_pk[NI, p] == "") ok = 0
        }
    }
    rk = rt == "" ? "" : tkey(rt)
    if (rt != "" && rk == "") ok = 0
    if (rt == "" && memk != "store") ok = 0
    if (!ok) next
    I_name[NI] = name; I_np[NI] = np; I_rk[NI] = rk; I_rs[NI] = rt == "" ? -1 : ksize(rk)
    I_mem[NI] = memk; I_mn[NI] = mn
    I_feat[NI] = feats == "-" ? "" : feats
    MOD[NI] = table == "portable" ? "std::arch::" : "std::arch::" table "::"
    ARCH = table == "portable" ? ARCH : table
    NI++
}

END {
    SRCLEN = 24 + rnd(25); DSTLEN = 16 + rnd(17)
    NT = 0; OOB = 0
    body = ""
    nst = 3 + rnd(6)
    for (st = 0; st < nst; st++) {
        r = rnd(10)
        if (r < 6) {
            # a value: an intrinsic's result type, or a vector or scalar
            i = rnd(NI)
            k = I_rk[i] != "" ? I_rk[i] : "v16u8"
            if (rnd(4) == 0) k = rnd(2) ? "v16u8" : "u64"
            TK[NT] = k; TSZ[NT] = ksize(k)
            e = expr(k, 1 + rnd(3))
            body = body "    let t" NT ": " k " = " e ";\n"
            NT++
        } else if (r < 8) {
            nc = 0
            for (i = 0; i < NI; i++) if (I_mem[i] == "store") cand[nc++] = i
            if (nc > 0) body = body "    " call(cand[rnd(nc)], 2) ";\n"
            else body = body "    " conv(expr("v16u8", 2), "v16u8", "v16u8") ".store(dst, " index_expr(16, DSTLEN) ");\n"
        } else {
            body = body "    h = h * 31 + " conv(expr("u64", 2), "u64", "u64") ";\n"
        }
    }
    for (i = 0; i < NT; i++) {
        if (TSZ[i] == 16) body = body "    h = mix16(h, " conv("t" i, TK[i], "v16u8") ");\n"
        else if (TSZ[i] == 8) body = body "    h = mix8(h, " conv("t" i, TK[i], "v8u8") ");\n"
        else body = body "    h = h * 31 + (t" i " as u64);\n"
    }

    print "// Generated by tests/fuzz/genarch.awk (seed " seed ")."
    print "use std::arch::{has, detect};"
    if (index(body, "__m128i") > 0) print "use std::arch::x86_64::__m128i;"
    print ""
    print "fn mix16(h: u64, v: v16u8) -> u64 {"
    print "    var b: [u8; 16] = [0; 16];"
    print "    v.store(&b[..], 0);"
    print "    var x = h;"
    print "    for k in 0..16 { x = x * 1099511628211 + (b[k] as u64); }"
    print "    x"
    print "}"
    print ""
    print "fn mix8(h: u64, v: v8u8) -> u64 {"
    print "    var b: [u8; 8] = [0; 8];"
    print "    v.store(&b[..], 0);"
    print "    var x = h;"
    print "    for k in 0..8 { x = x * 1099511628211 + (b[k] as u64); }"
    print "    x"
    print "}"
    print ""
    print "fn kernel(src: [u8], dst: inout [u8], x0: v16u8, x2: v8u8, s0: u64, j: i64) -> u64 {"
    print "    var h: u64 = s0 ^ (j as u64);"
    printf "%s", body
    print "    h = mix8(mix16(h, x0), x2) + (src[0] as u64);"
    print "    dst[0] = dst[0] ^ (h as u8);"
    print "    h"
    print "}"
    print ""
    gh = ""; gd = ""; ng = 0
    for (f in NEED) {
        if (f == "") continue
        nf = split(f, fs, /,/)
        for (q = 1; q <= nf; q++) {
            fe = trim(fs[q])
            if (fe in SEEN) continue
            SEEN[fe] = 1
            gh = gh (ng ? " && " : "") "has(\"" ARCH "." fe "\")"
            gd = gd (ng ? " && " : "") "detect(\"" ARCH "." fe "\")"
            ng++
        }
    }
    off = rnd(9)
    print "fn run(src: inout [u8], dst: inout [u8]) {"
    print "    var s0: u64 = " (1 + rnd(1000000)) ";"
    print "    for j in 0..4 {"
    print "        let x0 = v16u8::load(src, " rnd(off + SRCLEN - 15) ");"
    print "        let x2 = v8u8::load(src, " rnd(off + SRCLEN - 7) ");"
    print "        let h = kernel(src[" off ".." (off + SRCLEN) "], dst, x0, x2, s0, j);"
    print "        println(f\"{h}\");"
    print "        s0 = s0 ^ (h >> 3);"
    print "        src[j] = src[j] ^ (h as u8);"
    print "    }"
    print "}"
    print ""
    print "fn main() -> i32 {"
    print "    var src: [u8; " (SRCLEN + 8) "] = [0; " (SRCLEN + 8) "];"
    print "    var x: u64 = " (1 + rnd(1000000)) ";"
    print "    for i in 0.." (SRCLEN + 8) " {"
    print "        x = x ^ (x << 13);"
    print "        x = x ^ (x >> 7);"
    print "        x = x ^ (x << 17);"
    print "        src[i] = (x >> 24) as u8;"
    print "    }"
    print "    var dst: [u8; " DSTLEN "] = [0; " DSTLEN "];"
    if (ng) {
        print "    if " gh " {"
        print "        run(&src[..], &dst[..]);"
        print "    } else if " gd " {"
        print "        run(&src[..], &dst[..]);"
        print "    } else {"
        print "        println(\"skip: the CPU lacks a feature\");"
        print "    }"
    } else {
        print "    run(&src[..], &dst[..]);"
    }
    print "    var d: u64 = 0;"
    print "    for i in 0.." DSTLEN " { d = d * 31 + (dst[i] as u64); }"
    print "    println(f\"dst {d}\");"
    print "    0"
    print "}"
}
