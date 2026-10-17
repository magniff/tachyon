// bench/std: parse 1,000,000 float texts `d.ddddddddddddddddeX` (17 random
// digits, the exponent in [-300, 300]: the shape of a shortest f64) with
// str::parse::<f64>, the texts made first, in one buffer, five times. Prints the
// count and the FNV-1a hash of the bits read.
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
    let mut text: Vec<u8> = Vec::with_capacity(n * 24);
    for _ in 0..n {
        let r = next(&mut st);
        let mut m = r % 100000000000000000;
        let mut d = [0u8; 17];
        for k in 0..17 {
            d[16 - k] = b'0' + (m % 10) as u8;
            m /= 10;
        }
        text.push(d[0]);
        text.push(b'.');
        text.extend_from_slice(&d[1..]);
        text.push(b'e');
        let e = (next(&mut st) % 601) as i64 - 300;
        text.extend_from_slice(e.to_string().as_bytes());
        text.push(b' ');
    }
    let s = std::str::from_utf8(&text).unwrap();
    let mut h = 0xcbf29ce484222325u64;
    let mut count = 0;
    for _ in 0..5 {
        for w in s.split_ascii_whitespace() {
            let v: f64 = w.parse().unwrap();
            h = (h ^ v.to_bits()).wrapping_mul(0x100000001b3);
            count += 1;
        }
    }
    println!("{} {}", count, h);
}
