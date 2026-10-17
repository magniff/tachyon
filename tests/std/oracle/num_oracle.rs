// The Rust side of std's number-conversion checks (0.20, compiler/std/num.tach):
// prints, chunk by chunk, an FNV-1a hash of Rust's text for each value, so
// that tests/std/oracle/num_check.tach, which prints the same lines from
// tachyon's std, can be compared with it (tests/std/oracle/num.sh). The
// values are made the same way on both sides (xorshift64, fixed seeds).
//
//   num_oracle f32 LO HI       every f32 with bits in [LO, HI): {} {:?} {:e}
//   num_oracle f64 SEED N      N f64s (num_values below): {} {:?} {:e}
//   num_oracle parse SEED N    N float texts (num_text below): the f64 and
//                              f32 they parse to, as bits
//   num_oracle text SEED N     those texts, one per line (to debug)
//   num_oracle ints SEED N     N i64s: {} and their parse back
//
// A line: `INDEX HASH` per chunk of CHUNK values.
use std::fmt::Write;

const CHUNK: u64 = 1 << 20;

struct Fnv(u64);
impl Fnv {
    fn new() -> Fnv { Fnv(0xcbf29ce484222325) }
    fn bytes(&mut self, s: &[u8]) {
        for &b in s {
            self.0 ^= b as u64;
            self.0 = self.0.wrapping_mul(0x100000001b3);
        }
        self.0 ^= b'\n' as u64;
        self.0 = self.0.wrapping_mul(0x100000001b3);
    }
    fn u64(&mut self, x: u64) {
        let mut buf = String::new();
        write!(buf, "{}", x).unwrap();
        self.bytes(buf.as_bytes());
    }
}

struct Rng(u64);
impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x << 13;
        x ^= x >> 7;
        x ^= x << 17;
        self.0 = x;
        x
    }
    fn below(&mut self, n: u64) -> u64 { self.next() % n }
}

// The i-th value of the f64 sample: raw bits, a near-1 exponent, an
// integer, or a short decimal.
fn num_value(r: &mut Rng) -> f64 {
    let kind = r.below(4);
    if kind == 0 {
        loop {
            let v = f64::from_bits(r.next());
            if v.is_finite() { return v; }
        }
    }
    if kind == 1 {
        let m = r.next() & 0xfffffffffffff;
        let e = 1023 - 70 + r.below(140);
        return f64::from_bits((r.next() & (1 << 63)) | (e << 52) | m);
    }
    if kind == 2 {
        let bits = r.below(64);
        return (r.next() >> bits) as f64;
    }
    let digits = 1 + r.below(17);
    let mut d: u64 = 0;
    for _ in 0..digits { d = d * 10 + r.below(10); }
    let k = r.below(41) as i64 - 20;
    let p = 10f64.powi(k.abs() as i32);
    if k < 0 { d as f64 / p } else { d as f64 * p }
}

