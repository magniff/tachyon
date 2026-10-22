# Writes a random vole program of loops indexing arrays of fixed sizes
# (0.11): induction variables with steps of 1 to 4, steps read from the
# array, decreasing ones, two of them together, sift-downs (`child + 1 <
# end && a[child] < a[child + 1]`); now and then an index goes past an end
# (the bounds check stops the program with 101, alike at every level). The
# range analysis drops the checks it proves (range.vl): every level must
# print the same.
#
# usage: awk -v seed=N -f genrange.awk

function rnd(n) { return int(rand() * n) }

BEGIN {
    srand(seed)
    print "extern \"C\" {\n    fn printf(f: *u8, ...) -> i32;\n}\n"
    nf = 6
    for (f = 0; f < nf; f++) {
        n = 8 + rnd(60)
        size[f] = n
        print "#[inline(never)]"
        print "fn f" f "(a: [i64; " n "], x: i64) -> i64 {"
        print "    var t = 0;"
        kind = rnd(5)
        off = (rnd(5) == 0) ? rnd(5) - 2 : rnd(2)
        risky = rnd(6) == 0
        if (kind == 0) {
            # increasing, a constant step
            step = 1 + rnd(4)
            bound = n - off - rnd(4) + (risky ? rnd(4) : 0)
            print "    var i = " rnd(3) ";"
            print "    while i < " bound " {"
            print "        t += a[i + " off "] * 3 + i;"
            print "        i += " step ";"
            print "    }"
        } else if (kind == 1) {
            # a step read from the array
            bound = n - off - rnd(4) + (risky ? rnd(3) : 0)
            print "    var i = 0;"
            print "    while i < " bound " {"
            print "        t += a[i + " off "];"
            print "        i += 1 + (a[i % " n "] & " (1 + rnd(7)) ");"
            print "    }"
        } else if (kind == 2) {
            # decreasing
            start = n - (risky ? rnd(3) - 1 : rnd(3))
            step = 1 + rnd(3)
            print "    var i = " start ";"
            print "    while i > " rnd(3) " {"
            print "        i -= " step ";"
            print "        t += a[i" (risky ? " + 1" : "") "] - i;"
            print "    }"
        } else if (kind == 3) {
            # a sift-down
            print "    var root = x % " n ";"
            print "    if root < 0 { root = 0 - root; }"
            print "    let end = " (n - rnd(3) + (risky ? rnd(2) : 0)) ";"
            print "    loop {"
            print "        var child = 2 * root + 1;"
            print "        if child >= end {"
            print "            break;"
            print "        }"
            print "        if child + 1 < end && a[child] < a[child + 1] {"
            print "            child += 1;"
            print "        }"
            print "        t += a[root] * 2 + a[child];"
            print "        root = child;"
            print "    }"
        } else {
            # two induction variables, one reset
            step = 1 + rnd(3)
            print "    var i = 0;"
            print "    var j = " rnd(4) ";"
            print "    while i < " (n - rnd(4)) " {"
            print "        t += a[i] + a[j % " n "] + a[(i + j) / 2];"
            print "        i += " step ";"
            print "        j += " (step + rnd(2)) ";"
            print "        if j > " n " { j = " rnd(3) "; }"
            print "    }"
        }
        print "    t"
        print "}\n"
    }
    print "fn main() -> i32 {"
    for (f = 0; f < nf; f++) {
        print "    var a" f ": [i64; " size[f] "] = [0; " size[f] "];"
        print "    for k in 0.." size[f] " {"
        print "        a" f "[k] = (k * " (3 + rnd(20)) " + " rnd(9) ") % " (5 + rnd(30)) ";"
        print "    }"
        print "    unsafe { printf(c\"%ld\\n\", f" f "(a" f ", " rnd(100) ")); }"
    }
    print "    0"
    print "}"
}
