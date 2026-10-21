// bench/std: Display of 10,000,000 random i64 (random magnitude and sign)
// into one String, a space after each, cleared every 64 KB. Prints the
// length written and the FNV-1a hash.
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
    let n = 10_000_000;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut out = String::with_capacity(1 << 17);
    let mut h = 0xcbf29ce484222325u64;
    let mut total = 0usize;
    for _ in 0..n {
        let r = next(&mut st);
        let v = (r >> (r & 63)) as i64;
        let v = if r & 64 != 0 { v.wrapping_neg() } else { v };
        write!(out, "{} ", v).unwrap();
        if out.len() > 65536 {
            for &b in out.as_bytes() {
                h = (h ^ b as u64).wrapping_mul(0x100000001b3);
            }
            total += out.len();
            out.clear();
        }
    }
    for &b in out.as_bytes() {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    total += out.len();
    println!("{} {}", total, h);
}
