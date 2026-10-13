# Writes a random tachyon program of loops the vectorizer takes (0.10):
# reductions (+ - * & | ^ on integers; + on floats, which stay scalar),
# maps over slices (lanewise + - * / & | ^ and negation of loads,
# invariants and constants, at offsets of -1, 0 or 1), stencils, and
# explicit vector code (loads, arithmetic, sums, stores); called on slices
# of random lengths and starting points (so every alignment and remainder
# shows), on overlapping slices of one array at random distances, and now
# and then on a slice too short for the loop (the bounds check stops the
# program with 101 part way, alike at every level). Everything it does is
# defined, so every optimization level must print the same.
#
# usage: awk -v seed=N -f genvec.awk

function rnd(n) { return int(rand() * n) }

function is_float(t) { return substr(t, 1, 1) == "f" }

function bits(t) { return substr(t, 2) + 0 }

function lanes(t) { return 128 / bits(t) }

function vec_type(t,    b) {
    b = bits(t)
    return "v" (128 / b) (is_float(t) ? "f" : "i") b
}

function literal(t) {
    if (is_float(t)) return (rnd(2) ? "-" : "") rnd(50) "." rnd(10)
    if (substr(t, 1, 1) == "u") return rnd(200) ""
    return (rnd(3) == 0 ? "-" : "") rnd(100)
}

