// The events of one key and the numbers computed from them.

pub struct Group {
    pub key: Vec<u8>,
    // The number of the line holding its first event (1-based).
    pub first_line: i64,
    pub count: i64,
    pub sum: i64,
    pub min: i64,
    pub max: i64,
    // Every event, in input order (so `times` never decreases).
    pub times: Vec<i64>,
    pub values: Vec<i64>,
}

// The events of a group in the recent window.
pub struct Recent {
    pub n: i64,
    pub min: i64,
    pub median: i64,
    pub max: i64,
}

// The busiest window of a group: `count` events in [start, start + span).
pub struct Busiest {
    pub count: i64,
    pub start: i64,
}

impl Group {
    pub fn new(key: &[u8], line: i64) -> Group {
        Group {
            key: key.to_vec(),
            first_line: line,
            count: 0,
            sum: 0,
            min: 0,
            max: 0,
            times: Vec::new(),
            values: Vec::new(),
        }
    }

    pub fn add(&mut self, time: i64, value: i64) {
        if self.count == 0 || value < self.min {
            self.min = value;
        }
        if self.count == 0 || value > self.max {
            self.max = value;
        }
        self.count += 1;
        self.sum += value;
        self.times.push(time);
        self.values.push(value);
    }

    // The sum over the count, truncated toward zero.
    pub fn mean(&self) -> i64 {
        self.sum / self.count
    }

    // The index of the first event later than `cutoff` (the number of
    // events when there is none): a binary search over `times`.
    fn first_after(&self, cutoff: i64) -> usize {
        let mut lo = 0;
        let mut hi = self.times.len();
        while lo < hi {
            let mid = (lo + hi) / 2;
            if self.times[mid] <= cutoff {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lo
    }

    // The events with a time after `now - span`; None when there are none.
    pub fn recent(&self, now: i64, span: i64) -> Option<Recent> {
        if self.count == 0 {
            return None;
        }
        let start = self.first_after(now - span);
        let mut vals: Vec<i64> = self.values[start..].to_vec();
        let n = vals.len() as i64;
        vals.sort();
        Some(Recent {
            n: n,
            min: vals[0],
            median: median(&vals),
            max: vals[(n - 1) as usize],
        })
    }

    // The window [t, t + span), t the time of one of the group's events,
    // holding the most events; the earliest such t on a tie.
    pub fn busiest(&self, span: i64) -> Busiest {
        let t = &self.times;
        let mut best = Busiest { count: 0, start: 0 };
        let mut r = 0;
        for i in 0..t.len() {
            if r < i {
                r = i;
            }
            while r < t.len() && t[r] < t[i] + span {
                r += 1;
            }
            let count = (r - i) as i64;
            if count > best.count {
                best = Busiest { count: count, start: t[i] };
            }
        }
        best
    }
}

// The median of sorted values (at least one): the middle one, or the
// mean of the two middle ones truncated toward zero.
pub fn median(sorted: &[i64]) -> i64 {
    let n = sorted.len();
    if n % 2 == 1 {
        sorted[n / 2]
    } else {
        (sorted[n / 2 - 1] + sorted[n / 2]) / 2
    }
}

// Whether group a comes before group b in the ranking: the larger sum
// first, then the earlier first event.
fn ranks_before(groups: &[Group], a: i64, b: i64) -> bool {
    let ga = &groups[a as usize];
    let gb = &groups[b as usize];
    if ga.sum != gb.sum {
        return ga.sum > gb.sum;
    }
    ga.first_line < gb.first_line
}

// The group numbers in ranking order (a merge sort).
pub fn ranking(groups: &[Group]) -> Vec<i64> {
    let n = groups.len();
    let mut order: Vec<i64> = Vec::new();
    for i in 0..n {
        order.push(i as i64);
    }
    let mut tmp: Vec<i64> = vec![0; n];
    let mut width = 1;
    while width < n {
        let mut lo = 0;
        while lo < n {
            let mid = if lo + width < n { lo + width } else { n };
            let hi = if lo + 2 * width < n { lo + 2 * width } else { n };
            let mut i = lo;
            let mut j = mid;
            let mut k = lo;
            while k < hi {
                if j >= hi || (i < mid && !ranks_before(groups, order[j], order[i])) {
                    tmp[k] = order[i];
                    i += 1;
                } else {
                    tmp[k] = order[j];
                    j += 1;
                }
                k += 1;
            }
            lo = hi;
        }
        for k in 0..n {
            order[k] = tmp[k];
        }
        width *= 2;
    }
    order
}
