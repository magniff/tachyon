// bench/std: Display of 1,000,000 random f64 (in [0, 1e6), every
// mantissa bit random) into one String, a space after each. Prints the
// text's length and its FNV-1a hash (DUMP=1 in the environment: the text).
use std::fmt::Write;

fn next(s: &mut u64) -> u64 {
    let mut x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    x
}

fn main() {
    let n = 1_000_000;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut out = String::with_capacity(n * 20);
    for _ in 0..n {
        let x = (next(&mut st) >> 11) as f64 * (1.0 / 9007199254740992.0) * 1e6;
        write!(out, "{} ", x).unwrap();
    }
    let mut h = 0xcbf29ce484222325u64;
    for &b in out.as_bytes() {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    if std::env::var_os("DUMP").is_some() {
        print!("{}", out);
    }
    println!("{} {}", out.len(), h);
}
