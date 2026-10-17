// bench/std: HashMap<u64, u64> churn, 10,000,000 operations on about
// 100,000 keys (insert the i-th key, remove the one inserted 100,000
// before). Variants (argv[1]): `default` (SipHash), `same` (tachyon's
// 0.19 hash), `fold` (foldhash's): fairhash.rs.
use std::collections::HashMap;
use std::hash::BuildHasher;
mod fairhash;

fn next(s: &mut u64) -> u64 {
    let mut x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    x
}

fn run<S: BuildHasher>(s: S) {
    let ops = 10_000_000u64;
    let lag = 100_000u64;
    let mut ins = 0x9E3779B97F4A7C15u64;
    let mut del = ins;
    let mut m: HashMap<u64, u64, S> = HashMap::with_hasher(s);
    let (mut removed, mut sum) = (0u64, 0u64);
    for i in 0..ops / 2 {
        m.insert(next(&mut ins), i);
        if i >= lag {
            if let Some(v) = m.remove(&next(&mut del)) {
                removed += 1;
                sum = sum.wrapping_add(v);
            }
        }
    }
    println!("{} {} {}", m.len(), removed, sum);
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("same") => run(fairhash::Same),
        Some("fold") => run(fairhash::Fold),
        _ => run(std::collections::hash_map::RandomState::new()),
    }
}
