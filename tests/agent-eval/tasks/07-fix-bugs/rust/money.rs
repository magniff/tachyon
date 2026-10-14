// Money is kept in cents (an integer) and printed as D.CC.

// Appends `cents` as dollars and cents: 1234 -> "12.34", 5 -> "0.05".
pub fn push_cents(out: &mut String, cents: i64) {
    let mut c = cents;
    if c < 0 {
        out.push('-');
        c = -c;
    }
    out.push_str(&(c / 100).to_string());
    out.push('.');
    let rest = c % 100;
    if rest < 10 {
        out.push('0');
    }
    out.push_str(&rest.to_string());
}

// `percent`% of `cents`, rounded down to a whole cent.
pub fn percent_of(cents: i64, percent: i64) -> i64 {
    cents * percent / 100
}
