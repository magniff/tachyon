# Writes a random C interoperability test: a C file (cfile) and a tachyon
# file (tfile) that call each other with random signatures: scalars of
# every width, #[repr(C)] structs (nested, with arrays, packed or aligned),
# unions and enums (fieldless and with fields), more arguments than the
# registers hold, results of every kind, variadic calls.
#
# Every value is a known constant, checked leaf by leaf on the other side:
#   - tachyon calls c_fK(...) (defined in C), which checks its arguments and
#     returns a known value, checked by tachyon;
#   - tachyon calls d_fK(t_fK), C calls the extern "C" tachyon function
#     t_fK through the pointer and by name, with the same checks;
#   - tachyon calls the variadic v_fK(n, ...), which reads its arguments
#     with va_arg.
# A mismatch calls fail(function, argument) (exit code 1); the program
# prints "ok" at its end.
#
# usage: awk -v seed=N -v cfile=x.c -v tfile=x.tach -f gen.awk

function rnd(n) { return int(rand() * n) }

# ---- Types ----
#
# A type is a scalar name (i8 ... u64, f32, f64, bool, ptr), "S<k>" (a
# struct or union, TK[k] "struct" or "union"), "E" (the fieldless enum),
# "P<k>" (an enum with fields), or "A<n>:<scalar>" (an array, as a field
# only).

function is_scalar(t) { return t !~ /^[SPEA]/ }
function is_float(t) { return t == "f32" || t == "f64" }

function c_scalar(t) {
    if (t == "f32") return "float"
    if (t == "f64") return "double"
    if (t == "bool") return "bool"
    if (t == "ptr") return "uint8_t *"
    return (substr(t, 1, 1) == "u" ? "uint" : "int") substr(t, 2) "_t"
}

function t_scalar(t) { return t == "ptr" ? "*u8" : t }

function c_type(t) {
    if (t == "E") return "En"
    return is_scalar(t) ? c_scalar(t) : t
}

function t_type(t) { return t == "E" ? "En" : is_scalar(t) ? t_scalar(t) : t }

function pick_scalar(    k) {
    split("i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 bool ptr f64 i32 u8", SC, " ")
    return SC[1 + rnd(15)]
}

# A type for an argument, a result or a field (`depth` limits nesting).
function pick_type(depth,    k) {
    k = rnd(10)
    if (k < 5 || depth > 2) return pick_scalar()
    if (k < 8 && NS > 0) return "S" rnd(NS)
    if (k == 8) return "E"
    if (NP > 0) return "P" rnd(NP)
    return pick_scalar()
}

# ---- Values ----
#
# A value is fixed by the leaf counter LEAF: every walk over a type (the
# tachyon literal, the C literal, the checks) consumes leaves in the same
# order, so starting from the same LEAF gives the same value.

function h(n) { return (n * 2654435761 + SEED * 40503) % 1000003 }

function leaf(t,    k, v) {
    k = h(LEAF++)
    if (t == "bool") return k % 2 ? "true" : "false"
    if (t == "ptr") return 4096 + 16 * (k % 1000)
    if (t == "f32") return sprintf("%.2f", (k % 801 - 400) / 4)
    if (t == "f64") return sprintf("%.3f", (k % 2001 - 1000) / 8)
    if (t == "i8") { split("-128 -1 0 1 77 127 -77", V, " "); return V[1 + k % 7] }
    if (t == "u8") { split("0 1 200 255 128 77", V, " "); return V[1 + k % 6] }
    if (t == "i16") { split("-32768 -1 300 32767 -1234", V, " "); return V[1 + k % 5] }
    if (t == "u16") { split("65535 40000 7 32768", V, " "); return V[1 + k % 4] }
    if (t == "i32") { split("-2147483648 -1 123456 2147483647 -99", V, " "); return V[1 + k % 5] }
    if (t == "u32") { split("4294967295 3000000000 9 2147483648", V, " "); return V[1 + k % 4] }
    if (t == "i64") { split("-9223372036854775808 -1 1234567890123 9223372036854775807 -5", V, " "); return V[1 + k % 5] }
    split("18446744073709551615 9223372036854775808 42 4294967296", V, " ")
    return V[1 + k % 4]
}

# A scalar constant in C.
function c_leaf(t, v) {
    if (t == "f32") return v "f"
    if (t == "ptr") return "(uint8_t *)(uintptr_t)" v
    if (t == "i64" && v == "-9223372036854775808") return "(-9223372036854775807LL - 1)"
    if (t == "i32" && v == "-2147483648") return "(-2147483647 - 1)"
    if (t == "i64") return v "LL"
    if (t == "u64") return v "ULL"
    if (t == "u32") return v "U"
    return v
}

