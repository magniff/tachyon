# Writes a random tachyon program: integer arithmetic of every width,
# floats, shifts, comparisons, casts, branches, loops, arrays, pointers and
# calls.
# Everything it does is defined in tachyon (wrapping arithmetic, division
# by zero, shift amounts), loops are bounded and indices in range, so
# every optimization level must print the same.
#
# usage: awk -v seed=N [-v nonzero=1] -f gen.awk
#
# nonzero=1 makes every divisor positive and odd, for comparing with the
# seed, whose division traps on 0 and on MIN / -1.

function rnd(n) { return int(rand() * n) }

function pick_type() { return TYPES[rnd(NT)] }

function pick_int_type() { return TYPES[rnd(8)] }

function is_float(t) { return substr(t, 1, 1) == "f" }

function float_literal(t,    k) {
    k = rnd(8)
    if (k == 0) return "0.0"
    if (k == 1) return "-0.5"
    if (k == 2) return "1e10"
    if (k == 3) return "-3.25"
    return rnd(1000) "." rnd(100)
}

# A float expression of type t.
function float_expr(t, depth,    k, v, u, ops) {
    if (depth <= 0) {
        v = var_of(t)
        if (v != "" && rnd(3) > 0) return v
        return "(" float_literal(t) " as " t ")"
    }
    k = rnd(8)
    if (k <= 2) {
        split("+ - * /", ops, " ")
        return "(" float_expr(t, depth - 1) " " ops[1 + rnd(4)] " " float_expr(t, depth - 1) ")"
    }
    if (k == 3) return "(-" float_expr(t, depth - 1) ")"
    if (k == 4) {
        u = rnd(3) ? pick_int_type() : (t == "f32" ? "f64" : "f32")
        return "(" expr(u, depth - 1) " as " t ")"
    }
    if (k == 5) return "(if " cond(depth - 1) " { " float_expr(t, depth - 1) " } else { " float_expr(t, depth - 1) " })"
    v = var_of(t)
    if (v != "") return v
    return "(" float_literal(t) " as " t ")"
}

function bits(t) { return substr(t, 2) + 0 }

function signed(t) { return substr(t, 1, 1) == "i" }

# A literal of type t, in range.
function literal(t,    b, v) {
    if (is_float(t)) return "(" float_literal(t) " as " t ")"
    b = bits(t)
    if (rnd(4) == 0) {
        # Edge values.
        v = rnd(5)
        if (v == 0) return "0" t
        if (v == 1) return "1" t
        if (signed(t)) {
            if (v == 2) return "-1" t
            if (b == 8) return (v == 3 ? "127" : "-127") t
            if (b == 16) return (v == 3 ? "32767" : "-32767") t
            if (b == 32) return (v == 3 ? "2147483647" : "-2147483647") t
            return (v == 3 ? "9223372036854775807" : "-9223372036854775807") t
        }
        if (b == 8) return "255" t
        if (b == 16) return "65535" t
        if (b == 32) return "4294967295" t
        return "18446744073709551615" t
    }
    v = rnd(b >= 16 ? 1000 : 100)
    if (signed(t) && rnd(3) == 0) return "-" v t
    return v t
}

# A variable of type t in scope, or "".
function var_of(t,    i, n, cands) {
    n = 0
    for (i = 0; i < NV; i++) if (VT[i] == t) cands[n++] = VN[i]
    if (n == 0) return ""
    return cands[rnd(n)]
}

