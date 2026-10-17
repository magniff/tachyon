// bench/std: sort 5,000,000 random u64 (xorshift64), sort_unstable.
fn next(s: &mut u64) -> u64 {
    let mut x = *s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    *s = x;
    x
}

fn main() {
    let n = 5_000_000;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut v: Vec<u64> = Vec::with_capacity(n);
    for _ in 0..n {
        v.push(next(&mut st));
    }
    v.sort_unstable();
    let mut sum = 0u64;
    for x in &v {
        sum = sum.wrapping_mul(31).wrapping_add(*x);
    }
    println!("{}", sum);
}
