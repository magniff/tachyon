#!/bin/sh
# Two branches change the same lines, then meet: run in a git checkout of
# this directory on branch main. The edits are made with volec, as an
# agent on each branch would make them.
set -eu

# Branch rounding: every conversion rounds to the nearest whole number.
git checkout -q -b rounding
volec edit insert --before c_to_f >/dev/null 2>&1 <<'EOF'
// a / b, rounded to the nearest whole number (b > 0).
fn round_div(a: i64, b: i64) -> i64 {
    if a >= 0 { (a + b / 2) / b } else { (a - b / 2) / b }
}
EOF
volec edit patch c_to_f --old 'c * 9 / 5 + 32' --new 'round_div(c * 9, 5) + 32' >/dev/null 2>&1
volec edit patch f_to_c --old '(f - 32) * 5 / 9' --new 'round_div((f - 32) * 5, 9)' >/dev/null 2>&1
volec edit patch km_to_mi --old 'km * 1000 / 1609' --new 'round_div(km * 1000, 1609)' >/dev/null 2>&1
volec edit patch kg_to_lb --old 'kg * 100000 / 45359' --new 'round_div(kg * 100000, 45359)' >/dev/null 2>&1
volec edit patch main --old 'println("km  miles");' --new 'println("km  miles (rounded)");' >/dev/null 2>&1
volec edit insert --after kg_to_lb >/dev/null 2>&1 <<'EOF'
// Pounds to kilograms.
pub fn lb_to_kg(lb: i64) -> i64 {
    round_div(lb * 45359, 100000)
}
EOF
volec edit insert --in main --before 'println("kg  pounds");' >/dev/null 2>&1 <<'EOF'
println("pounds  kg");
for lb in [1, 100, 150] {
    println(f"{lb:>6}  {lb_to_kg(lb):>2}");
}
EOF
git commit -q -a -m 'Round every conversion to the nearest whole number'

# Branch main: miles back to kilometres, with the metres in a mile named.
git checkout -q main
volec edit insert --before km_to_mi >/dev/null 2>&1 <<'EOF'
const METRES_PER_MILE: i64 = 1609;
EOF
volec edit patch km_to_mi --old 'km * 1000 / 1609' --new 'km * 1000 / METRES_PER_MILE' >/dev/null 2>&1
volec edit insert --after km_to_mi >/dev/null 2>&1 <<'EOF'
// Miles to kilometres.
pub fn mi_to_km(mi: i64) -> i64 {
    mi * METRES_PER_MILE / 1000
}
EOF
volec edit insert --in main --before 'println("kg  pounds");' >/dev/null 2>&1 <<'EOF'
println("miles  km");
for mi in [1, 26, 100] {
    println(f"{mi:>5}  {mi_to_km(mi):>3}");
}
EOF
git commit -q -a -m 'Miles to kilometres'

git merge rounding
