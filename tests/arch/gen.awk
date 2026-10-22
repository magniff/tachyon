# Writes the test programs of one intrinsic table (compiler/arch/*.def):
# every intrinsic against a scalar reference, on edge and random inputs at
# run time and on constant ones the optimizer may fold (0.19,
# docs/design/arch.md §6). tests/arch/gen.sh runs it; its header says what
# the programs do. POSIX awk (macOS's and Linux's alike).
#
# usage: awk -v table=aarch64 -v out=DIR -v nrandom=N -v refs=FILE -f gen.awk TABLE.def
#
#   table    aarch64, x86_64 or portable: the module (std::arch::TABLE, or
#            std::arch) and the prefix of has("TABLE.FEATURE")
#   out      where the programs go: out/arch_<a64|x86|portable>_<family>.vl
#   nrandom  random cases per intrinsic (besides the edges and the
#            exhaustive 8-bit ones)
#   refs     a file of `NAME PATH` lines: the hand-written references
#            (`fn ref_NAME` in tests/arch/ref/*.vl)
#
# On stdout, one line each: `program PATH`, `skip NAME: why` (a form with
# nothing to compare: has, detect, hints, raw pointers) and `error NAME:
# why` (an intrinsic the generator cannot test: its semantics is prose and
# it has no hand reference, or a type it does not know).

function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function rep(c, n,    s) { s = ""; while (n-- > 0) s = s c; return s }

# A deterministic generator (Park-Miller; exact in awk's doubles), so a
# program is the same with every awk.
function rnd(n) { RNG = (RNG * 16807) % 2147483647; return RNG % n }
function hash(s,    h, i) {
    h = 7
    for (i = 1; i <= length(s); i++) h = (h * 31 + index(CHARS, substr(s, i, 1)) + 1) % 2147483647
    return h
}
function hexd(n) { return substr("0123456789abcdef", n + 1, 1) }

# ---- Lane types ----
function lbits(lt) { return substr(lt, 2) + 0 }
function lfloat(lt) { return substr(lt, 1, 1) == "f" }
function lsigned(lt) { return substr(lt, 1, 1) == "i" }
# The type a reference computes in: i64 for integers narrower than 64
# bits, the lane's own type for 64-bit ones, f64 for floats.
function ldom(lt) {
    if (lfloat(lt)) return "f64"
    if (lbits(lt) == 64) return lt
    return "i64"
}
function lzero(lt) { return lfloat(lt) ? "0.0" : "0" }
function is_lane(lt) { return lt ~ /^[ui](8|16|32|64)$/ || lt ~ /^f(32|64)$/ }

# Type t of parameter `who` (a name, or "r" for the result): sets X_kind
# (vec, opaque, tuple, scalar, slice, or "" for unknown), X_lt (the lane
# type; an opaque type's view), X_n (lanes in all; a slice: 0), X_vt (the
# vector type of one register), X_vn (its lanes), X_tm (registers: 1, or
# a tuple's count), X_cons (an opaque type's own name, for from_bits).
function tres(t, who,    parts, n, base, bits, lanes, v) {
    X_kind = ""; X_lt = ""; X_n = 0; X_vt = ""; X_vn = 0; X_tm = 1; X_cons = ""
    if (t ~ /^\[.*\]$/) {
        X_lt = substr(t, 2, length(t) - 2)
        if (is_lane(X_lt)) X_kind = "slice"
        return
    }
    if (is_lane(t)) { X_kind = "scalar"; X_lt = t; X_n = 1; return }
    if (t ~ /^v[0-9]+[uif][0-9]+$/) {
        match(t, /[uif][0-9]+$/)
        X_lt = substr(t, RSTART); X_vn = substr(t, 2, RSTART - 2) + 0
        if (!is_lane(X_lt)) return
        X_kind = "vec"; X_vt = t; X_n = X_vn
        return
    }
    if (t ~ /^(u?int|float|poly)[0-9]+x[0-9]+(x[234])?_t$/) {
        v = substr(t, 1, length(t) - 2)
        base = substr(v, 1, 1) == "u" || substr(v, 1, 1) == "p" ? "u" : substr(v, 1, 1) == "f" ? "f" : "i"
        sub(/^(u?int|float|poly)/, "", v)
        n = split(v, parts, "x")
        bits = parts[1] + 0; lanes = parts[2] + 0
        X_lt = base bits
        if (!is_lane(X_lt)) return
        X_vt = "v" lanes X_lt; X_vn = lanes
        X_tm = n == 3 ? parts[3] + 0 : 1
        X_kind = X_tm > 1 ? "tuple" : "vec"
        X_n = lanes * X_tm
        return
    }
    if (t ~ /^__m(128|256)[id]?$/) {
        bits = substr(t, 4, 3) + 0
        X_lt = t ~ /i$/ ? "u8" : t ~ /d$/ ? "f64" : "f32"
        if (who in VIEW) X_lt = VIEW[who]
        else if ("*" in VIEW && !lfloat(X_lt)) X_lt = VIEW["*"]
        X_vn = bits / lbits(X_lt); X_n = X_vn
        X_vt = "v" X_vn X_lt
        X_cons = t
        X_kind = "opaque"
        return
    }
}

# ---- The semantics column ----

