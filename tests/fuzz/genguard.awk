# Writes a random vole program of guarded accesses in loops (0.25): an
# element of an array, of a static array, of a struct's array field, of a
# slice, a field through a raw pointer (behind a null test), at an index
# far out of bounds, and calls that return only after 2^62 steps, under
# conditions that never hold (`k > 1000`, `j + k < 0`, `Z > 5`), in `for`,
# `while`, `loop`-with-`break` and nested loops; beside them accesses at
# good indices under conditions that do hold, guarded stores (scalar
# promotion's case) and plain work. Nothing may run where the program
# does not run it (LICM's preheader, promotion's load, if-conversion):
# every level must print the same, and none may crash or hang (run.sh -G
# stops a program after a few seconds).
#
# usage: awk -v seed=N -f genguard.awk

function rnd(n) { return int(rand() * n) }

# A condition in loop variable k (and j, in a nested loop) that never holds.
function never(nested) {
    c = rnd(nested ? 7 : 6)
    if (c == 0) return "k > " (1000 + rnd(1000))
    if (c == 1) return "k < 0"
    if (c == 2) return "k == " (bound + 3 + rnd(50)) " + Z"
    if (c == 3) return "Z > " (5 + rnd(5))
    if (c == 4) return "k * 2 == " (2 * bound + 1 + 2 * rnd(9))
    if (c == 5) return "k + Z > " (bound + 900)
    return "j + k > " (1000 + rnd(99))
}

# A condition that holds in some iterations.
function sometimes() {
    c = rnd(4)
    if (c == 0) return "k == " rnd(bound)
    if (c == 1) return "(k & " (1 + rnd(3)) ") == 0"
    if (c == 2) return "k + Z < " (1 + rnd(bound))
    return "Z == 0"
}

# An index far out of every bound (x is one, made from Z in main).
function far() {
    c = rnd(4)
    if (c == 0) return "x"
    if (c == 1) return "x + " rnd(4)
    if (c == 2) return "x + Z"
    return "y"
}

# An access at index `ix`, read.
function access(ix, sz) {
    c = rnd(6)
    if (c == 0) return "a[" ix "]"
    if (c == 1) return "G[" ix "]"
    if (c == 2) return "s.cells[" ix "]"
    if (c == 3) return "sl[" ix "]"
    if (c == 4) return "s.n + a[" ix "]"
    return "G[" ix "] * 3"
}

# One statement of a loop body (indented by `ind`).
function statement(ind, nested) {
    c = rnd(12)
    if (c <= 3) {
        print ind "if " never(nested) " { t += " access(far()) "; }"
    } else if (c == 4) {
        print ind "if " never(nested) " { t += slow(big); }"
    } else if (c == 5) {
        print ind "if " never(nested) " { a[" far() "] += k; }"
    } else if (c == 6) {
        print ind "if " never(nested) " && p != 0 as *Node { t += unsafe { (*p).v }; }"
    } else if (c == 7) {
        print ind "if " sometimes() " { t += " access("m") "; }"
    } else if (c == 8) {
        print ind "if " sometimes() " { a[m] += k + " rnd(5) "; }"
    } else if (c == 9) {
        print ind "if " sometimes() " && q != 0 as *Node { t += unsafe { (*q).v } + k; }"
    } else if (c == 10) {
        print ind "t += a[m] + G[" rnd(4) "];"
    } else {
        print ind "t = t * " (2 + rnd(5)) " + k;"
    }
}

function body(ind, nested) {
    n = 1 + rnd(4)
    for (st = 0; st < n; st++) statement(ind, nested)
}

BEGIN {
    srand(seed)
    print "extern \"C\" {\n    fn printf(f: *u8, ...) -> i32;\n}\n"
    print "static var Z: i64 = 0;"
    print "static var G: [i64; 4] = [" rnd(9) ", " rnd(9) ", " rnd(9) ", " rnd(9) "];\n"
    print "struct Grid { cells: [i64; 3], n: i64 }"
    print "struct Node { v: i64, next: i64 }\n"
    print "// Returns (willreturn, readnone, nopanic), after n steps: 2^62 of them."
    print "#[inline(never)]"
    print "fn slow(n: i64) -> i64 {"
    print "    var t = 0;"
    print "    for i in 0..n { t = t * 31 + i; }"
    print "    t"
    print "}\n"
    nf = 6
    for (f = 0; f < nf; f++) {
        bound = 2 + rnd(9)
        print (rnd(2) ? "#[inline(never)]\n" : "") "fn f" f "(x: i64, y: i64, m: i64, s: Grid, sl: [i64], p: *Node, q: *Node, big: i64) -> i64 {"
        print "    var a = [" rnd(9) ", " rnd(9) ", " rnd(9) "];"
        print "    var t = 0;"
        kind = rnd(5)
        if (kind == 0) {
            print "    for k in 0.." bound " + Z {"
            body("        ", 0)
            print "    }"
        } else if (kind == 1) {
            print "    var k = 0;"
            print "    while k < " bound " + Z {"
            body("        ", 0)
            print "        k += 1;"
            print "    }"
        } else if (kind == 2) {
            print "    var k = 0;"
            print "    loop {"
            if (rnd(2)) print "        if k >= " bound " + Z { break; }"
            body("        ", 0)
            if (rnd(3) == 0) print "        if Z == 0 && k == " rnd(bound) " { break; }"
            print "        k += 1;"
            print "        if k >= " bound " + Z { break; }"
            print "    }"
        } else if (kind == 3) {
            print "    for j in 0.." (1 + rnd(4)) " + Z {"
            print "        for k in 0.." bound " + Z {"
            body("            ", 1)
            print "        }"
            if (rnd(2)) print "        t += j;"
            print "    }"
        } else {
            # the guarded statement first, then a break that always comes
            print "    var k = 0;"
            print "    while k < " bound " + Z {"
            print "        t += 1;"
            print "        k += 1;"
            print "        if Z == 0 { continue; }"
            print "        t += " access(far()) ";"
            print "    }"
        }
        print "    t + a[m]"
        print "}\n"
    }
    print "fn main() -> i32 {"
    print "    Z = std::env::args().len() - 1;"
    print "    let x = " (rnd(2) ? "-1099511627776" : "1099511627776") " + Z;"
    print "    let y = -9223372036854775807 + Z;"
    print "    let big = 4611686018427387904 + Z;"
    print "    let s = Grid { cells: [" rnd(9) ", " rnd(9) ", " rnd(9) "], n: " rnd(9) " };"
    print "    let b = [" rnd(9) ", " rnd(9) ", " rnd(9) ", " rnd(9) "];"
    print "    var node = Node { v: " rnd(99) ", next: 0 };"
    print "    let null = 0 as *Node;"
    print "    let good = &node as *Node;"
    for (f = 0; f < nf; f++) {
        print "    unsafe { printf(c\"%ld\\n\", f" f "(x, y, " rnd(3) " + Z, s, b[0.." (3 + rnd(2)) "], null, good, big)); }"
    }
    print "    0"
    print "}"
}
