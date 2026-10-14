# Writes a random tachyon program of divisions by constants (0.11): for
# every integer type, quotients and remainders by random constants (small
# ones, powers of two and their neighbours, the type's extremes, random ones
# of every width, negative ones, 0, 1 and -1) of random values, of the
# type's extremes, and of exact multiples of the divisor and their
# neighbours. Each is checked against the same division by a divisor the
# compiler cannot know (the constant plus a zero read at run time), which
# stays a division instruction, and goes into a checksum; quotients and
# remainders alone go into it too. At -O1 and -O2 a division by a constant
# is a multiplication (isel.tach), at -O0 a division instruction: every
# level must print the same checksum, and no FAIL line.
#
# usage: awk -v seed=N [-v count=K] [-v iterations=M] [-v curated=1] -f gendiv.awk
#   count        constants per type (default 6)
#   iterations   dividends per constant (default 2000), times four
#   curated      the constants of curated_list below instead of random
#                ones (tests/run/opt_divide_constant.tach is made this way)

function rnd(n) { return int(rand() * n) }

function bits(t) { return substr(t, 2) + 0 }

function signed(t) { return substr(t, 1, 1) == "i" }

# 2^k as a decimal (k < 53) or hex digits (any k < 64).
function pow2(k) { return 2 ^ k }

function hex_pow2(k,    s, i) {
    s = (2 ^ (k % 4)) ""
    for (i = 0; i < int(k / 4); i++) s = s "0"
    return s
}

# 2^k - 1 in hex digits.
function hex_mask(k,    s, i) {
    s = (k % 4) ? sprintf("%x", 2 ^ (k % 4) - 1) : ""
    for (i = 0; i < int(k / 4); i++) s = s "f"
    return s == "" ? "0" : s
}

function hex_random(digits, top,    s, i) {
    s = sprintf("%x", 1 + rnd(top - 1))
    for (i = 1; i < digits; i++) s = s sprintf("%x", rnd(16))
    return s
}

# A constant divisor of type t, as an expression of that type.
function divisor(t,    b, k, kind, neg, v, small, n) {
    b = bits(t)
    kind = rnd(12)
    neg = signed(t) && rnd(3) == 0
    if (kind == 0) return lit(t, rnd(4) == 0 ? "0" : "1", neg)
    if (kind <= 3) {
        n = split("3 5 6 7 9 10 11 12 13 14 15 17 19 24 25 26 31 60 100 125 255 641 1000 7919 10000 65521 1000000 6700417", small, " ")
        v = small[1 + rnd(n)]
        if (v + 0 >= pow2(signed(t) ? b - 1 : b)) v = 3 + rnd(5)
        return lit(t, v, neg)
    }
    # 2^k + delta, delta in -1, 0, 1
    if (kind <= 6) {
        k = 1 + rnd(signed(t) ? b - 2 : b - 1)
        if (b <= 32) return lit(t, pow2(k) + rnd(3) - 1, neg)
        k = rnd(3)
        v = 2 + rnd(signed(t) ? 60 : 61)
        if (k == 0) return lit(t, "0x" hex_mask(v), neg)
        if (k == 1) return lit(t, "0x" hex_pow2(v), neg)
        return lit(t, "0x" substr(hex_pow2(v), 1, length(hex_pow2(v)) - 1) "1", neg)
    }
    # the extremes and their neighbours
    if (kind == 7) {
        k = rnd(4)
        if (b <= 32) {
            v = pow2(signed(t) ? b - 1 : b) - 1
            if (k == 1) v = v - 1
            if (k == 2) v = int(v / 2)
            if (k == 3) v = int(v / 3)
            if (signed(t) && rnd(4) == 0) return min_lit(t)
            return lit(t, v, neg)
        }
        if (signed(t) && rnd(4) == 0) return min_lit(t)
        v = signed(t) ? "7fffffffffffffff" : "ffffffffffffffff"
        if (k == 1) v = signed(t) ? "7ffffffffffffffe" : "fffffffffffffffe"
        if (k == 2) v = signed(t) ? "3fffffffffffffff" : "7fffffffffffffff"
        if (k == 3) v = signed(t) ? "2aaaaaaaaaaaaaaa" : "5555555555555555"
        return lit(t, "0x" v, neg)
    }
    # random, of every width
    k = 2 + rnd(signed(t) ? b - 2 : b - 1)
    if (b <= 32) return lit(t, 2 + rnd(pow2(k) - 2), neg)
    if (k <= 48) return lit(t, 2 + rnd(pow2(k) - 2), neg)
    return lit(t, "0x" hex_random(int(k / 4), signed(t) ? 8 : 16), neg)
}

# (Numbers are printed with %.0f: some awks print large ones in exponent
# notation.)
function lit(t, v, neg) {
    if (substr(v "", 1, 2) != "0x") v = sprintf("%.0f", v)
    if (neg) return "(0" t " - " v t ")"
    return v t
}

