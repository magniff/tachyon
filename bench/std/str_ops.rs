// bench/std: str's methods on 2,000,000 CSV-like lines (`k123, -4567 ,
// abcab`, made first): lines(), split(','), trim(), parse::<i64>(),
// starts_with, contains, three times. Prints the lines, the sum of the
// numbers, the words that contain "ab" and the keys that start with "k1".
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
    let n = 2_000_000u64;
    let mut st = 0x9E3779B97F4A7C15u64;
    let mut text = String::with_capacity(n as usize * 32);
    let letters = b"abcde";
    for _ in 0..n {
        let r = next(&mut st);
        write!(text, "k{}, {} , ", r % 1000, (r >> 10) as i64 % 100000 - 50000).unwrap();
        let len = 3 + (r >> 40) % 6;
        for j in 0..len {
            text.push(letters[((r >> (j * 3)) % 5) as usize] as char);
        }
        text.push('\n');
    }
    let s = text.as_str();
    let mut lines = 0i64;
    let mut sum: i64 = 0;
    let mut ab = 0i64;
    let mut k1 = 0i64;
    for _ in 0..3 {
        for line in s.lines() {
            let mut f = line.split(',');
            let key = f.next().unwrap();
            let num: i64 = f.next().unwrap().trim().parse().unwrap_or(0);
            let word = f.next().unwrap().trim();
            lines += 1;
            sum += num;
            if word.contains("ab") {
                ab += 1;
            }
            if key.starts_with("k1") {
                k1 += 1;
            }
        }
    }
    println!("{} {} {} {}", lines, sum, ab, k1);
}
