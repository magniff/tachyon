// bench/std rng (0.20, A7): xoshiro256++ seeded by splitmix64 (as
// rand_xoshiro), 10^9 next_u64, then 10^8 draws in [0, n) for n from 1 to
// 1024 by Lemire's method (as rand's UniformInt for u64, through u128):
// the algorithm of std's Xoshiro256pp, written in Rust. std only.
struct Xoshiro256pp {
    s: [u64; 4],
}

fn splitmix64(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9e3779b97f4a7c15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
    z ^ (z >> 31)
}

impl Xoshiro256pp {
    fn seed_from_u64(n: u64) -> Self {
        let mut st = n;
        let a = splitmix64(&mut st);
        let b = splitmix64(&mut st);
        let c = splitmix64(&mut st);
        let d = splitmix64(&mut st);
        Xoshiro256pp { s: [a, b, c, d] }
    }

    #[inline]
    fn next_u64(&mut self) -> u64 {
        let s = &mut self.s;
        let result = s[0].wrapping_add(s[3]).rotate_left(23).wrapping_add(s[0]);
        let t = s[1] << 17;
        s[2] ^= s[0];
        s[3] ^= s[1];
        s[1] ^= s[2];
        s[0] ^= s[3];
        s[2] ^= t;
        s[3] = s[3].rotate_left(45);
        result
    }

    #[inline]
    fn below(&mut self, n: u64) -> u64 {
        let mut m = (self.next_u64() as u128) * (n as u128);
        if (m as u64) < n {
            let t = n.wrapping_neg() % n;
            while (m as u64) < t {
                m = (self.next_u64() as u128) * (n as u128);
            }
        }
        (m >> 64) as u64
    }
}

fn main() {
    let mut r = Xoshiro256pp::seed_from_u64(20201016);
    let mut sum = 0u64;
    for _ in 0..1000000000u64 {
        sum = sum.wrapping_add(r.next_u64());
    }
    let mut sum2 = 0u64;
    for i in 0..100000000u64 {
        sum2 = sum2.wrapping_add(r.below((i & 1023) + 1));
    }
    println!("{} {}", sum, sum2);
}