# The same in tachyon (in a context of type t).
function t_leaf(t, v) {
    if (t == "ptr") return "(" v " as *u8)"
    return v
}

function array_len(t) { return substr(t, 2, index(t, ":") - 2) + 0 }
function array_elem(t) { return substr(t, index(t, ":") + 1) }

# The literal of a value of type t, in tachyon.
function t_value(t,    s, i, k, m, n) {
    if (is_scalar(t) && t !~ /^A/) return t_leaf(t, leaf(t))
    if (t ~ /^A/) {
        n = array_len(t)
        s = "["
        for (i = 0; i < n; i++) s = s (i ? ", " : "") t_leaf(array_elem(t), leaf(array_elem(t)))
        return s "]"
    }
    if (t == "E") {
        k = h(LEAF++) % 3
        return "En::" (k == 0 ? "A" : k == 1 ? "B" : "C")
    }
    if (t ~ /^P/) {
        k = substr(t, 2) + 0
        m = h(LEAF++) % PNV[k]
        s = t "::V" m
        n = PNF[k, m]
        if (n == 0) return s
        s = s "("
        for (i = 0; i < n; i++) s = s (i ? ", " : "") t_leaf(PFT[k, m, i], leaf(PFT[k, m, i]))
        return s ")"
    }
    k = substr(t, 2) + 0
    s = t " {"
    if (TK[k] == "union") {
        m = h(LEAF++) % NF_[k]
        return s " f" m ": " t_value(FT[k, m]) " }"
    }
    for (i = 0; i < NF_[k]; i++) s = s (i ? "," : "") " f" i ": " t_value(FT[k, i])
    return s " }"
}

# The same value in C (an initializer).
function c_value(t,    s, i, k, m, n) {
    if (is_scalar(t) && t !~ /^A/) return c_leaf(t, leaf(t))
    if (t ~ /^A/) {
        n = array_len(t)
        s = "{"
        for (i = 0; i < n; i++) s = s (i ? ", " : "") c_leaf(array_elem(t), leaf(array_elem(t)))
        return s "}"
    }
    if (t == "E") {
        k = h(LEAF++) % 3
        return "En_" (k == 0 ? "A" : k == 1 ? "B" : "C")
    }
    if (t ~ /^P/) {
        k = substr(t, 2) + 0
        m = h(LEAF++) % PNV[k]
        n = PNF[k, m]
        s = "{ .tag = " m
        if (n > 0) {
            s = s ", .u = { .v" m " = {"
            for (i = 0; i < n; i++) s = s (i ? ", " : " ") c_leaf(PFT[k, m, i], leaf(PFT[k, m, i]))
            s = s " } }"
        }
        return s " }"
    }
    k = substr(t, 2) + 0
    if (TK[k] == "union") {
        m = h(LEAF++) % NF_[k]
        return "{ .f" m " = " c_value(FT[k, m]) " }"
    }
    s = "{"
    for (i = 0; i < NF_[k]; i++) s = s (i ? "," : "") " .f" i " = " c_value(FT[k, i])
    return s " }"
}

# Statements checking that tachyon expression `e` (of type t) holds the
# value (calling fail(fk, arg) otherwise); printed with indentation `ind`.
function t_checks(t, e, fk, arg, ind,    i, k, m, n, v, b) {
    if (is_scalar(t) && t !~ /^A/) {
        v = leaf(t)
        print ind "if " e " != " t_leaf(t, v) " { fail(" fk ", " arg "); }" > TF
        return
    }
    if (t ~ /^A/) {
        n = array_len(t)
        for (i = 0; i < n; i++) {
            v = leaf(array_elem(t))
            print ind "if " e "[" i "] != " t_leaf(array_elem(t), v) " { fail(" fk ", " arg "); }" > TF
        }
        return
    }
    if (t == "E") {
        k = h(LEAF++) % 3
        print ind "if " e " != En::" (k == 0 ? "A" : k == 1 ? "B" : "C") " { fail(" fk ", " arg "); }" > TF
        return
    }
    if (t ~ /^P/) {
        k = substr(t, 2) + 0
        m = h(LEAF++) % PNV[k]
        n = PNF[k, m]
        b = "match " e " { " t "::V" m
        if (n > 0) {
            b = b "("
            for (i = 0; i < n; i++) b = b (i ? ", " : "") "x" DEPTHN "_" i
            b = b ")"
        }
        print ind b " => {" > TF
        for (i = 0; i < n; i++) {
            v = leaf(PFT[k, m, i])
            print ind "    if x" DEPTHN "_" i " != " t_leaf(PFT[k, m, i], v) " { fail(" fk ", " arg "); }" > TF
        }
        print ind "} _ => fail(" fk ", " arg "), }" > TF
        DEPTHN++
        return
    }
    k = substr(t, 2) + 0
    if (TK[k] == "union") {
        m = h(LEAF++) % NF_[k]
        t_checks(FT[k, m], e ".f" m, fk, arg, ind)
        return
    }
    for (i = 0; i < NF_[k]; i++) t_checks(FT[k, i], e ".f" i, fk, arg, ind)
}