# A trailing note, `(bytes)`, `(i16 lanes)`, `(a, b: i16 lanes; r: i8
# lanes)`, says the lanes an opaque type (__m128i, ...) is read as; any
# other trailing words in parentheses (`(wrapping)`) are a comment.
# Returns the semantics without the note and fills VIEW.
function strip_note(s,    note, items, n, i, it, names, nn, j, view, c, depth) {
    split("", VIEW)
    depth = 0
    if (s !~ /\)$/) return s
    # (the parenthesis that opens the last group)
    for (i = length(s); i > 0; i--) {
        c = substr(s, i, 1)
        if (c == ")") depth++
        else if (c == "(") { depth--; if (depth == 0) break }
    }
    depth = 0
    if (i <= 1 || substr(s, i - 1, 1) != " ") return s
    note = substr(s, i + 1, length(s) - i - 1)
    if (note !~ /^[a-z0-9 ,;:]+$/) return s
    n = split(note, items, /; */)
    for (i2 = 1; i2 <= n; i2++) {
        it = trim(items[i2]); names = "*"
        if (index(it, ":") > 0) { names = substr(it, 1, index(it, ":") - 1); it = trim(substr(it, index(it, ":") + 1)) }
        view = ""
        if (it == "bytes") view = "u8"
        else if (it ~ /^[uif](8|16|32|64) lanes$/) view = substr(it, 1, index(it, " ") - 1)
        if (view == "") continue
        nn = split(names, parts2, /, */)
        for (j = 1; j <= nn; j++) VIEW[trim(parts2[j])] = view
    }
    return trim(substr(s, 1, length(s) - length(note) - 2))
}

# Whether expression e names nothing but the parameters, k, and what the
# programs' prelude and the language give (max, min, abs, if, as, types).
function idents_ok(e,    rest, tok) {
    rest = e
    while (match(rest, /[A-Za-z_][A-Za-z_0-9]*|[0-9][0-9A-Za-z_.]*/)) {
        tok = substr(rest, RSTART, RLENGTH); rest = substr(rest, RSTART + RLENGTH)
        if (tok ~ /^[0-9]/) continue
        if (tok in ALLOWED || tok in PIDX) continue
        BADTOK = tok
        return 0
    }
    return 1
}

# Translates the semantics into SEM_kind (lane: `r[k] = E`; scalar: `r =
# E`; reduce: `r = max|min|sum over k of E`, SEM_op; store: `S[I] = E`,
# SEM_slice, SEM_index), SEM_expr; SEM_kind "" when it is prose.
# `X[A..B]` is the elements from A: `r = s[i..i + 16]` is `r[k] = s[i + k]`
# and `s[i..i + 16] = v` is `s[i + k] = v[k]`.
function sem_translate(s,    e, p1, p2, lhs, idx) {
    SEM_kind = ""; SEM_expr = ""; SEM_op = ""; SEM_slice = ""; SEM_index = ""
    if (substr(s, 1, 7) == "r[k] = ") {
        SEM_kind = "lane"; SEM_expr = substr(s, 8)
    } else if (s ~ /^r = (max|min|sum) over k of /) {
        SEM_kind = "reduce"; SEM_op = substr(s, 5, 3); SEM_expr = substr(s, 19)
    } else if (substr(s, 1, 4) == "r = ") {
        e = substr(s, 5)
        if (e ~ /^[A-Za-z_][A-Za-z_0-9]*\[[^]]*\.\.[^]]*\]$/) {
            p1 = index(e, "["); idx = substr(e, p1 + 1, length(e) - p1 - 1)
            SEM_kind = "lane"
            SEM_expr = substr(e, 1, p1) "(" substr(idx, 1, index(idx, "..") - 1) ") + k]"
        } else {
            SEM_kind = "scalar"; SEM_expr = e
        }
    } else if (s ~ /^[A-Za-z_][A-Za-z_0-9]*\[/ && index(s, "] = ") > 0) {
        p1 = index(s, "["); p2 = index(s, "] = ")
        lhs = substr(s, 1, p1 - 1)
        if (!(lhs in PIDX) || P_kind[PIDX[lhs]] != "slice") return
        idx = substr(s, p1 + 1, p2 - p1 - 1)
        e = substr(s, p2 + 4)
        if (index(idx, "..") > 0) {
            idx = "(" substr(idx, 1, index(idx, "..") - 1) ") + k"
            if (e in PIDX) e = e "[k]"
        }
        SEM_kind = "store"; SEM_slice = lhs; SEM_index = idx; SEM_expr = e
    }
    if (SEM_kind != "" && !(idents_ok(SEM_expr) && idents_ok(SEM_index))) SEM_kind = ""
}

# ---- Literals (the constant cases) ----

# Lane type lt, pattern e: an edge 0..9 (as the programs' edge_bits and
# float_edge), or -1 for a random value. Sets L_lane (an expression of
# type lt) and L_dom (the same value in the reference's type).
function literal(lt, e,    b, nd, h, i, m, x, s) {
    if (lfloat(lt)) {
        b = lbits(lt)
        if (e == 0) s = "0.0"
        else if (e == 1) s = "-0.0"
        else if (e == 2) s = "1.0"
        else if (e == 3) s = "-1.0"
        else if (e == 4) s = "(1.0 / 0.0)"
        else if (e == 5) s = "(-1.0 / 0.0)"
        else if (e == 6) s = "(0.0 / 0.0)"
        else if (e == 7) s = b == 32 ? "1.401298464324817e-45" : "4.9406564584124654e-324"
        else if (e == 8) s = b == 32 ? "3.4028234663852886e38" : "1.7976931348623157e308"
        else if (e == 9) s = b == 32 ? "1.1754943508222875e-38" : "2.2250738585072014e-308"
        else {
            # m * 2^x with m of 24 bits: exact in f32 and f64
            m = rnd(16777216); x = rnd(48) - 24
            while (x > 0) { m *= 2; x-- }
            while (x < 0) { m /= 2; x++ }
            s = sprintf("%.17g", rnd(2) ? -m : m)
            if (s !~ /[.e]/) s = s ".0"
            else if (s !~ /\./) sub(/e/, ".0e", s)
        }
        L_lane = "(" s " as " lt ")"
        L_dom = b == 32 ? "(" L_lane " as f64)" : L_lane
        return
    }
    b = lbits(lt); nd = b / 4
    if (e == 0) h = "0"
    else if (e == 1) h = "1"
    else if (e == 2) h = "2"
    else if (e == 3) h = "7" rep("f", nd - 1)
    else if (e == 4) h = "8" rep("0", nd - 1)
    else if (e == 5) h = "8" rep("0", nd - 2) "1"
    else if (e == 6) h = rep("f", nd - 1) "e"
    else if (e == 7) h = rep("f", nd)
    else if (e == 8) h = rep("5", nd)
    else if (e == 9) h = rep("3", nd)
    else { h = ""; for (i = 0; i < nd; i++) h = h hexd(rnd(16)) }
    if (b <= 32) {
        # (a decimal literal; a signed type's MIN stays a cast, which
        # no literal of the type spells)
        x = 0
        for (i = 1; i <= length(h); i++) x = x * 16 + index("0123456789abcdef", substr(h, i, 1)) - 1
        m = 2 ^ (b - 1)
        if (lsigned(lt) && x >= m) x -= 2 * m
        if (x != -m) { L_lane = sprintf("%d", x); L_dom = L_lane; return }
    }
    L_lane = lt == "u64" ? "0x" h "u64" : "(0x" h "u64 as " lt ")"
    L_dom = ldom(lt) == lt ? L_lane : "(" L_lane " as " ldom(lt) ")"
}

