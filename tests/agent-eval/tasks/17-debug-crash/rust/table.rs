// A hash table from keys to group numbers: open addressing with linear
// probing, the capacity a power of two, grown to keep it at most half
// full.

pub struct Table {
    // Per slot: the key's hash, the key, and its group (-1: a free slot).
    hashes: Vec<i32>,
    keys: Vec<Vec<u8>>,
    groups: Vec<i64>,
    used: i64,
}

// The hash of a key: h = h * 31 + byte over its bytes, in 32 bits.
pub fn hash_key(key: &[u8]) -> i32 {
    let mut h: i32 = 0;
    for &b in key {
        h = h.wrapping_mul(31).wrapping_add(b as i32);
    }
    h
}

impl Table {
    pub fn new() -> Table {
        let mut t = Table { hashes: Vec::new(), keys: Vec::new(), groups: Vec::new(), used: 0 };
        t.alloc(16);
        t
    }

    fn alloc(&mut self, cap: i64) {
        self.hashes = vec![0; cap as usize];
        self.keys = vec![Vec::new(); cap as usize];
        self.groups = vec![-1; cap as usize];
        self.used = 0;
    }

    fn cap(&self) -> i64 {
        self.groups.len() as i64
    }

    // The slot holding `key`, or the free slot where it would go.
    fn probe(&self, key: &[u8], h: i32) -> usize {
        let mask = self.cap() - 1;
        let mut i = (h as u32 as i64) & mask;
        loop {
            let s = i as usize;
            if self.groups[s] == -1 {
                return s;
            }
            if self.hashes[s] == h && self.keys[s].len() == key.len() {
                return s;
            }
            i = (i + 1) & mask;
        }
    }

    // The group of `key`, if it has one.
    pub fn get(&self, key: &[u8]) -> Option<i64> {
        let s = self.probe(key, hash_key(key));
        if self.groups[s] == -1 {
            None
        } else {
            Some(self.groups[s])
        }
    }

    // Records that `key` (not in the table yet) belongs to `group`.
    pub fn insert(&mut self, key: &[u8], group: i64) {
        if (self.used + 1) * 2 > self.cap() {
            self.grow();
        }
        let h = hash_key(key);
        let s = self.probe(key, h);
        self.hashes[s] = h;
        self.keys[s] = key.to_vec();
        self.groups[s] = group;
        self.used += 1;
    }

    // Doubles the capacity and puts every entry back.
    fn grow(&mut self) {
        let hashes = std::mem::take(&mut self.hashes);
        let keys = std::mem::take(&mut self.keys);
        let groups = std::mem::take(&mut self.groups);
        self.alloc(groups.len() as i64 * 2);
        for s in 0..groups.len() {
            if groups[s] != -1 {
                let t = self.probe(&keys[s], hashes[s]);
                self.hashes[t] = hashes[s];
                self.keys[t] = keys[s].clone();
                self.groups[t] = groups[s];
                self.used += 1;
            }
        }
    }

    pub fn len(&self) -> i64 {
        self.used
    }
}