# An expression of element type t over the loads `loads` (a list of
# expressions separated by |) and the invariant `k`.
function elem_expr(t, depth, nload, load,    k, ops, n) {
    if (depth <= 0) {
        k = rnd(6)
        if (k <= 3) return load[1 + rnd(nload)]
        if (k == 4) return "k"
        return "(" literal(t) " as " t ")"
    }
    k = rnd(10)
    if (is_float(t)) {
        n = split("+ - * /", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    if (k <= 6) return "(" elem_expr(t, depth - 1, nload, load) " " ops[1 + rnd(n)] " " elem_expr(t, depth - 1, nload, load) ")"
    if (k == 7 && substr(t, 1, 1) != "u") return "(-" elem_expr(t, depth - 1, nload, load) ")"
    return elem_expr(t, depth - 1, nload, load)
}

function pick_type() { return TYPES[1 + rnd(NT)] }

function reduction_kernel(id, t,    op, init, ops, n, load) {
    if (is_float(t)) {
        op = "+"
    } else {
        n = split("+ - * & | ^", ops, " ")
        op = ops[1 + rnd(n)]
    }
    init = literal(t)
    load[1] = "s[i]"
    print "#[inline(never)]"
    print "fn k" id "(s: [" t "], k: " t ") -> " t " {"
    print "    let mut acc: " t " = " init " as " t ";"
    print "    for i in 0..s.len as i64 {"
    print "        acc " op "= " elem_expr(t, rnd(3), 1, load) ";"
    print "    }"
    print "    acc"
    print "}"
    KIND[id] = "reduce"
}

function map_kernel(id, t,    load, oa, ob, oo, lo) {
    oa = rnd(3) - 1
    ob = rnd(3) - 1
    oo = rnd(2) ? 0 : rnd(3) - 1
    lo = (oa < 0 || ob < 0 || oo < 0) ? 1 : 0
    load[1] = "a[i" (oa < 0 ? " - 1" : oa > 0 ? " + 1" : "") "]"
    load[2] = "b[i" (ob < 0 ? " - 1" : ob > 0 ? " + 1" : "") "]"
    print "#[inline(never)]"
    print "fn k" id "(a: [" t "], b: [" t "], out: [" t "], n: i64, k: " t ") {"
    print "    for i in " lo "..n {"
    print "        out[i" (oo < 0 ? " - 1" : oo > 0 ? " + 1" : "") "] = " elem_expr(t, 1 + rnd(3), 2, load) ";"
    print "    }"
    print "}"
    KIND[id] = "map"
}

function stencil_kernel(id, t,    load) {
    load[1] = "a[i - 1]"
    load[2] = "a[i]"
    load[3] = "a[i + 1]"
    print "#[inline(never)]"
    print "fn k" id "(a: [" t "], out: [" t "], n: i64, k: " t ") {"
    print "    for i in 1..n - 1 {"
    print "        out[i] = " elem_expr(t, 2 + rnd(2), 3, load) ";"
    print "    }"
    print "}"
    KIND[id] = "stencil"
}

# Explicit vectors: a sum and a lanewise map, a vector at a time, then
# the rest one by one.
function explicit_kernel(id, t,    vt, l, op, ops, n) {
    vt = vec_type(t)
    l = lanes(t)
    if (is_float(t)) {
        n = split("+ - * /", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    op = ops[1 + rnd(n)]
    print "#[inline(never)]"
    print "fn k" id "(a: [" t "], b: [" t "], out: [" t "], n: i64, k: " t ") {"
    print "    let mut i = 0;"
    print "    let kv = " vt "::splat(k);"
    print "    while i + " l " <= n {"
    print "        let x = " vt "::load(a, i);"
    print "        let y = " vt "::load(b, i);"
    print "        let m = x " (is_float(t) ? "<" : ">") " y;"
    print "        let r = m.select(x " op " kv, y " op " x);"
    print "        r.store(out, i);"
    print "        i += " l ";"
    print "    }"
    print "    while i < n {"
    print "        out[i] = a[i] " op " b[i];"
    print "        i += 1;"
    print "    }"
    print "}"
    KIND[id] = "map"
}

# An outer loop over j around an inner loop over q (a constant count):
# acc[j] built over q from a[q * W + j] and b[q] (raw pointers into
# arrays sized for it), stored to out[j].
function nested_kernel(id, t,    load, op, ops, n) {
    if (is_float(t)) {
        n = split("+ - *", ops, " ")
    } else {
        n = split("+ - * & | ^", ops, " ")
    }
    op = ops[1 + rnd(n)]
    Q[id] = 2 + rnd(30)
    W[id] = 8 + rnd(40)
    load[1] = "a[q * " W[id] " + j]"
    load[2] = "b[q]"
    print "#[inline(never)]"
    print "unsafe fn k" id "(a: *" t ", b: *" t ", out: *" t ", n: i64, k: " t ") {"
    print "    for j in 0..n {"
    print "        let mut acc: " t " = k;"
    print "        for q in 0.." Q[id] " {"
    print "            acc = acc " op " " elem_expr(t, 1 + rnd(2), 2, load) ";"
    print "        }"
    print "        out[j] = acc;"
    print "    }"
    print "}"
    KIND[id] = "nested"
}

function fill(name, t, len,    s) {
    s = rnd(1000)
    print "    let mut " name ": [" t "; " len "] = [0 as " t "; " len "];"
    print "    for i in 0.." len " {"
    if (is_float(t)) {
        print "        " name "[i] = ((i * " (7 + rnd(90)) " + " s ") % 97) as " t " * 0.25 - 3.0;"
    } else {
        print "        " name "[i] = ((i * " (7 + rnd(9000)) " + " s ") % 100003 - 50000) as " t ";"
    }
    print "    }"
}

function show(name, t, len) {
    print "    for i in 0.." len " {"
    if (is_float(t)) {
        print "        unsafe { printf(c\"%.17g,\", " name "[i] as f64); }"
    } else {
        print "        unsafe { printf(c\"%lld,\", " name "[i] as i64); }"
    }
    print "    }"
    print "    unsafe { printf(c\"\\n\"); }"
}

function max3(a, b, c) { return a > b ? (a > c ? a : c) : (b > c ? b : c) }

BEGIN {
    srand(seed)
    NT = split("i8 i16 i32 i64 u8 u16 u32 u64 f32 f64", TYPES, " ")
    print "// Generated by tests/fuzz/genvec.awk, seed " seed "."
    print "extern \"C\" {"
    print "    fn printf(f: *u8, ...) -> i32;"
    print "}"
    print ""
    # Z: 0, but not known to the compiler (bounds stay run-time values).
    print "static mut Z: i64 = 0;"
    print ""
    nk = 3 + rnd(4)
    for (id = 0; id < nk; id++) {
        T[id] = TYPES[1 + rnd(NT)]
        k = rnd(10)
        if (k <= 1) reduction_kernel(id, T[id])
        else if (k == 2) nested_kernel(id, T[id])
        else if (k <= 5) map_kernel(id, T[id])
        else if (k <= 7) stencil_kernel(id, T[id])
        else {
            # (Vector types have signed lanes.)
            if (substr(T[id], 1, 1) == "u") T[id] = "i" substr(T[id], 2)
            explicit_kernel(id, T[id])
        }
        print ""
    }
    print "fn main() -> i32 {"
    print "    Z = unsafe { printf(c\"\") } as i64;"
    for (id = 0; id < nk; id++) {
        t = T[id]
        len = 1 + rnd(70)
        if (KIND[id] == "nested") len = Q[id] * W[id] + W[id]
        LEN[id] = len
        fill("a" id, t, len)
        fill("b" id, t, len)
        fill("c" id, t, len)
    }
    # The last call may stop with a failed bounds check.
    for (id = 0; id < nk; id++) {
        t = T[id]
        len = LEN[id]
        kv = "(" literal(t) " as " t ")"
        short = id == nk - 1 && rnd(4) == 0
        la = rnd(4); lb = rnd(4); lc = rnd(4)
        if (la > len) la = len
        if (lb > len) lb = len
        if (lc > len) lc = len
        minlen = len - max3(la, lb, lc)
        if (KIND[id] == "nested") {
            # out: c, or (now and then) a itself at an offset; n up to W.
            n = rnd(W[id] + 1)
            o = rnd(3) == 0 ? "&a" id "[" rnd(W[id]) "]" : "&c" id "[0]"
            print "    unsafe { k" id "(&a" id "[0], &b" id "[0], " o ", Z + " n ", " kv "); }"
            show("a" id, t, W[id])
            show("c" id, t, W[id])
        } else if (KIND[id] == "reduce") {
            hi = len - rnd(3)
            if (hi < la) hi = la
            print "    unsafe { printf(c\"k" id " %lld\\n\", k" id "(a" id "[Z + " la "..Z + " hi "], " kv ") as i64); }"
            if (is_float(t)) {
                print "    unsafe { printf(c\"k" id "f %.17g\\n\", k" id "(b" id "[Z + " la "..Z + " hi "], " kv ") as f64); }"
            }
        } else if (KIND[id] == "map") {
            n = short ? minlen + 2 : minlen - 1 - rnd(3)
            if (n < 0) n = 0
            print "    k" id "(a" id "[Z + " la ".." len "], b" id "[Z + " lb ".." len "], c" id "[Z + " lc ".." len "], Z + " n ", " kv ");"
            d = rnd(3); e = rnd(3)
            n = len - (d > e ? d : e) - 2
            if (n < 0) n = 0
            if (!short) print "    k" id "(a" id "[Z..Z + " len "], a" id "[Z + " d ".." len "], a" id "[Z + " e ".." len "], Z + " n ", " kv ");"
            show("a" id, t, len)
            show("c" id, t, len)
        } else {
            n = short ? minlen + 2 : minlen - rnd(2)
            if (n < 0) n = 0
            print "    k" id "(a" id "[Z + " la ".." len "], c" id "[Z + " lc ".." len "], Z + " n ", " kv ");"
            d = rnd(3)
            if (!short && len > d) print "    k" id "(c" id "[Z..Z + " len "], c" id "[Z + " d ".." len "], Z + " len - d ", " kv ");"
            show("c" id, t, len)
        }
    }
    print "    0"
    print "}"
}
