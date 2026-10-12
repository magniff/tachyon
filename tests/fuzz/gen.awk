# Writes a random tachyon program: integer arithmetic of every width,
# floats, shifts, comparisons, casts, branches, loops, arrays, pointers and
# calls; and (unless nonzero=1) the language of 0.3: structs (passed by
# value too), enums with and without fields, match on integers and enums
# (literals, ranges, alternatives, bindings, guards), methods and slices.
# Everything it does is defined in tachyon (wrapping arithmetic, division
# by zero, shift amounts), loops are bounded and indices in range, so
# every optimization level must print the same.
#
# usage: awk -v seed=N [-v nonzero=1] [-v loops=1] [-v generics=1] -f gen.awk
#
# loops=1 (the loop mode, for the loop optimizer of 0.4) adds more loops:
# counted loops with bounds from expressions, inclusive ranges, while loops
# of every integer type stepping up or down by varied steps, `!=` tests,
# early `break` and `continue`, loops over slices whose index may run one
# past the end (the bounds check exits with 101, alike at every level),
# and chains of equality tests on one value.
#
# generics=1 (the generics mode, 0.5) adds generic functions, a generic
# struct with methods and a generic enum, instantiated at the integer types
# of the expressions that use them (inferred, or written with `::<T>`).
#
# nonzero=1 makes every divisor positive and odd, for comparing with the
# seed, whose division traps on 0 and on MIN / -1, and leaves out what the
# seed does not have (the 0.3 language).

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
    k = rnd(FEAT ? 14 : 12)
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
    if (k >= 11 && GEN && rnd(2)) {
        v = generic_expr(t, depth)
        if (v != "") return v
    }
    if (k >= 11 && FEAT) {
        v = feature_expr(t, depth)
        if (v != "") return v
    }
    v = var_of(t)
    if (v != "") return v
    return literal(t)
}

# ---- Generics (0.5) ----

function generic_defs() {
    print "fn gp<T>(c: bool, a: T, b: T) -> T { if c { a } else { b } }"
    print ""
    print "fn gid<T>(x: T) -> T { let y: T = x; y }"
    print ""
    print "fn gpair<A, B>(a: A, b: B) -> (B, A) { (b, a) }"
    print ""
    print "struct GB<T> { v: T, w: T }"
    print ""
    print "impl<T> GB<T> {"
    print "    fn new(v: T, w: T) -> GB<T> { GB { v: v, w: w } }"
    print "    fn swap(self: GB<T>) -> GB<T> { GB::new(self.w, self.v) }"
    print "    fn first(self: *GB<T>) -> T { self.v }"
    print "    fn pick<U>(self: *GB<T>, c: bool, u: U, other: U) -> U { if c { u } else { other } }"
    print "}"
    print ""
    print "enum GM<T> { No, Yes(T) }"
    print ""
    print "fn gor<T>(m: GM<T>, d: T) -> T { match m { GM::Yes(x) => x, GM::No => d } }"
    print ""
}

# An integer expression of type t through the generic items, or "".
function generic_expr(t, depth,    k, a, b) {
    if (depth <= 0) return ""
    k = rnd(7)
    a = "(" expr(t, depth - 1) " as " t ")"
    b = "(" expr(t, depth - 1) " as " t ")"
    if (k == 0) return "gp(" cond(depth - 1) ", " a ", " b ")"
    if (k == 1) return "gid::<" t ">(" a ")"
    if (k == 2) return "gpair(" a ", " cond(depth - 1) ").1"
    if (k == 3) return "GB::new(" a ", " b ").swap().first()"
    if (k == 4) return "GB::<" t ">::new(" a ", " b ").pick(" cond(depth - 1) ", " b ", " a ")"
    if (k == 5) return "gor(GM::Yes(" a "), " b ")"
    return "gor(GM::<" t ">::No, " a ")"
}

# ---- The 0.3 language ----