# ---- Code of one intrinsic ----

# The code of intrinsic NAME (the line's columns are in globals): its
# reference (generated, unless a hand-written one exists), the run-time
# test, the constant test. Appends to BODY; returns 0 when it cannot.
function intrinsic(    i, j, p, np, ps, nt, pn, pt, m, mlist, cm, e, call, ninputs, n8, x8p, lx, ne, nx, ncase, nq, q, qv, cl, cv, args, sargs, dargs, refargs, code, ref, hasref, sfx, lits, f, combos, li, ol, guardp, pick) {
    split("", PIDX); NP = 0
    lp = index(SIG, "("); rp = index(SIG, ")")
    params = substr(SIG, lp + 1, rp - lp - 1)
    rest = trim(substr(SIG, rp + 1))
    RT = ""
    if (rest ~ /^->/) RT = trim(substr(rest, 3))
    np = params == "" ? 0 : split(params, ps, /, /)
    SEMX = strip_note(SEM)
    # Parameters.
    for (i = 1; i <= np; i++) {
        pn = trim(substr(ps[i], 1, index(ps[i], ":") - 1))
        pt = trim(substr(ps[i], index(ps[i], ":") + 1))
        NP++; P_name[NP] = pn; PIDX[pn] = NP
        if (pt ~ /^const /) {
            P_kind[NP] = "const"
            split(substr(pt, 7), lohi, /\.\.=/)
            P_lo[NP] = lohi[1] + 0; P_hi[NP] = lohi[2] + 0
            continue
        }
        tres(pt, pn)
        if (X_kind == "") { ERR = "parameter " pn ": type " pt " is not one the generator knows"; return 0 }
        P_kind[NP] = X_kind; P_lt[NP] = X_lt; P_n[NP] = X_n; P_vt[NP] = X_vt; P_vn[NP] = X_vn; P_tm[NP] = X_tm; P_cons[NP] = X_cons; P_type[NP] = pt
    }
    # The memory column: the slice, its index (the next parameter), the
    # lanes it touches.
    MEMK = ""; MS = 0; MLN = 0; ML = 0
    if (MEM ~ /^(load|store)\(/) {
        MEMK = substr(MEM, 1, index(MEM, "(") - 1)
        split(substr(MEM, index(MEM, "(") + 1), mlist, /[,)] */)
        MS = PIDX[trim(mlist[1])]
        if (MS == 0 || P_kind[MS] != "slice" || MS == NP) { ERR = "memory " MEM ": no slice parameter followed by its index"; return 0 }
        P_kind[MS + 1] = "index"
        MLN = (trim(mlist[2]) + 0) * 8 / lbits(P_lt[MS])
        ML = 2 * MLN + 3
        P_n[MS] = ML
    } else if (MEM != "none") {
        SKIP = "memory " MEM ": not generated"
        return 0
    }
    # The result.
    if (RT == "") {
        R_kind = "none"
        if (MEMK != "store") { ERR = "no result and no store: nothing to compare"; return 0 }
    } else {
        tres(RT, "r")
        if (X_kind == "" || X_kind == "slice") { ERR = "result type " RT " is not one the generator knows"; return 0 }
        R_kind = X_kind; R_lt = X_lt; R_n = X_n; R_vt = X_vt; R_vn = X_vn; R_tm = X_tm
    }
    CAST = FORM == "cast"
    if (CAST && (R_kind == "scalar" || NP != 1 || P_kind[1] == "scalar")) { ERR = "a cast of one vector is the only kind compared by bytes"; return 0 }
    # The reference.
    ref = "ref_" NAME
    hasref = NAME in REF
    if (!CAST && !hasref) {
        sem_translate(SEMX)
        if (SEM_kind == "") {
            ERR = "the semantics is not an expression (" (BADTOK != "" ? "`" BADTOK "`" : "its form") "): write fn " ref " in tests/arch/ref/ (tests/arch/gen.sh says how)"
            BADTOK = ""
            return 0
        }
        if (SEM_kind == "store" && R_kind != "none") { ERR = "a store semantics with a result"; return 0 }
        if ((SEM_kind == "lane") != (R_kind != "scalar" && R_kind != "none")) { ERR = "the semantics gives " (SEM_kind == "lane" ? "lanes" : "one value") ", the result is " (R_kind == "scalar" ? "one value" : "a vector"); return 0 }
        BODY = BODY "// " NAME ": " SEM "\n"
        BODY = BODY "fn " ref "(" ref_params() ") " (R_kind == "none" ? "" : "-> " ldom(R_lt) " ") "{\n"
        if (SEM_kind == "lane" || SEM_kind == "scalar") BODY = BODY "    (" SEM_expr ") as " ldom(R_lt) "\n"
        else if (SEM_kind == "reduce") {
            j = first_vector()
            if (j == 0) { ERR = "a reduction over k without a vector parameter"; return 0 }
            BODY = BODY "    var acc = { let k: i64 = 0; " SEM_expr " };\n"
            BODY = BODY "    for k in 1.." P_n[j] " {\n"
            if (SEM_op == "sum") BODY = BODY "        acc = acc + (" SEM_expr ");\n"
            else BODY = BODY "        acc = " SEM_op "(acc, " SEM_expr ");\n"
            BODY = BODY "    }\n    acc as " ldom(R_lt) "\n"
        } else {
            BODY = BODY "    for k in 0.." MLN " {\n        " SEM_slice "[" SEM_index "] = (" SEM_expr ") as " ldom(P_lt[MS]) ";\n    }\n"
        }
        BODY = BODY "}\n\n"
    } else if (hasref) {
        USED[REF[NAME]] = 1
    }
    # The constants: every value of a small range, else the ends, the
    # middle and three more; at most 64 combinations.
    nq = 1; NC = 0
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] != "const") continue
        NC++; CP[NC] = p
        split("", seen); CVN[NC] = 0
        if (P_hi[p] - P_lo[p] < 16) {
            for (j = P_lo[p]; j <= P_hi[p]; j++) CV[NC, ++CVN[NC]] = j
        } else {
            CV[NC, ++CVN[NC]] = P_lo[p]; CV[NC, ++CVN[NC]] = P_lo[p] + 1
            CV[NC, ++CVN[NC]] = int((P_lo[p] + P_hi[p]) / 2)
            CV[NC, ++CVN[NC]] = P_hi[p] - 1; CV[NC, ++CVN[NC]] = P_hi[p]
            for (j = 0; j < 3; j++) CV[NC, ++CVN[NC]] = P_lo[p] + rnd(P_hi[p] - P_lo[p] + 1)
        }
        nq *= CVN[NC]
    }
    combos = nq
    if (nq > 64) { nq = 0; for (j = 1; j <= NC; j++) if (CVN[j] > nq) nq = CVN[j] }
    # (combination q: value index of constant j)
    for (q = 0; q < nq; q++) {
        qv = q
        for (j = 1; j <= NC; j++) {
            if (combos > 64) QI[q, j] = q % CVN[j] + 1
            else { QI[q, j] = qv % CVN[j] + 1; qv = int(qv / CVN[j]) }
        }
    }
    # The inputs: edges (every pair for the first two), mixed edges,
    # random values, and every 8-bit value (pair) of the first two 8-bit
    # inputs.
    ninputs = 0; n8 = 0; lx = 0
    for (p = 1; p <= NP; p++) {
        X8[p] = -1
        if (P_kind[p] == "const" || P_kind[p] == "index" || P_kind[p] == "slice") continue
        ninputs++
        if (!lfloat(P_lt[p]) && lbits(P_lt[p]) == 8 && n8 < 2) { X8[p] = n8++; if (P_n[p] > lx) lx = P_n[p] }
    }
    ne = ninputs == 0 ? 1 : ninputs == 1 ? 10 : 100
    nx = n8 == 1 ? int((256 + lx - 1) / lx) : n8 == 2 ? int((65536 + lx - 1) / lx) : 0
    nr = NRANDOM
    if (MEMK != "") { nx = 0; nr = int(NRANDOM / 50) + 4 }
    ncase = ne + 4 + nr + nx

    # check_N: the result o against the reference.
    sfx = NTEST
    code = "fn check_" sfx "(" check_params() "o: [" (R_kind == "none" ? P_lt[MS] : CAST ? "u8" : R_lt) "], nbad: i64) -> i64 {\n"
    if (CAST) {
        code = code "    for k in 0.." (P_n[1] * lbits(P_lt[1]) / 8) " {\n        if x[k] != o[k] {\n"
        code = code fail_lines("k", "o[k]", "x[k]") "            return 1;\n        }\n    }\n    0\n}\n\n"
    } else if (R_kind == "none") {
        code = code "    var e: [" ldom(P_lt[MS]) "; " ML "] = [" lzero(P_lt[MS]) "; " ML "];\n"
        code = code "    for j in 0.." ML " { e[j] = " pv(MS) "[j]; }\n"
        code = code "    " ref "(" ref_args("&e[..]", "") ");\n"
        code = code "    for j in 0.." ML " {\n        if !" same(P_lt[MS], "e[j]", "o[j]") " {\n"
        code = code fail_lines("j", "o[j]", "e[j] as " P_lt[MS]) "            return 1;\n        }\n    }\n    0\n}\n\n"
    } else if (R_kind == "scalar") {
        code = code "    let want = " ref "(" ref_args("", "") ");\n"
        code = code "    if !" same(R_lt, "want", "o[0]") " {\n"
        code = code fail_lines("0", "o[0]", "want as " R_lt) "        return 1;\n    }\n    0\n}\n\n"
    } else {
        code = code "    for k in 0.." R_n " {\n        let want = " ref "(" ref_args("", "k") ");\n"
        code = code "        if !" same(R_lt, "want", "o[k]") " {\n"
        code = code fail_lines("k", "o[k]", "want as " R_lt) "            return 1;\n        }\n    }\n    0\n}\n\n"
    }
    BODY = BODY code

    # run_N: lane-typed copies of the inputs, the call (one per
    # combination of constants), the check.
    code = "fn run_" sfx "(q: i64, " run_params() "nbad: i64) -> i64 {\n"
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const" || P_kind[p] == "index") continue
        code = code "    var t" p ": [" P_lt[p] "; " P_n[p] "] = [" lzero(P_lt[p]) "; " P_n[p] "];\n"
        code = code "    for k in 0.." P_n[p] " { t" p "[k] = " pv(p) "[k] as " P_lt[p] "; }\n"
    }
    if (CAST) code = code "    var x: [u8; " (P_n[1] * lbits(P_lt[1]) / 8) "] = [0; " (P_n[1] * lbits(P_lt[1]) / 8) "];\n    " bytes_of(P_n[1] * lbits(P_lt[1]) / 8, build(1, "t1[..]")) ".store(&x[..], 0);\n"
    if (R_kind != "none") code = code "    var o: [" (CAST ? "u8" : R_lt) "; " out_n() "] = [" (CAST ? "0" : lzero(R_lt)) "; " out_n() "];\n"
    for (q = 0; q < nq; q++) {
        args = call_args(q, "run")
        code = code "    if q == " q " {\n" store_result(MOD NAME "(" args ")", "        ") "        return check_" sfx "(" check_args(q, "run") (R_kind == "none" ? "t" MS "[..]" : "o[..]") ", nbad);\n    }\n"
    }
    code = code "    0\n}\n\n"
    BODY = BODY code

    # fold_N: the same checks on constant inputs, which -O2 may fold:
    # the edges (all lanes alike), then random lanes; the first, middle
    # and last combination of constants.
    nlit = 0
    code = "fn fold_" sfx "(nbad: i64) -> i64 {\n    var bad: i64 = 0;\n"
    if (MEMK == "") {
        split("0 7 4 7 -1 -1 -1", lits, " ")
        split("0 1 3 7 -1 -1 -1", lits2, " ")
        for (li = 1; li <= 7; li++) {
            for (ol = 0; ol < 3; ol++) {
                q = ol == 0 ? 0 : ol == 1 ? int(nq / 2) : nq - 1
                if ((ol == 1 && (q == 0)) || (ol == 2 && (q == 0 || q == int(nq / 2)))) continue
                code = code "    {\n"
                pick = 0
                for (p = 1; p <= NP; p++) {
                    if (P_kind[p] == "const") continue
                    e = lits[li] + 0
                    if (pick == 1) e = lits2[li] + 0
                    else if (pick > 1 && e >= 0) e = (e + pick) % 10
                    pick++
                    dargs = ""; LITLANES[p] = ""
                    for (j = 0; j < P_n[p]; j++) {
                        literal(P_lt[p], e)
                        dargs = dargs (j ? ", " : "") L_dom
                        LITLANES[p] = LITLANES[p] (j ? ", " : "") L_lane
                    }
                    code = code "        let " pv(p) ": [" ldom(P_lt[p]) "; " P_n[p] "] = [" dargs "];\n"
                }
                if (CAST) code = code "        var x: [u8; " (P_n[1] * lbits(P_lt[1]) / 8) "] = [0; " (P_n[1] * lbits(P_lt[1]) / 8) "];\n        " bytes_of(P_n[1] * lbits(P_lt[1]) / 8, lit_build(1)) ".store(&x[..], 0);\n"
                code = code "        var o: [" (CAST ? "u8" : R_lt) "; " out_n() "] = [" (CAST ? "0" : lzero(R_lt)) "; " out_n() "];\n"
                code = code store_result(MOD NAME "(" call_args(q, "lit") ")", "        ")
                code = code "        bad += check_" sfx "(" check_args(q, "lit") "o[..], nbad + bad);\n    }\n"
                nlit++
            }
        }
    }
    code = code "    bad\n}\n\n"
    BODY = BODY code

    # test_N: the run-time cases, then the constant ones.
    code = "fn test_" sfx "() -> i64 {\n    var rng = Rng { s: " (hash(NAME) + 1) " };\n    var bad: i64 = 0;\n    var cases: i64 = 0;\n"
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const" || P_kind[p] == "index") continue
        code = code "    var " pv(p) ": [" ldom(P_lt[p]) "; " P_n[p] "] = [" lzero(P_lt[p]) "; " P_n[p] "];\n"
    }
    code = code "    for c in 0.." ncase " {\n"
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const" || P_kind[p] == "index") continue
        code = code "        " fill_call(p, p == MS ? "1000000000" : "c", ne, nr, (X8[p] >= 0 ? X8[p] : -1), n8, lx) ";\n"
    }
    ind = "        "
    if (MEMK != "") { code = code "        for " pv(MS + 1) " in 0.." (ML - MLN + 1) " {\n"; ind = "            " }
    code = code ind "for q in 0.." nq " {\n" ind "    bad += run_" sfx "(q, " run_args() "bad);\n" ind "    cases += 1;\n" ind "}\n"
    if (MEMK != "") code = code "        }\n"
    code = code "    }\n    bad += fold_" sfx "(bad);\n"
    code = code "    println(f\"" NAME ": {cases} run-time cases, " nlit " constant ones\");\n    bad\n}\n\n"
    BODY = BODY code
    return 1
}

