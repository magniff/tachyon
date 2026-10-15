// Cells within reach: a generated grid of open cells and walls, and many
// bounded breadth-first searches on it. The grid is one flat array of
// marks with a border of walls around it (so a neighbour needs no bounds
// test). A cell's mark is the number of the last search that reached it,
// and a wall's is the largest u32, which no search number exceeds: so one
// test (mark < this search) says "open and not yet reached", nothing is
// cleared or allocated per query, and the queue is reused.

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

// The mark of a wall.
const WALL: u32 = 4294967295;

struct Search {
    // the padded width: w + 2
    stride: i64,
    // per cell: WALL, or the stamp of the last search that reached it
    mark: Vec<u32>,
    queue: Vec<i32>,
    stamp: u32,
}

impl Search {
    // Visits `n` if it is open and not yet reached by this search.
    fn visit(&mut self, n: i64) {
        let n = n as usize;
        if self.mark[n] < self.stamp {
            self.mark[n] = self.stamp;
            self.queue.push(n as i32);
        }
    }

    // The number of open cells at most d steps from cell (r, c).
    fn reach(&mut self, r: i64, c: i64, d: i64) -> i64 {
        let stride = self.stride;
        let start = (r + 1) * stride + c + 1;
        if self.mark[start as usize] == WALL {
            return 0;
        }
        self.stamp += 1;
        self.queue.clear();
        self.queue.push(start as i32);
        self.mark[start as usize] = self.stamp;
        let mut head = 0;
        let mut dist = 0;
        while head < self.queue.len() && dist < d {
            let layer_end = self.queue.len();
            while head < layer_end {
                let cell = self.queue[head] as i64;
                head += 1;
                self.visit(cell - stride);
                self.visit(cell + stride);
                self.visit(cell - 1);
                self.visit(cell + 1);
            }
            dist += 1;
        }
        self.queue.len() as i64
    }
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

    let stride = w + 2;
    let cells = ((h + 2) * stride) as usize;
    let mut mark = vec![WALL; cells];
    for r in 0..h {
        for c in 0..w {
            if rng.next() % 100 >= p {
                mark[((r + 1) * stride + c + 1) as usize] = 0;
            }
        }
    }
    let mut s = Search {
        stride: stride,
        mark: mark,
        queue: Vec::with_capacity(4096),
        stamp: 0,
    };

    let mut out = String::new();
    let mut sum: i64 = 0;
    let mut hash: i64 = 0;
    for j in 0..q {
        let r = (rng.next() % h as u64) as i64;
        let c = (rng.next() % w as u64) as i64;
        let d = (rng.next() % (dmax + 1)) as i64;
        let a = s.reach(r, c, d);
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
