// Shortest paths: Dijkstra with a binary heap, one search per query.
use std::io::{self, Read, Write};

struct Scanner {
    data: Vec<u8>,
    pos: usize,
}

impl Scanner {
    fn next_int(&mut self) -> i64 {
        while self.pos < self.data.len()
            && !(self.data[self.pos] == b'-' || self.data[self.pos].is_ascii_digit())
        {
            self.pos += 1;
        }
        let mut negative = false;
        if self.pos < self.data.len() && self.data[self.pos] == b'-' {
            negative = true;
            self.pos += 1;
        }
        let mut n: i64 = 0;
        while self.pos < self.data.len() && self.data[self.pos].is_ascii_digit() {
            n = n * 10 + (self.data[self.pos] - b'0') as i64;
            self.pos += 1;
        }
        if negative {
            -n
        } else {
            n
        }
    }
}

#[derive(Clone, Copy)]
struct HeapItem {
    dist: i64,
    node: usize,
}

// A binary min-heap on dist.
struct MinHeap {
    items: Vec<HeapItem>,
}

impl MinHeap {
    fn push(&mut self, item: HeapItem) {
        self.items.push(item);
        let mut i = self.items.len() - 1;
        while i > 0 {
            let parent = (i - 1) / 2;
            if self.items[parent].dist <= self.items[i].dist {
                break;
            }
            self.items.swap(parent, i);
            i = parent;
        }
    }

    fn pop(&mut self) -> Option<HeapItem> {
        let n = self.items.len();
        if n == 0 {
            return None;
        }
        let top = self.items[0];
        let last = self.items.pop().unwrap();
        if n > 1 {
            self.items[0] = last;
            let len = n - 1;
            let mut i = 0;
            loop {
                let left = 2 * i + 1;
                let right = left + 1;
                let mut smallest = i;
                if left < len && self.items[left].dist < self.items[smallest].dist {
                    smallest = left;
                }
                if right < len && self.items[right].dist < self.items[smallest].dist {
                    smallest = right;
                }
                if smallest == i {
                    break;
                }
                self.items.swap(smallest, i);
                i = smallest;
            }
        }
        Some(top)
    }
}

// Adjacency lists in compressed form: the edges of u are
// targets[start[u]..start[u + 1]].
struct Graph {
    start: Vec<usize>,
    targets: Vec<usize>,
    weights: Vec<i64>,
}

fn build_graph(n: usize, from: &[usize], to: &[usize], w: &[i64]) -> Graph {
    let m = from.len();
    let mut start = vec![0usize; n + 1];
    for i in 0..m {
        start[from[i] + 1] += 1;
    }
    for u in 0..n {
        start[u + 1] += start[u];
    }
    let mut fill = start.clone();
    let mut targets = vec![0usize; m];
    let mut weights = vec![0i64; m];
    for i in 0..m {
        let k = fill[from[i]];
        targets[k] = to[i];
        weights[k] = w[i];
        fill[from[i]] += 1;
    }
    Graph {
        start,
        targets,
        weights,
    }
}

fn shortest(g: &Graph, s: usize, t: usize, dist: &mut Vec<i64>, heap: &mut MinHeap) -> i64 {
    for d in dist.iter_mut() {
        *d = -1;
    }
    heap.items.clear();
    dist[s] = 0;
    heap.push(HeapItem { dist: 0, node: s });
    while let Some(item) = heap.pop() {
        let u = item.node;
        if item.dist != dist[u] {
            continue; // stale entry
        }
        if u == t {
            return item.dist;
        }
        for k in g.start[u]..g.start[u + 1] {
            let v = g.targets[k];
            let nd = item.dist + g.weights[k];
            if dist[v] < 0 || nd < dist[v] {
                dist[v] = nd;
                heap.push(HeapItem { dist: nd, node: v });
            }
        }
    }
    -1
}

fn main() {
    let mut data = Vec::new();
    io::stdin().read_to_end(&mut data).unwrap();
    let mut sc = Scanner { data, pos: 0 };
    let n = sc.next_int() as usize;
    let m = sc.next_int() as usize;
    let q = sc.next_int() as usize;
    let mut from = Vec::with_capacity(m);
    let mut to = Vec::with_capacity(m);
    let mut w = Vec::with_capacity(m);
    for _ in 0..m {
        from.push(sc.next_int() as usize);
        to.push(sc.next_int() as usize);
        w.push(sc.next_int());
    }
    let g = build_graph(n, &from, &to, &w);
    let mut dist = vec![-1i64; n];
    let mut heap = MinHeap { items: Vec::new() };
    let mut out = Vec::new();
    for _ in 0..q {
        let s = sc.next_int() as usize;
        let t = sc.next_int() as usize;
        let d = shortest(&g, s, t, &mut dist, &mut heap);
        out.extend_from_slice(d.to_string().as_bytes());
        out.push(b'\n');
    }
    io::stdout().write_all(&out).unwrap();
}