function pv(p) { return "p_" P_name[p] }

function first_vector(    p) {
    for (p = 1; p <= NP; p++) if (P_kind[p] == "vec" || P_kind[p] == "opaque" || P_kind[p] == "tuple") return p
    return 0
}

function out_n() { return CAST ? R_n * lbits(R_lt) / 8 : R_kind == "scalar" ? 1 : R_n }

# The reference's parameters: a vector or a slice is its lanes ([D]), a
# scalar its value (D), a constant or an index an i64; the store's slice
# is `&[D]`; then `k: i64` for a vector result.
function ref_params(    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        s = s (p > 1 ? ", " : "") P_name[p] ": "
        if (P_kind[p] == "const" || P_kind[p] == "index") s = s "i64"
        else if (P_kind[p] == "scalar") s = s ldom(P_lt[p])
        else if (P_kind[p] == "slice" && R_kind == "none") s = s "inout [" ldom(P_lt[p]) "]"
        else s = s "[" ldom(P_lt[p]) "]"
    }
    if (R_kind != "none" && R_kind != "scalar") s = s (NP ? ", " : "") "k: i64"
    return s
}

# The reference's arguments in check_N: `slice` for the store's slice,
# then k.
function ref_args(slice, k,    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        s = s (p > 1 ? ", " : "")
        if (P_kind[p] == "scalar") s = s pv(p) "[0]"
        else if (P_kind[p] == "slice" && slice != "") s = s slice
        else s = s pv(p)
    }
    if (k != "") s = s (NP ? ", " : "") k
    return s
}

