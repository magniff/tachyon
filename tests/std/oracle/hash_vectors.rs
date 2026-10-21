// The hash vectors of tests/run/std_hash_vectors.tach (0.20): foldhash
// 0.2.0's fast FixedState (the crate itself, not a port) and Rust's
// DefaultHasher (SipHash-1-3, keys 0 and 0), over 100000 random sequences
// of writes. It needs the crate: in a cargo project with
// `foldhash = "=0.2.0"` (default-features = false) as its src/main.rs,
// `cargo run --release` prints the case's EXPECT lines but the last.
use std::collections::hash_map::DefaultHasher;
use std::hash::{BuildHasher, Hash, Hasher};

fn xorshift(x: &mut u64) -> u64 {
    let mut v = *x;
    v ^= v << 13;
    v ^= v >> 7;
    v ^= v << 17;
    *x = v;
    v
}

fn feed<H: Hasher>(h: &mut H, rng: &mut u64, pool: &[u8]) {
    let ops = 1 + xorshift(rng) % 5;
    for _ in 0..ops {
        let r = xorshift(rng);
        let x = xorshift(rng);
        match r % 6 {
            0 => h.write_u8(x as u8),
            1 => h.write_u16(x as u16),
            2 => h.write_u32(x as u32),
            3 => h.write_u64(x),
            4 => {
                let n = (x % 41) as usize;
                let at = ((x >> 16) % (1024 - 40)) as usize;
                h.write(&pool[at..at + n]);
            }
            _ => {
                let n = (x % 701) as usize;
                let at = ((x >> 16) % (1024 - 700)) as usize;
                h.write(&pool[at..at + n]);
            }
        }
    }
}

fn sip<T: Hash + ?Sized>(x: &T) -> u64 {
    let mut h = DefaultHasher::new();
    x.hash(&mut h);
    h.finish()
}

fn main() {
    let fs = foldhash::fast::FixedState::default();
    let words = ["", "a", "hello world!", "the quick brown fox jumps over the lazy dog"];
    println!("{} {} {}", fs.hash_one(0u64), fs.hash_one(1u64), fs.hash_one(12345u64));
    let f: Vec<u64> = words.iter().map(|w| fs.hash_one(w.as_bytes())).collect();
    println!("{} {} {} {}", f[0], f[1], f[2], f[3]);
    println!("{} {} {}", sip(&0u64), sip(&1u64), sip(&12345u64));
    let s: Vec<u64> = words.iter().map(|w| sip(w.as_bytes())).collect();
    println!("{} {} {} {}", s[0], s[1], s[2], s[3]);
    let mut rng = 0x2545f4914f6cdd1du64;
    let mut pool = [0u8; 1024];
    for b in pool.iter_mut() {
        *b = xorshift(&mut rng) as u8;
    }
    let mut fold = 0u64;
    let mut sip = 0u64;
    for _ in 0..100000 {
        let save = rng;
        let mut h = fs.build_hasher();
        feed(&mut h, &mut rng, &pool);
        fold = fold.rotate_left(5) ^ h.finish();
        rng = save;
        let mut s = DefaultHasher::new();
        feed(&mut s, &mut rng, &pool);
        sip = sip.rotate_left(5) ^ s.finish();
    }
    println!("fold {}", fold);
    println!("sip {}", sip);
}
