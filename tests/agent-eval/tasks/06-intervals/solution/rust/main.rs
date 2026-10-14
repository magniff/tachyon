// Interval coverage: merge closed integer intervals, answer queries on the union.
use std::io::{self, Read, Write};

struct Scanner {
    data: Vec<u8>,
    pos: usize,
}

impl Scanner {
    // The next run of non-space bytes.
    fn next_token(&mut self) -> &[u8] {
        while self.pos < self.data.len() && self.data[self.pos] <= b' ' {
            self.pos += 1;
        }
        let start = self.pos;
        while self.pos < self.data.len() && self.data[self.pos] > b' ' {
            self.pos += 1;
        }
        &self.data[start..self.pos]
    }

    fn next_int(&mut self) -> i64 {
        let tok = self.next_token();
        let mut i = 0;
        let negative = !tok.is_empty() && tok[0] == b'-';
        if negative {
            i = 1;
        }
        let mut n: i64 = 0;
        while i < tok.len() {
            n = n * 10 + (tok[i] - b'0') as i64;
            i += 1;
        }
        if negative {
            -n
        } else {
            n
        }
    }
}

#[derive(Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct Interval {
    lo: i64,
    hi: i64,
}

// The union: sorted, disjoint, non-touching intervals.
struct Union {
    parts: Vec<Interval>,
    // before[i]: the integers covered by parts[0..i].
    before: Vec<i64>,
}

fn merge(mut list: Vec<Interval>) -> Union {
    list.sort();
    let mut parts: Vec<Interval> = Vec::new();
    for iv in list {
        let n = parts.len();
        if n > 0 && iv.lo <= parts[n - 1].hi + 1 {
            if iv.hi > parts[n - 1].hi {
                parts[n - 1].hi = iv.hi;
            }
        } else {
            parts.push(iv);
        }
    }
    let mut before = Vec::with_capacity(parts.len() + 1);
    let mut total: i64 = 0;
    before.push(0);
    for p in &parts {
        total += p.hi - p.lo + 1;
        before.push(total);
    }
    Union { parts, before }
}

impl Union {
    // The index of the last part with lo <= x, or -1.
    fn find(&self, x: i64) -> i64 {
        let mut lo: i64 = 0;
        let mut hi: i64 = self.parts.len() as i64; // answer in lo-1..hi-1
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.parts[mid as usize].lo <= x {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo - 1
    }

    fn covers(&self, a: i64, b: i64) -> bool {
        let i = self.find(a);
        i >= 0 && self.parts[i as usize].hi >= b
    }

    // The covered integers that are <= x.
    fn count_upto(&self, x: i64) -> i64 {
        let i = self.find(x);
        if i < 0 {
            return 0;
        }
        let p = self.parts[i as usize];
        let end = if p.hi < x { p.hi } else { x };
        self.before[i as usize] + end - p.lo + 1
    }

    fn total(&self) -> i64 {
        self.before[self.parts.len()]
    }
}

fn push_yes_no(out: &mut Vec<u8>, yes: bool) {
    out.extend_from_slice(if yes { b"yes\n" } else { b"no\n" });
}

fn main() {
    let mut data = Vec::new();
    io::stdin().read_to_end(&mut data).unwrap();
    let mut sc = Scanner { data, pos: 0 };
    let n = sc.next_int();
    let mut list: Vec<Interval> = Vec::new();
    for _ in 0..n {
        let lo = sc.next_int();
        let hi = sc.next_int();
        list.push(Interval { lo, hi });
    }
    let u = merge(list);
    let mut out = Vec::new();
    out.extend_from_slice(format!("{} {}\n", u.parts.len(), u.total()).as_bytes());
    let q = sc.next_int();
    for _ in 0..q {
        let kind = sc.next_token().to_vec();
        if kind == b"point" {
            let x = sc.next_int();
            push_yes_no(&mut out, u.covers(x, x));
        } else if kind == b"cover" {
            let a = sc.next_int();
            let b = sc.next_int();
            push_yes_no(&mut out, u.covers(a, b));
        } else {
            let a = sc.next_int();
            let b = sc.next_int();
            let count = u.count_upto(b) - u.count_upto(a - 1);
            out.extend_from_slice(count.to_string().as_bytes());
            out.push(b'\n');
        }
    }
    io::stdout().write_all(&out).unwrap();
}