# check_N's parameters (every constant's value, the index, the inputs'
# lanes in the reference's types; a cast: x, the input's bytes), with a
# trailing ", ".
function check_params(    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const" || P_kind[p] == "index") s = s pv(p) ": i64, "
        else s = s pv(p) ": [" ldom(P_lt[p]) "], "
    }
    if (CAST) s = s "x: [u8], "
    return s
}
function check_args(q, how,    p, s, j) {
    s = ""
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const") s = s const_value(q, p) ", "
        else if (P_kind[p] == "index") s = s pv(p) ", "
        else s = s pv(p) (how == "lit" ? "[..]" : "") ", "
    }
    if (CAST) s = s "x[..], "
    return s
}
function const_value(q, p,    j) {
    for (j = 1; j <= NC; j++) if (CP[j] == p) return CV[j, QI[q, j]]
    return "0"
}

# run_N's parameters and test_N's arguments for them.
function run_params(    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const") continue
        if (P_kind[p] == "index") s = s pv(p) ": i64, "
        else s = s pv(p) ": [" ldom(P_lt[p]) "], "
    }
    return s
}
function run_args(    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const") continue
        if (P_kind[p] == "index") s = s pv(p) ", "
        else s = s pv(p) "[..], "
    }
    return s
}

# Parameter p's register value from lane-typed elements `src` (a slice
# expression).
function build(p, src,    j, s) {
    if (P_kind[p] == "vec") return P_vt[p] "::load(" src ", 0)"
    if (P_kind[p] == "opaque") return P_cons[p] "::from_bits(" P_vt[p] "::load(" src ", 0))"
    s = "("
    for (j = 0; j < P_tm[p]; j++) s = s (j ? ", " : "") P_vt[p] "::load(" src ", " (j * P_vn[p]) ")"
    return s ")"
}
# The same from the literal lanes of the constant case.
function lit_build(p,    j, s, n, lanes, part, k) {
    if (P_kind[p] == "vec") return P_vt[p] "(" LITLANES[p] ")"
    if (P_kind[p] == "opaque") return P_cons[p] "::from_bits(" P_vt[p] "(" LITLANES[p] "))"
    n = split(LITLANES[p], lanes, /, /)
    s = "("
    for (j = 0; j < P_tm[p]; j++) {
        part = ""
        for (k = 1; k <= P_vn[p]; k++) part = part (k > 1 ? ", " : "") lanes[j * P_vn[p] + k]
        s = s (j ? ", " : "") P_vt[p] "(" part ")"
    }
    return s ")"
}
# A vector of n bytes as the byte vector of its size (for casts).
function bytes_of(n, v) { return "v" n "u8::from_bits(" v ")" }

