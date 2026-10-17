// bench/std: `{:.3}` of 1,000,000 random f64 (in [0, 1e6)) into one
// String, a space after each. Prints the length and the FNV-1a hash.
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
    let mut out = String::with_capacity(n * 16);
    for _ in 0..n {
        let x = (next(&mut st) >> 11) as f64 * (1.0 / 9007199254740992.0) * 1e6;
        write!(out, "{:.3} ", x).unwrap();
    }
    let mut h = 0xcbf29ce484222325u64;
    for &b in out.as_bytes() {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    println!("{} {}", out.len(), h);
}