# The same in C.
function c_checks(t, e, fk, arg, ind,    i, k, m, n, v) {
    if (is_scalar(t) && t !~ /^A/) {
        v = leaf(t)
        print ind "if (" e " != " c_leaf(t, v) ") fail(" fk ", " arg ");" > CF
        return
    }
    if (t ~ /^A/) {
        n = array_len(t)
        for (i = 0; i < n; i++) {
            v = leaf(array_elem(t))
            print ind "if (" e "[" i "] != " c_leaf(array_elem(t), v) ") fail(" fk ", " arg ");" > CF
        }
        return
    }
    if (t == "E") {
        k = h(LEAF++) % 3
        print ind "if (" e " != En_" (k == 0 ? "A" : k == 1 ? "B" : "C") ") fail(" fk ", " arg ");" > CF
        return
    }
    if (t ~ /^P/) {
        k = substr(t, 2) + 0
        m = h(LEAF++) % PNV[k]
        n = PNF[k, m]
        print ind "if (" e ".tag != " m ") fail(" fk ", " arg ");" > CF
        for (i = 0; i < n; i++) {
            v = leaf(PFT[k, m, i])
            print ind "if (" e ".u.v" m ".f" i " != " c_leaf(PFT[k, m, i], v) ") fail(" fk ", " arg ");" > CF
        }
        return
    }
    k = substr(t, 2) + 0
    if (TK[k] == "union") {
        m = h(LEAF++) % NF_[k]
        c_checks(FT[k, m], e ".f" m, fk, arg, ind)
        return
    }
    for (i = 0; i < NF_[k]; i++) c_checks(FT[k, i], e ".f" i, fk, arg, ind)
}

# ---- Declarations ----

function define_types(    k, i, n, attr, line, m, kind) {
    print "enum En { A = 0, B = 5, C = -3 }" > TF
    print "typedef enum { En_A = 0, En_B = 5, En_C = -3 } En;" > CF
    NP = 1 + rnd(2)
    for (k = 0; k < NP; k++) {
        PNV[k] = 2 + rnd(3)
        line = "enum P" k " {"
        for (m = 0; m < PNV[k]; m++) {
            PNF[k, m] = rnd(4)
            line = line (m ? "," : "") " V" m
            if (PNF[k, m] > 0) {
                line = line "("
                for (i = 0; i < PNF[k, m]; i++) {
                    PFT[k, m, i] = pick_scalar()
                    line = line (i ? ", " : "") t_scalar(PFT[k, m, i])
                }
                line = line ")"
            }
        }
        print "#[repr(C)]" > TF
        print line " }" > TF
        print "typedef struct {" > CF
        print "    int32_t tag;" > CF
        n = 0
        for (m = 0; m < PNV[k]; m++) if (PNF[k, m] > 0) n++
        if (n > 0) {
            print "    union {" > CF
            for (m = 0; m < PNV[k]; m++) {
                if (PNF[k, m] == 0) continue
                line = "        struct {"
                for (i = 0; i < PNF[k, m]; i++) line = line " " c_scalar(PFT[k, m, i]) " f" i ";"
                print line " } v" m ";" > CF
            }
            print "    } u;" > CF
        }
        print "} P" k ";" > CF
    }
    NS = 2 + rnd(5)
    for (k = 0; k < NS; k++) {
        TK[k] = rnd(6) == 0 ? "union" : "struct"
        NF_[k] = 1 + rnd(5)
        attr = ""
        m = rnd(8)
        if (m == 0 && TK[k] == "struct") attr = "packed"
        if (m == 1) attr = "align"
        for (i = 0; i < NF_[k]; i++) {
            if (rnd(5) == 0) FT[k, i] = "A" (1 + rnd(4)) ":" pick_scalar()
            else if (rnd(3) == 0 && k > 0 && attr != "packed") FT[k, i] = "S" rnd(k)
            else FT[k, i] = pick_scalar()
        }
        print (attr == "packed" ? "#[repr(C, packed)]" : attr == "align" ? "#[repr(C, align(16))]" : "#[repr(C)]") > TF
        line = TK[k] " S" k " {"
        for (i = 0; i < NF_[k]; i++) {
            if (FT[k, i] ~ /^A/) line = line (i ? "," : "") " f" i ": [" t_scalar(array_elem(FT[k, i])) "; " array_len(FT[k, i]) "]"
            else line = line (i ? "," : "") " f" i ": " t_type(FT[k, i])
        }
        print line " }" > TF
        line = "typedef " TK[k] (attr == "packed" ? " __attribute__((packed))" : attr == "align" ? " __attribute__((aligned(16)))" : "") " {"
        for (i = 0; i < NF_[k]; i++) {
            if (FT[k, i] ~ /^A/) line = line " " c_scalar(array_elem(FT[k, i])) " f" i "[" array_len(FT[k, i]) "];"
            else line = line " " c_type(FT[k, i]) " f" i ";"
        }
        print line " } S" k ";" > CF
    }
}

