// bench/std: parse 10,000,000 decimal i64 texts (random magnitude and
// sign, made first, in one buffer) with str::parse::<i64>, three times.
// Prints the count and the sum.
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
    let mut text: Vec<u8> = Vec::with_capacity(n * 21);
    for _ in 0..n {
        let r = next(&mut st);
        let mut m = r >> (r & 63);
        if r & 64 != 0 { text.push(b'-'); }
        let mut d = [0u8; 20];
        let mut k = 20;
        loop {
            k -= 1;
            d[k] = b'0' + (m % 10) as u8;
            m /= 10;
            if m == 0 { break; }
        }
        text.extend_from_slice(&d[k..]);
        text.push(b' ');
    }
    let s = std::str::from_utf8(&text).unwrap();
    let mut sum = 0i64;
    let mut count = 0;
    for _ in 0..3 {
        for w in s.split_ascii_whitespace() {
            let v: i64 = w.parse().unwrap_or(0);
            sum = sum.wrapping_add(v);
            count += 1;
        }
    }
    println!("{} {}", count, sum);
}