# An expression of type t.
function expr(t, depth,    k, v, u, op, ops) {
    if (is_float(t)) return float_expr(t, depth)
    if (depth <= 0) {
        v = var_of(t)
        if (v != "" && rnd(3) > 0) return v
        return literal(t)
    }
    k = rnd(12)
    if (k <= 3) {
        split("+ - * / % & | ^", ops, " ")
        op = ops[1 + rnd(8)]
        if (nonzero && (op == "/" || op == "%"))
            return "(" expr(t, depth - 1) " " op " " divisor(t, depth - 1) ")"
        return "(" expr(t, depth - 1) " " op " " expr(t, depth - 1) ")"
    }
    if (k == 4) {
        u = pick_int_type()
        return "(" expr(t, depth - 1) " " (rnd(2) ? "<<" : ">>") " " expr(u, depth - 2) ")"
    }
    if (k == 5) {
        u = pick_type()
        # Float to integer conversions only to i64: the narrower ones and u64
        # differ between the seed and the releases (both are defined).
        if (is_float(u) && t != "i64") u = pick_int_type()
        return "(" expr(u, depth - 1) " as " t ")"
    }
    if (k == 6) {
        return "(if " cond(depth - 1) " { " expr(t, depth - 1) " } else { " expr(t, depth - 1) " })"
    }
    if (k == 7 && NA > 0) {
        v = rnd(NA)
        if (AT[v] == t) return AN[v] "[(" expr("u64", depth - 2) ") % " AL[v] "u64]"
    }
    if (k == 7 && rnd(2)) {
        # Integers from floats (saturating, NaN is 0) at 64 bits.
        u = rnd(2) ? "f64" : "f32"
        if (t == "i64") return "(" float_expr(u, depth - 1) " as " t ")"
    }
    if (k == 8 && NF > 0 && LOOPS == 0) {
        return "(" call(depth - 1) " as " t ")"
    }
    if (k == 9) {
        if (signed(t)) return "(-" expr(t, depth - 1) ")"
        return "(~" expr(t, depth - 1) ")"
    }
    if (k == 10 && NA > 0) {
        v = rnd(NA)
        if (AT[v] == t) return "(*(&" AN[v] "[" rnd(AL[v]) "]))"
    }
    v = var_of(t)
    if (v != "") return v
    return literal(t)
}

# A positive odd divisor (the seed traps on 0 and on MIN / -1).
function divisor(t, depth,    max) {
    if (!signed(t)) return "(" expr(t, depth) " | 1" t ")"
    max = bits(t) == 8 ? "127" : bits(t) == 16 ? "32767" : bits(t) == 32 ? "2147483647" : "9223372036854775807"
    return "((" expr(t, depth) " & " max t ") | 1" t ")"
}

function cond(depth,    t, ops, k) {
    k = rnd(5)
    if (k == 0 && depth > 0) return "(" cond(depth - 1) " && " cond(depth - 1) ")"
    if (k == 1 && depth > 0) return "(" cond(depth - 1) " || " cond(depth - 1) ")"
    if (k == 2 && depth > 0) return "(!" cond(depth - 1) ")"
    t = pick_type()
    split("== != < <= > >=", ops, " ")
    return "(" expr(t, depth) " " ops[1 + rnd(6)] " " expr(t, depth) ")"
}

# A call of an earlier function (returns u64).
function call(depth,    f, i, s) {
    f = rnd(NF)
    s = "f" f "("
    for (i = 0; i < FNP[f]; i++) {
        if (i > 0) s = s ", "
        s = s expr(FPT[f, i], depth > 1 ? 1 : 0)
    }
    return s ")"
}

function indent(n,    s) { s = ""; while (n-- > 0) s = s "    "; return s }

# Mutable scalar variables only (not loop counters).
function assignable(    i, n, cands) {
    n = 0
    for (i = 0; i < NV; i++) if (VM[i]) cands[n++] = i
    if (n == 0) return -1
    return cands[rnd(n)]
}

