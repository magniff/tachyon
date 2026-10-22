// bench/std: word count, 4,000,000 pseudo-random words counted in a
// HashMap<&[u8], u64>. Variants (argv[1]): `default` (SipHash), `same`
// (vole's hash), `fold` (foldhash's): fairhash.rs.
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

fn run<S: BuildHasher>(h: S) {
    let words = 4_000_000;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut text: Vec<u8> = Vec::with_capacity(words * 6);
    for _ in 0..words {
        let a = next(&mut st) % 4096;
        let b = next(&mut st) % 4096;
        let mut id = a * b / 64;
        loop {
            text.push(b'a' + (id % 26) as u8);
            id /= 26;
            if id == 0 {
                break;
            }
        }
        text.push(b' ');
    }
    let mut counts: HashMap<&[u8], u64, S> = HashMap::with_hasher(h);
    let mut total = 0u64;
    let mut i = 0;
    while i < text.len() {
        let start = i;
        while text[i] != b' ' {
            i += 1;
        }
        *counts.entry(&text[start..i]).or_insert(0) += 1;
        total += 1;
        i += 1;
    }
    let squares: u64 = counts.values().map(|c| c * c).sum();
    println!("{} {} {}", counts.len(), total, squares);
}

fn main() {
    match std::env::args().nth(1).as_deref() {
        Some("same") => run(fairhash::Same),
        Some("fold") => run(fairhash::Fold),
        _ => run(std::collections::hash_map::RandomState::new()),
    }
}