# The intrinsic's arguments for combination q: from run_N's copies, or
# (how "lit") the constant case's literals.
function call_args(q, how,    p, s) {
    s = ""
    for (p = 1; p <= NP; p++) {
        s = s (p > 1 ? ", " : "")
        if (P_kind[p] == "const") s = s const_value(q, p)
        else if (P_kind[p] == "index") s = s pv(p)
        else if (P_kind[p] == "slice") s = s (MEMK == "store" ? "&t" p "[..]" : "t" p "[..]")
        else if (P_kind[p] == "scalar") s = s (how == "lit" ? LITLANES[p] : "t" p "[0]")
        else s = s (how == "lit" ? lit_build(p) : build(p, "t" p "[..]"))
    }
    return s
}

# The statement keeping the result c in o.
function store_result(c, ind,    j, s) {
    if (CAST) return ind bytes_of(R_n * lbits(R_lt) / 8, c) ".store(&o[..], 0);\n"
    if (R_kind == "none") return ind c ";\n"
    if (R_kind == "scalar") return ind "o[0] = " c ";\n"
    if (R_kind == "vec") return ind c ".store(&o[..], 0);\n"
    if (R_kind == "opaque") return ind R_vt "::from_bits(" c ").store(&o[..], 0);\n"
    s = ind "let r = " c ";\n"
    for (j = 0; j < R_tm; j++) s = s ind "r." j ".store(&o[..], " (j * R_vn) ");\n"
    return s
}

# Whether the reference's `want` (its type) and the result's `got` (lane
# type lt) agree; floats: NaN is any NaN, and zeros by their sign.
function same(lt, want, got) {
    if (lfloat(lt)) return "same_float((" want " as " lt ") as f64, " got " as f64)"
    return "((" want " as " lt ") == " got ")"
}

# The lines printing a failure (the first ten of a program).
function fail_lines(k, got, want,    p, s) {
    s = "            if nbad < 10 {\n                let fail_got = " got ";\n                let fail_want = " want ";\n                print(\"FAIL " NAME "\");\n"
    for (p = 1; p <= NP; p++) {
        if (P_kind[p] == "const" || P_kind[p] == "index") s = s "                print(f\" " P_name[p] "={" pv(p) "}\");\n"
        else s = s "                print(\" " P_name[p] "=\");\n                show(" pv(p) ");\n"
    }
    s = s "                println(f\": " (CAST ? "byte" : R_kind == "none" ? "element" : R_kind == "scalar" ? "result" : "lane") " {" k "}: got {fail_got}, want {fail_want}\");\n            }\n"
    return s
}

