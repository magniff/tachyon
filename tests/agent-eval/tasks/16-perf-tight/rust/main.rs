// Cells within reach: a generated grid of open cells and walls, and many
// bounded breadth-first searches on it. Correct, but too slow on the
// large tests.

use std::collections::HashMap;
use std::io::{self, Read, Write};

struct Rng {
    x: u64,
}

impl Rng {
    fn next(&mut self) -> u64 {
        self.x = self.x.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        self.x >> 33
    }
}

// Parses the unsigned integers of the input line.
fn numbers(text: &[u8]) -> Vec<u64> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < text.len() {
        if text[i] >= b'0' && text[i] <= b'9' {
            let mut v: u64 = 0;
            while i < text.len() && text[i] >= b'0' && text[i] <= b'9' {
                v = v.wrapping_mul(10).wrapping_add((text[i] - b'0') as u64);
                i += 1;
            }
            out.push(v);
        } else {
            i += 1;
        }
    }
    out
}

#[derive(Clone, Copy)]
struct Step {
    r: i64,
    c: i64,
    dist: i64,
}

// The number of open cells at most d steps from cell (r, c).
fn reach(grid: &Vec<Vec<bool>>, r: i64, c: i64, d: i64) -> i64 {
    let h = grid.len() as i64;
    let w = grid[0].len() as i64;
    if !grid[r as usize][c as usize] {
        return 0;
    }
    let mut seen: HashMap<i64, bool> = HashMap::new();
    let mut queue: Vec<Step> = Vec::new();
    seen.insert(r * w + c, true);
    queue.push(Step { r: r, c: c, dist: 0 });
    let mut head = 0;
    while head < queue.len() {
        let s = queue[head];
        head += 1;
        if s.dist == d {
            continue;
        }
        let moves = [(-1, 0), (1, 0), (0, -1), (0, 1)];
        for m in moves {
            let nr = s.r + m.0;
            let nc = s.c + m.1;
            if nr < 0 || nr >= h || nc < 0 || nc >= w {
                continue;
            }
            if !grid[nr as usize][nc as usize] {
                continue;
            }
            if seen.contains_key(&(nr * w + nc)) {
                continue;
            }
            seen.insert(nr * w + nc, true);
            queue.push(Step { r: nr, c: nc, dist: s.dist + 1 });
        }
    }
    seen.len() as i64
}

fn main() {
    let mut input = Vec::new();
    io::stdin().read_to_end(&mut input).unwrap();
    let nums = numbers(&input);
    let h = nums[0] as i64;
    let w = nums[1] as i64;
    let q = nums[2] as i64;
    let p = nums[3];
    let dmax = nums[4];
    let mut rng = Rng { x: nums[5] };

    let mut grid: Vec<Vec<bool>> = Vec::new();
    for _ in 0..h {
        let mut row: Vec<bool> = Vec::new();
        for _ in 0..w {
            row.push(rng.next() % 100 >= p);
        }
        grid.push(row);
    }

    let mut out = String::new();
    let mut sum: i64 = 0;
    let mut hash: i64 = 0;
    for j in 0..q {
        let r = (rng.next() % h as u64) as i64;
        let c = (rng.next() % w as u64) as i64;
        let d = (rng.next() % (dmax + 1)) as i64;
        let a = reach(&grid, r, c, d);
        if j < 10 {
            out.push_str(&a.to_string());
            out.push('\n');
        }
        sum += a;
        hash = (hash * 1000003 + a) % 1000000007;
    }
    out.push_str(&format!("sum {}\nhash {}\n", sum, hash));
    io::stdout().write_all(out.as_bytes()).unwrap();
}