function statement(level, loops,    k, v, t, a, op, ops, n, lim, saved) {
    k = rnd(10)
    if (k <= 3) {
        v = assignable()
        if (v < 0) return
        split("= += -= *= ^= |= &=", ops, " ")
        op = ops[1 + rnd(is_float(VT[v]) ? 4 : 7)]
        print indent(level) VN[v] " " op " " expr(VT[v], 3) ";"
        return
    }
    if (k == 4 && NA > 0) {
        a = rnd(NA)
        print indent(level) AN[a] "[(" expr("u64", 2) ") % " AL[a] "u64] = " expr(AT[a], 2) ";"
        return
    }
    if (k == 5 && NA > 0) {
        a = rnd(NA)
        print indent(level) "*(&" AN[a] "[" rnd(AL[a]) "]) " (rnd(2) ? "=" : "+=") " " expr(AT[a], 2) ";"
        return
    }
    if (k == 6 && level < 4) {
        print indent(level) "if " cond(2) " {"
        statements(level + 1, loops, 1 + rnd(3))
        if (rnd(2)) {
            print indent(level) "} else {"
            statements(level + 1, loops, 1 + rnd(3))
        }
        print indent(level) "}"
        return
    }
    if (k == 7 && loops < 2 && level < 4) {
        n = NV
        lim = 1 + rnd(7)
        print indent(level) "for i" level " in 0.." lim " {"
        VN[NV] = "i" level; VT[NV] = "i64"; VM[NV] = 0; NV++
        LOOPS++
        statements(level + 1, loops + 1, 1 + rnd(3))
        LOOPS--
        NV = n
        print indent(level) "}"
        return
    }
    if (k == 8 && loops < 2 && level < 4) {
        # A while loop with its own counter.
        COUNTER++
        print indent(level) "let mut w" COUNTER ": i32 = 0;"
        print indent(level) "while w" COUNTER " < " (1 + rnd(6)) " {"
        saved = COUNTER
        LOOPS++
        statements(level + 1, loops + 1, 1 + rnd(3))
        LOOPS--
        print indent(level + 1) "w" saved " += 1;"
        print indent(level) "}"
        return
    }
    if (k == 9 && NF > 0 && LOOPS == 0) {
        v = assignable()
        if (v < 0) return
        print indent(level) VN[v] (is_float(VT[v]) ? " += " : " ^= ") call(2) " as " VT[v] ";"
        return
    }
}

function statements(level, loops, count,    i) {
    for (i = 0; i < count; i++) statement(level, loops)
}

function function_def(f,    i, n, t, line) {
    NV = 0
    NA = 0
    FNP[f] = 1 + rnd(4)
    line = "fn f" f "("
    for (i = 0; i < FNP[f]; i++) {
        t = pick_type()
        FPT[f, i] = t
        if (i > 0) line = line ", "
        line = line "mut p" i ": " t
        VN[NV] = "p" i; VT[NV] = t; VM[NV] = 1; NV++
    }
    print line ") -> u64 {"
    n = 2 + rnd(4)
    for (i = 0; i < n; i++) {
        t = pick_type()
        print "    let mut v" i ": " t " = " expr(t, 2) ";"
        VN[NV] = "v" i; VT[NV] = t; VM[NV] = 1; NV++
    }
    n = rnd(3)
    for (i = 0; i < n; i++) {
        t = pick_type()
        AN[NA] = "a" i; AT[NA] = t; AL[NA] = 2 + rnd(7)
        print "    let mut a" i ": [" t "; " AL[NA] "] = [" literal(t) "; " AL[NA] "];"
        NA++
    }
    statements(1, 0, 4 + rnd(8))
    # The result mixes every variable and array element.
    print "    let mut h: u64 = 1469598103934665603;"
    for (i = 0; i < NV; i++) {
        if (is_float(VT[i])) print "    h = (h ^ ((" VN[i] " * 1000.0) as i64 as u64)) * 1099511628211;"
        else print "    h = (h ^ (" VN[i] " as u64)) * 1099511628211;"
    }
    for (i = 0; i < NA; i++) {
        if (is_float(AT[i])) print "    for k in 0.." AL[i] " { h = (h ^ ((" AN[i] "[k] * 1000.0) as i64 as u64)) * 1099511628211; }"
        else print "    for k in 0.." AL[i] " { h = (h ^ (" AN[i] "[k] as u64)) * 1099511628211; }"
    }
    print "    h"
    print "}"
    print ""
}

BEGIN {
    srand(seed)
    split("i8 i16 i32 i64 u8 u16 u32 u64 f64 f32", T, " ")
    NT = 10
    for (i = 0; i < NT; i++) TYPES[i] = T[i + 1]
    print "// Generated by tests/fuzz/gen.awk, seed " seed "."
    print "extern fn printf(format: *u8, ...) -> i32;"
    print ""
    NF = 0
    count = 3 + rnd(4)
    for (f = 0; f < count; f++) {
        function_def(f)
        NF = f + 1
    }
    print "fn main() -> i32 {"
    NV = 0
    NA = 0
    for (f = 0; f < count; f++) {
        for (r = 0; r < 3; r++) {
            line = "    printf(c\"%lu\\n\", f" f "("
            for (i = 0; i < FNP[f]; i++) {
                if (i > 0) line = line ", "
                line = line literal(FPT[f, i])
            }
            print line "));"
        }
    }
    print "    0"
    print "}"
}