// The i-th float text: digits (1 to 40, some zeros), a point somewhere or
// none, an exponent or none, a sign or none; sometimes a special case.
fn num_text(r: &mut Rng, out: &mut Vec<u8>) {
    out.clear();
    let sign = r.below(4);
    if sign == 0 { out.push(b'-'); } else if sign == 1 { out.push(b'+'); }
    let n = if r.below(8) == 0 { 1 + r.below(40) } else { 1 + r.below(19) };
    let point = r.below(n + 2);
    let zeros = r.below(3);
    for i in 0..n {
        if i == point && i > 0 { out.push(b'.'); }
        let d = if zeros == 0 && r.below(3) == 0 { 0 } else { r.below(10) };
        out.push(b'0' + d as u8);
    }
    if point == n { out.push(b'.'); }
    if r.below(3) != 0 {
        out.push(if r.below(2) == 0 { b'e' } else { b'E' });
        let es = r.below(3);
        if es == 0 { out.push(b'-'); } else if es == 1 { out.push(b'+'); }
        let e = if r.below(2) == 0 { r.below(30) } else { r.below(400) };
        let mut buf = String::new();
        write!(buf, "{}", e).unwrap();
        out.extend_from_slice(buf.as_bytes());
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mode = args[1].as_str();
    let a: u64 = args[2].parse().unwrap();
    let b: u64 = args[3].parse().unwrap();
    let mut s = String::new();
    match mode {
        "f32" => {
            let lo = a;
            let hi = b;
            let threads = 12;
            let chunks: Vec<u64> = (lo / CHUNK..(hi + CHUNK - 1) / CHUNK).collect();
            let mut results: Vec<(u64, u64)> = Vec::new();
            std::thread::scope(|sc| {
                let hs: Vec<_> = (0..threads).map(|t| {
                    let chunks = &chunks;
                    sc.spawn(move || {
                        let mut res = Vec::new();
                        let mut s = String::new();
                        for (j, &c) in chunks.iter().enumerate() {
                            if j % threads != t { continue; }
                            let mut h = Fnv::new();
                            let start = (c * CHUNK).max(lo);
                            let end = ((c + 1) * CHUNK).min(hi);
                            for bits in start..end {
                                let v = f32::from_bits(bits as u32);
                                if !v.is_finite() { continue; }
                                s.clear(); write!(s, "{}", v).unwrap(); h.bytes(s.as_bytes());
                                s.clear(); write!(s, "{:?}", v).unwrap(); h.bytes(s.as_bytes());
                                s.clear(); write!(s, "{:e}", v).unwrap(); h.bytes(s.as_bytes());
                            }
                            res.push((c, h.0));
                        }
                        res
                    })
                }).collect();
                for h in hs { results.extend(h.join().unwrap()); }
            });
            results.sort();
            for (c, h) in results { println!("{} {:016x}", c, h); }
        }
        "f64" => {
            let mut r = Rng(a);
            let mut h = Fnv::new();
            for i in 0..b {
                let v = num_value(&mut r);
                s.clear(); write!(s, "{}", v).unwrap(); h.bytes(s.as_bytes());
                s.clear(); write!(s, "{:?}", v).unwrap(); h.bytes(s.as_bytes());
                s.clear(); write!(s, "{:e}", v).unwrap(); h.bytes(s.as_bytes());
                if (i + 1) % CHUNK == 0 || i + 1 == b {
                    println!("{} {:016x}", i / CHUNK, h.0);
                    h = Fnv::new();
                }
            }
        }
        "ftext" => {
            let mut r = Rng(a);
            for _ in 0..b {
                let v = num_value(&mut r);
                println!("{:016x} {} {:?} {:e}", v.to_bits(), v, v, v);
            }
        }
        "parse" | "text" => {
            let mut r = Rng(a);
            let mut h = Fnv::new();
            let mut t = Vec::new();
            for i in 0..b {
                num_text(&mut r, &mut t);
                let st = std::str::from_utf8(&t).unwrap();
                let x: f64 = st.parse().unwrap();
                let y: f32 = st.parse().unwrap();
                if mode == "text" {
                    println!("{} {:016x} {:08x}", st, x.to_bits(), y.to_bits());
                    continue;
                }
                h.u64(x.to_bits());
                h.u64(y.to_bits() as u64);
                if (i + 1) % CHUNK == 0 || i + 1 == b {
                    println!("{} {:016x}", i / CHUNK, h.0);
                    h = Fnv::new();
                }
            }
        }
        "ints" => {
            let mut r = Rng(a);
            let mut h = Fnv::new();
            for i in 0..b {
                let v = (r.next() >> r.below(64)) as i64;
                let v = if r.below(2) == 0 { v } else { v.wrapping_neg() };
                s.clear(); write!(s, "{}", v).unwrap(); h.bytes(s.as_bytes());
                let back: i64 = s.parse().unwrap();
                h.u64(back as u64);
                if (i + 1) % CHUNK == 0 || i + 1 == b {
                    println!("{} {:016x}", i / CHUNK, h.0);
                    h = Fnv::new();
                }
            }
        }
        _ => panic!("mode"),
    }
}
