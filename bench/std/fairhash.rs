// bench/std's fair hashers for Rust's HashMap (included by the hash_*
// programs): `same`, tachyon's std hash as of 0.19 (splitmix64's
// finalizer for an integer, FNV-1a for bytes), and `fold`, foldhash
// (0.2's fast FixedState: 0.20's std hash, design §2.4.2), so that a
// row compares tables, not hash functions. Rust's default (SipHash-1-3)
// is the third variant.
use std::convert::TryInto;
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

// foldhash 0.2's fast hasher with its fixed seeds (FixedState), written
// out: tachyon's std hash from 0.20 (std::hash, bit for bit). Inputs above
// 16 bytes take foldhash's path up to 128 bytes, enough for these
// benchmarks.
const ARBITRARY3: u64 = 0x082efa98ec4e6c89;
const SEEDS: [u64; 6] = [0xc0ac29b7c97c50dd, 0x3f84d5b5b5470917, 0x9216d5d98979fb1b, 0xd1310ba698dfb5ac, 0x2ffd72dbd01adfb7, 0xb8e1afed6a267e96];

#[inline(always)]
fn folded_multiply(x: u64, y: u64) -> u64 {
    let full = (x as u128).wrapping_mul(y as u128);
    (full as u64) ^ ((full >> 64) as u64)
}

#[derive(Clone, Copy, Default)]
pub struct Fold;

pub struct FoldHasher { acc: u64, sponge: u128, sponge_len: u8 }

impl BuildHasher for Fold {
    type Hasher = FoldHasher;
    #[inline(always)]
    fn build_hasher(&self) -> FoldHasher { FoldHasher { acc: ARBITRARY3, sponge: 0, sponge_len: 0 } }
}

impl FoldHasher {
    #[inline(always)]
    fn write_num<T: Into<u128>>(&mut self, x: T) {
        let bits: usize = 8 * core::mem::size_of::<T>();
        if self.sponge_len as usize + bits > 128 {
            let lo = self.sponge as u64;
            let hi = (self.sponge >> 64) as u64;
            self.acc = folded_multiply(lo ^ self.acc, hi ^ SEEDS[0]);
            self.sponge = x.into();
            self.sponge_len = bits as u8;
        } else {
            self.sponge |= x.into() << self.sponge_len;
            self.sponge_len += bits as u8;
        }
    }
}

#[inline(always)]
fn load(b: &[u8], i: usize) -> u64 { u64::from_le_bytes(b[i..i + 8].try_into().unwrap()) }

impl Hasher for FoldHasher {
    #[inline(always)]
    fn write(&mut self, bytes: &[u8]) {
        let len = bytes.len();
        self.acc = self.acc.rotate_right(len as u32);
        if len <= 16 {
            let mut s0 = self.acc;
            let mut s1 = SEEDS[1];
            if len >= 8 {
                s0 ^= load(bytes, 0);
                s1 ^= load(bytes, len - 8);
            } else if len >= 4 {
                s0 ^= u32::from_le_bytes(bytes[0..4].try_into().unwrap()) as u64;
                s1 ^= u32::from_le_bytes(bytes[len - 4..].try_into().unwrap()) as u64;
            } else if len > 0 {
                s0 ^= bytes[0] as u64;
                s1 ^= ((bytes[len - 1] as u64) << 8) | bytes[len / 2] as u64;
            }
            self.acc = folded_multiply(s0, s1);
        } else {
            // (inputs above 16 bytes, at most 128 here: foldhash's tail loop)
            let (mut s0, mut s1) = (self.acc, self.acc.wrapping_add(SEEDS[1]));
            let v = bytes;
            let n = v.len();
            s0 = folded_multiply(load(v, 0) ^ s0, load(v, n - 16) ^ SEEDS[0]);
            s1 = folded_multiply(load(v, 8) ^ s1, load(v, n - 8) ^ SEEDS[0]);
            if n >= 32 {
                s0 = folded_multiply(load(v, 16) ^ s0, load(v, n - 32) ^ SEEDS[0]);
                s1 = folded_multiply(load(v, 24) ^ s1, load(v, n - 24) ^ SEEDS[0]);
                if n >= 64 {
                    s0 = folded_multiply(load(v, 32) ^ s0, load(v, n - 48) ^ SEEDS[0]);
                    s1 = folded_multiply(load(v, 40) ^ s1, load(v, n - 40) ^ SEEDS[0]);
                    if n >= 96 {
                        s0 = folded_multiply(load(v, 48) ^ s0, load(v, n - 64) ^ SEEDS[0]);
                        s1 = folded_multiply(load(v, 56) ^ s1, load(v, n - 56) ^ SEEDS[0]);
                    }
                }
            }
            self.acc = s0 ^ s1;
        }
    }
    #[inline(always)] fn write_u8(&mut self, i: u8) { self.write_num(i) }
    #[inline(always)] fn write_u32(&mut self, i: u32) { self.write_num(i) }
    #[inline(always)] fn write_u64(&mut self, i: u64) { self.write_num(i) }
    #[inline(always)] fn write_usize(&mut self, i: usize) { self.write_num(i as u64) }
    #[inline(always)]
    fn finish(&self) -> u64 {
        if self.sponge_len > 0 {
            folded_multiply((self.sponge as u64) ^ self.acc, ((self.sponge >> 64) as u64) ^ SEEDS[0])
        } else {
            self.acc
        }
    }
}

