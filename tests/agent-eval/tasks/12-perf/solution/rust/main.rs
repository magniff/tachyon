// Distinct values in ranges, offline: queries grouped by their right end,
// a Fenwick tree over positions that counts each value at its last
// occurrence so far. O((n + q) log n).

use std::io::Read;

struct Rng {
    x: u64,
}

impl Rng {
    fn next(&mut self) -> u64 {
        self.x = self.x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.x >> 33
    }
}

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).unwrap();
    let nums: Vec<u64> = input.split_whitespace().map(|w| w.parse().unwrap()).collect();
    let (n, q, m) = (nums[0] as usize, nums[1] as usize, nums[2]);
    let mut rng = Rng { x: nums[3] };

    let mut a: Vec<u64> = Vec::with_capacity(n);
    for _ in 0..n {
        a.push(rng.next() % m);
    }
    // Values to ranks 0..k.
    let mut sorted = a.clone();
    sorted.sort_unstable();
    sorted.dedup();
    let rank: Vec<u32> = a.iter().map(|v| sorted.binary_search(v).unwrap() as u32).collect();

    // Queries as lists by right end: head[r], next[j].
    let mut ql: Vec<u32> = vec![0; q];
    let mut head: Vec<u32> = vec![u32::MAX; n];
    let mut next: Vec<u32> = vec![u32::MAX; q];
    for j in 0..q {
        let u = (rng.next() % n as u64) as usize;
        let v = (rng.next() % n as u64) as usize;
        let (l, r) = if u < v { (u, v) } else { (v, u) };
        ql[j] = l as u32;
        next[j] = head[r];
        head[r] = j as u32;
    }

    let mut tree: Vec<i32> = vec![0; n + 1];
    let mut last: Vec<u32> = vec![u32::MAX; sorted.len()];
    let mut ans: Vec<u32> = vec![0; q];
    for i in 0..n {
        let k = rank[i] as usize;
        if last[k] != u32::MAX {
            let mut p = last[k] as usize + 1;
            while p <= n {
                tree[p] -= 1;
                p += p & p.wrapping_neg();
            }
        }
        last[k] = i as u32;
        let mut p = i + 1;
        while p <= n {
            tree[p] += 1;
            p += p & p.wrapping_neg();
        }
        let mut j = head[i];
        while j != u32::MAX {
            let l = ql[j as usize] as usize;
            let mut s: i64 = 0;
            let mut p = i + 1;
            while p > 0 {
                s += tree[p] as i64;
                p -= p & p.wrapping_neg();
            }
            let mut p = l;
            while p > 0 {
                s -= tree[p] as i64;
                p -= p & p.wrapping_neg();
            }
            ans[j as usize] = s as u32;
            j = next[j as usize];
        }
    }

    let mut out = String::new();
    let mut sum: u64 = 0;
    let mut hash: u64 = 0;
    for j in 0..q {
        if j < 10 {
            out.push_str(&ans[j].to_string());
            out.push('\n');
        }
        sum += ans[j] as u64;
        hash = (hash * 1000003 + ans[j] as u64) % 1000000007;
    }
    out.push_str(&format!("sum {}\nhash {}\n", sum, hash));
    print!("{}", out);
}