# An integer expression of type t using structs, enums, match, methods or
# slices, or "".
function feature_expr(t, depth,    k, v, i, f, s, lo, hi, n, e, body, u) {
    k = rnd(8)
    if (k == 0 && NSV > 0) {
        # A field.
        v = rnd(NSV)
        s = SVS[v]
        f = rnd(SNF[s])
        if (is_float(SFT[s, f])) return "((" SVN[v] ".f" f " * 8.0) as i64 as " t ")"
        return "(" SVN[v] ".f" f " as " t ")"
    }
    if (k == 1 && NSV > 0) {
        # A method.
        v = rnd(NSV)
        return "(" SVN[v] ".m1() as " t ")"
    }
    if (k == 2 && depth > 0) return int_match(t, depth)
    if (k == 3 && NEV > 0 && depth > 0) return enum_match(t, depth)
    if (k == 4 && NCV > 0) {
        v = rnd(NCV)
        if (rnd(2)) return "(" CVN[v] " as " t ")"
        return "(match " CVN[v] " { C::A => " expr(t, depth - 1) ", C::B | C::C => " literal(t) ", C::D => " expr(t, depth - 1) " })"
    }
    if (k == 5 && NA > 0) {
        # An element of a slice of an array.
        v = rnd(NA)
        if (AT[v] != t) return ""
        lo = rnd(AL[v])
        hi = lo + 1 + rnd(AL[v] - lo)
        return "(" AN[v] "[" lo ".." hi "])[" rnd(hi - lo) "]"
    }
    if (k == 6 && NSV > 0 && depth > 0) {
        # A struct by value through a function.
        v = rnd(NSV)
        s = SVS[v]
        return "(S" s "::g(" SVN[v] ", " expr("i64", depth - 1) ").f0 as " t ")"
    }
    return ""
}

# A match on an integer: distinct literal arms, an alternative, a range
# above them, a guard, and a wildcard.
function int_match(t, depth,    u, n, i, s, used, x, lo) {
    u = pick_int_type()
    s = "(match " expr(u, depth - 1) " {"
    n = 1 + rnd(4)
    for (i = 0; i < n; i++) {
        x = rnd(20)
        if (x in used) continue
        used[x] = 1
        if (rnd(3) == 0 && !((x + 21) in used)) {
            used[x + 21] = 1
            s = s " " x " | " (x + 21) " => " expr(t, depth - 1) ","
        } else {
            s = s " " x " => " expr(t, depth - 1) ","
        }
    }
    if (rnd(2)) {
        lo = 45 + rnd(10)
        s = s " " lo "..=" (lo + rnd(30)) " => " expr(t, depth - 1) ","
    }
    if (rnd(2)) s = s " w if w > 70 => " expr(t, depth - 1) ","
    return s " _ => " expr(t, depth - 1) " })"
}

# A match on an enum with fields: every variant, one with a guard.
function enum_match(t, depth,    v, s, saved) {
    v = rnd(NEV)
    saved = NV
    s = "(match " EVN[v] " {"
    VN[NV] = "x0"; VT[NV] = ET0; VM[NV] = 0; NV++
    if (rnd(2)) s = s " E::V0(x0) if x0 > 5" ET0 " => " expr(t, depth - 1) ","
    s = s " E::V0(x0) => " expr(t, depth - 1) ","
    NV = saved
    VN[NV] = "x1"; VT[NV] = ET1; VM[NV] = 0; NV++
    VN[NV] = "x2"; VT[NV] = ET2; VM[NV] = 0; NV++
    s = s " E::V1(x1, x2) => " expr(t, depth - 1) ","
    NV = saved
    return s " E::V2 => " literal(t) " })"
}

# A value of enum E.
function enum_value(depth,    k) {
    k = rnd(3)
    if (k == 0) return "E::V0(" expr(ET0, depth) ")"
    if (k == 1) return "E::V1(" expr(ET1, depth) ", " expr(ET2, depth) ")"
    return "E::V2"
}

function c_value(    k) {
    k = rnd(4)
    return "C::" (k == 0 ? "A" : k == 1 ? "B" : k == 2 ? "C" : "D")
}

# A literal of struct s.
function struct_value(s, depth,    i, line) {
    line = "S" s " {"
    for (i = 0; i < SNF[s]; i++) {
        if (i > 0) line = line ","
        line = line " f" i ": " expr(SFT[s, i], depth)
    }
    return line " }"
}

# The type definitions, with methods.
function type_defs(    s, i, n) {
    NS = 1 + rnd(2)
    for (s = 0; s < NS; s++) {
        SNF[s] = 1 + rnd(4)
        line = "struct S" s " {"
        for (i = 0; i < SNF[s]; i++) {
            SFT[s, i] = pick_type()
            if (i > 0) line = line ","
            line = line " f" i ": " SFT[s, i]
        }
        # f0 is an integer (methods modify it).
        SFT[s, 0] = pick_int_type()
        sub(/f0: [a-z0-9]+/, "f0: " SFT[s, 0], line)
        print line " }"
        print ""
        print "impl S" s " {"
        print "    fn m0(self: *S" s ", x: " SFT[s, 0] ") {"
        print "        self.f0 = self.f0 ^ x;"
        print "    }"
        print "    fn m1(self: S" s ") -> u64 {"
        line = "        let mut h: u64 = 7;"
        print line
        for (i = 0; i < SNF[s]; i++) {
            if (is_float(SFT[s, i])) print "        h = h * 31 + ((self.f" i " * 4.0) as i64 as u64);"
            else print "        h = h * 31 + (self.f" i " as u64);"
        }
        print "        h"
        print "    }"
        print "    fn g(v: Self, k: i64) -> Self {"
        print "        let mut w = v;"
        print "        w.f0 = w.f0 ^ (k as " SFT[s, 0] ");"
        print "        w"
        print "    }"
        print "}"
        print ""
    }
    ET0 = pick_int_type(); ET1 = pick_int_type(); ET2 = pick_int_type()
    print "enum E { V0(" ET0 "), V1(" ET1 ", " ET2 "), V2 }"
    print ""
    print "enum C { A, B, C, D }"
    print ""
}