# Filling parameter p's lanes for case c (see the prelude's fill_*).
function fill_call(p, c, ne, nr, x8, n8, lx,    lt, f) {
    lt = P_lt[p]
    f = lfloat(lt) ? "fill_float" : ldom(lt) == "u64" ? "fill_u64" : "fill_int"
    return f "(&rng, " c ", " (p - 1) ", &" pv(p) "[..], " lbits(lt) ", " (lsigned(lt) ? "true" : "false") ", " ne ", " nr ", " x8 ", " n8 ", " (lx ? lx : 1) ")"
}

# ---- Programs ----

function flush(    f, i, r, u, ot) {
    if (NTESTS == 0) return
    f = OUT "/arch_" PREFIX "_" FAMILY (PART > 1 ? "_" PART : "") ".vl"
    print "// Generated by tests/arch/gen.sh from compiler/arch/" TABLE ".def (do not edit):" >f
    print "// the " FAMILY_TITLE " intrinsics against their references." >f
    print "use std::arch::{has, detect};" >f
    # (the opaque x86 types the program names)
    u = ""
    split("__m128i __m128d __m128 __m256i __m256d __m256", ot, " ")
    for (i = 1; i <= 6; i++) if (index(BODY, ot[i] "::") > 0) u = u (u == "" ? "" : ", ") ot[i]
    if (u != "") print "use std::arch::x86_64::{" u "};" >f
    print "" >f
    printf "%s", PRELUDE >f
    for (r in USED) {
        while ((getline line < r) > 0) print line >f
        close(r)
        print "" >f
    }
    printf "%s", BODY >f
    print "fn main() -> i32 {\n    var bad: i64 = 0;" >f
    for (i = 0; i < NTESTS; i++) print MAINS[i] >f
    print "    if bad != 0 {\n        println(f\"" PREFIX "_" FAMILY ": {bad} failing\");\n        return 1;\n    }\n    0\n}" >f
    close(f)
    print "program " f
    NTESTS = 0; BODY = ""; split("", USED)
}

function family_slug(s) {
    s = tolower(s)
    gsub(/[^a-z0-9]+/, "_", s)
    sub(/^_+/, "", s); sub(/_+$/, "", s)
    return s
}

