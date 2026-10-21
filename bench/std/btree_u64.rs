// bench/std: btree_u64, 1M inserts of random u64 keys, 1M lookups (half of
// them hits), and 1000 range scans of about 1000 pairs each, on std's
// BTreeMap. (The argument `sip` is accepted, for the harness, and changes
// nothing: a B-tree does not hash.)
use std::collections::BTreeMap;

fn xorshift(x: &mut u64) -> u64 {
    let mut v = *x;
    v ^= v << 13;
    v ^= v >> 7;
    v ^= v << 17;
    *x = v;
    v
}

fn main() {
    let n = 1000000;
    let mut m: BTreeMap<u64, u64> = BTreeMap::new();
    let mut x = 0x9e3779b97f4a7c15u64;
    for i in 0..n {
        m.insert(xorshift(&mut x), i as u64);
    }
    let mut y = 0x9e3779b97f4a7c15u64;
    let mut sum = 0u64;
    let mut hits = 0;
    for i in 0..n {
        let k = if i % 2 == 0 { xorshift(&mut y) } else { xorshift(&mut x) };
        if let Some(v) = m.get(&k) {
            sum = sum.wrapping_add(*v);
            hits += 1;
        }
    }
    let mut scanned = 0;
    let mut ssum = 0u64;
    for _ in 0..1000 {
        let lo = xorshift(&mut x) >> 1;
        for (_, v) in m.range(lo..lo + (1u64 << 54)) {
            scanned += 1;
            ssum = ssum.wrapping_add(*v);
        }
    }
    println!("{} {} {} {} {}", m.len(), hits, sum, scanned, ssum);
}