# Locals of the new types (declared after the arrays).
function feature_locals(    i, s) {
    NSV = 0; NEV = 0; NCV = 0
    n = rnd(3)
    for (i = 0; i < n; i++) {
        s = rnd(NS)
        SVN[NSV] = "s" i; SVS[NSV] = s
        print "    let mut s" i ": S" s " = " struct_value(s, 1) ";"
        NSV++
    }
    n = rnd(3)
    for (i = 0; i < n; i++) {
        EVN[NEV] = "e" i
        print "    let mut e" i ": E = " enum_value(1) ";"
        NEV++
    }
    n = rnd(2)
    for (i = 0; i < n; i++) {
        CVN[NCV] = "c" i
        print "    let mut c" i ": C = " c_value() ";"
        NCV++
    }
}

# A statement on the new types, or nothing.
function feature_statement(level,    k, v, w, s, f, op) {
    k = rnd(6)
    if (k == 0 && NSV > 0) {
        v = rnd(NSV)
        s = SVS[v]
        f = rnd(SNF[s])
        print indent(level) SVN[v] ".f" f " = " expr(SFT[s, f], 2) ";"
        return
    }
    if (k == 1 && NSV > 0) {
        v = rnd(NSV)
        s = SVS[v]
        print indent(level) SVN[v] ".m0(" expr(SFT[s, 0], 2) ");"
        return
    }
    if (k == 2 && NSV > 1) {
        v = rnd(NSV)
        w = rnd(NSV)
        if (SVS[v] == SVS[w]) print indent(level) SVN[v] " = " SVN[w] ";"
        return
    }
    if (k == 3 && NEV > 0) {
        print indent(level) EVN[rnd(NEV)] " = " enum_value(2) ";"
        return
    }
    if (k == 4 && NCV > 0) {
        print indent(level) CVN[rnd(NCV)] " = " c_value() ";"
        return
    }
    if (k == 5 && NA > 0 && NSV > 0) {
        # Writes through a slice.
        v = rnd(NA)
        print indent(level) "{"
        print indent(level + 1) "let sl = " AN[v] "[1..];"
        print indent(level + 1) "sl[" rnd(AL[v] - 1) "] = " expr(AT[v], 2) ";"
        print indent(level) "}"
    }
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
    if (LOOPMODE && rnd(3) == 0) {
        loop_statement(level, loops)
        return
    }
    k = rnd(FEAT ? 12 : 10)
    if (k >= 10) {
        feature_statement(level)
        return
    }
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
        INFOR[LOOPS] = 1
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
        INFOR[LOOPS] = 0
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

# The loop mode's statements: more loops, exits, slices, test chains.
function loop_statement(level, loops,    k, n, t, lo, hi, step, start, bound, a, x, i, m, v, saved) {
    k = rnd(9)
    if (level >= 4 || loops >= 3) k = 8
    if (k == 0) {
        # A counted loop with bounds from expressions.
        n = NV
        lo = "((" expr("i64", 1) ") % 5)"
        hi = "((" expr("i64", 1) ") % 9 + " rnd(12) ")"
        print indent(level) "for i" level " in " lo (rnd(3) == 0 ? "..=" : "..") hi " {"
        VN[NV] = "i" level; VT[NV] = "i64"; VM[NV] = 0; NV++
        LOOPS++
        INFOR[LOOPS] = 1
        statements(level + 1, loops + 1, 1 + rnd(3))
        LOOPS--
        NV = n
        print indent(level) "}"
        return
    }
    if (k <= 3) {
        # A while loop on its own counter of any integer type: up, down, or
        # up to an exact end with !=.
        t = pick_int_type()
        COUNTER++
        saved = COUNTER
        step = 1 + rnd(3)
        start = signed(t) ? rnd(41) - 20 : rnd(21)
        if (k == 1) {
            bound = start - 3 + rnd(40)
            if (!signed(t) && bound < 0) bound = 0
            print indent(level) "let mut w" saved ": " t " = " start ";"
            print indent(level) "while w" saved " < " bound " {"
        } else if (k == 2) {
            bound = signed(t) ? start - rnd(30) : step - 1 + rnd(5)
            if (start < bound) start = bound + rnd(30)
            print indent(level) "let mut w" saved ": " t " = " start ";"
            print indent(level) "while w" saved " > " bound " {"
        } else {
            step = 1
            bound = start + rnd(25)
            print indent(level) "let mut w" saved ": " t " = " start ";"
            print indent(level) "while w" saved " != " bound " {"
        }
        n = NV
        VN[NV] = "w" saved; VT[NV] = t; VM[NV] = 0; NV++
        LOOPS++
        INFOR[LOOPS] = 0
        statements(level + 1, loops + 1, 1 + rnd(3))
        LOOPS--
        NV = n
        print indent(level + 1) "w" saved (k == 2 ? " -= " : " += ") step ";"
        print indent(level) "}"
        return
    }
    if (k == 4 && LOOPS > 0) {
        print indent(level) "if " cond(1) " { " (INFOR[LOOPS] && rnd(2) ? "continue" : "break") "; }"
        return
    }
    if (k == 5 && FEAT && NA > 0) {
        # A loop over a slice; its index may run one past the end.
        a = rnd(NA)
        lo = rnd(AL[a])
        hi = lo + rnd(AL[a] - lo + 1)
        COUNTER++
        saved = COUNTER
        print indent(level) "{"
        print indent(level + 1) "let sl" saved " = " AN[a] "[" lo ".." hi "];"
        x = rnd(16) == 0 ? " + 1" : ""
        if (rnd(2)) {
            print indent(level + 1) "for j in 0..(sl" saved ".len as i64" x ") {"
            v = assignable()
            if (rnd(2) || v < 0 || is_float(VT[v]) || is_float(AT[a])) print indent(level + 2) "sl" saved "[j] = " expr(AT[a], 1) ";"
            else print indent(level + 2) VN[v] " ^= sl" saved "[j] as " VT[v] ";"
        } else {
            print indent(level + 1) "let mut j: u64 = 0;"
            print indent(level + 1) "while j < (sl" saved ".len" x ") as u64 {"
            print indent(level + 2) "sl" saved "[j] = " expr(AT[a], 1) ";"
            print indent(level + 2) "j += 1;"
        }
        print indent(level + 1) "}"
        print indent(level) "}"
        return
    }
    if (k == 6) {
        # A chain of equality tests on one value.
        v = assignable()
        if (v < 0 || is_float(VT[v])) return
        m = 3 + rnd(4)
        x = "(" VN[v] " % 8)"
        for (i = 0; i < m; i++) {
            print indent(level) (i == 0 ? "if " : "} else if ") x " == " rnd(8) " {"
            print indent(level + 1) VN[v] " += " (1 + rnd(9)) ";"
        }
        print indent(level) "} else {"
        print indent(level + 1) VN[v] " ^= 3;"
        print indent(level) "}"
        return
    }
    if (k == 7) {
        # A counted loop with a constant trip count (unrolled).
        n = NV
        print indent(level) "for i" level " in " rnd(3) ".." rnd(20) " {"
        VN[NV] = "i" level; VT[NV] = "i64"; VM[NV] = 0; NV++
        LOOPS++
        INFOR[LOOPS] = 1
        statements(level + 1, loops + 1, 1 + rnd(2))
        LOOPS--
        NV = n
        print indent(level) "}"
        return
    }
    v = assignable()
    if (v < 0) return
    print indent(level) VN[v] " " (is_float(VT[v]) ? "+=" : "^=") " " expr(VT[v], 2) ";"
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
    if (FEAT) feature_locals()
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
    if (FEAT) {
        for (i = 0; i < NSV; i++) print "    h = (h ^ " SVN[i] ".m1()) * 1099511628211;"
        for (i = 0; i < NEV; i++) print "    h = (h ^ (match " EVN[i] " { E::V0(a) => a as u64, E::V1(a, b) => (a as u64) * 3 + b as u64, E::V2 => 77 })) * 1099511628211;"
        for (i = 0; i < NCV; i++) print "    h = (h ^ (" CVN[i] " as u64)) * 1099511628211;"
        NSV = 0; NEV = 0; NCV = 0
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
    FEAT = nonzero ? 0 : 1
    GEN = (generics && !nonzero) ? 1 : 0
    LOOPMODE = loops ? 1 : 0
    print "// Generated by tests/fuzz/gen.awk, seed " seed "."
    # (run.sh gives the seed the 0.2 form, with tests/seed-compat.awk.)
    print "extern \"C\" { fn printf(format: *u8, ...) -> i32; }"
    print ""
    if (FEAT) type_defs()
    if (GEN) generic_defs()
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