BEGIN {
    CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.,:;()[]<>=+-*/&|^!~ "
    RNG = 12345; NTESTS = 0
    OUT = out; TABLE = table; NRANDOM = nrandom + 0
    PREFIX = table == "aarch64" ? "a64" : table == "x86_64" ? "x86" : table
    MOD = table == "portable" ? "std::arch::" : "std::arch::" table "::"
    split("k if else as true false max min abs clamp u8 u16 u32 u64 i8 i16 i32 i64 f32 f64 bool", al, " ")
    for (i in al) ALLOWED[al[i]] = 1
    if (refs != "") while ((getline line < refs) > 0) { split(line, rf, " "); REF[rf[1]] = rf[2] }
    FAMILY = "all"; FAMILY_TITLE = "std::arch"; PART = 1
    # The prelude: the random inputs, the edges, the comparisons.
    PRELUDE = "struct Rng { s: u64 }\n\n" \
        "fn next(r: inout Rng) -> u64 {\n    var x = r.s;\n    x = x ^ (x << 13);\n    x = x ^ (x >> 7);\n    x = x ^ (x << 17);\n    r.s = x;\n    x\n}\n\n" \
        "fn max<T>(a: T, b: T) -> T { if a > b { a } else { b } }\n" \
        "fn min<T>(a: T, b: T) -> T { if a < b { a } else { b } }\n" \
        "fn abs(a: i64) -> i64 { if a < 0 { -a } else { a } }\n" \
        "fn clamp(a: i64, lo: i64, hi: i64) -> i64 { if a < lo { lo } else if a > hi { hi } else { a } }\n\n" \
        "fn show<T>(xs: [T]) {\n    print(\"[\");\n    for k in 0..xs.len as i64 {\n        if k > 0 { print(\" \"); }\n        print(f\"{xs[k]}\");\n    }\n    print(\"]\");\n}\n\n" \
        "// The integer edges: 0, 1, 2, MAX, MIN, MIN + 1, -2, -1, 0x55.., 0x33..\n" \
        "fn edge_bits(e: i64, bits: i64) -> u64 {\n    let ones: u64 = if bits == 64 { 0xffffffffffffffffu64 } else { (1u64 << bits) - 1 };\n    let top: u64 = 1u64 << (bits - 1);\n" \
        "    if e == 0 { return 0; }\n    if e == 1 { return 1; }\n    if e == 2 { return 2; }\n    if e == 3 { return top - 1; }\n    if e == 4 { return top; }\n    if e == 5 { return top + 1; }\n    if e == 6 { return ones - 1; }\n    if e == 7 { return ones; }\n    if e == 8 { return ones / 3; }\n    ones / 5\n}\n\n" \
        "// The float edges: 0, -0, 1, -1, inf, -inf, NaN, the least denormal, MAX, the least normal.\n" \
        "fn float_edge(e: i64, bits: i64) -> u64 {\n    let f32s: [u64; 10] = [0, 0x80000000, 0x3f800000, 0xbf800000, 0x7f800000, 0xff800000, 0x7fc00000, 1, 0x7f7fffff, 0x00800000];\n" \
        "    let f64s: [u64; 10] = [0, 0x8000000000000000, 0x3ff0000000000000, 0xbff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 1, 0x7fefffffffffffff, 0x0010000000000000];\n" \
        "    if bits == 32 { f32s[e] } else { f64s[e] }\n}\n\n" \
        "fn float_of(x: u64, bits: i64) -> f64 {\n    if bits == 32 {\n        let t: [i32; 4] = [x as i32; 4];\n        var o: [f32; 4] = [0.0; 4];\n        v4f32::from_bits(v4i32::load(t[..], 0)).store(&o[..], 0);\n        return o[0] as f64;\n    }\n" \
        "    let t: [i64; 2] = [x as i64; 2];\n    var o: [f64; 2] = [0.0; 2];\n    v2f64::from_bits(v2i64::load(t[..], 0)).store(&o[..], 0);\n    o[0]\n}\n\n" \
        "fn same_float(want: f64, got: f64) -> bool {\n    if want != want { return got != got; }\n    if want == 0.0 && got == 0.0 { return 1.0 / want == 1.0 / got; }\n    want == got\n}\n\n" \
        "// Lane k of input p in case c: below ne an edge (every pair of the\n// first two inputs), then four cases of mixed edges, nr random ones\n// (an edge, a small value or any), then every 8-bit value (n8 = 1) or\n// pair (n8 = 2) of the 8-bit inputs (x8 = 0, 1; -1: random).\n" \
        "fn case_bits(rng: inout Rng, c: i64, p: i64, k: i64, n: i64, bits: i64, ne: i64, nr: i64, x8: i64, n8: i64, lx: i64) -> u64 {\n" \
        "    if c < ne {\n        if p == 0 { return edge_bits(c % 10, bits); }\n        if p == 1 { return edge_bits((c / 10) % 10, bits); }\n        return edge_bits((c + p) % 10, bits);\n    }\n" \
        "    if c < ne + 4 { return edge_bits((k + 3 * p + c) % 10, bits); }\n" \
        "    if c >= ne + 4 + nr && x8 >= 0 {\n        let j = (c - ne - 4 - nr) * lx + k;\n        if n8 == 1 || x8 == 1 { return (j & 255) as u64; }\n        return ((j >> 8) & 255) as u64;\n    }\n" \
        "    let r = next(&rng);\n    if r & 3 == 0 { return edge_bits(((r >> 8) % 10) as i64, bits); }\n    if r & 3 == 1 { return (r >> 8) % ((2 * n + 2) as u64); }\n    next(&rng)\n}\n\n" \
        "fn fill_int(rng: inout Rng, c: i64, p: i64, dst: inout [i64], bits: i64, signed: bool, ne: i64, nr: i64, x8: i64, n8: i64, lx: i64) {\n" \
        "    let n = dst.len as i64;\n    for k in 0..n {\n        let x = case_bits(&rng, c, p, k, n, bits, ne, nr, x8, n8, lx);\n" \
        "        if bits == 64 {\n            dst[k] = x as i64;\n        } else {\n            let m = x & ((1u64 << bits) - 1);\n            if signed && (m >> (bits - 1)) != 0 {\n                dst[k] = (m as i64) - (1i64 << bits);\n            } else {\n                dst[k] = m as i64;\n            }\n        }\n    }\n}\n\n" \
        "fn fill_u64(rng: inout Rng, c: i64, p: i64, dst: inout [u64], bits: i64, signed: bool, ne: i64, nr: i64, x8: i64, n8: i64, lx: i64) {\n" \
        "    let n = dst.len as i64;\n    for k in 0..n { dst[k] = case_bits(&rng, c, p, k, n, bits, ne, nr, x8, n8, lx); }\n}\n\n" \
        "fn fill_float(rng: inout Rng, c: i64, p: i64, dst: inout [f64], bits: i64, signed: bool, ne: i64, nr: i64, x8: i64, n8: i64, lx: i64) {\n" \
        "    let n = dst.len as i64;\n    for k in 0..n {\n        var e: i64 = -1;\n        if c < ne { e = if p == 0 { c % 10 } else if p == 1 { (c / 10) % 10 } else { (c + p) % 10 }; }\n" \
        "        else if c < ne + 4 { e = (k + 3 * p + c) % 10; }\n        if e >= 0 {\n            dst[k] = float_of(float_edge(e, bits), bits);\n        } else {\n" \
        "            let r = next(&rng);\n            if r & 3 == 0 {\n                dst[k] = float_of(float_edge(((r >> 8) % 10) as i64, bits), bits);\n            } else if r & 3 == 1 {\n                dst[k] = ((r >> 8) % 64) as f64 - 32.0;\n            } else {\n                dst[k] = float_of(next(&rng), bits);\n            }\n        }\n    }\n}\n\n"
}

/^[ \t]*#[ \t]*----/ {
    flush()
    t = $0
    sub(/^[ \t]*#[ \t]*-+[ \t]*/, "", t); sub(/[ \t]*-+[ \t]*$/, "", t); sub(/ *\(.*$/, "", t)
    FAMILY_TITLE = t
    FAMILY = family_slug(t); PART = 1
    next
}
/^[ \t]*#/ || /^[ \t]*$/ { next }
{
    nf = split($0, col, / \| /)
    NAME = trim(col[1]); FEATS = trim(col[2]); SIG = trim(col[3]); FORM = trim(col[4])
    MEM = trim(col[7]); SEM = trim(col[9])
    if (FORM ~ /^feat/ || FORM == "hint") { print "skip " NAME ": form " FORM ": nothing to compare"; next }
    ERR = ""; SKIP = ""
    NTEST = NTESTS
    saved = BODY
    if (!intrinsic()) {
        BODY = saved
        if (SKIP != "") print "skip " NAME ": " SKIP
        else print "error " NAME ": " ERR
        next
    }
    if (FEATS == "-") {
        MAINS[NTESTS] = "    bad += test_" NTEST "();"
    } else {
        nfe = split(FEATS, fe, /,/)
        gh = ""; gd = ""
        for (i = 1; i <= nfe; i++) {
            gh = gh (i > 1 ? " && " : "") "has(\"" TABLE "." trim(fe[i]) "\")"
            gd = gd (i > 1 ? " && " : "") "detect(\"" TABLE "." trim(fe[i]) "\")"
        }
        MAINS[NTESTS] = "    if " gh " {\n        bad += test_" NTEST "();\n    } else if " gd " {\n        bad += test_" NTEST "();\n    } else {\n        println(\"" NAME ": skipped, the CPU lacks " FEATS "\");\n    }"
    }
    NTESTS++
    if (NTESTS >= 40) { flush(); PART++ }
}
END { flush() }