# Curated divisors per type: each way of isel.tach's lowering (narrow and
# 64-bit, the add fix-up of 65-bit magic numbers, the corrections of signed
# ones, powers of two, 0, 1, -1, the extremes).
function curated_list(t) {
    if (t == "u8") return "0 1 2 3 5 7 10 13 26 100 127 128 129 254 255"
    if (t == "u16") return "0 1 3 7 10 26 641 1000 32767 32768 32769 65534 65535"
    if (t == "u32") return "0 1 3 5 6 7 10 25 26 100 641 1000 1000000 6700417 2147483647 2147483648 2147483649 4294967294 4294967295"
    if (t == "u64") return "0 1 3 5 6 7 10 26 100 641 1000 274177 6700417 1000000007 0x5555555555555555 0xd486c8a807eeb4 0x7fffffffffffffff 0x8000000000000000 0x8000000000000001 0xfffffffffffffffe 0xffffffffffffffff"
    if (t == "i8") return "0 1 -1 2 -2 3 -3 5 7 -7 10 26 -26 100 127 -127 MIN"
    if (t == "i16") return "0 1 -1 3 -3 7 -7 10 26 641 -641 1000 16384 -16384 32767 -32767 MIN"
    if (t == "i32") return "0 1 -1 3 -3 5 6 7 -7 10 26 -26 100 641 1000 1000000 -1000000 1073741824 -4 2147483647 -2147483647 MIN"
    return "0 1 -1 3 -3 5 7 -7 10 26 100 641 274177 -6700417 1000000007 0x5555555555555555 0x4000000000000000 -8 0x7fffffffffffffff -0x7fffffffffffffff MIN"
}

function curated_lit(t, v) {
    if (v == "MIN") return min_lit(t)
    if (substr(v, 1, 1) == "-") return lit(t, substr(v, 2), 1)
    return lit(t, v, 0)
}

function min_lit(t) {
    if (t == "i64") return "(0i64 - 0x7fffffffffffffffi64 - 1i64)"
    return "(0" t " - " sprintf("%.0f", pow2(bits(t) - 1) - 1) t " - 1" t ")"
}

BEGIN {
    srand(seed)
    if (count == "") count = 6
    if (iterations == "") iterations = 2000
    nt = split("u8 u16 u32 u64 i8 i16 i32 i64", types, " ")
    if (curated) {
        print "// Divisions by constants (0.11), made by tests/fuzz/gendiv.awk -v curated=1"
        print "// -v iterations=" iterations " -v seed=" seed "."
    } else {
        print "// A random program of divisions by constants (tests/fuzz/gendiv.awk, seed " seed ")."
    }
    print "extern \"C\" {"
    print "    fn printf(format: *u8, ...) -> i32;"
    print "}"
    print ""
    nf = 0
    for (ti = 1; ti <= nt; ti++) {
        t = types[ti]
        nc = curated ? split(curated_list(t), clist, " ") : count
        for (j = 0; j < nc; j++) {
            c = curated ? curated_lit(t, clist[j + 1]) : divisor(t)
            f = "k" nf
            fty[nf] = t
            nf++
            print "// " t " by " c
            print "fn " f "_one(x: " t ", rt: " t ") -> u64 {"
            print "    let q = x / " c ";"
            print "    let r = x % " c ";"
            print "    if q != x / rt || r != x % rt {"
            print "        unsafe { printf(c\"FAIL " f " %ld: %ld %ld, %ld %ld\\n\", x as i64, q as i64, r as i64, (x / rt) as i64, (x % rt) as i64); }"
            print "    }"
            print "    (q as u64) * 7u64 + (r as u64)"
            print "}"
            print ""
            print "fn " f "(x: " t ", z: " t ") -> u64 {"
            print "    let rt = " c " + z;"
            print "    let m = x / rt * rt;"
            print "    let mut sum = " f "_one(x, rt);"
            print "    sum = sum * 31u64 + " f "_one(m, rt);"
            print "    sum = sum * 31u64 + " f "_one(m - 1" t ", rt);"
            print "    sum = sum * 31u64 + " f "_one(m + 1" t ", rt);"
            print "    sum"
            print "}"
            print ""
            print "#[inline(never)]"
            print "fn " f "_q(x: " t ") -> " t " {"
            print "    x / " c
            print "}"
            print ""
            print "#[inline(never)]"
            print "fn " f "_r(x: " t ") -> " t " {"
            print "    x % " c
            print "}"
            print ""
        }
    }
    print "fn main() -> i32 {"
    print "    let z = unsafe { printf(c\"\") } as u64;"
    print "    let special: [u64; 24] = [0u64, 1u64, 2u64, 3u64, 0x7fu64, 0x80u64, 0xffu64, 0x7fffu64, 0x8000u64, 0xffffu64,"
    print "        0x7fffffffu64, 0x80000000u64, 0xffffffffu64, 0x7fffffffffffffffu64, 0x8000000000000000u64,"
    print "        0xffffffffffffffffu64, 0xfffffffffffffffeu64, 0x8000000000000001u64, 0xffffffff80000000u64,"
    print "        0xffffffffffff8000u64, 0xffffffffffffff80u64, 0x7ffffffeu64, 0xfffffffeu64, 0x100000000u64];"
    print "    let mut state = " (1 + rnd(1000000)) "u64;"
    print "    let mut acc = 0u64;"
    print "    let mut i = 0;"
    print "    while i < " iterations " {"
    print "        let mut x = 0u64;"
    print "        if i < 24 {"
    print "            x = special[i];"
    print "        } else {"
    print "            state = state * 6364136223846793005u64 + 1442695040888963407u64;"
    print "            x = state ^ (state >> 29u64);"
    print "            if i % 3 == 0 {"
    print "                x = x >> (state >> 58u64);"
    print "            }"
    print "        }"
    for (k = 0; k < nf; k++) {
        t = fty[k]
        print "        acc = acc * 31u64 + k" k "(x as " t ", z as " t ");"
        print "        acc = acc * 31u64 + (k" k "_r(x as " t ") as u64);"
        print "        acc = acc * 31u64 + (k" k "_q((x ^ 0x5555u64) as " t ") as u64);"
    }
    print "        i += 1;"
    print "    }"
    print "    unsafe { printf(c\"%lu\\n\", acc); }"
    print "    0"
    print "}"
}
