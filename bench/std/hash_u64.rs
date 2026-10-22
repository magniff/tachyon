// bench/std: HashMap<u64, u64>, 2,000,000 inserts of random u64, then
// 2,000,000 lookups (half hits). Variants (argv[1]): `default` (SipHash),
// `same` (vole's hash), `fold` (foldhash's): fairhash.rs.
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
    let n = 2_000_000usize;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut keys = Vec::with_capacity(n);
    let mut m: HashMap<u64, u64, S> = HashMap::with_hasher(s);
    for i in 0..n {
        let k = next(&mut st);
        keys.push(k);
        m.insert(k, i as u64);
    }
    let (mut found, mut sum) = (0u64, 0u64);
    for i in 0..n {
        let k = if i % 2 == 0 { keys[i] } else { next(&mut st) };
        if let Some(v) = m.get(&k) {
            found += 1;
            sum = sum.wrapping_add(*v);
        }
    }
    println!("{} {} {}", found, sum, m.len());
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("same") => run(fairhash::Same),
        Some("fold") => run(fairhash::Fold),
        _ => run(std::collections::hash_map::RandomState::new()),
    }
}