# Function K: its parameters and result.
function define_signature(k,    i) {
    NPAR[k] = rnd(4) == 0 ? 6 + rnd(10) : rnd(7)
    for (i = 0; i < NPAR[k]; i++) PT[k, i] = pick_type(0)
    RT[k] = rnd(5) == 0 ? "void" : pick_type(0)
}

function c_params(k,    i, s) {
    s = ""
    for (i = 0; i < NPAR[k]; i++) s = s (i ? ", " : "") c_type(PT[k, i]) " a" i
    return s == "" ? "void" : s
}

function t_params(k,    i, s) {
    s = ""
    for (i = 0; i < NPAR[k]; i++) s = s (i ? ", " : "") "a" i ": " t_type(PT[k, i])
    return s
}

function t_param_types(k,    i, s) {
    s = ""
    for (i = 0; i < NPAR[k]; i++) s = s (i ? ", " : "") t_type(PT[k, i])
    return s
}

function c_ret(k) { return RT[k] == "void" ? "void" : c_type(RT[k]) }
function t_ret(k) { return RT[k] == "void" ? "" : " -> " t_type(RT[k]) }

# The arguments' values start at leaf 1000 * (2 * k + 1), the result's at
# 1000 * (2 * k + 2).
function args_base(k) { return 1000 * (2 * k + 1) }
function result_base(k) { return 1000 * (2 * k + 2) }

function emit_function(k,    i, line) {
    # C: c_fK checks its arguments and returns the result.
    print c_ret(k) " c_f" k "(" c_params(k) ") {" > CF
    LEAF = args_base(k)
    for (i = 0; i < NPAR[k]; i++) c_checks(PT[k, i], "a" i, k, i, "    ")
    if (RT[k] != "void") {
        LEAF = result_base(k)
        print "    " c_ret(k) " r = " c_value(RT[k]) ";" > CF
        print "    return r;" > CF
    }
    print "}" > CF
    # C: d_fK calls the tachyon function through the pointer and by name.
    print c_ret(k) " t_f" k "(" c_params(k) ");" > CF
    print "void d_f" k "(" c_ret(k) " (*f)(" c_params(k) ")) {" > CF
    for (round = 0; round < 2; round++) {
        LEAF = args_base(k)
        line = (round == 0 ? "f(" : "t_f" k "(")
        for (i = 0; i < NPAR[k]; i++) {
            print "    " c_type(PT[k, i]) " x" round "_" i " = " c_value(PT[k, i]) ";" > CF
            line = line (i ? ", " : "") "x" round "_" i
        }
        line = line ")"
        if (RT[k] == "void") {
            print "    " line ";" > CF
        } else {
            print "    " c_ret(k) " r" round " = " line ";" > CF
            LEAF = result_base(k)
            c_checks(RT[k], "r" round, k, 100 + round, "    ")
        }
    }
    print "}" > CF
    # Tachyon: t_fK, the extern "C" definition.
    print "extern \"C\" fn t_f" k "(" t_params(k) ")" t_ret(k) " {" > TF
    LEAF = args_base(k)
    for (i = 0; i < NPAR[k]; i++) t_checks(PT[k, i], "a" i, k, 200 + i, "    ")
    if (RT[k] != "void") {
        LEAF = result_base(k)
        print "    " t_value(RT[k]) > TF
    }
    print "}" > TF
}

