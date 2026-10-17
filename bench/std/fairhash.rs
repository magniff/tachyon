// bench/std's fair hashers for Rust's HashMap (included by the hash_*
// programs): `same`, tachyon's std hash as of 0.19 (splitmix64's
// finalizer for an integer, FNV-1a for bytes), and `fold`, foldhash's
// folded multiply (what 0.20's std moves to: design §2.4.2), so that a
// row compares tables, not hash functions. Rust's default (SipHash-1-3)
// is the third variant.
use std::hash::{BuildHasher, Hasher};

#[derive(Clone, Copy, Default)]
pub struct Same;

pub struct SameHasher {
    h: u64,
    bytes: bool,
}

fn mix64(x: u64) -> u64 {
    let mut z = x.wrapping_add(0x9e3779b97f4a7c15);
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}

impl Hasher for SameHasher {
    fn write(&mut self, bytes: &[u8]) {
        if !self.bytes {
            self.bytes = true;
            self.h = 0xcbf29ce484222325;
        }
        for &b in bytes {
            self.h = (self.h ^ b as u64).wrapping_mul(0x100000001b3);
        }
    }
    // (a slice's length prefix: tachyon's hash of [u8] has none)
    fn write_usize(&mut self, _n: usize) {}
    fn write_u64(&mut self, x: u64) {
        self.h = mix64(x);
    }
    fn finish(&self) -> u64 {
        self.h
    }
}

impl BuildHasher for Same {
    type Hasher = SameHasher;
    fn build_hasher(&self) -> SameHasher {
        SameHasher { h: 0, bytes: false }
    }
}

#[derive(Clone, Copy, Default)]
pub struct Fold;

pub struct FoldHasher {
    acc: u64,
}

const FOLD_SEED: u64 = 0x243f6a8885a308d3;
const FOLD_MUL: u64 = 0x5851f42d4c957f2d;

fn folded_multiply(x: u64, y: u64) -> u64 {
    let p = (x as u128) * (y as u128);
    (p as u64) ^ ((p >> 64) as u64)
}

impl Hasher for FoldHasher {
    fn write(&mut self, bytes: &[u8]) {
        let mut chunks = bytes.chunks_exact(8);
        for c in &mut chunks {
            let w = u64::from_le_bytes([c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7]]);
            self.acc = folded_multiply(self.acc ^ w, FOLD_MUL);
        }
        let rest = chunks.remainder();
        if !rest.is_empty() {
            let mut w = 0u64;
            for (i, &b) in rest.iter().enumerate() {
                w |= (b as u64) << (8 * i);
            }
            self.acc = folded_multiply(self.acc ^ w ^ ((rest.len() as u64) << 56), FOLD_MUL);
        }
    }
    fn write_usize(&mut self, n: usize) {
        self.acc = self.acc.wrapping_add(n as u64);
    }
    fn write_u64(&mut self, x: u64) {
        self.acc = folded_multiply(self.acc ^ x, FOLD_MUL);
    }
    fn finish(&self) -> u64 {
        folded_multiply(self.acc, FOLD_SEED)
    }
}

impl BuildHasher for Fold {
    type Hasher = FoldHasher;
    fn build_hasher(&self) -> FoldHasher {
        FoldHasher { acc: FOLD_SEED }
    }
}