# The tachyon calls of main for function K.
function emit_calls(k,    i, line) {
    LEAF = args_base(k)
    line = "c_f" k "("
    for (i = 0; i < NPAR[k]; i++) line = line (i ? ", " : "") t_value(PT[k, i])
    line = line ")"
    if (RT[k] == "void") {
        print "    " line ";" > TF
    } else {
        print "    let r" k ": " t_type(RT[k]) " = " line ";" > TF
        LEAF = result_base(k)
        t_checks(RT[k], "r" k, k, 300, "    ")
    }
    print "    d_f" k "(t_f" k ");" > TF
}

# A variadic call: v_fK(n, ...) with arguments of the promoted kinds.
function emit_variadic(k,    i, n, t, line) {
    n = 1 + rnd(12)
    for (i = 0; i < n; i++) {
        t = rnd(3) == 0 && NS > 0 ? "S" rnd(NS) : pick_scalar()
        if (t ~ /^S/ && TK[substr(t, 2) + 0] == "union") t = "f64"
        VT[i] = t
    }
    print "void v_f" k "(int n, ...) {" > CF
    print "    va_list ap;" > CF
    print "    va_start(ap, n);" > CF
    LEAF = 50000 + 1000 * k
    for (i = 0; i < n; i++) {
        t = VT[i]
        if (t == "f32") line = "(float)va_arg(ap, double)"
        else if (t == "i8" || t == "i16" || t == "u8" || t == "u16") line = "(" c_scalar(t) ")va_arg(ap, int)"
        else if (t == "bool") line = "(bool)va_arg(ap, int)"
        else line = "va_arg(ap, " c_type(t) ")"
        print "    " c_type(t) " y" i " = " line ";" > CF
        c_checks(t, "y" i, k, 400 + i, "    ")
    }
    print "    va_end(ap);" > CF
    print "}" > CF
    LEAF = 50000 + 1000 * k
    line = "    v_f" k "(" n
    for (i = 0; i < n; i++) {
        t = VT[i]
        if (is_scalar(t)) line = line ", " t_variadic_leaf(t, leaf(t))
        else line = line ", " t_value(t)
    }
    print line ");" > TF
    print "    fn v_f" k "(n: i32, ...);" > DECLS
}

# A scalar argument of a variadic call: typed by its suffix.
function t_variadic_leaf(t, v) {
    if (t == "ptr") return "(" v " as *u8)"
    if (t == "bool") return v
    return v t
}

BEGIN {
    srand(seed)
    SEED = seed
    TF = tfile
    CF = cfile
    DECLS = tfile ".decls"
    printf "" > DECLS
    print "// Generated by tests/abi/gen.awk, seed " seed "." > TF
    print "/* Generated by tests/abi/gen.awk, seed " seed ". */" > CF
    print "#include <stdarg.h>\n#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n#include <stdlib.h>" > CF
    print "void fail(int f, int a) { printf(\"FAIL function %d argument %d\\n\", f, a); fflush(stdout); exit(1); }" > CF
    print "#[repr(C)]" > TF
    define_types()
    NFN = 4 + rnd(5)
    for (k = 0; k < NFN; k++) {
        define_signature(k)
        emit_function(k)
    }
    print "extern \"C\" {" > TF
    print "    fn printf(format: *u8, ...) -> i32;" > TF
    print "    fn fail(f: i32, a: i32);" > TF
    for (k = 0; k < NFN; k++) {
        print "    fn c_f" k "(" t_params(k) ")" t_ret(k) ";" > TF
        print "    fn d_f" k "(f: extern \"C\" fn(" t_param_types(k) ")" t_ret(k) ");" > TF
    }
    close(DECLS)
    # The variadic functions are declared after main, which calls them.
    print "}" > TF
    print "fn main() -> i32 {" > TF
    DEPTHN = 0
    for (k = 0; k < NFN; k++) emit_calls(k)
    NV = 1 + rnd(3)
    for (k = 0; k < NV; k++) emit_variadic(k)
    print "    printf(c\"ok\\n\");" > TF
    print "    0" > TF
    print "}" > TF
    close(DECLS)
    print "extern \"C\" {" > TF
    while ((getline line < DECLS) > 0) print line > TF
    print "}" > TF
}
